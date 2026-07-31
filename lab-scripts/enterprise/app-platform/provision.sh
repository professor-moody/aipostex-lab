#!/bin/bash
# Provision enterprise app host by reusing the mini app-platform role.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "[*] Provisioning ent-app-01 via app-platform role..."
bash "${LAB_ROOT}/app-platform/provision.sh"
echo "[+] ent-app-01 provisioning complete"
