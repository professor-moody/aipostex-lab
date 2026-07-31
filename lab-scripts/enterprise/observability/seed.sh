#!/bin/bash
set -euo pipefail

mkdir -p /var/log/acme-observe
cat > /var/log/acme-observe/events.jsonl <<'EOF'
{"timestamp":"2026-05-20T12:00:00Z","source":"litellm.platform.acme.internal","event":"startup","message":"gateway ready"}
{"timestamp":"2026-05-20T12:02:00Z","source":"mlflow.mlops.acme.internal","event":"model_registered","model":"fraud-model-v3"}
{"timestamp":"2026-05-20T12:05:00Z","source":"jupyter.research.acme.internal","event":"notebook_saved","path":"notebooks/rag-prototype.ipynb"}
EOF
chmod a+r /var/log/acme-observe/events.jsonl
echo "[+] ent-observe-01 seeding complete"
