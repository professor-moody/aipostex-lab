#!/bin/bash
# Provision enterprise MLOps host by reusing the mini ML platform role.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "[*] Provisioning ent-mlops-01 via ml-platform role..."
bash "${LAB_ROOT}/ml-platform/provision.sh"
echo "[+] ent-mlops-01 provisioning complete"
