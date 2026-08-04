#!/bin/bash
# reset-wave.sh — One-command between-wave reset for the RTV tactic.
#
# Run on the Proxmox host. For each estate it:
#   1. rolls back every VM to the lab-ready snapshot (qm)
#   2. waits for the VMs to come back (SSH readiness, not a flat sleep)
#   3. re-arms the chain state that a disk-only snapshot can't restore:
#        - re-seed Ray jobs + MLflow runs + ChromaDB on ailab-ml (seed.sh)
#        - restart the MCP server on ailab-dev (acme-mcp)
#   4. verifies (verify-lab.sh + verify-chain.sh) and prints PASS + elapsed
#
# Estates reset in parallel; the wall-clock long pole is the slowest single estate,
# so N estates fit roughly the same window as one. This automates the "Before each
# wave" runbook in docs/deployment/rtv-operator-checklist.md.
#
# Usage:
#   bash reset-wave.sh                       # reset the base estate, verify, report
#   bash reset-wave.sh --dry-run             # print the plan; touch nothing
#   bash reset-wave.sh --groups "0 1 2"      # reset multiple estates in parallel (estates deployed via GROUP_ID)
#   bash reset-wave.sh --snapshot NAME       # override snapshot (same as SNAPSHOT=NAME)
#   SNAPSHOT=lab-ready bash reset-wave.sh    # override snapshot name
#   SKIP_VERIFY=1 bash reset-wave.sh         # rollback + re-arm only (skip verifiers)
#
# Intentionally NOT `set -e`: a single estate's failure must not abort the others or
# hide the per-estate report. We track failures explicitly.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-scripts/lib/inventory.sh
source "${SCRIPT_DIR}/lib/inventory.sh"

# ── Config (env-overridable) ────────────────────────────────────────────────
SNAPSHOT="${SNAPSHOT:-lab-ready}"
ESTATE_GROUPS="${ESTATE_GROUPS:-0}"                  # estate group offsets; 0 = the base estate
SSH_USER="${SSH_USER:-labadmin}"
# UserKnownHostsFile=/dev/null: a VM's SSH host key changes across a rollback/reimage, so
# checking known_hosts would make boot-wait/re-arm SSH fail on a legit estate host (hit this
# live on ailab-ds). verify-lab.sh already does this; reset-wave must too.
SSH_OPTS="${SSH_OPTS:--o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=4 -o BatchMode=yes}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-180}"   # seconds to wait for a VM to answer SSH
SLA_SECONDS="${SLA_SECONDS:-600}"     # 10-min between-wave SLA, for the report verdict
DRY_RUN="${DRY_RUN:-0}"
SKIP_VERIFY="${SKIP_VERIFY:-0}"
RESET_LOG_DIR="${RESET_LOG_DIR:-/tmp/reset-wave}"
# Per-group offsets. Group 0 = the base estate (real inventory IDs / 172.16.50).
# NOTE: the authoritative multi-estate ID/subnet scheme lives in lib/inventory.sh
# (GROUP_ID -> VM IDs / subnet / bridge); these strides MUST MATCH its defaults
# (VMID_STRIDE=1000, SUBNET_STRIDE=1) so reset and deploy agree, and the operator
# must ensure the resulting IDs never collide with non-lab VMs on the host (e.g. the
# foundry VMs at 310-350). The 1000 default keeps estate K at 1k*K+base, well clear
# of 106 / 210-250 / 310-350 / templates 1101-1102.
VMID_STRIDE="${VMID_STRIDE:-1000}"
SUBNET_STRIDE="${SUBNET_STRIDE:-1}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --groups)  ESTATE_GROUPS="$2"; shift 2 ;;
        --snapshot) SNAPSHOT="$2"; shift 2 ;;
        --skip-verify) SKIP_VERIFY=1; shift ;;
        -h|--help)
            # Print the leading comment block (stripping "# "), stopping at the first
            # non-comment line — robust to the header growing/shrinking.
            awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
run()  { if [[ "${DRY_RUN}" == "1" ]]; then echo "  [dry-run] $*"; else eval "$*"; fi; }

# ── Estate topology ─────────────────────────────────────────────────────────
# Group 0 is the base estate from inventory.sh. Additional groups apply the SAME
# offset scheme that lib/inventory.sh's GROUP_ID deploy uses: VM IDs +VMID_STRIDE*group
# (default 1000) and subnet 172.16.(50+SUBNET_STRIDE*group). A group whose VMs don't
# exist yet simply fails its qm rollback and is reported FAILED — never blocking others.
estate_vmids() {   # $1=group -> "dev ml ds app attack k8s" VM IDs
    local g=$1 base
    for base in 210 220 230 250 240 260; do printf '%s ' "$((base + VMID_STRIDE * g))"; done
}
estate_subnet() {  # $1=group -> "172.16.<octet>"
    echo "172.16.$((50 + SUBNET_STRIDE * $1))"
}
estate_host_ip() { # $1=group $2=host -> IP on that estate's subnet
    local g=$1 host=$2 octet
    case "$host" in
        ml)  octet=20 ;; dev) octet=10 ;; ds) octet=30 ;; app) octet=40 ;; attack) octet=99 ;; k8s) octet=50 ;;
    esac
    echo "$(estate_subnet "$g").${octet}"
}

# Identity guard: before any destructive `qm stop/rollback`, confirm a VMID is actually THIS
# estate's lab VM — its qm-config name is the expected ailab-<role> AND its net0 bridge is
# this estate's vmbr10<g>. Catches a wrong VMID_STRIDE, a fat-fingered --groups, or an ID
# collision with a non-lab VM (e.g. foundry 310-350) BEFORE the rollback, not after. Estate
# VMs keep the same ailab-<role> name across estates (only VMID/bridge/subnet differ), so the
# bridge is the estate-discriminating half of the check.
verify_vmid_identity() {  # $1=group  $2=vmid  $3=expected_name -> 0 ok / 1 mismatch
    local g=$1 vmid=$2 expected=$3 cfg name bridge want_bridge
    want_bridge="vmbr10${g}"
    cfg=$(qm config "$vmid" 2>/dev/null) || { echo "  IDENTITY: vmid ${vmid} has no qm config (absent?)"; return 1; }
    name=$(sed -n 's/^name: //p' <<<"$cfg" | head -1)
    bridge=$(sed -n 's/^net0:.*bridge=\([^,]*\).*/\1/p' <<<"$cfg" | head -1)
    if [[ "$name" != "$expected" ]]; then
        echo "  IDENTITY MISMATCH: vmid ${vmid} name='${name}' != expected '${expected}' — refusing to touch it"; return 1
    fi
    if [[ "$bridge" != "$want_bridge" ]]; then
        echo "  IDENTITY MISMATCH: vmid ${vmid} bridge='${bridge}' != expected '${want_bridge}' — refusing to touch it"; return 1
    fi
    return 0
}

# ── Per-estate reset ────────────────────────────────────────────────────────
# Body returns 0/non-0; the wrapper captures rc + timing. (Keeping the `return`s
# out of the redirected wrapper avoids exiting before the .result write.)
_reset_estate_body() {
    local g=$1
    local tag="estate-${g}"
    echo "=== reset ${tag} (snapshot=${SNAPSHOT}) ==="
    local dev ml ds app attack k8s
    read -r dev ml ds app attack k8s <<<"$(estate_vmids "$g")"
    local all_ids="$dev $ml $ds $app $attack $k8s"
    local ml_ip dev_ip ds_ip app_ip
    ml_ip=$(estate_host_ip "$g" ml)
    dev_ip=$(estate_host_ip "$g" dev)
    ds_ip=$(estate_host_ip "$g" ds)
    app_ip=$(estate_host_ip "$g" app)

    # 0. Identity guard — verify every VMID is this estate's lab VM before any destructive qm.
    echo "[0/4] identity guard (names + vmbr10${g})"
    local -a _guard_ids=("$dev" "$ml" "$ds" "$app" "$attack" "$k8s")
    local -a _guard_names=("ailab-dev" "ailab-ml" "ailab-ds" "ailab-app" "ailab-attack" "ailab-k8s")
    local _gi
    for _gi in "${!_guard_ids[@]}"; do
        if [[ "${DRY_RUN}" == "1" ]] && ! command -v qm >/dev/null 2>&1; then
            echo "  [dry-run] would verify ${_guard_ids[$_gi]} is ${_guard_names[$_gi]} on vmbr10${g}"
            continue
        fi
        if ! verify_vmid_identity "$g" "${_guard_ids[$_gi]}" "${_guard_names[$_gi]}"; then
            if [[ "${DRY_RUN}" == "1" ]]; then
                echo "  [dry-run] IDENTITY WARN on ${_guard_ids[$_gi]} (a real run would ABORT this estate)"
            else
                echo "FAIL: identity guard on ${_guard_ids[$_gi]} — aborting estate ${g} (no VM touched)"; return 1
            fi
        fi
    done

    # 1. Rollback (stop -> rollback -> start), per VM
    echo "[1/4] rollback ${all_ids}"
    local vmid
    for vmid in $all_ids; do
        run "qm stop $vmid >/dev/null 2>&1 || true"
        run "qm rollback $vmid '${SNAPSHOT}'" || { echo "FAIL: rollback $vmid"; return 1; }
    done
    for vmid in $all_ids; do run "qm start $vmid"; done

    # 2. Boot-wait: every host the verifiers depend on (dev .10, ml .20, ds .30, app .40)
    #    must answer SSH before we re-arm + verify. Per-host timeout budget.
    echo "[2/4] boot-wait (dev=${dev_ip} ml=${ml_ip} ds=${ds_ip} app=${app_ip}, timeout=${BOOT_TIMEOUT}s each)"
    local host_ip waited
    for host_ip in "$dev_ip" "$ml_ip" "$ds_ip" "$app_ip"; do
        if [[ "${DRY_RUN}" == "1" ]]; then echo "  [dry-run] would wait for ${host_ip}"; continue; fi
        waited=0
        while ! ssh ${SSH_OPTS} "${SSH_USER}@${host_ip}" true 2>/dev/null; do
            sleep 5; waited=$((waited + 5))
            if (( waited > BOOT_TIMEOUT )); then echo "FAIL: ${host_ip} not up after ${BOOT_TIMEOUT}s"; return 1; fi
        done
    done

    # 3. Re-arm the disk-only-snapshot gaps. Thread this estate's subnet into the seed so a
    #    GROUP_ID>0 estate re-arms chains pointing at its OWN services, not the base subnet.
    echo "[3/4] re-arm: seed ml + restart MCP on dev"
    local estate_sub; estate_sub=$(estate_subnet "$g")
    run "ssh ${SSH_OPTS} ${SSH_USER}@${ml_ip} 'sudo env ESTATE_SUBNET=${estate_sub} bash ~/lab/ml-platform/seed.sh'" || { echo "FAIL: seed ml"; return 1; }
    run "ssh ${SSH_OPTS} ${SSH_USER}@${dev_ip} 'sudo systemctl restart acme-mcp'" || echo "WARN: acme-mcp restart returned non-zero"

    # k8s node (260) was rolled back + started with the estate above. Its Docker/k3s
    # vuln+secure pair self-restarts on boot (restart: unless-stopped) and re-applies its
    # seed manifests — no explicit re-arm needed. Non-fatal readiness note only: the pair
    # needs ~90s to come up. verify-lab runs 3 k8s checks; a slow/degraded k8s node shows
    # up as verify-lab warnings (surfaced in the report below), not a gate failure.
    if [[ "${DRY_RUN}" != "1" ]]; then
        local k8s_ip; k8s_ip="$(estate_host_ip "$g" k8s)"
        if curl -sk --max-time 4 "https://${k8s_ip}:6443/version" >/dev/null 2>&1; then
            echo "  k8s pair reachable on ${k8s_ip}:6443/6444"
        else
            echo "  note: k8s pair on ${k8s_ip} still coming up (Docker+k3s ~90s; not gating)"
        fi
    fi

    # 4. Verify (run on this host; must reach this estate's subnet)
    if [[ "${SKIP_VERIFY}" == "1" ]]; then
        echo "[4/4] verify skipped (SKIP_VERIFY=1)"
    else
        echo "[4/4] verify-lab + verify-chain"
        local subnet; subnet=$(estate_subnet "$g")
        run "LAB_SUBNET=${subnet} bash '${SCRIPT_DIR}/verify-lab.sh'"   || { echo "FAIL: verify-lab"; return 1; }
        run "LAB_SUBNET=${subnet} bash '${SCRIPT_DIR}/ctf/verify-chain.sh'" || { echo "FAIL: verify-chain"; return 1; }
    fi
    echo "OK: ${tag} reset clean"
    return 0
}

reset_estate() {
    local g=$1
    local tag="estate-${g}"
    local logf="${RESET_LOG_DIR}/${tag}.log"
    local t0 t1 rc
    t0=$(date +%s)
    _reset_estate_body "$g" >"${logf}" 2>&1
    rc=$?
    t1=$(date +%s)
    echo "$rc $((t1 - t0))" >"${RESET_LOG_DIR}/${tag}.result"
    return $rc
}

# ── Main ────────────────────────────────────────────────────────────────────
mkdir -p "${RESET_LOG_DIR}"
rm -f "${RESET_LOG_DIR}"/*.result 2>/dev/null || true
WAVE_T0=$(date +%s)
read -ra GROUP_LIST <<<"${ESTATE_GROUPS}"

log "Reset wave: groups=[${ESTATE_GROUPS}] snapshot=${SNAPSHOT} dry-run=${DRY_RUN}"
echo ""

# Launch every estate in parallel; the wall-clock is the slowest single estate.
pids=()
for g in "${GROUP_LIST[@]}"; do
    reset_estate "$g" &
    pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done

# ── Report ──────────────────────────────────────────────────────────────────
WAVE_ELAPSED=$(( $(date +%s) - WAVE_T0 ))
echo ""
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo -e "  Reset-wave report"
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
fail_total=0
for g in "${GROUP_LIST[@]}"; do
    res="${RESET_LOG_DIR}/estate-${g}.result"
    if [[ -f "$res" ]]; then
        read -r rc secs <"$res"
    else
        rc=1; secs=0
    fi
    if [[ "$rc" == "0" ]]; then
        echo -e "  estate-${g}: ${GREEN}PASS${NC} (${secs}s)   log: ${RESET_LOG_DIR}/estate-${g}.log"
        # verify-lab exits 0 even with warnings (WARN doesn't fail the gate), so a
        # degraded-but-passing estate would read as fully clean. Both verify-lab AND
        # verify-chain print a "Final: ... N warnings" line, so SUM the warnings across
        # every summary line — reading only the last one would let a verify-lab warning
        # be masked by a clean verify-chain summary.
        wcount=$(sed -E 's/\x1b\[[0-9;]*m//g' "${RESET_LOG_DIR}/estate-${g}.log" 2>/dev/null \
            | awk '/Final:/ { for (i = 1; i <= NF; i++) if ($i ~ /^warning/) s += $(i-1) } END { print s + 0 }')
        if [[ -n "$wcount" && "$wcount" -gt 0 ]]; then
            echo -e "    ${YELLOW}⚠ ${wcount} verify warning(s) — degraded seeding; see log${NC}"
        fi
    else
        echo -e "  estate-${g}: ${RED}FAIL${NC} (${secs}s)   log: ${RESET_LOG_DIR}/estate-${g}.log"
        fail_total=$((fail_total + 1))
    fi
done
echo -e "  ────────────────────────────────────────────────"
if (( WAVE_ELAPSED <= SLA_SECONDS )); then
    echo -e "  wall-clock: ${GREEN}${WAVE_ELAPSED}s${NC} (SLA ${SLA_SECONDS}s)"
else
    echo -e "  wall-clock: ${RED}${WAVE_ELAPSED}s${NC} — OVER SLA (${SLA_SECONDS}s)"
fi
echo -e "${CYAN}════════════════════════════════════════════════${NC}"

[[ "${fail_total}" -eq 0 ]]
