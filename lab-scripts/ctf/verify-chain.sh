#!/bin/bash
# verify-chain.sh — internal proof that the guided chain is real.
#
# This is an operator/event-readiness verifier, not the attendee score.
# It proves negative and positive auth behavior for:
#   Ray leak -> MLflow Basic Auth gateway -> HF token -> TGI gateway.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lab-scripts/lib/inventory.sh
source "${LAB_DIR}/lib/inventory.sh"
# shellcheck source=lab-scripts/lib/chain-config.sh
source "${LAB_DIR}/lib/chain-config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

RAY_URL="$(chain_ray_url)"
MLFLOW_URL="$(chain_mlflow_url)"
TGI_URL="$(chain_tgi_url)"
LITELLM_URL="$(chain_litellm_url)"
MLFLOW_AUTH="$(chain_mlflow_basic_header)"
HF_AUTH="$(chain_hf_bearer_header)"
LITELLM_AUTH="$(chain_litellm_bearer_header)"

log() { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
section() { echo ""; echo -e "${YELLOW}── $1 ──${NC}"; }
pass() { echo -e "  ${GREEN}[✓]${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}[✗]${NC} $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${YELLOW}[!]${NC} $1"; WARN=$((WARN + 1)); }

status_of() {
    curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "$@"
}

expect_status() {
    local name=$1 expected=$2
    shift 2
    local got
    got=$(status_of "$@" || true)
    if [[ "${got}" == "${expected}" ]]; then
        pass "${name} (${got})"
    else
        fail "${name} — expected ${expected}, got ${got:-curl-error}"
    fi
}

expect_body_contains() {
    local name=$1 expected=$2
    shift 2
    local body
    body=$(curl -fsS --max-time 8 "$@" 2>/dev/null || true)
    if grep -Fq "${expected}" <<<"${body}"; then
        pass "${name}"
    else
        fail "${name} — expected body marker '${expected}'"
    fi
}

check_ray_leak() {
    section "Ray leak"
    expect_body_contains "Ray dashboard reachable" "ray" "${RAY_URL}/api/version"

    local jobs
    jobs=$(curl -fsS --max-time 8 "${RAY_URL}/api/jobs/" 2>/dev/null || true)
    if [[ -z "${jobs}" ]]; then
        fail "Ray jobs API returned no body"
        return
    fi
    if grep -Fq "MLFLOW_TRACKING_URI" <<<"${jobs}" && grep -Fq "${CHAIN_MLFLOW_PASSWORD}" <<<"${jobs}"; then
        pass "Ray job runtime_env exposes MLflow URI and credential"
        return
    fi

    if ! command -v jq >/dev/null 2>&1; then
        warn "jq missing; could not inspect per-job Ray details"
        return
    fi

    local job_ids found
    found=0
    job_ids=$(jq -r 'if type=="array" then .[] else (.jobs // [])[] end | .job_id // .id // .submission_id // empty' <<<"${jobs}" 2>/dev/null || true)
    while IFS= read -r job_id; do
        [[ -n "${job_id}" ]] || continue
        detail=$(curl -fsS --max-time 8 "${RAY_URL}/api/jobs/${job_id}" 2>/dev/null || true)
        if grep -Fq "MLFLOW_TRACKING_URI" <<<"${detail}" && grep -Fq "${CHAIN_MLFLOW_PASSWORD}" <<<"${detail}"; then
            found=1
            break
        fi
    done <<<"${job_ids}"

    if [[ "${found}" -eq 1 ]]; then
        pass "Ray job detail exposes MLflow URI and credential"
    else
        fail "Ray runtime_env does not expose the guided-chain MLflow credential"
    fi
}

check_mlflow_gate() {
    section "MLflow auth gate"
    expect_body_contains "MLflow auth gateway health reachable" "OK" "${MLFLOW_URL}/health"
    expect_status "MLflow API rejects no credential" "401" \
        -X POST "${MLFLOW_URL}/api/2.0/mlflow/experiments/search" \
        -H "Content-Type: application/json" \
        --data '{"max_results":1}'
    expect_status "MLflow API rejects wrong credential" "401" \
        -X POST "${MLFLOW_URL}/api/2.0/mlflow/experiments/search" \
        -H "Content-Type: application/json" \
        -H "Authorization: Basic bm90OnRoZS1wYXNzd29yZA==" \
        --data '{"max_results":1}'
    expect_status "MLflow API accepts Ray-looted credential" "200" \
        -X POST "${MLFLOW_URL}/api/2.0/mlflow/experiments/search" \
        -H "Content-Type: application/json" \
        -H "${MLFLOW_AUTH}" \
        --data '{"max_results":5}'
    # The HF token lives in run params of a non-default experiment. MLflow's
    # runs/search requires experiment_ids (an empty body returns nothing), so
    # enumerate experiments first — this also mirrors how the tool discovers it.
    local exp_ids runs_body
    exp_ids=$(curl -fsS --max-time 8 -X POST "${MLFLOW_URL}/api/2.0/mlflow/experiments/search" \
        -H "Content-Type: application/json" -H "${MLFLOW_AUTH}" --data '{"max_results":1000}' 2>/dev/null \
        | python3 -c 'import sys,json; print(json.dumps([e["experiment_id"] for e in json.load(sys.stdin).get("experiments",[])]))' 2>/dev/null || echo '[]')
    runs_body=$(curl -fsS --max-time 8 -X POST "${MLFLOW_URL}/api/2.0/mlflow/runs/search" \
        -H "Content-Type: application/json" -H "${MLFLOW_AUTH}" \
        --data "{\"experiment_ids\":${exp_ids},\"max_results\":1000}" 2>/dev/null || true)
    if grep -Fq "${CHAIN_HF_TOKEN}" <<<"${runs_body}"; then
        pass "MLflow exposes HF token in run params/tags"
    else
        fail "MLflow exposes HF token in run params/tags — expected body marker '${CHAIN_HF_TOKEN}'"
    fi
}

check_tgi_gate() {
    section "TGI auth gate"
    expect_body_contains "TGI gateway health reachable" "ok" "${TGI_URL}/health"
    expect_status "TGI /generate rejects no credential" "401" \
        -X POST "${TGI_URL}/generate" \
        -H "Content-Type: application/json" \
        --data '{"inputs":"incident response","parameters":{"max_new_tokens":5}}'
    expect_status "TGI /generate rejects wrong credential" "401" \
        -X POST "${TGI_URL}/generate" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer wrong-token" \
        --data '{"inputs":"incident response","parameters":{"max_new_tokens":5}}'
    # The credential_replay marker is returned even in fixture mode, so for RRR require
    # REAL inference unless an explicit fixture profile is selected.
    if [[ "${CHAIN_ALLOW_FIXTURE_TGI:-0}" == "1" ]]; then
        expect_body_contains "TGI /generate accepts looted HF token (fixture profile)" "credential_replay" \
            -X POST "${TGI_URL}/generate" \
            -H "Content-Type: application/json" \
            -H "${HF_AUTH}" \
            --data '{"inputs":"incident response","parameters":{"max_new_tokens":5}}'
    else
        expect_body_contains "TGI /generate returns REAL inference for looted HF token" '"inference": "real"' \
            -X POST "${TGI_URL}/generate" \
            -H "Content-Type: application/json" \
            -H "${HF_AUTH}" \
            --data '{"inputs":"incident response","parameters":{"max_new_tokens":5}}'
    fi
}

check_litellm_climax() {
    section "LiteLLM real-inference climax (looted master key)"
    expect_status "LiteLLM authed rejects request without master key" "401" \
        -X POST "${LITELLM_URL}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        --data '{"model":"local-smollm","messages":[{"role":"user","content":"ping"}]}'
    expect_body_contains "LiteLLM authed master key drives real Ollama generation" "choices" \
        -X POST "${LITELLM_URL}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "${LITELLM_AUTH}" \
        --data '{"model":"local-smollm","messages":[{"role":"user","content":"Say READY"}],"max_tokens":16}'
}

check_optional_production_tgi() {
    if [[ "${CHAIN_ENABLE_PRODUCTION_TGI:-0}" != "1" ]]; then
        return
    fi

    section "Advanced production TGI gate"
    local prod_url proxy_arg
    prod_url="$(chain_production_tgi_url)"
    proxy_arg=()
    if [[ -n "${CHAIN_PRODUCTION_PROXY:-}" ]]; then
        proxy_arg=(--proxy "${CHAIN_PRODUCTION_PROXY}")
    fi

    # Skip (warn, do not fail) when the optional production TGI is enabled but not
    # actually deployed/reachable. Otherwise "direct blocked" passes trivially (nothing
    # listening) while the proxied checks fail — a misleading partial pass.
    local proxied_health
    proxied_health=$(status_of "${proxy_arg[@]}" "${prod_url}/health" || true)
    if [[ "${proxied_health}" != "200" ]]; then
        warn "Production TGI enabled but not reachable at ${prod_url}${CHAIN_PRODUCTION_PROXY:+ via proxy} — skipping advanced section (deploy the segmented prod-TGI host + pivot first)"
        return
    fi

    expect_status "Production TGI direct access blocked" "000" "${prod_url}/health"
    expect_body_contains "Production TGI proxied health reachable" "ok" "${proxy_arg[@]}" "${prod_url}/health"
    expect_status "Production TGI proxied request rejects no credential" "401" \
        "${proxy_arg[@]}" -X POST "${prod_url}/generate" \
        -H "Content-Type: application/json" \
        --data '{"inputs":"production check","parameters":{"max_new_tokens":5}}'
    expect_body_contains "Production TGI accepts reused Layer 1 HF token after pivot" "credential_replay" \
        "${proxy_arg[@]}" -X POST "${prod_url}/generate" \
        -H "Content-Type: application/json" \
        -H "${HF_AUTH}" \
        --data '{"inputs":"production check","parameters":{"max_new_tokens":5}}'
}

# check_optional_segmentation runs only when the opt-in segmentation toggle is on
# (AIPOSTEX_SEGMENTATION=1). It asserts the exposed MLflow backend (ailab-ml:5000)
# is network-refused from the attack box while the gated gateway (ailab-ds:5000)
# still answers — i.e. the credential-chain hop is also enforced at L3. The default
# flat lab leaves this off, so the standard chain verification is unaffected.
check_optional_segmentation() {
    [[ "${AIPOSTEX_SEGMENTATION:-0}" == "1" ]] || return 0
    section "optional: network segmentation (AIPOSTEX_SEGMENTATION=1)"
    local backend gateway got
    backend="http://$(inventory_host_ip ailab-ml):5000/"
    gateway="http://$(inventory_host_ip ailab-ds):5000/"
    # Use status_of (which emits curl's own "000" on failure) + ||true, rather than
    # `curl ... || echo "000"` — on a blocked connection curl ALREADY prints 000, so
    # the `|| echo` would append a second value ("000\n000") and the equality check
    # would wrongly fail even though the block worked.
    got=$(status_of "${backend}" 2>/dev/null || true); got=${got:-000}
    if [[ "${got}" == "000" ]]; then
        pass "direct MLflow backend (ailab-ml:5000) refused from the attack box"
    else
        fail "segmentation on but ailab-ml:5000 still directly reachable (got ${got}); run 'sudo bash segmentation.sh enable' on ailab-ml"
    fi
    got=$(status_of "${gateway}" 2>/dev/null || true); got=${got:-000}
    if [[ "${got}" != "000" ]]; then
        pass "gated MLflow gateway (ailab-ds:5000) still reachable (${got})"
    else
        fail "gateway path broken under segmentation (got ${got})"
    fi
}

main() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  aipostex Guided Chain Verification${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo ""
    log "Ray:    ${RAY_URL}"
    log "MLflow: ${MLFLOW_URL}"
    log "TGI:    ${TGI_URL}"
    log "LiteLLM: ${LITELLM_URL}"

    check_ray_leak
    check_mlflow_gate
    check_tgi_gate
    check_litellm_climax
    check_optional_production_tgi
    check_optional_segmentation

    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "  Final: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${WARN} warnings${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo ""

    [[ "${FAIL}" -eq 0 ]]
}

main "$@"
