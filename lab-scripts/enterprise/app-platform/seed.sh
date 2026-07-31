#!/bin/bash
set -euo pipefail

if ! id appuser >/dev/null 2>&1; then
    useradd -m -s /bin/bash appuser
fi

sudo -u appuser mkdir -p /home/appuser/projects/rag-support-app
cat > /home/appuser/projects/rag-support-app/.env <<'EOF'
LITELLM_BASE_URL=http://litellm.platform.acme.internal:4000
OPENAI_API_KEY=sk-proj-FAKE-rag-app-litellm-key-1234567890
VECTOR_DB_URL=http://weaviate.data.acme.internal:8080
MINIO_ENDPOINT=http://minio.data.acme.internal:9000
VAULT_ADDR=http://vault.security.acme.internal:8200
EOF
cat > /home/appuser/projects/rag-support-app/README.md <<'EOF'
# Support RAG App

Prototype app that reads support runbooks from vector DB collections and calls the shared LiteLLM gateway.
EOF
chown -R appuser:appuser /home/appuser/projects/rag-support-app
echo "[+] ent-app-01 seeding complete"
