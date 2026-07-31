#!/bin/bash
# Provision enterprise developer workstation by reusing the mini dev role.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "[*] Provisioning ent-dev-01 via dev-workstation role..."
bash "${LAB_ROOT}/dev-workstation/provision.sh"
echo "[+] ent-dev-01 provisioning complete"
