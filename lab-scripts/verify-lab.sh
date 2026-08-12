#!/bin/bash
# verify-lab.sh — Full environment verification from your attack box
#
# Run from any machine that can reach 172.16.50.0/24
# Usage: bash verify-lab.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-scripts/lib/inventory.sh
source "${SCRIPT_DIR}/lib/inventory.sh"
# shellcheck source=lab-scripts/lib/service-catalog.sh
source "${SCRIPT_DIR}/lib/service-catalog.sh"

DEV_IP=$(inventory_host_ip "ailab-dev")
ML_IP=$(inventory_host_ip "ailab-ml")
DS_IP=$(inventory_host_ip "ailab-ds")
APP_IP=$(inventory_host_ip "ailab-app")
ATTACK_IP=$(inventory_host_ip "ailab-attack")
SIEM_IP=$(inventory_host_ip "ailab-siem")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

print_final_status_and_exit() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "  Final: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${WARN} warnings${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo ""

    if [[ $FAIL -eq 0 && $WARN -eq 0 ]]; then
        echo -e "${GREEN}Lab environment is fully operational. Ready for demo.${NC}"
        return 0
    fi

    if [[ $FAIL -eq 0 ]]; then
        echo -e "${YELLOW}Services are up but some data may not be seeded. Check warnings above.${NC}"
        return 0
    fi

    echo -e "${RED}Some services are down. Fix failures before running demos.${NC}"
    return 1
}

check() {
    local host=$1 port=$2 name=$3 path=$4 expect=$5 header=${6:-}
    local curl_args=(curl -sf --max-time 6)
    local result
    if [[ -n "${header}" ]]; then
        curl_args+=(-H "${header}")
    fi
    if [[ "$path" == "/mcp" ]]; then
        # Real MCP (Streamable HTTP) server: no GET health route — POST initialize
        # (the SSE-framed reply carries serverInfo).
        result=$("${curl_args[@]}" -X POST \
            -H 'Content-Type: application/json' \
            -H 'Accept: application/json, text/event-stream' \
            -d '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"verify","version":"1"}}}' \
            "http://$host:$port$path" 2>/dev/null || echo "UNREACHABLE")
    else
        result=$("${curl_args[@]}" "http://$host:$port$path" 2>/dev/null || echo "UNREACHABLE")
    fi
    if echo "$result" | grep -qi "$expect"; then
        echo -e "  ${GREEN}[✓]${NC} $name ($host:$port)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}[✗]${NC} $name ($host:$port) — expected '$expect'"
        FAIL=$((FAIL + 1))
    fi
}

run_service_checks_for_host() {
    local host_alias=$1
    local host_ip
    host_ip=$(inventory_host_ip "${host_alias}")
    echo -e "${YELLOW}── ${host_alias} (${host_ip}) ──${NC}"
    while IFS='|' read -r service_host port path expect name header; do
        [[ "${service_host}" == "${host_alias}" ]] || continue
        check "${host_ip}" "${port}" "${name}" "${path}" "${expect}" "${header}"
    done < <(inventory_service_health_checks)
    echo ""
}

check_ssh() {
    local host=$1 name=$2
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "labadmin@${host}" "echo ok" >/dev/null 2>&1; then
        echo -e "  ${GREEN}[✓]${NC} SSH to $name ($host)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}[✗]${NC} SSH to $name ($host)"
        FAIL=$((FAIL + 1))
    fi
}

main() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  aipostex Lab Environment Verification${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo ""

    # ── Network Connectivity ──────────────────────────────────
    echo -e "${YELLOW}── Network Connectivity ──${NC}"
    local host ip
    for host in ${LAB_ALL_HOSTS}; do
        ip=$(inventory_host_ip "$host")
        if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
            echo -e "  ${GREEN}[✓]${NC} Ping $ip"
            PASS=$((PASS + 1))
        else
            echo -e "  ${RED}[✗]${NC} Ping $ip"
            FAIL=$((FAIL + 1))
        fi
    done

    echo ""

    # ── SSH Access ────────────────────────────────────────────
    echo -e "${YELLOW}── SSH Access ──${NC}"
    check_ssh "$DEV_IP" "ailab-dev"
    check_ssh "$ML_IP" "ailab-ml"
    check_ssh "$DS_IP" "ailab-ds"
    check_ssh "$APP_IP" "ailab-app"
    check_ssh "$ATTACK_IP" "ailab-attack"

    echo ""

    run_service_checks_for_host "ailab-dev"
    run_service_checks_for_host "ailab-ml"
    run_service_checks_for_host "ailab-ds"
    run_service_checks_for_host "ailab-app"

    # ── Service Summary ──────────────────────────────────────
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "  Services: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"

    if [[ $FAIL -gt 0 ]]; then
        echo ""
        echo -e "${RED}Some services are not responding. Check systemd services on the affected VMs.${NC}"
        echo "  ssh labadmin@<ip> 'systemctl list-units --type=service --state=failed'"
        echo ""
    fi

    # ── Deep Validation (only if core services are up) ───────
    # Disable exit-on-error for deep validation — jq pipelines may return
    # non-zero on empty/unexpected data and we want to report, not abort.
    # NOTE: Cannot use a subshell here because PASS/FAIL/WARN counters
    # must propagate to print_final_status_and_exit. Strict mode is
    # restored at the end of this block.
    set +eo pipefail
    echo ""
    echo -e "${YELLOW}── Deep Validation ──${NC}"

# Ollama models
echo ""
echo "Ollama models on ailab-dev:"
models=$(curl -sf --max-time 5 "http://${DEV_IP}:11434/api/tags" 2>/dev/null || echo "")
if [ -n "$models" ]; then
    echo "$models" | jq -r '.models[].name' 2>/dev/null | while read -r m; do
        echo "  • $m"
    done
    # Check for custom models with system prompts
    count=$(echo "$models" | jq '.models | length' 2>/dev/null || echo "0")
    if [ "$count" -ge 3 ]; then
        echo -e "  ${GREEN}[✓]${NC} Found $count models (expecting base + 2 custom)"
    else
        echo -e "  ${YELLOW}[!]${NC} Found $count models (expecting 3: smollm2, acme-assistant, acme-support)"
        WARN=$((WARN + 1))
    fi
else
    echo -e "  ${RED}(failed to connect)${NC}"
fi

# ChromaDB collections (use Python client via SSH — REST API is unreliable in 0.6.x)
echo ""
echo "ChromaDB collections on ailab-ml:"
chroma_out=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "labadmin@${ML_IP}" \
    "/opt/chromadb/venv/bin/python3 -c 'import chromadb; c=chromadb.HttpClient(); cols=c.list_collections(); [print(n) for n in cols]'" 2>/dev/null || echo "")
if [ -n "$chroma_out" ]; then
    count=0
    while IFS= read -r c; do
        [ -n "$c" ] && echo "  • $c" && count=$((count + 1))
    done <<< "$chroma_out"
    if [ "$count" -ge 4 ]; then
        echo -e "  ${GREEN}[✓]${NC} Found $count collections (expecting 4: 3 sensitive + 1 noise)"
    else
        echo -e "  ${YELLOW}[!]${NC} Found $count collections (expecting 4)"
        WARN=$((WARN + 1))
    fi
else
    echo -e "  ${RED}(failed to connect)${NC}"
fi

# MCP tools — the target is a real MCP-SDK (FastMCP, Streamable HTTP) server at
# /mcp. It is session-strict (a bare tools/list is rejected) and SSE-frames its
# replies, so do a proper initialize -> session -> tools/list handshake and count
# the tool names it returns.
echo ""
echo "MCP tools on ailab-dev:"
mcp_hdr=$(mktemp)
curl -sf --max-time 6 -D "$mcp_hdr" -o /dev/null -X POST "http://${DEV_IP}:3000/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"verify-lab","version":"1.0"}}}' 2>/dev/null || true
sid=$(grep -i '^Mcp-Session-Id:' "$mcp_hdr" 2>/dev/null | tr -d '\r' | awk '{print $2}')
rm -f "$mcp_hdr"
if [ -n "$sid" ]; then
    curl -sf --max-time 6 -X POST "http://${DEV_IP}:3000/mcp" \
        -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
        -H "Mcp-Session-Id: $sid" \
        -d '{"jsonrpc":"2.0","id":2,"method":"notifications/initialized"}' >/dev/null 2>&1 || true
    tool_names=$(curl -sf --max-time 6 -X POST "http://${DEV_IP}:3000/mcp" \
        -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
        -H "Mcp-Session-Id: $sid" \
        -d '{"jsonrpc":"2.0","id":3,"method":"tools/list"}' 2>/dev/null \
        | grep '^data:' | sed 's/^data: *//' | jq -r '.result.tools[]?.name' 2>/dev/null)
    echo "$tool_names" | while read -r t; do [ -n "$t" ] && echo "  • $t"; done
    tool_count=$(echo "$tool_names" | grep -c .)
    if [ "$tool_count" -ge 5 ]; then
        echo -e "  ${GREEN}[✓]${NC} MCP server exposes $tool_count tools (expecting 5)"
    else
        echo -e "  ${YELLOW}[!]${NC} MCP server exposes $tool_count tools (expecting 5)"
        WARN=$((WARN + 1))
    fi
else
    echo -e "  ${RED}(failed to initialize MCP session at :3000/mcp)${NC}"
fi

# Gradio config
echo ""
echo "Gradio routes on ailab-dev:"
gradio_cfg=$(curl -sf --max-time 5 "http://${DEV_IP}:7860/config" 2>/dev/null || echo "")
gradio_info=$(curl -sf --max-time 5 "http://${DEV_IP}:7860/gradio_api/info" 2>/dev/null || echo "")
if [ -n "$gradio_cfg" ]; then
    echo "$gradio_cfg" | jq -r '.dependencies[]?.api_name // empty | ltrimstr("/")' 2>/dev/null | while read -r route; do
        echo "  • $route"
    done
    if echo "$gradio_cfg" | jq -e '
        .enable_queue == true
        or any(.dependencies[]?; (.queue // false) == true)
    ' >/dev/null 2>&1; then
        echo -e "  ${GREEN}[✓]${NC} Queue enabled"
    else
        echo -e "  ${YELLOW}[!]${NC} Queue not enabled in /config"
        WARN=$((WARN + 1))
    fi
    if printf '%s\n%s\n' "$gradio_cfg" "$gradio_info" | jq -s -e '
        [
            (.[0].dependencies[]?.api_name // empty | ltrimstr("/")),
            (.[1].named_endpoints? | keys[]? | ltrimstr("/"))
        ] |
        (index("predict_text") != null and index("export_bundle") != null and index("ingest_file") != null)
    ' >/dev/null 2>&1; then
        echo -e "  ${GREEN}[✓]${NC} Found expected Gradio routes"
    else
        echo -e "  ${YELLOW}[!]${NC} Missing one or more expected Gradio routes"
        WARN=$((WARN + 1))
    fi
else
    echo -e "  ${RED}(failed to connect)${NC}"
fi

# Weaviate classes
echo ""
echo "Weaviate classes on ailab-ds:"
wv_schema=$(curl -sf --max-time 5 "http://${DS_IP}:8080/v1/schema" 2>/dev/null || echo "")
wv_classes=$(echo "$wv_schema" | jq -r '.classes[]?.class // empty' 2>/dev/null || echo "")
if [ -z "$wv_classes" ]; then
    wv_classes=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
        "labadmin@${DS_IP}" "/opt/data-sci-seed/venv/bin/python3 - <<'PY'
import weaviate

client = weaviate.connect_to_local()
try:
    collections = client.collections.list_all()
    names = collections.keys() if hasattr(collections, 'keys') else collections
    for name in names:
        print(name)
finally:
    client.close()
PY" 2>/dev/null || echo "")
fi
if [ -n "$wv_schema" ]; then
    wv_count=0
    while IFS= read -r c; do
        [ -n "$c" ] || continue
        echo "  • $c"
        wv_count=$((wv_count + 1))
    done <<< "$wv_classes"
    if [ "$wv_count" -ge 3 ]; then
        echo -e "  ${GREEN}[✓]${NC} Found $wv_count classes (expecting 3)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}[!]${NC} Found $wv_count classes (expecting 3)"
        WARN=$((WARN + 1))
    fi
else
    echo -e "  ${RED}(failed to connect)${NC}"
fi

# Qdrant collections
echo ""
echo "Qdrant collections on ailab-ds:"
qd_resp=$(curl -sf --max-time 5 "http://${DS_IP}:6333/collections" 2>/dev/null || echo "")
qd_collections=$(echo "$qd_resp" | jq -r '.result.collections[]?.name // empty' 2>/dev/null || echo "")
if [ -z "$qd_collections" ]; then
    qd_collections=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
        "labadmin@${DS_IP}" "/opt/data-sci-seed/venv/bin/python3 - <<'PY'
from qdrant_client import QdrantClient

client = QdrantClient(host='localhost', port=6333, timeout=10)
for collection in client.get_collections().collections:
    print(collection.name)
PY" 2>/dev/null || echo "")
fi
if [ -n "$qd_resp" ]; then
    qd_count=0
    while IFS= read -r c; do
        [ -n "$c" ] || continue
        echo "  • $c"
        qd_count=$((qd_count + 1))
    done <<< "$qd_collections"
    if [ "$qd_count" -ge 3 ]; then
        echo -e "  ${GREEN}[✓]${NC} Found $qd_count collections (expecting 3)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}[!]${NC} Found $qd_count collections (expecting 3)"
        WARN=$((WARN + 1))
    fi
else
    echo -e "  ${RED}(failed to connect)${NC}"
fi

# PostgreSQL/pgvector tables
echo ""
echo "PostgreSQL/pgvector tables on ailab-ds:"
pg_tables=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
    "labadmin@${DS_IP}" "sudo -u postgres psql -d labdb -t -A -c \"SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename\"" 2>/dev/null || echo "")
if [ -n "$pg_tables" ]; then
    count=0
    while IFS= read -r t; do
        [ -n "$t" ] && echo "  • $t" && count=$((count + 1))
    done <<< "$pg_tables"
    if [ "$count" -ge 4 ]; then
        echo -e "  ${GREEN}[✓]${NC} Found $count tables"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}[!]${NC} Found $count tables (expecting 4)"
        WARN=$((WARN + 1))
    fi
    # Check pgvector extension
    pgvec=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
        "labadmin@${DS_IP}" "sudo -u postgres psql -d labdb -t -A -c \"SELECT 1 FROM pg_extension WHERE extname = 'vector'\"" 2>/dev/null || echo "")
    if echo "$pgvec" | grep -q "1"; then
        echo -e "  ${GREEN}[✓]${NC} pgvector extension installed"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}[!]${NC} pgvector extension not found"
        WARN=$((WARN + 1))
    fi
else
    echo -e "  ${RED}(failed to connect)${NC}"
fi

# Black-box RAG app
echo ""
echo "Black-box RAG app on ailab-ds:"
rag_health=$(curl -sf --max-time 5 "http://${DS_IP}:8091/health" 2>/dev/null || echo "")
if echo "$rag_health" | grep -qi "healthy"; then
    echo -e "  ${GREEN}[✓]${NC} RAG app :8091 health check OK"
    PASS=$((PASS + 1))
    rag_sources=$(curl -sf --max-time 8 -X POST "http://${DS_IP}:8091/query" \
        -H "Content-Type: application/json" -d '{"query":"list all server names"}' 2>/dev/null || echo "")
    if echo "$rag_sources" | grep -qi "AD_Server_Inventory"; then
        echo -e "  ${GREEN}[✓]${NC} RAG /query returns source citations from the seeded knowledge base"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}[!]${NC} RAG /query did not return expected source citations"
        WARN=$((WARN + 1))
    fi
else
    echo -e "  ${YELLOW}[!]${NC} RAG app :8091 not responding"
    WARN=$((WARN + 1))
fi

# MLflow registry
echo ""
echo "MLflow registry on ailab-ml:"
mlflow_registry=$(curl -sf --max-time 5 "http://${ML_IP}:5000/api/2.0/mlflow/registered-models/search" 2>/dev/null || echo "")
if [ -n "$mlflow_registry" ]; then
    echo "$mlflow_registry" | jq -r '.registered_models[]?.name // empty' 2>/dev/null | while read -r name; do
        echo "  • $name"
    done
    if echo "$mlflow_registry" | grep -q "acme-churn-ensemble" && echo "$mlflow_registry" | grep -q "acme-fraud-bert"; then
        echo -e "  ${GREEN}[✓]${NC} Found expected registered models"
    else
        echo -e "  ${YELLOW}[!]${NC} Missing one or more expected registered models"
        WARN=$((WARN + 1))
    fi
else
    echo -e "  ${RED}(failed to connect)${NC}"
fi

# Ray jobs
echo ""
echo "Ray seeded jobs on ailab-ml:"
ray_jobs=$(curl -sf --max-time 5 "http://${ML_IP}:8265/api/jobs/" 2>/dev/null || echo "")
if [ -n "$ray_jobs" ]; then
    echo "$ray_jobs" | jq -r '.[]?.metadata.name // empty' 2>/dev/null | while read -r name; do
        echo "  • $name"
    done
    if echo "$ray_jobs" | grep -q "runtime-env-validator" && echo "$ray_jobs" | grep -q "churn-model-retraining"; then
        echo -e "  ${GREEN}[✓]${NC} Found expected Ray seeded jobs"
    else
        echo -e "  ${YELLOW}[!]${NC} Missing one or more expected Ray seeded jobs"
        WARN=$((WARN + 1))
    fi
else
    echo -e "  ${RED}(failed to connect)${NC}"
fi

# Attack-box MCP fixtures
echo ""
echo "Attack-box MCP fixtures:"
# Validate CONTENT (a real http://<ip>:... peer URL), not just existence — an empty
# inventory could write a malformed http://:3000 that a bare -f check would pass.
if grep -q 'http://[0-9]' "$HOME/lab/mcp-configs/remote_mcp_chain.json" 2>/dev/null || \
   ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "labadmin@${ATTACK_IP}" "grep -q 'http://[0-9]' ~/lab/mcp-configs/remote_mcp_chain.json" 2>/dev/null; then
    echo -e "  ${GREEN}[✓]${NC} remote_mcp_chain.json present (valid peer URL)"
else
    echo -e "  ${YELLOW}[!]${NC} remote_mcp_chain.json missing or malformed — re-run attack-box/setup.sh"
    WARN=$((WARN + 1))
fi

echo ""
echo "LangServe on ailab-app:"
langserve_docs=$(curl -sf --max-time 5 "http://${APP_IP}:8090/docs" 2>/dev/null || echo "")
if echo "$langserve_docs" | grep -qi "langserve\|swagger"; then
    echo -e "  ${GREEN}[✓]${NC} LangServe docs are reachable"
else
    echo -e "  ${YELLOW}[!]${NC} LangServe docs not returning expected content"
    WARN=$((WARN + 1))
fi

echo ""
echo "Streamlit on ailab-app:"
streamlit_health=$(curl -sf --max-time 5 "http://${APP_IP}:8501/_stcore/health" 2>/dev/null || echo "")
if echo "$streamlit_health" | grep -qi "ok"; then
    echo -e "  ${GREEN}[✓]${NC} Streamlit native health endpoint returns ok"
else
    echo -e "  ${YELLOW}[!]${NC} Streamlit native health endpoint missing"
    WARN=$((WARN + 1))
fi

echo ""
echo "A2A agents on ailab-app:"
for a2a_port in 8100 8101 8102; do
    a2a_card=$(curl -sf --max-time 5 "http://${APP_IP}:${a2a_port}/.well-known/agent-card.json" 2>/dev/null || echo "")
    skill_count=$(echo "$a2a_card" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('skills',[])))" 2>/dev/null || echo "0")
    if [ "$skill_count" -ge 4 ]; then
        agent_name=$(echo "$a2a_card" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name',''))" 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}[✓]${NC} Port ${a2a_port}: '${agent_name}' — ${skill_count} skills advertised"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}[!]${NC} Port ${a2a_port}: expected >=4 skills in agent card, got ${skill_count}"
        WARN=$((WARN + 1))
    fi
done

# Multi-turn task history seeded on 8101
mt_history=$(curl -sf --max-time 5 -X POST "http://${APP_IP}:8101/" \
    -H "Content-Type: application/json" \
    -H "A2A-Version: 1.0" \
    -d '{"jsonrpc":"2.0","id":"v1","method":"GetTask","params":{"id":"task-acme-procurement-0001","historyLength":20}}' 2>/dev/null \
    | python3 -c "import sys,json; r=json.load(sys.stdin); result=r.get('result',{}); task=result.get('task', result); print(len(task.get('history',[])))" 2>/dev/null || echo "0")
if [ "$mt_history" -ge 4 ]; then
    echo -e "  ${GREEN}[✓]${NC} Multi-turn task history seeded (${mt_history} turns in task-acme-procurement-0001)"
    PASS=$((PASS + 1))
else
    echo -e "  ${YELLOW}[!]${NC} Multi-turn task history not seeded (got ${mt_history} turns, expected >=4)"
    WARN=$((WARN + 1))
fi

echo ""
echo "Lab listener on ailab-attack:"
listener_health=$(curl -sf --max-time 5 "http://${ATTACK_IP}:9000/health" 2>/dev/null || echo "")
if echo "$listener_health" | grep -qi "healthy"; then
    echo -e "  ${GREEN}[✓]${NC} Lab listener :9000 health check OK"
    PASS=$((PASS + 1))
else
    echo -e "  ${YELLOW}[!]${NC} Lab listener :9000 not responding — run lab-listener.service on attack box"
    WARN=$((WARN + 1))
fi

echo ""
echo "Post-Ex Oracle on ailab-app:"
pox_health=$(curl -sf --max-time 5 "http://${APP_IP}:8765/health" 2>/dev/null || echo "")
if echo "$pox_health" | grep -qi "healthy"; then
    echo -e "  ${GREEN}[✓]${NC} Post-Ex Oracle :8765 health check OK"
    pox_replay=$(curl -sf --max-time 5 "http://${APP_IP}:8765/replay/expectations" 2>/dev/null || echo "[]")
    replay_count=$(echo "$pox_replay" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    if [ "$replay_count" -ge 15 ]; then
        echo -e "  ${GREEN}[✓]${NC} Post-Ex Oracle seeded with ${replay_count} credential validators"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}[!]${NC} Post-Ex Oracle replay expectations: ${replay_count} (expected >=15, run seed.py)"
        WARN=$((WARN + 1))
    fi
else
    echo -e "  ${YELLOW}[!]${NC} Post-Ex Oracle :8765 not responding (opt-in service)"
    WARN=$((WARN + 1))
fi

echo ""
echo "Elastic detection stack on ailab-siem (${SIEM_IP}):"
# Elasticsearch up? With security on, an unauthenticated request returns 401 'missing
# authentication' — which still proves ES is reachable. Set ELASTIC_PASSWORD to also
# verify cluster health, the loaded detection rules, and that Beats telemetry is landing.
es_probe=$(curl -s --max-time 5 "http://${SIEM_IP}:9200" 2>/dev/null || echo "")
if echo "$es_probe" | grep -qiE "missing authentication|cluster_name"; then
    echo -e "  ${GREEN}[✓]${NC} Elasticsearch :9200 reachable"
    PASS=$((PASS + 1))
    if [ -n "${ELASTIC_PASSWORD:-}" ]; then
        es_health=$(curl -sf --max-time 5 -u "elastic:${ELASTIC_PASSWORD}" "http://${SIEM_IP}:9200/_cluster/health" 2>/dev/null || echo "")
        if echo "$es_health" | grep -qiE '"status":"(green|yellow)"'; then
            echo -e "  ${GREEN}[✓]${NC} ES cluster health green/yellow"
            PASS=$((PASS + 1))
        else
            echo -e "  ${YELLOW}[!]${NC} ES cluster health not green/yellow"
            WARN=$((WARN + 1))
        fi
        rule_count=$(curl -sf --max-time 5 -u "elastic:${ELASTIC_PASSWORD}" -H "kbn-xsrf: true" \
            "http://${SIEM_IP}:5601/api/detection_engine/rules/_find?filter=alert.attributes.tags:aipostex&per_page=1" 2>/dev/null \
            | grep -oE '"total":[0-9]+' | head -1 | cut -d: -f2)
        if [ "${rule_count:-0}" -ge 5 ]; then
            echo -e "  ${GREEN}[✓]${NC} ${rule_count} aipostex detection rules loaded in Kibana"
            PASS=$((PASS + 1))
        else
            echo -e "  ${YELLOW}[!]${NC} expected >=5 aipostex detection rules, found ${rule_count:-0}"
            WARN=$((WARN + 1))
        fi
        app_docs=$(curl -sf --max-time 5 -u "elastic:${ELASTIC_PASSWORD}" \
            "http://${SIEM_IP}:9200/filebeat-*/_count" -H "Content-Type: application/json" \
            --data-binary '{"query":{"term":{"event.dataset":"aipostex.app"}}}' 2>/dev/null \
            | grep -oE '"count":[0-9]+' | head -1 | cut -d: -f2)
        if [ "${app_docs:-0}" -ge 1 ]; then
            echo -e "  ${GREEN}[✓]${NC} Filebeat shipping app telemetry (event.dataset:aipostex.app = ${app_docs})"
            PASS=$((PASS + 1))
        else
            echo -e "  ${YELLOW}[!]${NC} no aipostex.app events in Elasticsearch yet"
            WARN=$((WARN + 1))
        fi
    else
        echo -e "  ${CYAN}[i]${NC} set ELASTIC_PASSWORD to also verify cluster health, rules, and Beats telemetry"
    fi
else
    echo -e "  ${YELLOW}[!]${NC} Elasticsearch :9200 on ${SIEM_IP} not responding"
    WARN=$((WARN + 1))
fi

echo ""
echo "Bespoke IT-helpdesk agent on ailab-app:"
helpdesk_health=$(curl -sf --max-time 5 "http://${APP_IP}:8110/health" 2>/dev/null || echo "")
if echo "$helpdesk_health" | grep -qi "healthy"; then
    echo -e "  ${GREEN}[✓]${NC} Helpdesk agent :8110 health check OK"
    PASS=$((PASS + 1))
else
    echo -e "  ${YELLOW}[!]${NC} Helpdesk agent :8110 not responding"
    WARN=$((WARN + 1))
fi

echo ""
echo "Inference gateways and mocks:"
tgi_info=$(curl -sf --max-time 5 "http://${APP_IP}:8180/info" 2>/dev/null || echo "")
tei_info=$(curl -sf --max-time 5 "http://${ML_IP}:8181/info" 2>/dev/null || echo "")
vllm_models=$(curl -sf --max-time 5 "http://${ML_IP}:8182/v1/models" 2>/dev/null || echo "")
vllm_chat=$(curl -sf --max-time 5 -X POST "http://${ML_IP}:8182/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"vllm-lab-model","messages":[{"role":"user","content":"ping"}]}' 2>/dev/null || echo "")
if echo "$tgi_info" | grep -qi "model_id"; then
    echo -e "  ${GREEN}[✓]${NC} HF TGI gateway info endpoint returns model metadata"
else
    echo -e "  ${YELLOW}[!]${NC} HF TGI gateway info endpoint missing expected metadata"
    WARN=$((WARN + 1))
fi
if echo "$tei_info" | grep -qi "embedding"; then
    echo -e "  ${GREEN}[✓]${NC} HF TEI mock info endpoint returns embedding metadata"
else
    echo -e "  ${YELLOW}[!]${NC} HF TEI mock info endpoint missing expected metadata"
    WARN=$((WARN + 1))
fi
if echo "$vllm_models" | grep -qi "vllm-lab-model"; then
    echo -e "  ${GREEN}[✓]${NC} vLLM mock model list returns expected model id"
else
    echo -e "  ${YELLOW}[!]${NC} vLLM mock model list missing expected model id"
    WARN=$((WARN + 1))
fi
if echo "$vllm_chat" | grep -qi "chat.completion"; then
    echo -e "  ${GREEN}[✓]${NC} vLLM mock chat completions endpoint returns OpenAI-compatible response"
else
    echo -e "  ${YELLOW}[!]${NC} vLLM mock chat completions endpoint missing expected response"
    WARN=$((WARN + 1))
fi

# W&B mock deep validation
echo ""
echo "W&B mock on ailab-ml:"
wandb_health=$(curl -sf --max-time 5 "http://${ML_IP}:8444/healthz" 2>/dev/null || echo "")
if echo "$wandb_health" | grep -qi "wandb"; then
    echo -e "  ${GREEN}[✓]${NC} W&B mock :8444 health check OK"
    PASS=$((PASS + 1))
    wandb_projects=$(curl -sf --max-time 5 -X POST "http://${ML_IP}:8444/graphql" \
        -H "Content-Type: application/json" \
        -d '{"query":"query Projects($entity: String!, $perPage: Int = 20) { models(entityName: $entity, first: $perPage) { edges { node { id name entityName } } } }","variables":{"entity":"acme-ml-team","perPage":20}}' 2>/dev/null || echo "")
    proj_count=$(echo "$wandb_projects" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',{}).get('models',{}).get('edges',[])))" 2>/dev/null || echo "0")
    if [ "$proj_count" -ge 2 ]; then
        echo -e "  ${GREEN}[✓]${NC} W&B mock returns ${proj_count} projects"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}[!]${NC} W&B mock expected >=2 projects, got ${proj_count}"
        WARN=$((WARN + 1))
    fi
    wandb_runs=$(curl -sf --max-time 5 -X POST "http://${ML_IP}:8444/graphql" \
        -H "Content-Type: application/json" \
        -d '{"query":"query Runs($entity: String!, $project: String!, $perPage: Int = 20) { project(entityName: $entity, name: $project) { runs(first: $perPage) { edges { node { id name config summaryMetrics } } } } }","variables":{"entity":"acme-ml-team","project":"churn-prediction","perPage":20}}' 2>/dev/null || echo "")
    run_count=$(echo "$wandb_runs" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',{}).get('project',{}).get('runs',{}).get('edges',[])))" 2>/dev/null || echo "0")
    if [ "$run_count" -ge 2 ]; then
        echo -e "  ${GREEN}[✓]${NC} W&B churn-prediction has ${run_count} runs with seeded configs"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}[!]${NC} W&B churn-prediction expected >=2 runs, got ${run_count}"
        WARN=$((WARN + 1))
    fi
else
    echo -e "  ${YELLOW}[!]${NC} W&B mock :8444 not responding — check wandb-mock.service on ailab-ml"
    WARN=$((WARN + 1))
fi

# Kubeflow mock deep validation
echo ""
echo "Kubeflow mock on ailab-ml:"
kf_dashboard=$(curl -sf --max-time 5 "http://${ML_IP}:9000/pipeline/" 2>/dev/null || echo "")
if echo "$kf_dashboard" | grep -qi "pipeline"; then
    echo -e "  ${GREEN}[✓]${NC} Kubeflow mock :9000 dashboard reachable"
    PASS=$((PASS + 1))
    kf_pipelines=$(curl -sf --max-time 5 "http://${ML_IP}:9000/pipeline/api/v1beta1/pipelines?page_size=50" 2>/dev/null || echo "")
    pipe_count=$(echo "$kf_pipelines" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('pipelines',[])))" 2>/dev/null || echo "0")
    if [ "$pipe_count" -ge 2 ]; then
        echo -e "  ${GREEN}[✓]${NC} Kubeflow mock returns ${pipe_count} pipelines"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}[!]${NC} Kubeflow mock expected >=2 pipelines, got ${pipe_count}"
        WARN=$((WARN + 1))
    fi
    kf_runs=$(curl -sf --max-time 5 "http://${ML_IP}:9000/pipeline/api/v1beta1/runs?page_size=50" 2>/dev/null || echo "")
    run_count=$(echo "$kf_runs" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('runs',[])))" 2>/dev/null || echo "0")
    if [ "$run_count" -ge 3 ]; then
        echo -e "  ${GREEN}[✓]${NC} Kubeflow mock has ${run_count} runs with seeded pipeline params"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}[!]${NC} Kubeflow mock expected >=3 runs, got ${run_count}"
        WARN=$((WARN + 1))
    fi
else
    echo -e "  ${YELLOW}[!]${NC} Kubeflow mock :9000 not responding — check kubeflow-mock.service on ailab-ml"
    WARN=$((WARN + 1))
fi

# TF Serving mock deep validation
echo ""
echo "TF Serving mock on ailab-ml:"
tfs_model=$(curl -sf --max-time 5 "http://${ML_IP}:8501/v1/models/acme-fraud-scorer" 2>/dev/null || echo "")
if echo "$tfs_model" | grep -qi "model_version_status"; then
    echo -e "  ${GREEN}[✓]${NC} TF Serving mock :8501 returns model status"
    PASS=$((PASS + 1))
    version_count=$(echo "$tfs_model" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('model_version_status',[])))" 2>/dev/null || echo "0")
    if [ "$version_count" -ge 2 ]; then
        echo -e "  ${GREEN}[✓]${NC} acme-fraud-scorer has ${version_count} versions"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}[!]${NC} Expected >=2 model versions, got ${version_count}"
        WARN=$((WARN + 1))
    fi
    tfs_metrics=$(curl -sf --max-time 5 "http://${ML_IP}:8501/monitoring/prometheus/metrics" 2>/dev/null || echo "")
    if echo "$tfs_metrics" | grep -q "tensorflow"; then
        echo -e "  ${GREEN}[✓]${NC} TF Serving Prometheus metrics endpoint available"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}[!]${NC} TF Serving /monitoring/prometheus/metrics not returning expected data"
        WARN=$((WARN + 1))
    fi
else
    echo -e "  ${YELLOW}[!]${NC} TF Serving mock :8501 not responding — check tfserving-mock.service on ailab-ml"
    WARN=$((WARN + 1))
fi

# Kubernetes cluster (ailab-k8s) — real k3s target, deliberately weak (anon RBAC)
echo ""
K8S_IP=$(inventory_host_ip ailab-k8s)
echo "Kubernetes cluster on ailab-k8s (${K8S_IP}):"
if curl -sk --max-time 6 "https://${K8S_IP}:6443/version" 2>/dev/null | grep -q "gitVersion"; then
    echo -e "  ${GREEN}[✓]${NC} k3s API anon-reachable :6443"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}[✗]${NC} k3s API :6443 not anon-reachable"
    FAIL=$((FAIL + 1))
fi
if curl -sk --max-time 6 "https://${K8S_IP}:6443/api/v1/namespaces/ml-prod/secrets" 2>/dev/null | grep -q '"kind"'; then
    echo -e "  ${GREEN}[✓]${NC} anonymous secret-read in ml-prod (deliberately weak)"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}[✗]${NC} anonymous secret-read blocked — anon-rbac binding missing"
    FAIL=$((FAIL + 1))
fi
if curl -sk --max-time 6 "https://${K8S_IP}:6443/api/v1/namespaces/ml-prod/pods" 2>/dev/null | grep -qi "Running"; then
    echo -e "  ${GREEN}[✓]${NC} ml-prod workload pod Running"
    PASS=$((PASS + 1))
else
    echo -e "  ${YELLOW}[!]${NC} ml-prod pod not Running yet"
    WARN=$((WARN + 1))
fi

# Filesystem artifacts (requires SSH)
echo ""
echo "Filesystem artifacts on ailab-dev:"
if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "labadmin@${DEV_IP}" "test -d /home/devuser" 2>/dev/null; then
    artifact_count=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "labadmin@${DEV_IP}" "sudo find /home/devuser \( -name '.env' -o -name 'claude_desktop_config.json' -o -name 'credentials' -o -name 'token' -o -name '*.jsonl' -o -name 'mcp.json' \) 2>/dev/null | wc -l" 2>/dev/null || echo "0")
    echo -e "  Found ${artifact_count} discoverable files"
    if [ "$artifact_count" -ge 8 ]; then
        echo -e "  ${GREEN}[✓]${NC} Sufficient artifacts for demo"
    else
        echo -e "  ${YELLOW}[!]${NC} Expected 8+ findable artifacts, found $artifact_count"
        WARN=$((WARN + 1))
    fi
else
    echo -e "  ${YELLOW}[!]${NC} /home/devuser not found — run seed-filesystem.sh"
    WARN=$((WARN + 1))
fi

    set -euo pipefail
    print_final_status_and_exit
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
