#!/usr/bin/env bash
# load-detection-rules.sh — import the aipostex detection rules into Kibana's Detection
# Engine from detection-rules.ndjson. Idempotent: --overwrite refreshes existing rules.
#
#   SIEM_HOST=172.16.50.60 ELASTIC_PASSWORD='...' bash load-detection-rules.sh
#
# Rules and the telemetry they match:
#   aipostex-revshell-indicators   process.args ~ /dev/tcp|/dev/udp        (auditbeat process)
#   aipostex-fim-sensitive-path    file_integrity change in a privesc path (auditbeat FIM)
#   aipostex-app-prompt-injection  injection/encoding phrasing in ai.query (filebeat app)
#   aipostex-app-kb-enumeration    KB/secret enumeration in ai.query       (filebeat app)
#   aipostex-app-rag-ingestion     ai.event_type:ingest                    (filebeat app)
set -euo pipefail

SIEM_HOST="${SIEM_HOST:-172.16.50.60}"
ELASTIC_PASSWORD="${ELASTIC_PASSWORD:-CHANGE_ME_elastic_password}"
KB="http://${SIEM_HOST}:5601"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
NDJSON="${SCRIPT_DIR}/detection-rules.ndjson"

if [[ "${ELASTIC_PASSWORD}" == CHANGE_ME_* ]]; then
  echo "[!] set ELASTIC_PASSWORD to the real elastic password (see operator notes)" >&2; exit 1
fi
[[ -f "${NDJSON}" ]] || { echo "[!] ${NDJSON} not found" >&2; exit 1; }

echo "[*] importing $(grep -c . "${NDJSON}") rules into ${KB}"
RESP=$(curl -s -u "elastic:${ELASTIC_PASSWORD}" -H "kbn-xsrf: true" \
  -X POST "${KB}/api/detection_engine/rules/_import?overwrite=true" \
  --form "file=@${NDJSON};type=application/ndjson")
echo "${RESP}" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(f\"[+] success={d.get('success')} imported={d.get('success_count')} errors={len(d.get('errors',[]))}\")
for e in d.get('errors',[]):
    print('    ! ', e.get('rule_id'), e.get('error',{}).get('message'))
" || { echo "[!] unexpected response:"; echo "${RESP}"; exit 1; }
