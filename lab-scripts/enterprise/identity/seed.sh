#!/bin/bash
set -euo pipefail

export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-root-enterprise-FAKE}"

echo "[*] Seeding Vault KV data..."
for _ in $(seq 1 30); do
    if vault status >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

vault secrets enable -path=kv kv-v2 >/dev/null 2>&1 || true
vault kv put kv/mlops/mlflow \
    tracking_uri=http://mlflow.mlops.acme.internal:5000 \
    registry_token=mlflow-registry-token-FAKE-enterprise >/dev/null
vault kv put kv/inference/litellm \
    proxy_url=http://litellm.platform.acme.internal:4000 \
    notebook_key=sk-ant-FAKE-notebook-key-abcdef1234567890 >/dev/null
vault kv put kv/data/minio \
    endpoint=http://minio.data.acme.internal:9001 \
    access_key=minioadmin \
    secret_key=minioadmin-FAKE-enterprise-secret >/dev/null

echo "[+] ent-idp-01 seeding complete"
