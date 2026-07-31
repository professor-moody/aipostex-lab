#!/bin/bash
# Provision enterprise inference host with native Ollama, LiteLLM, and TGI fixture.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_ROOT="/opt/acme-inference"
RUNTIME_VENV="${RUNTIME_ROOT}/venv"

echo "[*] Provisioning ent-inference-01..."

if ! id inferuser >/dev/null 2>&1; then
    useradd -m -s /bin/bash inferuser
fi

echo "[*] Installing Ollama..."
OLLAMA_VERSION="${OLLAMA_VERSION:-0.6.2}"
curl -fsSL https://ollama.com/install.sh | OLLAMA_VERSION="${OLLAMA_VERSION}" sh
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF
systemctl daemon-reload
systemctl enable --now ollama
for _ in $(seq 1 30); do
    curl -sf http://localhost:11434/api/version >/dev/null 2>&1 && break
    sleep 2
done
ollama pull smollm2:135m

echo "[*] Installing LiteLLM gateway..."
mkdir -p "${RUNTIME_ROOT}" /opt/litellm
python3 -m venv "${RUNTIME_VENV}"
"${RUNTIME_VENV}/bin/pip" install --quiet "litellm[proxy]==1.60.7"
cp "${SCRIPT_DIR}/litellm_enterprise.yaml" /opt/litellm/config.yaml
chown -R inferuser:inferuser "${RUNTIME_ROOT}" /opt/litellm

cat > /etc/systemd/system/litellm.service <<EOF
[Unit]
Description=Enterprise LiteLLM Gateway
After=network.target ollama.service

[Service]
User=inferuser
ExecStart=${RUNTIME_VENV}/bin/litellm --config /opt/litellm/config.yaml --port 4000 --host 0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now litellm

echo "[*] Installing HF TGI fixture..."
mkdir -p /opt/hf-tgi-mock
cp "${LAB_ROOT}/ml-platform/hf-tgi-mock/server.py" /opt/hf-tgi-mock/server.py
chown -R inferuser:inferuser /opt/hf-tgi-mock
cat > /etc/systemd/system/hf-tgi-mock.service <<'EOF'
[Unit]
Description=Enterprise HF TGI Fixture
After=network.target

[Service]
User=inferuser
WorkingDirectory=/opt/hf-tgi-mock
ExecStart=/usr/bin/python3 /opt/hf-tgi-mock/server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now hf-tgi-mock

for spec in "LiteLLM|http://localhost:4000/health/liveliness" "HF TGI|http://localhost:8180/health"; do
    IFS='|' read -r name url <<<"${spec}"
    echo "[*] Waiting for ${name}..."
    for i in $(seq 1 30); do
        if curl -sf "${url}" >/dev/null 2>&1; then
            echo "[+] ${name} ready"
            break
        fi
        if [[ $i -eq 30 ]]; then
            echo "[!] ${name} failed readiness"
            exit 1
        fi
        sleep 2
    done
done

echo "[+] ent-inference-01 provisioning complete"
