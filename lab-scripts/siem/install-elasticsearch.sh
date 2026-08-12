#!/usr/bin/env bash
# install-elasticsearch.sh — Elasticsearch 8.x on ailab-siem (the detection host).
# Run ON the SIEM VM as root.
#
#   sudo ELASTIC_PASSWORD='...' KIBANA_PASSWORD='...' bash install-elasticsearch.sh
#
# Lab posture: single-node, security ENABLED (required for the Detection Engine) but
# HTTP + transport TLS OFF — the lab subnet is isolated, so auth rides plain HTTP with
# no certs. Bound to all interfaces, 2g heap.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

ES_HEAP="${ES_HEAP:-2g}"
ELASTIC_PASSWORD="${ELASTIC_PASSWORD:-CHANGE_ME_elastic_password}"
KIBANA_PASSWORD="${KIBANA_PASSWORD:-CHANGE_ME_kibana_system_password}"
ESBIN=/usr/share/elasticsearch/bin

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then echo "[!] run as root" >&2; exit 1; fi
if [[ "${ELASTIC_PASSWORD}" == CHANGE_ME_* || "${KIBANA_PASSWORD}" == CHANGE_ME_* ]]; then
  echo "[!] set ELASTIC_PASSWORD and KIBANA_PASSWORD (see operator notes)" >&2; exit 1
fi

if ! dpkg -l 2>/dev/null | grep -q '^ii  elasticsearch '; then
  echo "[*] adding Elastic 8.x apt repo"
  curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list
  apt-get update -qq
  echo "[*] installing elasticsearch (~600MB)"
  apt-get install -y -qq elasticsearch
fi

echo "[*] writing lab config (single-node, security on, TLS off, bind all)"
cat > /etc/elasticsearch/elasticsearch.yml <<'YML'
cluster.name: aipostex-detect
node.name: ailab-siem
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
xpack.security.enabled: true
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
YML

mkdir -p /etc/elasticsearch/jvm.options.d
printf -- '-Xms%s\n-Xmx%s\n' "${ES_HEAP}" "${ES_HEAP}" > /etc/elasticsearch/jvm.options.d/heap.options

# A fresh security-enabled install auto-provisions TLS material into the keystore; with
# TLS disabled here, remove any stale certs/keystore so the node starts clean.
rm -rf /etc/elasticsearch/certs 2>/dev/null || true

systemctl daemon-reload
systemctl enable elasticsearch >/dev/null 2>&1 || true
systemctl restart elasticsearch

echo "[*] waiting for Elasticsearch on :9200 ..."
for _ in $(seq 1 40); do
  curl -s -m5 -u "elastic:x" http://localhost:9200 2>/dev/null | grep -q '"status":401' && break
  curl -s -m5 http://localhost:9200 2>/dev/null | grep -q 'missing authentication' && break
  sleep 3
done

echo "[*] setting elastic + kibana_system passwords (deterministic)"
BOOT_PW="$("${ESBIN}/elasticsearch-reset-password" -u elastic -b -s)"
curl -s -u "elastic:${BOOT_PW}" -X POST "http://localhost:9200/_security/user/elastic/_password" \
  -H 'Content-Type: application/json' -d "{\"password\":\"${ELASTIC_PASSWORD}\"}" >/dev/null
curl -s -u "elastic:${ELASTIC_PASSWORD}" -X POST "http://localhost:9200/_security/user/kibana_system/_password" \
  -H 'Content-Type: application/json' -d "{\"password\":\"${KIBANA_PASSWORD}\"}" >/dev/null

echo "[+] Elasticsearch up + secured:"
curl -s -u "elastic:${ELASTIC_PASSWORD}" http://localhost:9200 | tr ',' '\n' | grep -E 'cluster_name|number' | sed 's/^/    /'
