#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "[*] Seeding ent-mlops-01 via ml-platform role..."
bash "${LAB_ROOT}/ml-platform/seed.sh"
mkdir -p /opt/acme-mlops/ci-logs
cat > /opt/acme-mlops/ci-logs/model-promote-2026-05-20.log <<'EOF'
2026-05-20T12:03:21Z promote fraud-model-v3
MLFLOW_TRACKING_URI=http://mlflow.mlops.acme.internal:5000
MODEL_REGISTRY_URL=http://mlflow.mlops.acme.internal:5000
LITELLM_PROXY=http://litellm.platform.acme.internal:4000
VAULT_ADDR=http://vault.security.acme.internal:8200
VAULT_TOKEN=vault-lab-ci-token-FAKE-mlops
EOF
chmod -R a+rX /opt/acme-mlops
echo "[+] ent-mlops-01 seeding complete"
