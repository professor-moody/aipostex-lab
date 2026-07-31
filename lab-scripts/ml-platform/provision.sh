#!/bin/bash
# provision.sh — Provision ailab-ml (ML platform server)
# Run as root on 172.16.50.20 AFTER base-setup.sh
# Installs: ChromaDB, MLflow, LiteLLM proxy, Ray
# All as native services with systemd units
set -euo pipefail

HF_TGI_MOCK_VERSION="${HF_TGI_MOCK_VERSION:-1.0-lab}"
HF_TEI_MOCK_VERSION="${HF_TEI_MOCK_VERSION:-1.0-lab}"
VLLM_MOCK_VERSION="${VLLM_MOCK_VERSION:-1.0-lab}"
ML_RUNTIME_ROOT="/opt/ailab-ml"
ML_RUNTIME_VENV="${ML_RUNTIME_ROOT}/venv"
ENABLE_LEGACY_ML_TGI="${ENABLE_LEGACY_ML_TGI:-0}"

# ── Helper: wait for a service health endpoint ──────────────
wait_for_service() {
    local name=$1 url=$2 retries=${3:-20} unit=${4:-}
    echo "[*] Waiting for ${name}..."
    for i in $(seq 1 "$retries"); do
        if curl -sf --max-time 3 "$url" &>/dev/null; then
            echo "[+] ${name} is ready"
            return 0
        fi
        sleep 2
    done
    echo "[!] ${name} failed to start after $((retries * 2))s"
    if [[ -n "$unit" ]]; then
        journalctl -u "$unit" --no-pager -n 20
    fi
    return 1
}

trap 'echo "[!] provision.sh failed at line $LINENO"; exit 1' ERR

echo "[*] Provisioning ailab-ml (ML platform)..."
echo "    HF TGI mock version:  ${HF_TGI_MOCK_VERSION}"
echo "    HF TEI mock version:  ${HF_TEI_MOCK_VERSION}"
echo "    vLLM mock version:    ${VLLM_MOCK_VERSION}"

# ── Create mluser ───────────────────────────────────────────
if ! id mluser &>/dev/null; then
    useradd -m -s /bin/bash mluser
    echo "[+] Created mluser"
else
    echo "[*] mluser already exists"
fi

# ── Shared ML runtime venv ──────────────────────────────────
echo "[*] Preparing shared ML runtime venv..."
mkdir -p "${ML_RUNTIME_ROOT}"
python3 -m venv "${ML_RUNTIME_VENV}"
"${ML_RUNTIME_VENV}/bin/pip" install --quiet \
    "mlflow==2.21.3" \
    "litellm[proxy]==1.60.7" \
    "boto3==1.34.162" \
    "botocore==1.34.162" \
    "ray[default]==2.54.1"
chown -R mluser:mluser "${ML_RUNTIME_ROOT}"

# ── ChromaDB (isolated venv to avoid dependency conflicts) ──
echo "[*] Installing ChromaDB in venv..."
mkdir -p /opt/chromadb/data
python3 -m venv /opt/chromadb/venv
/opt/chromadb/venv/bin/pip install --quiet "chromadb==0.6.3"
chown -R mluser:mluser /opt/chromadb

cat > /etc/systemd/system/chromadb.service << 'EOF'
[Unit]
Description=ChromaDB Vector Database
After=network.target

[Service]
User=mluser
WorkingDirectory=/opt/chromadb
ExecStart=/opt/chromadb/venv/bin/chroma run --host 0.0.0.0 --port 8000 --path /opt/chromadb/data
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable chromadb
systemctl restart chromadb

echo "[*] Waiting for ChromaDB on :8000..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:8000/api/v1/heartbeat &>/dev/null; then
        echo "[+] ChromaDB is ready"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[!] ChromaDB failed to start. Journal output:"
        journalctl -u chromadb --no-pager -n 30
        echo "[!] Attempting restart..."
        systemctl restart chromadb
        sleep 5
        if ! curl -sf http://localhost:8000/api/v1/heartbeat &>/dev/null; then
            echo "[!] ChromaDB still not responding after restart"
            exit 1
        fi
        echo "[+] ChromaDB came up after restart"
    fi
    sleep 2
done
echo "[+] ChromaDB installed (port 8000, no auth)"

# ── MLflow ──────────────────────────────────────────────────
echo "[*] Installing MLflow..."

mkdir -p /opt/mlflow/artifacts
# Proxied-artifact store: enables the real mlflow-artifacts REST write API (via
# --serve-artifacts + --artifacts-destination below). New runs created through the
# tracking server get mlflow-artifacts: URIs backed here; existing file:// runs under
# /opt/mlflow/artifacts stay readable via --default-artifact-root.
mkdir -p /opt/mlflow/mlartifacts
chown -R mluser:mluser /opt/mlflow
chmod 1777 /opt/mlflow/artifacts

cat > /etc/systemd/system/mlflow.service << EOF
[Unit]
Description=MLflow Tracking Server
After=network.target

[Service]
User=mluser
ExecStart=${ML_RUNTIME_VENV}/bin/mlflow server --host 0.0.0.0 --port 5000 --backend-store-uri sqlite:////opt/mlflow/mlflow.db --default-artifact-root /opt/mlflow/artifacts --artifacts-destination /opt/mlflow/mlartifacts --serve-artifacts
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mlflow
systemctl restart mlflow

echo "[*] Waiting for MLflow on :5000..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:5000/ &>/dev/null; then
        echo "[+] MLflow is ready"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[!] MLflow failed to start. Journal output:"
        journalctl -u mlflow --no-pager -n 30
        echo "[!] Attempting restart..."
        systemctl restart mlflow
        sleep 5
        if ! curl -sf http://localhost:5000/ &>/dev/null; then
            echo "[!] MLflow still not responding after restart"
            exit 1
        fi
        echo "[+] MLflow came up after restart"
    fi
    sleep 2
done
echo "[+] MLflow installed (port 5000, no auth)"

# MLflow registry hook controller. This watches real MLflow model-version tags
# and delivers hook URLs; it does not add any invented endpoint to MLflow itself.
sudo -u mluser mkdir -p /home/mluser/projects/mlflow-hook-controller
mkdir -p /var/lib/aipostex/mlflow-hook-controller
chown -R mluser:mluser /var/lib/aipostex
if [ -f "$(dirname "$0")/mlflow-hook-controller/server.py" ]; then
    cp "$(dirname "$0")/mlflow-hook-controller/server.py" /home/mluser/projects/mlflow-hook-controller/server.py
    chown mluser:mluser /home/mluser/projects/mlflow-hook-controller/server.py
fi

cat > /etc/systemd/system/mlflow-hook-controller.service << 'EOF'
[Unit]
Description=MLflow Registry Hook Controller
After=network.target mlflow.service
Requires=mlflow.service

[Service]
User=mluser
WorkingDirectory=/home/mluser/projects/mlflow-hook-controller
Environment="MLFLOW_HOOK_TRACKING_URI=http://localhost:5000"
Environment="MLFLOW_HOOK_TAG_KEY=aipostex.hook.url"
Environment="MLFLOW_HOOK_STATE=/var/lib/aipostex/mlflow-hook-controller/delivered.json"
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mlflow-hook-controller
systemctl restart mlflow-hook-controller
if ! systemctl is-active --quiet mlflow-hook-controller; then
    echo "[!] MLflow hook controller failed to start. Journal output:"
    journalctl -u mlflow-hook-controller --no-pager -n 30
    exit 1
fi
echo "[+] MLflow hook controller installed (systemd: mlflow-hook-controller.service)"

# ── LiteLLM Proxy ──────────────────────────────────────────
echo "[*] Installing LiteLLM proxy..."

mkdir -p /opt/litellm

if [ -f "$(dirname "$0")/litellm_config.yaml" ]; then
    cp "$(dirname "$0")/litellm_config.yaml" /opt/litellm/config.yaml
    # The static config hardcodes the base-estate Ollama upstream (172.16.50.10). Thread
    # LAB_SUBNET so LiteLLM reaches THIS estate's dev Ollama — required for the real-inference
    # hop of the chain on AWS (10.0.1) and on any multi-estate (172.16.51+), no-op on base.
    sed -i "s|172\.16\.50\.10:11434|${LAB_SUBNET:-172.16.50}.10:11434|g" /opt/litellm/config.yaml
fi
chown -R mluser:mluser /opt/litellm

cat > /etc/systemd/system/litellm.service << EOF
[Unit]
Description=LiteLLM API Proxy
After=network.target

[Service]
User=mluser
ExecStart=${ML_RUNTIME_VENV}/bin/litellm --config /opt/litellm/config.yaml --port 4000 --host 0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable litellm
systemctl restart litellm

echo "[*] Waiting for LiteLLM on :4000..."
for i in $(seq 1 20); do
    if curl -sf http://localhost:4000/health &>/dev/null; then
        echo "[+] LiteLLM is ready"
        break
    fi
    if [ "$i" -eq 20 ]; then
        echo "[!] LiteLLM failed to start. Journal output:"
        journalctl -u litellm --no-pager -n 30
        echo "[*] LiteLLM may need Ollama backend — continuing anyway"
    fi
    sleep 2
done
echo "[+] LiteLLM proxy installed (port 4000)"

# ── LiteLLM Authenticated Instance ───────────────────────
echo "[*] Setting up authenticated LiteLLM instance on :4001..."

if [ -f "$(dirname "$0")/litellm_config_authed.yaml" ]; then
    cp "$(dirname "$0")/litellm_config_authed.yaml" /opt/litellm/config_authed.yaml
    # Same LAB_SUBNET threading as the open :4000 config (this one drives the chain's
    # authed real-inference climax with the looted master key).
    sed -i "s|172\.16\.50\.10:11434|${LAB_SUBNET:-172.16.50}.10:11434|g" /opt/litellm/config_authed.yaml
fi
chown -R mluser:mluser /opt/litellm

cat > /etc/systemd/system/litellm-authed.service << EOF
[Unit]
Description=LiteLLM API Proxy (Authenticated)
After=network.target litellm.service

[Service]
User=mluser
ExecStart=${ML_RUNTIME_VENV}/bin/litellm --config /opt/litellm/config_authed.yaml --port 4001 --host 0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable litellm-authed
systemctl restart litellm-authed

echo "[*] Waiting for LiteLLM-authed on :4001..."
for i in $(seq 1 20); do
    if curl -sf -H "Authorization: Bearer sk-litellm-lab-auth-key-FAKE123" http://localhost:4001/health &>/dev/null; then
        echo "[+] LiteLLM-authed is ready"
        break
    fi
    if [ "$i" -eq 20 ]; then
        echo "[!] LiteLLM-authed failed to start. Journal output:"
        journalctl -u litellm-authed --no-pager -n 30
        echo "[*] LiteLLM-authed may need Ollama backend — continuing anyway"
    fi
    sleep 2
done
echo "[+] LiteLLM-authed proxy installed (port 4001, master_key required)"

# ── Ray ────────────────────────────────────────────────────
echo "[*] Installing Ray..."
mkdir -p /opt/ray
chown mluser:mluser /opt/ray

cat > /etc/systemd/system/ray.service << EOF
[Unit]
Description=Ray Head Node
After=network.target

[Service]
User=mluser
ExecStart=${ML_RUNTIME_VENV}/bin/ray start --head --dashboard-host=0.0.0.0 --dashboard-port=8265 --block
Restart=always
RestartSec=5
Environment="RAY_TMPDIR=/opt/ray"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ray
systemctl restart ray
echo "[+] Ray installed (dashboard :8265, no auth)"

# Boot-time self-heal for the guided-chain Ray seed. Ray keeps its job records in the
# head's IN-MEMORY store, so a plain reboot (or a disk-only snapshot restore) comes up
# with hop 1 of the chain empty and nothing to re-plant it. reset-wave re-arms it and
# `reseed.sh ml` is the manual break-glass, but neither runs on an ordinary boot — so an
# attendee could sit down to a dead hop 1. This oneshot re-seeds Ray once it is healthy on
# every boot, GUARDED to skip if the seed is already present (composes with reset-wave and
# never double-submits). Logic lives in ml-platform/chain-seed-boot.sh (synced to ~labadmin/lab).
cat > /etc/systemd/system/aipostex-chain-seed.service << 'EOF'
[Unit]
Description=aipostex guided-chain Ray seed (boot-time self-heal for Ray's in-memory job store)
After=ray.service network-online.target
Wants=ray.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/home/labadmin/lab/ml-platform/chain-seed-boot.sh
TimeoutStartSec=300
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable aipostex-chain-seed.service
echo "[+] Boot-time chain-seed self-heal installed (aipostex-chain-seed.service)"

echo "[*] Waiting for Ray dashboard..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:8265/api/version &>/dev/null; then
        echo "[+] Ray dashboard is ready"
        break
    fi
    sleep 2
done

# ── HF TGI Mock (legacy ML-host copy) ──────────────────────
if [[ "${ENABLE_LEGACY_ML_TGI}" == "1" ]]; then
echo "[*] Setting up legacy HF TGI mock on ML host..."
sudo -u mluser mkdir -p /home/mluser/projects/hf-tgi-mock
if [ -f "$(dirname "$0")/hf-tgi-mock/server.py" ]; then
    cp "$(dirname "$0")/hf-tgi-mock/server.py" /home/mluser/projects/hf-tgi-mock/server.py
    chown mluser:mluser /home/mluser/projects/hf-tgi-mock/server.py
fi

cat > /etc/systemd/system/hf-tgi-mock.service << 'EOF'
[Unit]
Description=HF TGI Mock
After=network.target

[Service]
User=mluser
WorkingDirectory=/home/mluser/projects/hf-tgi-mock
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hf-tgi-mock
systemctl restart hf-tgi-mock

wait_for_service "HF TGI mock" "http://localhost:8180/health" 20 hf-tgi-mock
else
    systemctl disable --now hf-tgi-mock >/dev/null 2>&1 || true
    echo "[*] Legacy ML-host HF TGI mock disabled; TGI gateway runs on ailab-app:8180"
fi

# ── HF TEI Mock ───────────────────────────────────────────
echo "[*] Setting up HF TEI mock..."
sudo -u mluser mkdir -p /home/mluser/projects/hf-tei-mock
if [ -f "$(dirname "$0")/hf-tei-mock/server.py" ]; then
    cp "$(dirname "$0")/hf-tei-mock/server.py" /home/mluser/projects/hf-tei-mock/server.py
    chown mluser:mluser /home/mluser/projects/hf-tei-mock/server.py
fi

cat > /etc/systemd/system/hf-tei-mock.service << 'EOF'
[Unit]
Description=HF TEI Mock
After=network.target

[Service]
User=mluser
WorkingDirectory=/home/mluser/projects/hf-tei-mock
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hf-tei-mock
systemctl restart hf-tei-mock

wait_for_service "HF TEI mock" "http://localhost:8181/info" 20 hf-tei-mock

# ── vLLM Mock ─────────────────────────────────────────────
echo "[*] Setting up vLLM mock..."
sudo -u mluser mkdir -p /home/mluser/projects/vllm-mock
if [ -f "$(dirname "$0")/vllm-mock/server.py" ]; then
    cp "$(dirname "$0")/vllm-mock/server.py" /home/mluser/projects/vllm-mock/server.py
    chown mluser:mluser /home/mluser/projects/vllm-mock/server.py
fi

cat > /etc/systemd/system/vllm-mock.service << 'EOF'
[Unit]
Description=vLLM Mock
After=network.target

[Service]
User=mluser
WorkingDirectory=/home/mluser/projects/vllm-mock
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vllm-mock
systemctl restart vllm-mock

wait_for_service "vLLM mock" "http://localhost:8182/health" 20 vllm-mock

# ── BentoML Mock ─────────────────────────────────────────
echo "[*] Setting up BentoML mock..."
sudo -u mluser mkdir -p /home/mluser/projects/bentoml-mock
if [ -f "$(dirname "$0")/bentoml-mock/server.py" ]; then
    cp "$(dirname "$0")/bentoml-mock/server.py" /home/mluser/projects/bentoml-mock/server.py
    chown mluser:mluser /home/mluser/projects/bentoml-mock/server.py
fi

cat > /etc/systemd/system/bentoml-mock.service << 'EOF'
[Unit]
Description=BentoML Mock
After=network.target

[Service]
User=mluser
WorkingDirectory=/home/mluser/projects/bentoml-mock
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable bentoml-mock
systemctl restart bentoml-mock

wait_for_service "BentoML mock" "http://localhost:3333/healthz" 20 bentoml-mock

# ── TorchServe Mock ──────────────────────────────────────
echo "[*] Setting up TorchServe mock..."
sudo -u mluser mkdir -p /home/mluser/projects/torchserve-mock
if [ -f "$(dirname "$0")/torchserve-mock/server.py" ]; then
    cp "$(dirname "$0")/torchserve-mock/server.py" /home/mluser/projects/torchserve-mock/server.py
    chown mluser:mluser /home/mluser/projects/torchserve-mock/server.py
fi

cat > /etc/systemd/system/torchserve-mock.service << 'EOF'
[Unit]
Description=TorchServe Mock
After=network.target

[Service]
User=mluser
WorkingDirectory=/home/mluser/projects/torchserve-mock
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable torchserve-mock
systemctl restart torchserve-mock

wait_for_service "TorchServe mock" "http://localhost:8081/models" 20 torchserve-mock

# ── Triton Mock ──────────────────────────────────────────
echo "[*] Setting up Triton mock..."
sudo -u mluser mkdir -p /home/mluser/projects/triton-mock
if [ -f "$(dirname "$0")/triton-mock/server.py" ]; then
    cp "$(dirname "$0")/triton-mock/server.py" /home/mluser/projects/triton-mock/server.py
    chown mluser:mluser /home/mluser/projects/triton-mock/server.py
fi

cat > /etc/systemd/system/triton-mock.service << 'EOF'
[Unit]
Description=Triton Inference Server Mock
After=network.target

[Service]
User=mluser
WorkingDirectory=/home/mluser/projects/triton-mock
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable triton-mock
systemctl restart triton-mock

wait_for_service "Triton mock" "http://localhost:8500/v2/health/ready" 20 triton-mock

# ── W&B Mock ─────────────────────────────────────────────
echo "[*] Setting up W&B mock..."
sudo -u mluser mkdir -p /home/mluser/projects/wandb-mock
if [ -f "$(dirname "$0")/wandb-mock/server.py" ]; then
    cp "$(dirname "$0")/wandb-mock/server.py" /home/mluser/projects/wandb-mock/server.py
    chown mluser:mluser /home/mluser/projects/wandb-mock/server.py
fi

cat > /etc/systemd/system/wandb-mock.service << 'EOF'
[Unit]
Description=Weights & Biases Mock Server
After=network.target

[Service]
User=mluser
WorkingDirectory=/home/mluser/projects/wandb-mock
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wandb-mock
systemctl restart wandb-mock

wait_for_service "W&B mock" "http://localhost:8444/healthz" 20 wandb-mock

# ── Kubeflow Pipelines Mock ──────────────────────────────
echo "[*] Setting up Kubeflow Pipelines mock..."
sudo -u mluser mkdir -p /home/mluser/projects/kubeflow-mock
if [ -f "$(dirname "$0")/kubeflow-mock/server.py" ]; then
    cp "$(dirname "$0")/kubeflow-mock/server.py" /home/mluser/projects/kubeflow-mock/server.py
    chown mluser:mluser /home/mluser/projects/kubeflow-mock/server.py
fi

cat > /etc/systemd/system/kubeflow-mock.service << 'EOF'
[Unit]
Description=Kubeflow Pipelines Mock
After=network.target

[Service]
User=mluser
WorkingDirectory=/home/mluser/projects/kubeflow-mock
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kubeflow-mock
systemctl restart kubeflow-mock

wait_for_service "Kubeflow mock" "http://localhost:9000/pipeline/" 20 kubeflow-mock

# Second Kubeflow instance serving ONLY the modern KFP 2.x v2beta1 API (no
# v1beta1) so aipostex's v2beta1 support is exercised against a realistic
# modern-cluster shape. Reuses the same server.py via KUBEFLOW_API_MODE=v2.
cat > /etc/systemd/system/kubeflow-mock-v2.service << 'EOF'
[Unit]
Description=Kubeflow Pipelines Mock (v2beta1-only)
After=network.target

[Service]
User=mluser
WorkingDirectory=/home/mluser/projects/kubeflow-mock
Environment=KUBEFLOW_MOCK_PORT=9001
Environment=KUBEFLOW_API_MODE=v2
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kubeflow-mock-v2
systemctl restart kubeflow-mock-v2

wait_for_service "Kubeflow mock v2" "http://localhost:9001/pipeline/" 20 kubeflow-mock-v2

# ── TF Serving Mock ──────────────────────────────────────
echo "[*] Setting up TF Serving mock..."
sudo -u mluser mkdir -p /home/mluser/projects/tfserving-mock
if [ -f "$(dirname "$0")/tfserving-mock/server.py" ]; then
    cp "$(dirname "$0")/tfserving-mock/server.py" /home/mluser/projects/tfserving-mock/server.py
    chown mluser:mluser /home/mluser/projects/tfserving-mock/server.py
fi

cat > /etc/systemd/system/tfserving-mock.service << 'EOF'
[Unit]
Description=TensorFlow Serving Mock
After=network.target

[Service]
User=mluser
WorkingDirectory=/home/mluser/projects/tfserving-mock
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tfserving-mock
systemctl restart tfserving-mock

wait_for_service "TF Serving mock" "http://localhost:8501/v1/models/acme-fraud-scorer" 20 tfserving-mock

# ── Summary ─────────────────────────────────────────────────
echo ""
echo "[+] ailab-ml provisioning complete"
echo "    Services:"
echo "      ChromaDB    :8000  (systemd: chromadb.service)"
echo "      MLflow      :5000  (systemd: mlflow.service)"
echo "      MLflow hook controller (systemd: mlflow-hook-controller.service)"
echo "      LiteLLM     :4000  (systemd: litellm.service, no auth)"
echo "      LiteLLM     :4001  (systemd: litellm-authed.service, master_key)"
echo "      Ray         :8265  (systemd: ray.service)"
echo "      HF TGI      :8180  (systemd: tgi-gateway.service on ailab-app; set ENABLE_LEGACY_ML_TGI=1 for legacy ML-host mock)"
echo "      HF TEI      :8181  (systemd: hf-tei-mock.service)"
echo "      vLLM        :8182  (systemd: vllm-mock.service)"
echo "      BentoML     :3333  (systemd: bentoml-mock.service)"
echo "      TorchServe  :8080-8082  (systemd: torchserve-mock.service)"
echo "      Triton      :8500  (systemd: triton-mock.service)"
echo "      W&B         :8444  (systemd: wandb-mock.service)"
echo "      Kubeflow    :9000  (systemd: kubeflow-mock.service)"
echo "      TF Serving  :8501  (systemd: tfserving-mock.service)"
