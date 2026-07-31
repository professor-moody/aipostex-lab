#!/bin/bash
# Provision enterprise identity host with dnsmasq, Keycloak, and Vault.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "${SCRIPT_DIR}/../common.sh"

KEYCLOAK_VERSION="${KEYCLOAK_VERSION:-26.1.4}"
VAULT_VERSION="${VAULT_VERSION:-1.18.4}"

echo "[*] Provisioning ent-idp-01 (DNS, Keycloak, Vault)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl wget unzip jq dnsmasq openjdk-17-jre-headless 2>/dev/null

echo "[*] Configuring dnsmasq for ${ENT_DOMAIN}..."
enterprise_hosts_entries > /etc/enterprise-hosts
cat > /etc/dnsmasq.d/acme-enterprise.conf <<EOF
domain=${ENT_DOMAIN}
expand-hosts
addn-hosts=/etc/enterprise-hosts
listen-address=0.0.0.0
bind-interfaces
EOF
systemctl enable --now dnsmasq
systemctl restart dnsmasq

echo "[*] Installing Keycloak ${KEYCLOAK_VERSION}..."
if ! id keycloak >/dev/null 2>&1; then
    useradd -r -m -d /opt/keycloak -s /usr/sbin/nologin keycloak
fi
if [[ ! -d "/opt/keycloak/keycloak-${KEYCLOAK_VERSION}" ]]; then
    wget -q "https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/keycloak-${KEYCLOAK_VERSION}.tar.gz" -O /tmp/keycloak.tar.gz
    tar -C /opt/keycloak -xzf /tmp/keycloak.tar.gz
    rm -f /tmp/keycloak.tar.gz
fi
ln -sfn "/opt/keycloak/keycloak-${KEYCLOAK_VERSION}" /opt/keycloak/current
mkdir -p /opt/keycloak/current/data/import
cat > /opt/keycloak/current/data/import/acme-realm.json <<'EOF'
{
  "realm": "acme",
  "enabled": true,
  "clients": [
    {
      "clientId": "litellm-gateway",
      "enabled": true,
      "publicClient": false,
      "secret": "kc-litellm-client-secret-FAKE"
    },
    {
      "clientId": "mlflow-ui",
      "enabled": true,
      "publicClient": false,
      "secret": "kc-mlflow-client-secret-FAKE"
    }
  ],
  "users": [
    {
      "username": "research.lead",
      "enabled": true,
      "email": "research.lead@acme.internal",
      "credentials": [{"type": "password", "value": "ResearchLead-FAKE-2026", "temporary": false}]
    }
  ]
}
EOF
chown -R keycloak:keycloak /opt/keycloak

cat > /etc/systemd/system/keycloak.service <<'EOF'
[Unit]
Description=Enterprise Keycloak
After=network.target

[Service]
User=keycloak
Group=keycloak
WorkingDirectory=/opt/keycloak/current
Environment="KEYCLOAK_ADMIN=admin"
Environment="KEYCLOAK_ADMIN_PASSWORD=admin-FAKE-enterprise"
ExecStart=/opt/keycloak/current/bin/kc.sh start-dev --http-host=0.0.0.0 --http-port=8080 --import-realm --health-enabled=true
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now keycloak

echo "[*] Installing Vault ${VAULT_VERSION}..."
if ! command -v vault >/dev/null 2>&1; then
    wget -q "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" -O /tmp/vault.zip
    unzip -q -o /tmp/vault.zip -d /usr/local/bin
    rm -f /tmp/vault.zip
    chmod 0755 /usr/local/bin/vault
fi
if ! id vault >/dev/null 2>&1; then
    useradd -r -m -d /opt/vault -s /usr/sbin/nologin vault
fi
cat > /etc/systemd/system/vault.service <<'EOF'
[Unit]
Description=Enterprise Vault Dev Fixture
After=network.target

[Service]
User=vault
Group=vault
Environment="VAULT_DEV_ROOT_TOKEN_ID=root-enterprise-FAKE"
ExecStart=/usr/local/bin/vault server -dev -dev-listen-address=0.0.0.0:8200 -dev-root-token-id=root-enterprise-FAKE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now vault

enterprise_wait_for_http "Keycloak realm" "http://localhost:8080/realms/acme" "acme" 60
enterprise_wait_for_http "Vault" "http://localhost:8200/v1/sys/health" "initialized" 30
echo "[+] ent-idp-01 provisioning complete"
