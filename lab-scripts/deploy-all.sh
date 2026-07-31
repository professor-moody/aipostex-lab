#!/bin/bash
# deploy-all.sh — One-shot lab deployment from your attack box / Proxmox host
#
# Prerequisites:
#   - All four target VMs already running
#   - SSH access as labadmin to all targets
#   - This script directory contains all lab-scripts/ subdirectories
#
# Usage:
#   bash deploy-all.sh              # Full deploy (all phases)
#   bash deploy-all.sh --phase 1    # Base setup only
#   bash deploy-all.sh --phase 2    # Provision services only (assumes base done)
#   bash deploy-all.sh --phase 3    # Seed data only (assumes services running)
#   bash deploy-all.sh --phase 4    # Verify only
#   bash deploy-all.sh --skip-base  # Skip base setup (useful for re-deploy)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-scripts/lib/inventory.sh
source "${SCRIPT_DIR}/lib/inventory.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

DEV=$(inventory_host_ip "ailab-dev")
ML=$(inventory_host_ip "ailab-ml")
DS=$(inventory_host_ip "ailab-ds")
APP=$(inventory_host_ip "ailab-app")
K8S=$(inventory_host_ip "ailab-k8s")

# "IP:name" list for the target roles (dev ml ds app) this profile wants — default = all.
# Single-tactic deploys set LAB_PROFILE / LAB_ONLY_ROLES (see lib/inventory.sh).
wanted_targets() {
    local out=""
    inventory_role_wanted dev && out="$out $DEV:ailab-dev"
    inventory_role_wanted ml  && out="$out $ML:ailab-ml"
    inventory_role_wanted ds  && out="$out $DS:ailab-ds"
    inventory_role_wanted app && out="$out $APP:ailab-app"
    echo "$out"
}

PHASE="all"
SKIP_BASE=false
SHOW_HELP=false

log() { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
ok()  { echo -e "${GREEN}[+]${NC} $1"; }
err() { echo -e "${RED}[!]${NC} $1" >&2; }
warn(){ echo -e "${YELLOW}[*]${NC} $1"; }

# shellcheck disable=SC2154
trap 'rc=$?; err "deploy-all.sh failed at line $LINENO (phase=$PHASE)"; exit $rc' ERR

usage() {
    cat <<EOF
Usage: $0 [--phase 1|2|3|4|all] [--skip-base]

  --phase      Run only one deploy phase or 'all' (default)
  --skip-base  Skip phase 1 during a full deploy
EOF
}

parse_args() {
    PHASE="all"
    SKIP_BASE=false
    SHOW_HELP=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --phase)
                if [[ $# -lt 2 || -z "${2:-}" ]]; then
                    err "--phase requires a value"
                    usage >&2
                    return 2
                fi
                PHASE="$2"
                shift 2
                ;;
            --skip-base)
                SKIP_BASE=true
                shift
                ;;
            -h|--help)
                usage
                SHOW_HELP=true
                return 0
                ;;
            *)
                err "Unknown argument: $1"
                usage >&2
                return 2
                ;;
        esac
    done

    case "$PHASE" in
        1|2|3|4|all) ;;
        *)
            err "Unknown phase: $PHASE"
            usage >&2
            return 2
            ;;
    esac

    return 0
}

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

ssh_cmd() {
    local host=$1
    shift
    ssh $SSH_OPTS "labadmin@$host" "$@"
}

scp_to() {
    local host=$1
    shift
    scp $SSH_OPTS -r "$@" "labadmin@$host:~/lab/"
}

copy_base_payload() {
    local host=$1
    ssh_cmd "$host" "mkdir -p ~/lab"
    scp_to "$host" "$SCRIPT_DIR/base-setup.sh" "$SCRIPT_DIR/lib"
}

wait_for_ssh() {
    local host=$1
    local name=$2
    log "Waiting for SSH on $name ($host)..."
    for _ in $(seq 1 30); do
        if ssh_cmd "$host" "echo ok" >/dev/null 2>&1; then
            ok "SSH ready on $name"
            return 0
        fi
        sleep 3
    done
    err "SSH timeout on $name ($host)"
    return 1
}

# ══════════════════════════════════════════════════════════
# PHASE 1: Base OS Setup
# ══════════════════════════════════════════════════════════

phase_1() {
    log "═══ PHASE 1: Base OS Setup ═══"

    for host_info in $(wanted_targets); do
        IFS=: read -r host name <<< "$host_info"
        wait_for_ssh "$host" "$name"
        copy_base_payload "$host"
        log "Running base-setup.sh on $name..."
        ssh_cmd "$host" "sudo env LAB_INVENTORY_PATH=/home/labadmin/lab/lib/inventory.sh bash /home/labadmin/lab/base-setup.sh"
        ok "$name base setup complete"
    done

    # Distribute the attack box SSH pubkey so it can reach all targets
    ATTACK_IP=$(inventory_host_ip "ailab-attack")
    ATTACK_PUBKEY_FILE="/home/labadmin/.ssh/id_ed25519.pub"
    log "Distributing attack box SSH pubkey to target VMs..."
    ATTACK_PUBKEY=$(ssh $SSH_OPTS "labadmin@${ATTACK_IP}" "cat ${ATTACK_PUBKEY_FILE} 2>/dev/null" 2>/dev/null || true)
    if [[ -n "$ATTACK_PUBKEY" ]]; then
        for host_info in $(wanted_targets); do
            IFS=: read -r host name <<< "$host_info"
            ssh_cmd "$host" "grep -qF 'labadmin@ailab-attack' ~/.ssh/authorized_keys 2>/dev/null || echo '$ATTACK_PUBKEY' >> ~/.ssh/authorized_keys"
            ok "Attack box pubkey added to $name"
        done
    else
        warn "Could not read attack box pubkey — run attack-box/setup.sh first, then re-run --phase 1"
    fi

    ok "Phase 1 complete: Base OS configured on all VMs"
}

# ══════════════════════════════════════════════════════════
# PHASE 2: Provision Services (native installs)
# ══════════════════════════════════════════════════════════

phase_2() {
    log "═══ PHASE 2: Provision Services ═══"

    # --- ailab-dev ---
    if inventory_role_wanted dev; then
        log "Provisioning dev-workstation services..."
        ssh_cmd "$DEV" "mkdir -p ~/lab"
        scp_to "$DEV" "$SCRIPT_DIR/dev-workstation/"
        ssh_cmd "$DEV" "sudo env LAB_SUBNET=${LAB_SUBNET} bash ~/lab/dev-workstation/provision.sh"
        ok "ailab-dev provisioned"
    fi

    # --- ailab-ml ---
    if inventory_role_wanted ml; then
        log "Provisioning ml-platform services..."
        ssh_cmd "$ML" "mkdir -p ~/lab"
        scp_to "$ML" "$SCRIPT_DIR/ml-platform/"
        ssh_cmd "$ML" "sudo env LAB_SUBNET=${LAB_SUBNET} bash ~/lab/ml-platform/provision.sh"
        ok "ailab-ml provisioned"
    fi

    # --- ailab-ds ---
    if inventory_role_wanted ds; then
        log "Provisioning data-sci services..."
        ssh_cmd "$DS" "mkdir -p ~/lab"
        scp_to "$DS" "$SCRIPT_DIR/data-sci/"
        ssh_cmd "$DS" "sudo env LAB_SUBNET=${LAB_SUBNET} bash ~/lab/data-sci/provision.sh"
        ok "ailab-ds provisioned"
    fi

    # --- ailab-app ---
    if inventory_role_wanted app; then
        log "Provisioning app-platform services..."
        ssh_cmd "$APP" "mkdir -p ~/lab"
        scp_to "$APP" "$SCRIPT_DIR/app-platform/"
        ssh_cmd "$APP" "sudo env LAB_SUBNET=${LAB_SUBNET} bash ~/lab/app-platform/provision.sh"
        ok "ailab-app provisioned"
    fi

    # --- ailab-k8s (real single-node k3s "ACME cluster") ---
    # Self-contained: base-setup + k3s provision (not the generic role service-matcher path).
    if inventory_role_wanted k8s; then
        log "Provisioning k8s cluster (ailab-k8s)..."
        wait_for_ssh "$K8S" "ailab-k8s"
        copy_base_payload "$K8S"
        ssh_cmd "$K8S" "sudo env LAB_INVENTORY_PATH=/home/labadmin/lab/lib/inventory.sh bash /home/labadmin/lab/base-setup.sh"
        scp_to "$K8S" "$SCRIPT_DIR/k8s-node/"
        ssh_cmd "$K8S" "sudo env LAB_SUBNET=${LAB_SUBNET} bash ~/lab/k8s-node/provision.sh"
        ok "ailab-k8s provisioned (k3s)"
    fi

    warn "Waiting 10s for all services to initialize..."
    sleep 10

    for host_info in $(wanted_targets); do
        IFS=: read -r host name <<< "$host_info"
        svc_count=$(ssh_cmd "$host" "systemctl list-units --type=service --state=running --no-legend | grep -cE '$(inventory_host_service_matcher "$name")'" 2>/dev/null || echo "0")
        log "$name: $svc_count lab services running"
    done

    ok "Phase 2 complete: All services provisioned"
}

# ══════════════════════════════════════════════════════════
# PHASE 3: Seed Data
# ══════════════════════════════════════════════════════════

phase_3() {
    log "═══ PHASE 3: Seed Data ═══"

    if inventory_role_wanted dev; then
        log "Seeding dev-workstation data..."
        ssh_cmd "$DEV" "sudo bash ~/lab/dev-workstation/seed.sh"
        ok "ailab-dev seeded"
    fi

    if inventory_role_wanted ml; then
        log "Seeding ml-platform data..."
        ssh_cmd "$ML" "sudo env ESTATE_SUBNET=${LAB_SUBNET} bash ~/lab/ml-platform/seed.sh"
        ok "ailab-ml seeded"
    fi

    if inventory_role_wanted ds; then
        log "Seeding data-sci data..."
        ssh_cmd "$DS" "sudo bash ~/lab/data-sci/seed.sh"
        ok "ailab-ds seeded"
    fi

    ok "Phase 3 complete: All data seeded"
}

# ══════════════════════════════════════════════════════════
# PHASE 4: Verify
# ══════════════════════════════════════════════════════════

phase_4() {
    log "═══ PHASE 4: Verification ═══"
    bash "$SCRIPT_DIR/verify-lab.sh"
}

# ══════════════════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════════════════

main() {
    local parse_status
    parse_args "$@"
    parse_status=$?
    if [[ "$parse_status" -ne 0 ]]; then
        exit "$parse_status"
    fi
    if [[ "$SHOW_HELP" == "true" ]]; then
        exit 0
    fi

    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  aipostex Lab Environment Deployment (Native)${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
    echo ""

    local start_time end_time elapsed minutes seconds
    start_time=$(date +%s)

    case "$PHASE" in
        1)
            phase_1
            ;;
        2)
            phase_2
            ;;
        3)
            phase_3
            ;;
        4)
            phase_4
            ;;
        all)
            if [[ "$SKIP_BASE" == "true" ]]; then
                warn "Skipping base setup (--skip-base)"
            else
                phase_1
            fi
            echo ""
            phase_2
            echo ""
            phase_3
            echo ""
            phase_4
            ;;
    esac

    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    minutes=$((elapsed / 60))
    seconds=$((elapsed % 60))

    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Deployment completed in ${minutes}m ${seconds}s${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
