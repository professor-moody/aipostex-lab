#!/bin/bash
# Provision enterprise observability host with OpenSearch, Grafana, and log receiver.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSEARCH_VERSION="${OPENSEARCH_VERSION:-2.17.1}"
GRAFANA_VERSION="${GRAFANA_VERSION:-11.5.2}"

echo "[*] Provisioning ent-observe-01..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl wget gnupg2 apt-transport-https software-properties-common openjdk-17-jre-headless 2>/dev/null

echo "[*] Installing OpenSearch ${OPENSEARCH_VERSION}..."
if ! id opensearch >/dev/null 2>&1; then
    useradd -r -m -d /opt/opensearch -s /usr/sbin/nologin opensearch
fi
if [[ ! -d "/opt/opensearch/opensearch-${OPENSEARCH_VERSION}" ]]; then
    wget -q "https://artifacts.opensearch.org/releases/bundle/opensearch/${OPENSEARCH_VERSION}/opensearch-${OPENSEARCH_VERSION}-linux-x64.tar.gz" -O /tmp/opensearch.tar.gz
    tar -C /opt/opensearch -xzf /tmp/opensearch.tar.gz
    rm -f /tmp/opensearch.tar.gz
fi
ln -sfn "/opt/opensearch/opensearch-${OPENSEARCH_VERSION}" /opt/opensearch/current
cat > /opt/opensearch/current/config/opensearch.yml <<'EOF'
cluster.name: acme-enterprise-lab
node.name: ent-observe-01
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
plugins.security.disabled: true
EOF
chown -R opensearch:opensearch /opt/opensearch

cat > /etc/systemd/system/opensearch.service <<'EOF'
[Unit]
Description=Enterprise OpenSearch
After=network.target

[Service]
User=opensearch
Group=opensearch
WorkingDirectory=/opt/opensearch/current
Environment="OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g"
ExecStart=/opt/opensearch/current/bin/opensearch
Restart=always
RestartSec=10
LimitNOFILE=65535
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now opensearch

echo "[*] Installing Grafana ${GRAFANA_VERSION}..."
if ! dpkg -s grafana >/dev/null 2>&1; then
    wget -q "https://dl.grafana.com/oss/release/grafana_${GRAFANA_VERSION}_amd64.deb" -O /tmp/grafana.deb
    apt-get install -y -qq /tmp/grafana.deb 2>/dev/null
    rm -f /tmp/grafana.deb
fi
mkdir -p /etc/grafana/provisioning/datasources
cat > /etc/grafana/provisioning/datasources/opensearch.yaml <<'EOF'
apiVersion: 1
datasources:
  - name: Enterprise OpenSearch
    type: grafana-opensearch-datasource
    access: proxy
    url: http://localhost:9200
    isDefault: true
EOF
systemctl enable --now grafana-server

echo "[*] Installing enterprise log receiver..."
mkdir -p /opt/acme-observe /var/log/acme-observe
cp "${SCRIPT_DIR}/log-receiver.py" /opt/acme-observe/log-receiver.py
chmod 0755 /opt/acme-observe/log-receiver.py
cat > /etc/systemd/system/acme-log-receiver.service <<'EOF'
[Unit]
Description=ACME Enterprise Log Receiver
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/acme-observe/log-receiver.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now acme-log-receiver

for spec in "OpenSearch|http://localhost:9200/_cluster/health|status" "Grafana|http://localhost:3000/api/health|database" "Log receiver|http://localhost:9201/health|ok"; do
    IFS='|' read -r name url expect <<<"${spec}"
    echo "[*] Waiting for ${name}..."
    for i in $(seq 1 60); do
        if curl -sf "${url}" 2>/dev/null | grep -qi "${expect}"; then
            echo "[+] ${name} ready"
            break
        fi
        if [[ $i -eq 60 ]]; then
            echo "[!] ${name} failed readiness"
            exit 1
        fi
        sleep 2
    done
done

echo "[+] ent-observe-01 provisioning complete"
