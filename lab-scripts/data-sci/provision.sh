#!/bin/bash
# provision.sh — Provision ailab-ds (data science server)
# Run as root on 172.16.50.30 AFTER base-setup.sh
# Installs: Ollama, Jupyter, Weaviate (binary), Qdrant (binary), PostgreSQL+pgvector
# All as native services with systemd units
set -euo pipefail

# Version pins — CHECK GITHUB RELEASES AT BUILD TIME
WEAVIATE_VERSION="${WEAVIATE_VERSION:-1.28.4}"
QDRANT_VERSION="${QDRANT_VERSION:-1.13.2}"
MLFLOW_GATEWAY_USER="${MLFLOW_GATEWAY_USER:-ray-pipeline}"
MLFLOW_GATEWAY_PASSWORD="${MLFLOW_GATEWAY_PASSWORD:-MlflowRayChain!2026}"
MLFLOW_UPSTREAM="${MLFLOW_UPSTREAM:-http://${LAB_SUBNET:-172.16.50}.20:5000}"
# Black-box RAG app (:8091) — knowledge-base chat with document upload; real
# generation via the OpenAI-compatible upstream (LiteLLM -> Ollama).
RAG_UPSTREAM_URL="${RAG_UPSTREAM_URL:-http://${LAB_SUBNET:-172.16.50}.20:4000/v1/chat/completions}"
RAG_UPSTREAM_MODEL="${RAG_UPSTREAM_MODEL:-local-smollm}"
# Detection telemetry: the RAG app appends events to ${APP_EVENT_LOG_DIR}/rag.jsonl,
# which Filebeat ships to the real Elastic detection stack (ailab-siem, .60). See
# lab-scripts/siem/. The old ai-siem mock on :5601 has been retired.
APP_EVENT_LOG_DIR="${APP_EVENT_LOG_DIR:-/var/log/aipostex}"

echo "[*] Provisioning ailab-ds (data science server)..."
echo "    Weaviate version: ${WEAVIATE_VERSION}"
echo "    Qdrant version:   ${QDRANT_VERSION}"

wait_for_http_match() {
    local service_name=$1
    local service_unit=$2
    local url=$3
    local expected=$4
    local attempts=${5:-30}

    echo "[*] Waiting for ${service_name} to be ready..."
    for i in $(seq 1 "${attempts}"); do
        local response
        response=$(curl -sf "${url}" 2>/dev/null || true)
        if echo "${response}" | grep -qi "${expected}"; then
            echo "[+] ${service_name} is ready"
            return 0
        fi
        sleep 2
    done

    echo "[!] ${service_name} failed readiness check at ${url}"
    journalctl -u "${service_unit}" --no-pager -n 30 || true
    return 1
}

# ── Create dsuser ───────────────────────────────────────────
if ! id dsuser &>/dev/null; then
    useradd -m -s /bin/bash dsuser
    echo "[+] Created dsuser"
else
    echo "[*] dsuser already exists"
fi

# ── Ollama ──────────────────────────────────────────────────
OLLAMA_VERSION="${OLLAMA_VERSION:-0.6.2}"
echo "[*] Installing Ollama v${OLLAMA_VERSION}..."
curl -fsSL https://ollama.com/install.sh | OLLAMA_VERSION="${OLLAMA_VERSION}" sh

mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama
wait_for_http_match "Ollama" "ollama" "http://localhost:11434/api/version" "version"

# ── Jupyter ─────────────────────────────────────────────────
echo "[*] Installing JupyterLab..."
sudo -u dsuser /usr/bin/python3 -m pip install --user --break-system-packages "jupyterlab==4.4.1" 2>/dev/null

sudo -u dsuser mkdir -p /home/dsuser/.jupyter
cat > /home/dsuser/.jupyter/jupyter_lab_config.py << 'PYEOF'
c.ServerApp.token = ''
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.port = 8889
c.ServerApp.open_browser = False
c.ServerApp.root_dir = '/home/dsuser'
PYEOF
chown dsuser:dsuser /home/dsuser/.jupyter/jupyter_lab_config.py

cat > /etc/systemd/system/jupyter-ds.service << 'EOF'
[Unit]
Description=Jupyter Lab (dsuser)
After=network.target

[Service]
User=dsuser
WorkingDirectory=/home/dsuser
ExecStart=/home/dsuser/.local/bin/jupyter lab --config=/home/dsuser/.jupyter/jupyter_lab_config.py
Restart=always
RestartSec=5
Environment="PATH=/home/dsuser/.local/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable jupyter-ds
systemctl restart jupyter-ds
wait_for_http_match "Jupyter" "jupyter-ds" "http://localhost:8889/api" "version"
echo "[+] Jupyter installed (port 8889, no auth)"

# ── Weaviate ────────────────────────────────────────────────
echo "[*] Installing Weaviate v${WEAVIATE_VERSION}..."
cd /tmp
WEAVIATE_URL="https://github.com/weaviate/weaviate/releases/download/v${WEAVIATE_VERSION}/weaviate-v${WEAVIATE_VERSION}-linux-amd64.tar.gz"
if wget -q "${WEAVIATE_URL}" -O weaviate.tar.gz; then
    tar xzf weaviate.tar.gz
    mv weaviate /usr/local/bin/
    rm -f weaviate.tar.gz
    echo "[+] Weaviate binary installed"
else
    echo "[!] Weaviate binary download failed."
    echo "[!] Check the release URL: ${WEAVIATE_URL}"
    echo "[!] Visit https://github.com/weaviate/weaviate/releases for the latest version."
    exit 1
fi

mkdir -p /opt/weaviate/data

cat > /etc/systemd/system/weaviate.service << 'EOF'
[Unit]
Description=Weaviate Vector Database
After=network.target

[Service]
ExecStart=/usr/local/bin/weaviate --port 8080 --host 0.0.0.0 --scheme http
Environment=AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true
Environment=PERSISTENCE_DATA_PATH=/opt/weaviate/data
Environment=DEFAULT_VECTORIZER_MODULE=none
Environment=QUERY_DEFAULTS_LIMIT=100
Environment=CLUSTER_HOSTNAME=ds-weaviate
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable weaviate
systemctl restart weaviate

echo "[*] Waiting for Weaviate on :8080..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:8080/v1/.well-known/ready &>/dev/null; then
        echo "[+] Weaviate is ready"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[!] Weaviate failed to start. Journal output:"
        journalctl -u weaviate --no-pager -n 30
        exit 1
    fi
    sleep 2
done
echo "[+] Weaviate installed (port 8080, anonymous access)"

# ── Qdrant ──────────────────────────────────────────────────
echo "[*] Installing Qdrant v${QDRANT_VERSION}..."
cd /tmp
QDRANT_URL="https://github.com/qdrant/qdrant/releases/download/v${QDRANT_VERSION}/qdrant-x86_64-unknown-linux-musl.tar.gz"
if wget -q "${QDRANT_URL}" -O qdrant.tar.gz; then
    tar xzf qdrant.tar.gz
    mv qdrant /usr/local/bin/
    rm -f qdrant.tar.gz
    echo "[+] Qdrant binary installed"
else
    echo "[!] Qdrant binary download failed at v${QDRANT_VERSION}"
    echo "    Check https://github.com/qdrant/qdrant/releases for the correct URL"
    exit 1
fi

mkdir -p /opt/qdrant/storage /opt/qdrant/snapshots

cat > /opt/qdrant/config.yaml << 'YAML'
storage:
  storage_path: /opt/qdrant/storage
  snapshots_path: /opt/qdrant/snapshots
service:
  host: 0.0.0.0
  http_port: 6333
  grpc_port: 6334
YAML

# ── Qdrant (API-key enforced) — honesty control, NOT a target ────────────────
# A second Qdrant instance with Qdrant's own service.api_key set, so requests
# without the api-key header are refused. It exists so the precision benchmark
# can check that aipostex claims nothing against a vector database it never got
# into. Separate storage so it shares nothing with the open instance.
mkdir -p /opt/qdrant-secure/storage /opt/qdrant-secure/snapshots
cat > /opt/qdrant-secure/config.yaml << 'YAML'
storage:
  storage_path: /opt/qdrant-secure/storage
  snapshots_path: /opt/qdrant-secure/snapshots
service:
  host: 0.0.0.0
  http_port: 6335
  grpc_port: 6336
  api_key: acme-qdrant-4b8e21fa
YAML

cat > /etc/systemd/system/qdrant-secure.service << 'EOF'
[Unit]
Description=Qdrant (API-key enforced honesty control)
After=network.target

[Service]
WorkingDirectory=/opt/qdrant-secure
ExecStart=/usr/local/bin/qdrant --config-path /opt/qdrant-secure/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable qdrant-secure
systemctl restart qdrant-secure
echo "[+] Qdrant honesty control installed (port 6335, API key REQUIRED)"

cat > /etc/systemd/system/qdrant.service << 'EOF'
[Unit]
Description=Qdrant Vector Database
After=network.target

[Service]
WorkingDirectory=/opt/qdrant
ExecStart=/usr/local/bin/qdrant --config-path /opt/qdrant/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable qdrant
systemctl restart qdrant

echo "[*] Waiting for Qdrant on :6333..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:6333/healthz &>/dev/null; then
        echo "[+] Qdrant is ready"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[!] Qdrant failed to start. Journal output:"
        journalctl -u qdrant --no-pager -n 30
        exit 1
    fi
    sleep 2
done
echo "[+] Qdrant installed (port 6333, no auth)"

# ── PostgreSQL + pgvector ────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/provision-pgvector.sh"

# ── MLflow Auth Gateway ─────────────────────────────────────
echo "[*] Installing MLflow auth gateway on :5000..."
sudo -u dsuser mkdir -p /home/dsuser/projects/mlflow-auth-gateway
if [ -f "$(dirname "$0")/mlflow-auth-gateway/server.py" ]; then
    cp "$(dirname "$0")/mlflow-auth-gateway/server.py" /home/dsuser/projects/mlflow-auth-gateway/server.py
    chown dsuser:dsuser /home/dsuser/projects/mlflow-auth-gateway/server.py
fi

cat > /etc/systemd/system/mlflow-auth-gateway.service << EOF
[Unit]
Description=MLflow Auth Gateway (aipostex-lab)
After=network.target

[Service]
User=dsuser
WorkingDirectory=/home/dsuser/projects/mlflow-auth-gateway
Environment="MLFLOW_GATEWAY_PORT=5000"
Environment="MLFLOW_UPSTREAM=${MLFLOW_UPSTREAM}"
Environment="MLFLOW_GATEWAY_USER=${MLFLOW_GATEWAY_USER}"
Environment="MLFLOW_GATEWAY_PASSWORD=${MLFLOW_GATEWAY_PASSWORD}"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mlflow-auth-gateway
systemctl restart mlflow-auth-gateway
wait_for_http_match "MLflow auth gateway" "mlflow-auth-gateway" "http://localhost:5000/health" "OK"

# ── Black-box RAG app (:8091) ───────────────────────────────
echo "[*] Preparing application event-log dir for Filebeat (${APP_EVENT_LOG_DIR})..."
install -d -m 1777 "${APP_EVENT_LOG_DIR}"
echo "[*] Installing black-box RAG app (:8091)..."
sudo -u dsuser mkdir -p /home/dsuser/projects/rag-app
if [ -f "$(dirname "$0")/rag-app-mock/server.py" ]; then
    cp "$(dirname "$0")/rag-app-mock/server.py" /home/dsuser/projects/rag-app/server.py
    chown dsuser:dsuser /home/dsuser/projects/rag-app/server.py
fi

cat > /etc/systemd/system/rag-app.service << EOF
[Unit]
Description=Black-box RAG App (aipostex-lab)
After=network.target

[Service]
User=dsuser
WorkingDirectory=/home/dsuser/projects/rag-app
Environment="RAG_APP_PORT=8091"
Environment="RAG_UPSTREAM_URL=${RAG_UPSTREAM_URL}"
Environment="RAG_UPSTREAM_MODEL=${RAG_UPSTREAM_MODEL}"
Environment="EVENT_LOG=${APP_EVENT_LOG_DIR}/rag.jsonl"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rag-app
systemctl restart rag-app
wait_for_http_match "RAG app" "rag-app" "http://localhost:8091/health" "healthy"

# ── Summary ─────────────────────────────────────────────────
echo ""
echo "[+] ailab-ds provisioning complete"
echo "    Services:"
echo "      Ollama    :11434  (systemd: ollama.service)"
echo "      Jupyter   :8889   (systemd: jupyter-ds.service)"
echo "      Weaviate  :8080   (systemd: weaviate.service)"
echo "      Qdrant    :6333   (systemd: qdrant.service)"
echo "      PostgreSQL:5432   (systemd: postgresql.service, pgvector enabled)"
echo "      MLflow GW :5000   (systemd: mlflow-auth-gateway.service, Basic auth)"
echo "      RAG app   :8091   (systemd: rag-app.service, black-box RAG)"
