#!/bin/bash
# lab-verify-listeners.sh — Validate callback listener and A2A push-webhook round-trip
#
# Confirms that:
#   1. The lab-listener service is reachable from the attack box
#   2. The listener is reachable from each target VM (outbound webhook path)
#   3. POST → query API round-trip works
#   4. Full A2A push notification round-trip: SendMessage -> CreateTaskPushNotificationConfig -> re-send -> callback fires
#
# Run from ailab-attack after provisioning the attack box and ailab-app.
# Usage: bash lab-verify-listeners.sh [--verbose]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/inventory.sh"

VERBOSE=false
for arg in "$@"; do
    [[ "$arg" == "--verbose" ]] && VERBOSE=true
done

ATTACK_IP=$(inventory_host_ip "ailab-attack")
APP_IP=$(inventory_host_ip "ailab-app")
LISTENER_URL="http://${ATTACK_IP}:9000"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0

ok() { echo -e "${GREEN}[✓]${NC} $*"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}[✗]${NC} $*"; FAIL=$((FAIL + 1)); }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
step() { echo -e "${CYAN}[*]${NC} $*"; }

echo ""
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo "  aipostex-lab :: Listener Verification"
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo ""

# ── 1. Listener health from attack box ──────────────────────────────────────

step "Check 1: listener health from attack box"
health=$(curl -sf --max-time 5 "${LISTENER_URL}/health" 2>/dev/null || echo "")
if echo "$health" | grep -qi "healthy"; then
    ok "Listener ${LISTENER_URL}/health → healthy"
else
    fail "Listener not reachable at ${LISTENER_URL}/health"
    echo "  Ensure lab-listener.service is running: systemctl status lab-listener"
    echo ""
    echo -e "${RED}Cannot continue — fix listener first.${NC}"
    exit 1
fi

# ── 2. Listener reachable from each target VM ────────────────────────────────

step "Check 2: listener reachable from target VMs"
for host in ${LAB_TARGET_HOSTS}; do
    ip=$(inventory_host_ip "$host")
    resp=$(ssh ${SSH_OPTS} "labadmin@${ip}" \
        "curl -sf --max-time 5 ${LISTENER_URL}/health" 2>/dev/null || echo "")
    if echo "$resp" | grep -qi "healthy"; then
        ok "${host} (${ip}) can reach listener"
    else
        fail "${host} (${ip}) cannot reach ${LISTENER_URL}/health"
        warn "Check that port 9000 is reachable from ${host} to ailab-attack (${ATTACK_IP})"
    fi
done

# ── 3. POST → query round-trip ───────────────────────────────────────────────

step "Check 3: webhook POST → query API round-trip"
PROBE_ID="lab-verify-$(date +%s)"
post_resp=$(curl -sf -X POST "${LISTENER_URL}/callback/webhook" \
    -H "Content-Type: application/json" \
    -H "X-Probe-Id: ${PROBE_ID}" \
    -d "{\"taskId\":\"${PROBE_ID}\",\"status\":\"verify\",\"notes\":\"lab-verify-listeners check\"}" \
    2>/dev/null || echo "")
if $VERBOSE; then
    echo "    POST response: $post_resp"
fi

# Wait a beat for the ring buffer
sleep 1

query_resp=$(curl -sf "${LISTENER_URL}/callbacks?probe_id=${PROBE_ID}" 2>/dev/null || echo "")
cnt=$(echo "$query_resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "0")
if [ "${cnt}" -ge 1 ] 2>/dev/null; then
    ok "POST → query round-trip: probe_id=${PROBE_ID} count=${cnt}"
else
    fail "Query API returned count=${cnt} for probe_id=${PROBE_ID} (expected >=1)"
fi

# ── 4. SSRF beacon check ─────────────────────────────────────────────────────

step "Check 4: SSRF beacon endpoint"
SSRF_TOKEN="ssrf-verify-$(date +%s)"
ssrf_resp=$(curl -sf --max-time 5 \
    "${LISTENER_URL}/callback/ssrf/${SSRF_TOKEN}?probe_id=${SSRF_TOKEN}" 2>/dev/null || echo "")
if echo "$ssrf_resp" | grep -qi "received"; then
    ok "SSRF beacon endpoint responds (token=${SSRF_TOKEN})"
else
    fail "SSRF beacon endpoint did not respond as expected"
fi

# ── 5. Exfil sink ────────────────────────────────────────────────────────────

step "Check 5: exfil sink upload"
EXFIL_TAG="exfil-verify-$(date +%s)"
exfil_resp=$(curl -sf -X POST "${LISTENER_URL}/callback/exfil?tag=${EXFIL_TAG}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "lab-verify-listeners exfil test payload $(date)" \
    2>/dev/null || echo "")
exfil_ok=$(echo "$exfil_resp" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('recorded') and d.get('sha256') else 1)" 2>/dev/null; echo $?)
if [ "${exfil_ok}" -eq 0 ] 2>/dev/null; then
    sha=$(echo "$exfil_resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('sha256','')[:16])" 2>/dev/null || echo "")
    ok "Exfil sink recorded upload (sha256=${sha}...)"
else
    fail "Exfil sink did not return expected response"
fi

# ── 6. Full A2A push-webhook round-trip ─────────────────────────────────────

step "Check 6: A2A push notification round-trip (SendMessage -> CreateTaskPushNotificationConfig -> callback)"
A2A_TASK_ID="lab-verify-task-$(date +%s)"
A2A_URL="http://${APP_IP}:8100"
WEBHOOK_URL="${LISTENER_URL}/callback/webhook?probe_id=${A2A_TASK_ID}"

# Step 6a: Send initial task to create task state
step "  6a: SendMessage to create task ${A2A_TASK_ID}"
send_resp=$(curl -sf -X POST "${A2A_URL}/" \
    -H "Content-Type: application/json" \
    -H "A2A-Version: 1.0" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":\"v1\",\"method\":\"SendMessage\",\"params\":{\"message\":{\"role\":\"user\",\"parts\":[{\"text\":\"ping lab verify\"}],\"messageId\":\"${A2A_TASK_ID}\",\"taskId\":\"${A2A_TASK_ID}\"},\"metadata\":{}}}" \
    2>/dev/null || echo "")
if echo "$send_resp" | grep -qi "completed"; then
    ok "  SendMessage returned completed state"
else
    warn "  SendMessage response: ${send_resp:0:100}"
fi

# Step 6b: Register push webhook
step "  6b: CreateTaskPushNotificationConfig -> ${WEBHOOK_URL}"
push_resp=$(curl -sf -X POST "${A2A_URL}/" \
    -H "Content-Type: application/json" \
    -H "A2A-Version: 1.0" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":\"v2\",\"method\":\"CreateTaskPushNotificationConfig\",\"params\":{\"taskId\":\"${A2A_TASK_ID}\",\"pushNotificationConfig\":{\"url\":\"${WEBHOOK_URL}\"}}}" \
    2>/dev/null || echo "")
if $VERBOSE; then
    echo "    CreateTaskPushNotificationConfig response: $push_resp"
fi
if echo "$push_resp" | grep -qi "pushNotificationConfig"; then
    ok "  CreateTaskPushNotificationConfig accepted webhook URL"
else
    warn "  CreateTaskPushNotificationConfig response: ${push_resp:0:100}"
fi

# Step 6c: Re-send task to trigger webhook fire
step "  6c: SendMessage again to trigger push webhook"
curl -sf -X POST "${A2A_URL}/" \
    -H "Content-Type: application/json" \
    -H "A2A-Version: 1.0" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":\"v3\",\"method\":\"SendMessage\",\"params\":{\"message\":{\"role\":\"user\",\"parts\":[{\"text\":\"fire it\"}],\"messageId\":\"${A2A_TASK_ID}-again\",\"taskId\":\"${A2A_TASK_ID}\"},\"metadata\":{}}}" \
    >/dev/null 2>&1 || true

# Step 6d: Poll listener for callback (up to 5s)
step "  6d: polling listener for callback (up to 5s)"
fired=false
for _attempt in 1 2 3 4 5; do
    sleep 1
    cb_count=$(curl -sf "${LISTENER_URL}/callbacks?probe_id=${A2A_TASK_ID}" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "0")
    if [ "${cb_count:-0}" -ge 1 ] 2>/dev/null; then
        fired=true
        break
    fi
done

if $fired; then
    ok "A2A push webhook fired and received by listener (probe_id=${A2A_TASK_ID})"
else
    fail "A2A push webhook never received (waited 5s, count=0 for probe_id=${A2A_TASK_ID})"
    warn "Check that ailab-app (${APP_IP}) can reach attack box (${ATTACK_IP}:9000)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo -e "  Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo ""

if [ "${FAIL}" -eq 0 ]; then
    echo -e "${GREEN}All listener verification checks passed.${NC}"
    echo "  Lab is ready for A2A push-hijack and callback-validated probes."
    exit 0
else
    echo -e "${RED}${FAIL} check(s) failed. See above for details.${NC}"
    exit 1
fi
