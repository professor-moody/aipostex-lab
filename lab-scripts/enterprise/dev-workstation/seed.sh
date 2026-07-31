#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "[*] Seeding ent-dev-01 via dev-workstation role..."
bash "${LAB_ROOT}/dev-workstation/seed.sh"
sudo -u devuser mkdir -p /home/devuser/projects/acme-enterprise
cat > /home/devuser/projects/acme-enterprise/README.md <<'EOF'
# ACME Enterprise AI Notes

Internal endpoints:

- LiteLLM gateway: http://litellm.platform.acme.internal:4000
- MLflow tracking: http://mlflow.mlops.acme.internal:5000
- Vault: http://vault.security.acme.internal:8200

Old notebook token and test keys may still exist in notebook outputs.
EOF
chown -R devuser:devuser /home/devuser/projects/acme-enterprise
echo "[+] ent-dev-01 seeding complete"
