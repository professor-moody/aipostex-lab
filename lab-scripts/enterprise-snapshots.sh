#!/bin/bash
# enterprise-snapshots.sh — manage snapshots for enterprise lab VMs only.
#
# Usage:
#   bash enterprise-snapshots.sh create <name> [description]
#   bash enterprise-snapshots.sh restore <name>
#   bash enterprise-snapshots.sh --yes restore <name>
#   bash enterprise-snapshots.sh list
#   bash enterprise-snapshots.sh delete <name>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-scripts/lib/enterprise-inventory.sh
source "${SCRIPT_DIR}/lib/enterprise-inventory.sh"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

AUTO_CONFIRM=false

usage() {
    cat <<EOF
Usage: $0 [--yes] {create|restore|list|delete} [snapshot-name] [description]

This script targets only enterprise VMs:
  ${ENT_HOSTS}
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes)
            AUTO_CONFIRM=true
            shift
            ;;
        -h|--help)
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
DESC="${3:-aipostex enterprise snapshot}"

confirm_action() {
    local prompt=$1
    if [[ "$AUTO_CONFIRM" == "true" ]]; then
        return 0
    fi
    read -r -p "${prompt} [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] && return 0
    echo -e "${YELLOW}Aborted by user.${NC}"
    return 1
}

enterprise_vm_ids() {
    local host
    for host in ${ENT_HOSTS}; do
        enterprise_host_id "$host"
    done
}

vm_name() {
    local vmid=$1
    qm config "$vmid" | grep -oP 'name: \K.*' 2>/dev/null || echo "VM-$vmid"
}

case "$ACTION" in
    create)
        [[ -z "$NAME" ]] && { echo "Error: snapshot name required"; usage; }
        echo -e "${CYAN}Creating enterprise snapshot '$NAME'...${NC}"
        while read -r vmid; do
            qm snapshot "$vmid" "$NAME" --description "$DESC"
            echo -e "  ${GREEN}[✓]${NC} $(vm_name "$vmid") ($vmid)"
        done < <(enterprise_vm_ids)
        ;;
    restore)
        [[ -z "$NAME" ]] && { echo "Error: snapshot name required"; usage; }
        echo -e "${CYAN}Restoring enterprise VMs to '$NAME'...${NC}"
        echo -e "${YELLOW}This stops and rolls back only enterprise VMs.${NC}"
        confirm_action "Continue?" || exit 3
        while read -r vmid; do
            echo -n "  $(vm_name "$vmid") ($vmid): "
            qm stop "$vmid" 2>/dev/null || true
            sleep 2
            qm rollback "$vmid" "$NAME"
            echo -e "${GREEN}rolled back${NC}"
        done < <(enterprise_vm_ids)
        while read -r vmid; do
            qm start "$vmid"
        done < <(enterprise_vm_ids)
        echo -e "${GREEN}Enterprise VMs restored and starting.${NC}"
        ;;
    list)
        while read -r vmid; do
            echo -e "${CYAN}── $(vm_name "$vmid") ($vmid) ──${NC}"
            qm listsnapshot "$vmid" 2>/dev/null | grep -v "current" || echo "  (no snapshots)"
            echo ""
        done < <(enterprise_vm_ids)
        ;;
    delete)
        [[ -z "$NAME" ]] && { echo "Error: snapshot name required"; usage; }
        echo -e "${CYAN}Deleting enterprise snapshot '$NAME'...${NC}"
        confirm_action "Continue?" || exit 3
        while read -r vmid; do
            if qm delsnapshot "$vmid" "$NAME" 2>/dev/null; then
                echo -e "  ${GREEN}[✓]${NC} $(vm_name "$vmid") ($vmid)"
            else
                echo -e "  ${YELLOW}[!]${NC} $(vm_name "$vmid") ($vmid) — snapshot not found"
            fi
        done < <(enterprise_vm_ids)
        ;;
    *)
        usage
        ;;
esac
