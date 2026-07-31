#!/bin/bash
# setup.sh — Standalone attack box provisioning
#
# Run from the Proxmox host or any machine with SSH access to 172.16.50.99.
# This is intentionally separate from deploy-all.sh so the attack box
# survives target lab rebuilds.
#
# Usage: bash attack-box/setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lab-scripts/lib/inventory.sh
source "${LAB_DIR}/lib/inventory.sh"

ATTACK=$(inventory_host_ip "ailab-attack")
CI_USER="labadmin"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
ok()  { echo -e "${GREEN}[+]${NC} $1"; }
err() { echo -e "${RED}[!]${NC} $1"; }
warn(){ echo -e "${YELLOW}[*]${NC} $1"; }

ssh_cmd() {
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${CI_USER}@${ATTACK}" "$@"
}

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  aipostex Attack Box Setup${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""

# ── Wait for SSH ────────────────────────────────────────

log "Waiting for SSH on ailab-attack ($ATTACK)..."
for i in $(seq 1 30); do
    if ssh_cmd "echo ok" >/dev/null 2>&1; then
        ok "SSH ready"
        break
    fi
    if [[ $i -eq 30 ]]; then
        err "SSH timeout — is ailab-attack running at $ATTACK?"
        exit 1
    fi
    sleep 3
done

# ── Phase 1: Base setup ────────────────────────────────

log "Copying shared base payload to attack box..."
ssh_cmd "mkdir -p ~/lab"
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r \
    "$LAB_DIR/base-setup.sh" \
    "$LAB_DIR/lib" \
    "${CI_USER}@${ATTACK}:~/lab/"
ok "Base payload copied"

log "Running base-setup.sh on attack box..."
ssh_cmd "sudo env LAB_INVENTORY_PATH=/home/labadmin/lab/lib/inventory.sh bash /home/labadmin/lab/base-setup.sh"
ok "Base setup complete"

# ── Phase 2: Copy lab-scripts ──────────────────────────

log "Copying lab-scripts to attack box..."
ssh_cmd "mkdir -p ~/lab"
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r "$LAB_DIR"/* "${CI_USER}@${ATTACK}:~/lab/"
# Verify the copy landed the files provision.sh depends on; an incomplete transfer here is
# what once let provisioning "succeed" with the listener uninstalled / mcp-configs missing.
if ! ssh_cmd "test -f ~/lab/attack-box/lab-listener/server.py && test -f ~/lab/lib/inventory.sh"; then
    err "lab-scripts copy incomplete on the attack box (listener source / inventory missing)"
    exit 1
fi
ok "Lab scripts copied to ~/lab/"

# ── Phase 3: Provision ─────────────────────────────────

log "Running attack box provisioning..."
ssh_cmd "sudo bash ~/lab/attack-box/provision.sh"
ok "Provisioning complete"

# ── Done ────────────────────────────────────────────────

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Attack Box Ready${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""
echo "  SSH to attack box:  ssh ${CI_USER}@${ATTACK}"
echo ""
echo "  From the attack box, you can:"
echo "    - SSH to targets:   ssh ailab-dev / ailab-ml / ailab-ds / ailab-app"
echo "    - Deploy the lab:   bash ~/lab/deploy-all.sh"
echo "    - Verify the lab:   bash ~/lab/verify-lab.sh"
echo ""
echo -e "${YELLOW}  Tailscale setup (do this once):${NC}"
echo "    ssh ${CI_USER}@${ATTACK}"
echo "    sudo tailscale up"
echo "    tailscale ip -4          # note the Tailscale IP"
echo ""
echo "  Then from your workstation:"
echo "    ssh ${CI_USER}@<tailscale-ip>"
echo "    scp ./aipostex ${CI_USER}@<tailscale-ip>:~/"
echo ""
