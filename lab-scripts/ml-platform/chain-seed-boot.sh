#!/usr/bin/env bash
# chain-seed-boot.sh — boot-time self-heal for the guided-chain Ray seed.
#
# WHY THIS EXISTS: Ray keeps its job records in the head's IN-MEMORY store. The
# lab-ready snapshots are disk-only (no vmstate), and a plain reboot restarts Ray
# with an empty job store — so hop 1 of the guided chain (the MLflow credential
# planted in a job's runtime_env) silently vanishes, with nothing to re-plant it.
# reset-wave re-arms it and `reseed.sh ml` is the manual break-glass, but neither
# runs on an ordinary boot. This unit makes a fresh/rebooted ML host self-seed so
# the estate is ready the second an attendee sits down — no facilitator action.
#
# GUARDED (seed-if-empty): if the chain credential is already present in the Ray
# job list it exits without submitting, so it composes safely with reset-wave's
# re-arm and never double-submits. Idempotent, subnet-aware, safe to run anytime.
set -uo pipefail

ML_RUNTIME_VENV="/opt/ailab-ml/venv"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAY_URL="http://localhost:8265"
MARKER_PW="MlflowRayChain"        # substring of CHAIN_MLFLOW_PASSWORD
export ESTATE_SUBNET="${ESTATE_SUBNET:-172.16.50}"

log() { echo "[chain-seed-boot] $*"; }

# 1. Wait for Ray's job API to accept requests. ray.service runs `ray start --block`
#    (Type=simple), so After=ray.service releases us while Ray may still be warming
#    up — poll the dashboard until it answers, up to ~180s.
ready=0
for _ in $(seq 1 90); do
    if curl -fsS --max-time 4 "${RAY_URL}/api/version" >/dev/null 2>&1; then ready=1; break; fi
    sleep 2
done
if [[ "${ready}" -ne 1 ]]; then
    log "Ray API never became ready — leaving the seed to reset-wave/reseed"
    exit 0    # non-fatal: never fail the boot; the break-glass reseed still exists
fi

# 2. Already seeded? Compose with reset-wave; never double-submit.
jobs="$(curl -fsS --max-time 8 "${RAY_URL}/api/jobs/" 2>/dev/null || true)"
if grep -Fq "MLFLOW_TRACKING_URI" <<<"${jobs}" && grep -Fq "${MARKER_PW}" <<<"${jobs}"; then
    log "chain seed already present — nothing to do"
    exit 0
fi

# 3. Re-plant. seed_ray.py has its own readiness wait and writes /opt/ray/seed-run.json.
log "chain seed absent — re-seeding Ray (ESTATE_SUBNET=${ESTATE_SUBNET})"
exec "${ML_RUNTIME_VENV}/bin/python3" "${SCRIPT_DIR}/seed_ray.py" localhost 8265
