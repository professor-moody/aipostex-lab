#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "[*] Seeding ent-data-01 via data-sci role..."
bash "${LAB_ROOT}/data-sci/seed.sh"

echo "[*] Seeding MinIO enterprise buckets..."
mkdir -p /var/lib/minio/data/acme-ml-data/churn/weekly
mkdir -p /var/lib/minio/data/acme-model-artifacts/fraud/v3
cat > /var/lib/minio/data/acme-ml-data/churn/weekly/README.txt <<'EOF'
Weekly churn feature export for support RAG and retraining jobs.
Owner: research-ai
EOF
cat > /var/lib/minio/data/acme-model-artifacts/fraud/v3/model-card.md <<'EOF'
# Fraud Model v3

Registry: http://mlflow.mlops.acme.internal:5000
Deployment: http://litellm.platform.acme.internal:4000
EOF
chown -R minio:minio /var/lib/minio/data
echo "[+] ent-data-01 seeding complete"
