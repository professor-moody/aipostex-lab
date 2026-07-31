#!/bin/bash
# lab-snapshots.sh — Manage snapshots for all lab VMs
#
# Usage:
#   bash lab-snapshots.sh create <name> [description]          # Snapshot all VMs
#   bash lab-snapshots.sh restore <name>                       # Restore all VMs to snapshot
#   bash lab-snapshots.sh delete <name>                        # Delete snapshot from all VMs
#   bash lab-snapshots.sh --yes restore <name>                 # Non-interactive restore
#   bash lab-snapshots.sh --yes delete <name>                  # Non-interactive delete
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-scripts/lib/inventory.sh
source "${SCRIPT_DIR}/lib/inventory.sh"

DEV_ID=$(inventory_host_id "ailab-dev")
ML_ID=$(inventory_host_id "ailab-ml")
DS_ID=$(inventory_host_id "ailab-ds")
APP_ID=$(inventory_host_id "ailab-app")
ATTACK_ID=$(inventory_host_id "ailab-attack")
K8S_ID=$(inventory_host_id "ailab-k8s")
ALL_IDS="$DEV_ID $ML_ID $DS_ID $APP_ID $ATTACK_ID $K8S_ID"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [--yes] {create|restore|list|delete} [snapshot-name] [description]"
    echo ""
    echo "  create  <name> [desc]   Create snapshot on all lab VMs"
    echo "  restore <name>          Rollback all lab VMs to named snapshot + start"
    echo "  list                    Show snapshots for all VMs"
    echo "  delete  <name>          Remove named snapshot from all VMs"
    exit 1
}

AUTO_CONFIRM=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes)
            AUTO_CONFIRM=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            break
            ;;
    esac
done

[[ $# -lt 1 ]] && usage

ACTION=$1
NAME="${2:-}"
DESC="${3:-aipostex lab snapshot}"

confirm_action() {
    local prompt=$1
    if [[ "$AUTO_CONFIRM" == "true" ]]; then
        return 0
    fi

    read -r -p "${prompt} [y/N] " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        return 0
    fi

    echo -e "${YELLOW}Aborted by user.${NC}"
    return 1
}

case $ACTION in
    create)
        [[ -z "$NAME" ]] && { echo "Error: snapshot name required"; usage; }
        echo -e "${CYAN}Creating snapshot '$NAME' on all VMs...${NC}"
        for vmid in $ALL_IDS; do
            vmname=$(qm config $vmid | grep -oP 'name: \K.*' 2>/dev/null || echo "VM-$vmid")
            qm snapshot $vmid "$NAME" --description "$DESC"
            echo -e "  ${GREEN}[✓]${NC} $vmname ($vmid)"
        done
        echo -e "${GREEN}Done. Restore with: $0 restore $NAME${NC}"
        ;;

    restore)
        [[ -z "$NAME" ]] && { echo "Error: snapshot name required"; usage; }
        # Pre-flight: EVERY target VM must already carry this snapshot before we stop any of
        # them. Otherwise a VM missing the snapshot fails its `qm rollback` mid-loop, after
        # earlier VMs are already stopped and rolled back — leaving the estate half-restored
        # (the exact risk the paused rebaseline hit). Match the name as a whole token so
        # "lab-ready" never spuriously matches "lab-ready-cand".
        echo -e "${CYAN}Pre-flight: verifying all VMs have snapshot '$NAME'...${NC}"
        missing_snap=""
        for vmid in $ALL_IDS; do
            if ! qm listsnapshot "$vmid" 2>/dev/null | grep -qE "(^|[^[:alnum:]_-])${NAME}([^[:alnum:]_-]|\$)"; then
                missing_snap="${missing_snap} ${vmid}"
            fi
        done
        if [[ -n "$missing_snap" ]]; then
            echo -e "${YELLOW}Abort: snapshot '$NAME' missing on VM(s):${missing_snap} — no VM was touched.${NC}"
            exit 4
        fi
        echo -e "${GREEN}All VMs have '$NAME'.${NC}"

        echo -e "${CYAN}Restoring all VMs to snapshot '$NAME'...${NC}"
        echo -e "${YELLOW}This will stop running VMs and roll back to the snapshot.${NC}"
        confirm_action "Continue?" || exit 3

        for vmid in $ALL_IDS; do
            vmname=$(qm config $vmid | grep -oP 'name: \K.*' 2>/dev/null || echo "VM-$vmid")
            echo -n "  $vmname ($vmid): "
            qm stop $vmid 2>/dev/null || true
            sleep 2
            qm rollback $vmid "$NAME"
            echo -e "${GREEN}rolled back${NC}"
        done

        echo -e "${CYAN}Starting all VMs...${NC}"
        for vmid in $ALL_IDS; do
            qm start $vmid
        done

        echo -e "${YELLOW}Waiting 30s for boot...${NC}"
        sleep 30

        echo -e "${GREEN}All VMs restored and running. Run verify-lab.sh to confirm.${NC}"
        ;;

    list)
        for vmid in $ALL_IDS; do
            vmname=$(qm config $vmid | grep -oP 'name: \K.*' 2>/dev/null || echo "VM-$vmid")
            echo -e "${CYAN}── $vmname ($vmid) ──${NC}"
            qm listsnapshot $vmid 2>/dev/null | grep -v "current" || echo "  (no snapshots)"
            echo ""
        done
        ;;

    delete)
        [[ -z "$NAME" ]] && { echo "Error: snapshot name required"; usage; }
        echo -e "${CYAN}Deleting snapshot '$NAME' from all VMs...${NC}"
        confirm_action "Continue?" || exit 3

        for vmid in $ALL_IDS; do
            vmname=$(qm config $vmid | grep -oP 'name: \K.*' 2>/dev/null || echo "VM-$vmid")
            if qm delsnapshot $vmid "$NAME" 2>/dev/null; then
                echo -e "  ${GREEN}[✓]${NC} $vmname ($vmid)"
            else
                echo -e "  ${YELLOW}[!]${NC} $vmname ($vmid) — snapshot not found"
            fi
        done
        ;;

    *)
        usage
        ;;
esac
