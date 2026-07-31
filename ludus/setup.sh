#!/bin/bash
# setup.sh — Register aipostex Ludus roles and set the range config.
#
# This script:
#   1. Syncs files from lab-scripts/ into role files/ directories
#   2. Registers each role with the Ludus server
#   3. Sets the range configuration
#
# Usage: bash ludus/setup.sh
#
# Prerequisites:
#   - ludus CLI installed and authenticated
#   - Templates already built (ubuntu-24.04-x64-server-template, debian-12-x64-server-template)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}[*]${NC} $1"; }
ok()  { echo -e "${GREEN}[+]${NC} $1"; }
err() { echo -e "${RED}[!]${NC} $1" >&2; exit 1; }

# Preflight
if ! command -v ludus >/dev/null 2>&1; then
    err "ludus CLI not found. Install from https://docs.ludus.cloud"
fi

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  aipostex Lab — Ludus Setup${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""

# Step 1: Sync files
log "Step 1: Syncing files from lab-scripts/ into roles..."
bash "${SCRIPT_DIR}/sync-files.sh"
echo ""

# Step 2: Register roles
log "Step 2: Registering roles with Ludus server..."
ROLES=(
    aipostex_base
    aipostex_dev_workstation
    aipostex_ml_platform
    aipostex_data_sci
    aipostex_app_platform
    aipostex_attack_box
)

for role in "${ROLES[@]}"; do
    log "  Adding ${role}..."
    ludus ansible role add -d "${SCRIPT_DIR}/roles/${role}" --force
    ok "  ${role} registered"
done
echo ""

# Step 3: Set range config
log "Step 3: Setting range configuration..."
ludus range config set -f "${SCRIPT_DIR}/range-config.yml"
ok "Range config set"

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup Complete${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""
echo "  Next steps:"
echo "    ludus range deploy          # Deploy the range"
echo "    ludus range logs -f         # Watch deployment progress"
echo "    ludus range status          # Check deployment status"
echo ""
echo "  After deployment:"
echo "    ludus user wireguard        # Get WireGuard config for range access"
echo "    ludus testing start         # Snapshot VMs and enter testing mode"
echo ""
