#!/usr/bin/env bash
# install-kibana.sh — Kibana 8.x on ailab-siem (Elastic Security UI + Detection Engine).
# Run ON the SIEM VM as root, AFTER install-elasticsearch.sh.
#
#   sudo KIBANA_PASSWORD='...' bash install-kibana.sh
#
# KIBANA_PASSWORD must match the kibana_system password set by install-elasticsearch.sh.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

SIEM_HOST="${SIEM_HOST:-172.16.50.60}"
KIBANA_PASSWORD="${KIBANA_PASSWORD:-CHANGE_ME_kibana_system_password}"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then echo "[!] run as root" >&2; exit 1; fi
if [[ "${KIBANA_PASSWORD}" == CHANGE_ME_* ]]; then
  echo "[!] set KIBANA_PASSWORD to the kibana_system password from install-elasticsearch.sh" >&2; exit 1
fi

if ! dpkg -l 2>/dev/null | grep -q '^ii  kibana '; then
  echo "[*] installing kibana (~300MB)"
  apt-get install -y -qq kibana
fi

# Encryption keys make saved objects / alerting durable across restarts. Generate once
# and keep them stable (regenerating invalidates encrypted saved objects).
gen() { tr -dc 'a-f0-9' </dev/urandom | head -c48; }
ENC_SAVED="${ENC_SAVED:-$(gen)}"
ENC_SEC="${ENC_SEC:-$(gen)}"
ENC_REP="${ENC_REP:-$(gen)}"

echo "[*] writing /etc/kibana/kibana.yml"
cat > /etc/kibana/kibana.yml <<YML
server.host: "0.0.0.0"
server.port: 5601
server.publicBaseUrl: "http://${SIEM_HOST}:5601"
elasticsearch.hosts: ["http://localhost:9200"]
elasticsearch.username: "kibana_system"
elasticsearch.password: "${KIBANA_PASSWORD}"
xpack.encryptedSavedObjects.encryptionKey: "${ENC_SAVED}"
xpack.security.encryptionKey: "${ENC_SEC}"
xpack.reporting.encryptionKey: "${ENC_REP}"
YML

systemctl daemon-reload
systemctl enable kibana >/dev/null 2>&1 || true
systemctl restart kibana

echo "[*] waiting for Kibana on :5601 (first boot optimizes bundles, ~1-2 min) ..."
for _ in $(seq 1 60); do
  if curl -s -m5 "http://localhost:5601/api/status" 2>/dev/null | grep -q '"level":"available"'; then
    echo "[+] Kibana available at http://${SIEM_HOST}:5601"; exit 0
  fi
  sleep 5
done
echo "[!] Kibana did not report available in time; check: journalctl -u kibana -n 50"
