#!/bin/bash
# teardown-lab.sh — Destroy all lab infrastructure
#
# Usage:
#   bash teardown-lab.sh              # Destroy VMs only (keep template + bridge)
#   bash teardown-lab.sh --full       # Destroy everything including template + bridge
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-scripts/lib/inventory.sh
source "${SCRIPT_DIR}/lib/inventory.sh"

DEV_ID=$(inventory_host_id "ailab-dev")
ML_ID=$(inventory_host_id "ailab-ml")
DS_ID=$(inventory_host_id "ailab-ds")
APP_ID=$(inventory_host_id "ailab-app")
ATTACK_ID=$(inventory_host_id "ailab-attack")
TEMPLATE_ID="${LAB_TEMPLATE_ID}"
ATTACK_TEMPLATE_ID="${LAB_ATTACK_TEMPLATE_ID}"
BRIDGE="${LAB_BRIDGE}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FULL=false
[[ "${1:-}" == "--full" ]] && FULL=true

echo ""
echo -e "${RED}═══════════════════════════════════════════════${NC}"
echo -e "${RED}  aipostex Lab Teardown${NC}"
echo -e "${RED}═══════════════════════════════════════════════${NC}"
echo ""

if [[ "$FULL" == "true" ]]; then
    echo "This will destroy: VMs $DEV_ID $ML_ID $DS_ID $APP_ID $ATTACK_ID, templates $TEMPLATE_ID $ATTACK_TEMPLATE_ID, and bridge $BRIDGE"
else
    echo "This will destroy: VMs $DEV_ID $ML_ID $DS_ID $APP_ID $ATTACK_ID (templates and bridge preserved)"
fi
echo ""
read -p "Are you sure? Type 'yes' to confirm: " -r
[[ "$REPLY" == "yes" ]] || { echo "Aborted."; exit 0; }

# Stop and destroy lab VMs
for vmid in $DEV_ID $ML_ID $DS_ID $APP_ID $ATTACK_ID; do
    if qm status $vmid >/dev/null 2>&1; then
        echo -n "  Destroying VM $vmid... "
        qm stop $vmid 2>/dev/null || true
        sleep 2
        qm destroy $vmid --purge
        echo -e "${GREEN}done${NC}"
    else
        echo -e "  VM $vmid: ${YELLOW}not found${NC}"
    fi
done

if [[ "$FULL" == "true" ]]; then
    # Destroy templates
    for tmpl in $TEMPLATE_ID $ATTACK_TEMPLATE_ID; do
        if qm status $tmpl >/dev/null 2>&1; then
            echo -n "  Destroying template $tmpl... "
            qm destroy $tmpl --purge
            echo -e "${GREEN}done${NC}"
        fi
    done

    # Remove bridge
    if ip link show $BRIDGE >/dev/null 2>&1; then
        echo -n "  Removing bridge $BRIDGE... "
        ifdown $BRIDGE 2>/dev/null || true

        # Remove from /etc/network/interfaces
        # Create backup first
        cp /etc/network/interfaces "/etc/network/interfaces.bak.$(date +%s)"
        sed -i "/# aipostex lab network/,/post-down.*MASQUERADE/d" /etc/network/interfaces
        sed -i "/auto $BRIDGE/,/post-down.*MASQUERADE/d" /etc/network/interfaces

        echo -e "${GREEN}done${NC}"
        echo -e "  ${YELLOW}Backup saved to /etc/network/interfaces.bak.*${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Teardown complete.${NC}"
if [[ "$FULL" != "true" ]]; then
    echo "Templates ($TEMPLATE_ID, $ATTACK_TEMPLATE_ID) and bridge ($BRIDGE) preserved for quick rebuild."
    echo "Rebuild with: bash proxmox-setup.sh  (skip steps 1-4, just clone)"
fi
