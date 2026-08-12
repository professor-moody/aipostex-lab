#!/usr/bin/env bash
# install-beats.sh — install + configure Filebeat and Auditbeat on a TARGET host so
# it ships endpoint + application telemetry to the Elastic detection stack (ailab-siem).
#
# Run ON the target VM as root. Idempotent: safe to re-run to refresh config.
#
#   sudo SIEM_HOST=172.16.50.60 ELASTIC_PASSWORD='...' bash install-beats.sh
#
# The apps on this host must write their event JSONL to /var/log/aipostex/*.jsonl
# (the app provisioning creates that dir 1777 and sets EVENT_LOG); Filebeat's
# filestream input picks it up. Auditbeat needs no app cooperation.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

SIEM_HOST="${SIEM_HOST:-172.16.50.60}"
ELASTIC_PASSWORD="${ELASTIC_PASSWORD:-CHANGE_ME_elastic_password}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "[!] must run as root" >&2; exit 1
fi
if [[ "${ELASTIC_PASSWORD}" == CHANGE_ME_* ]]; then
  echo "[!] set ELASTIC_PASSWORD to the real elastic password (see operator notes)" >&2
  exit 1
fi

if ! dpkg -l 2>/dev/null | grep -qE '^ii  (filebeat|auditbeat) '; then
  echo "[*] adding Elastic 8.x apt repo"
  curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch \
    | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" \
    > /etc/apt/sources.list.d/elastic-8.x.list
  apt-get update -qq
  echo "[*] installing filebeat + auditbeat"
  apt-get install -y -qq filebeat auditbeat
fi

render() {  # render <template> <dest>
  sed -e "s|__SIEM_HOST__|${SIEM_HOST}|g" \
      -e "s|__ELASTIC_PASSWORD__|${ELASTIC_PASSWORD}|g" \
      "$1" > "$2"
  chmod 0600 "$2"
}

echo "[*] writing /etc/filebeat/filebeat.yml + /etc/auditbeat/auditbeat.yml (SIEM ${SIEM_HOST})"
render "${SCRIPT_DIR}/beats/filebeat.yml"  /etc/filebeat/filebeat.yml
render "${SCRIPT_DIR}/beats/auditbeat.yml" /etc/auditbeat/auditbeat.yml

filebeat  test config >/dev/null && echo "[+] filebeat config OK"
auditbeat test config >/dev/null && echo "[+] auditbeat config OK"

for svc in filebeat auditbeat; do
  systemctl enable "$svc" >/dev/null 2>&1 || true
  systemctl restart "$svc"
  sleep 1
  echo "[+] $svc: $(systemctl is-active "$svc")"
done
echo "[+] beats shipping to http://${SIEM_HOST}:9200"
