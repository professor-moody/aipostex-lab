#!/bin/bash
# reseed.sh - restore ONE shared estate host in seconds, without a wave reset.
#
# Run ON THE ATTACK BOX during a wave (facilitator "panic button"). Attendees share
# one estate and use the tool freely; the rare destructive action (RCE cleanup,
# `ollama delete`, `torchserve unregister`, a dropped collection, a killed service)
# breaks that one host for its other users. `reset-wave` would fix it but rolls the
# attack box back too - wiping EVERY seat's in-progress work. This restores just the
# one host and leaves all seats untouched.
#
# The chain spine is structurally safe (no verb deletes the seeded Ray job or the
# HF-token MLflow run), so a reseed is only ever needed for a broken branch surface.
#
# Usage:
#   bash reseed.sh <dev|ml|ds|app|k8s>            # restore a whole host's seeded state
#   bash reseed.sh <host> --service <unit>        # just restart one systemd unit (e.g. torchserve-mock)
#   bash reseed.sh --list                         # what each host restores
#   LAB_SUBNET=10.0.1 bash reseed.sh ml           # AWS estate (or any GROUP_ID>0 estate)
#
# Recipes mirror the reset-wave.sh [3/4] re-arm + the per-role seed scripts.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-scripts/lib/inventory.sh
source "${SCRIPT_DIR}/lib/inventory.sh"

SSH_USER="${SSH_USER:-labadmin}"
SSH_OPTS="${SSH_OPTS:--o StrictHostKeyChecking=no -o ConnectTimeout=6 -o BatchMode=yes}"
SERVICE=""
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

log(){ echo -e "${CYAN}[reseed]${NC} $*"; }
ok(){  echo -e "${GREEN}[+]${NC} $*"; }
die(){ echo -e "${RED}[!]${NC} $*" >&2; exit 1; }
rsh(){ ssh $SSH_OPTS "${SSH_USER}@$1" "${@:2}"; }

list_hosts() {
    cat <<EOF
reseed <host>  - restores, on subnet ${LAB_SUBNET}:
  dev   .10   dev-workstation/seed.sh (Ollama models + files + notebooks) + restart acme-mcp
  ml    .20   ml-platform/seed.sh (ChromaDB + MLflow + Ray; restart-then-seed built in)
  ds    .30   data-sci/seed.sh (Weaviate + Qdrant + pgvector) + warm Ollama
  app   .40   restart the app units (langserve/streamlit/tgi-gateway/a2a/post-ex-oracle)
  k8s   .50   docker restart k8s-vuln k8s-secure (k3s pair re-applies its seed manifests)
  <host> --service <unit>   restart a single systemd unit (e.g. torchserve-mock, hf-tgi-mock)
EOF
}

HOST=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --service) SERVICE="$2"; shift 2 ;;
        --list|-l) list_hosts; exit 0 ;;
        -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
        dev|ml|ds|app|k8s) HOST="$1"; shift ;;
        *) die "unknown arg: $1 (want one of dev|ml|ds|app|k8s, or --list)" ;;
    esac
done
[[ -n "$HOST" ]] || { list_hosts; exit 2; }

ip="$(inventory_host_ip "ailab-${HOST}")" || die "no IP for host ${HOST}"
sub="${LAB_SUBNET}"
log "restoring ${HOST} (${ip}) on subnet ${sub}${SERVICE:+, service ${SERVICE}}"

# Targeted single-unit restart (for the in-memory-fixture mocks: torchserve/triton/vllm/
# bentoml/wandb/kubeflow/hf-* - their seeded state is in-process, so a restart restores it).
if [[ -n "$SERVICE" ]]; then
    rsh "$ip" "sudo systemctl restart '${SERVICE}'" || die "restart ${SERVICE} on ${HOST} failed"
    ok "restarted ${SERVICE} on ${HOST}"
    exit 0
fi

case "$HOST" in
    dev)
        rsh "$ip" "sudo bash ~/lab/dev-workstation/seed.sh && sudo systemctl restart acme-mcp" \
            || die "reseed dev failed" ;;
    ml)
        rsh "$ip" "sudo env ESTATE_SUBNET=${sub} bash ~/lab/ml-platform/seed.sh" \
            || die "reseed ml failed" ;;
    ds)
        rsh "$ip" "sudo bash ~/lab/data-sci/seed.sh; (echo hi | ollama run smollm2:135m >/dev/null 2>&1 || true)" \
            || die "reseed ds failed" ;;
    app)
        # app-platform has no seed.sh - its fixtures are baked and served by systemd; restart re-seeds.
        rsh "$ip" "for u in langserve streamlit tgi-gateway a2a-agent-basic a2a-agent-multiturn a2a-agent-authed a2a-agent-real post-ex-oracle; do sudo systemctl restart \$u 2>/dev/null || true; done" \
            || die "reseed app failed" ;;
    k8s)
        rsh "$ip" "sudo docker restart k8s-vuln k8s-secure" \
            || die "reseed k8s failed" ;;
esac
ok "reseed ${HOST} complete - seats untouched, no wave reset needed"
