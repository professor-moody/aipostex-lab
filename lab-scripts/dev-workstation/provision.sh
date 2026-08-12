#!/bin/bash
# provision.sh — Provision ailab-dev (developer workstation)
# Run as root on 172.16.50.10 AFTER base-setup.sh
# Installs: Ollama, Jupyter, vulnerable MCP server, Gradio lab app
# All as native services with systemd units
set -euo pipefail

echo "[*] Provisioning ailab-dev (developer workstation)..."

wait_for_http_match() {
    local service_name=$1
    local service_unit=$2
    local url=$3
    local expected=$4
    local attempts=${5:-30}

    echo "[*] Waiting for ${service_name} to be ready..."
    for _ in $(seq 1 "${attempts}"); do
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

wait_for_mcp_ready() {
    # Streamable HTTP MCP has no GET health route; probe with a POST initialize
    # and accept any response carrying a JSON-RPC result / protocolVersion (the
    # reply is SSE-framed, so cap the read with --max-time instead of waiting for
    # the stream to close).
    local service_name=$1
    local service_unit=$2
    local url=$3
    local attempts=${4:-30}

    echo "[*] Waiting for ${service_name} to be ready..."
    for _ in $(seq 1 "${attempts}"); do
        local body
        body=$(curl -s --max-time 6 -X POST "${url}" \
            -H 'Content-Type: application/json' \
            -H 'Accept: application/json, text/event-stream' \
            -d '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}' 2>/dev/null || true)
        if echo "${body}" | grep -qiE 'protocolVersion|"result"'; then
            echo "[+] ${service_name} is ready"
            return 0
        fi
        sleep 2
    done

    echo "[!] ${service_name} failed readiness check at ${url}"
    journalctl -u "${service_unit}" --no-pager -n 30 || true
    return 1
}

# ── Create devuser ──────────────────────────────────────────
if ! id devuser &>/dev/null; then
    useradd -m -s /bin/bash devuser
    echo "[+] Created devuser"
else
    echo "[*] devuser already exists"
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

# ── Ollama maintenance helper (INTENTIONAL privesc misconfig) ───────────────
# An authentic ops pattern gone wrong: an admin gave devuser passwordless sudo to
# a small "maintenance" helper so it could prune/reload Ollama models without a
# ticket — but left the helper world-writable. Ollama's on-disk weight store
# (/usr/share/ollama/.ollama/models, 0750 root/ollama-only) is unreadable by
# devuser and Ollama serves no HTTP blob download, so model-weight theft REQUIRES
# a local root. This sudo-NOPASSWD + world-writable-script combo (a GTFOBins-class
# misconfig) is the intended devuser→root path, reached via the co-located MCP RCE
# (acme-mcp runs as devuser). devuser is deliberately NOT in the ollama group, so
# the 0750 store stays realistic and the ONLY path to the weights is this escalation.
echo "[*] Installing ollama-maintenance helper (intentional privesc primitive)..."
cat > /usr/local/bin/ollama-maintenance.sh << 'MAINTEOF'
#!/bin/bash
# ACME ops: prune stale Ollama model blobs + reload the service.
# Run via: sudo /usr/local/bin/ollama-maintenance.sh
set -e
echo "[ollama-maintenance] running as $(id -un) (uid=$(id -u))"
find /usr/share/ollama/.ollama/models -type f -name '*.partial' -mtime +7 -delete 2>/dev/null || true
systemctl reload ollama 2>/dev/null || systemctl restart ollama 2>/dev/null || true
echo "[ollama-maintenance] done"
MAINTEOF
chown root:root /usr/local/bin/ollama-maintenance.sh
# The misconfig: world-writable (0777) so any local account — including the
# devuser the MCP RCE lands as — can overwrite the body an instant before sudo
# executes it as root. Synchronous, well inside the MCP execute_command window.
chmod 0777 /usr/local/bin/ollama-maintenance.sh
cat > /etc/sudoers.d/ollama-maintenance << 'SUDOEOF'
# Passwordless maintenance access granted to devuser (ops convenience).
devuser ALL=(root) NOPASSWD: /usr/local/bin/ollama-maintenance.sh
SUDOEOF
chmod 0440 /etc/sudoers.d/ollama-maintenance
visudo -cf /etc/sudoers.d/ollama-maintenance >/dev/null && echo "[+] ollama-maintenance sudoers rule installed"

# ── Jupyter ─────────────────────────────────────────────────
echo "[*] Installing JupyterLab..."
sudo -u devuser /usr/bin/python3 -m pip install --user --break-system-packages "jupyterlab==4.4.1" 2>/dev/null

sudo -u devuser mkdir -p /home/devuser/.jupyter
cat > /home/devuser/.jupyter/jupyter_lab_config.py << 'PYEOF'
c.ServerApp.token = ''
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.root_dir = '/home/devuser'
PYEOF
chown devuser:devuser /home/devuser/.jupyter/jupyter_lab_config.py

cat > /etc/systemd/system/jupyter.service << 'EOF'
[Unit]
Description=Jupyter Lab (devuser)
After=network.target

[Service]
User=devuser
WorkingDirectory=/home/devuser
ExecStart=/home/devuser/.local/bin/jupyter lab --config=/home/devuser/.jupyter/jupyter_lab_config.py
Restart=always
RestartSec=5
Environment="PATH=/home/devuser/.local/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable jupyter
systemctl restart jupyter
wait_for_http_match "Jupyter" "jupyter" "http://localhost:8888/api" "version"
echo "[+] Jupyter installed (port 8888, no auth)"

# ── MCP Server (real MCP SDK / FastMCP, Streamable HTTP) ─────
# The lab's MCP target is a genuine MCP-SDK server (not a hand-written mock), so
# aipostex is exercised against true SDK behaviour: /mcp endpoint discovery, the
# initialize→session handshake, and pydantic-enforced tool argument schemas.
echo "[*] Setting up MCP server (official MCP SDK, FastMCP, Streamable HTTP)..."
MCP_APP_DIR="/home/devuser/projects/internal-tools/mcp-server"
sudo -u devuser mkdir -p "$MCP_APP_DIR"

if [ -f "$(dirname "$0")/mcp-real-server/server.py" ]; then
    cp "$(dirname "$0")/mcp-real-server/server.py" \
       "$(dirname "$0")/mcp-real-server/requirements.txt" \
       "$MCP_APP_DIR/"
    chown -R devuser:devuser "$MCP_APP_DIR"
fi

# Native Python venv with the pinned MCP SDK (no Docker — GPU is the only
# Docker-worthy constraint in this lab; the SDK runs fine under a plain venv).
if [ ! -x "$MCP_APP_DIR/.venv/bin/python" ]; then
    sudo -u devuser python3 -m venv "$MCP_APP_DIR/.venv"
fi
sudo -u devuser "$MCP_APP_DIR/.venv/bin/pip" install -q --upgrade pip
sudo -u devuser "$MCP_APP_DIR/.venv/bin/pip" install -q -r "$MCP_APP_DIR/requirements.txt"

cat > /etc/systemd/system/acme-mcp.service << 'EOF'
[Unit]
Description=ACME Internal MCP Server (official MCP SDK, Streamable HTTP)
After=network.target

[Service]
User=devuser
WorkingDirectory=/home/devuser/projects/internal-tools/mcp-server
Environment="MCP_HOST=0.0.0.0"
Environment="MCP_PORT=3000"
ExecStart=/home/devuser/projects/internal-tools/mcp-server/.venv/bin/python server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable acme-mcp
systemctl restart acme-mcp
wait_for_mcp_ready "ACME MCP server" "acme-mcp" "http://localhost:3000/mcp" 30
echo "[+] MCP server installed (port 3000, real MCP SDK — /mcp Streamable HTTP)"

# ── Vulnerable MCP server (:3002) — sandbox-escape + SSTI targets ────────────
echo "[*] Setting up vulnerable MCP server (sandbox-escape + SSTI)..."
VULN_MCP_DIR="/home/devuser/projects/internal-tools/mcp-vuln-server"
sudo -u devuser mkdir -p "$VULN_MCP_DIR"
install -d -o devuser -g devuser /data/documents 2>/dev/null || { mkdir -p /data/documents; chown devuser:devuser /data/documents; }
if [ -f "$(dirname "$0")/mcp-vuln-server/server.py" ]; then
    cp "$(dirname "$0")/mcp-vuln-server/server.py" \
       "$(dirname "$0")/mcp-vuln-server/requirements.txt" \
       "$VULN_MCP_DIR/"
    chown -R devuser:devuser "$VULN_MCP_DIR"
fi
if [ ! -x "$VULN_MCP_DIR/.venv/bin/python" ]; then
    sudo -u devuser python3 -m venv "$VULN_MCP_DIR/.venv"
fi
sudo -u devuser "$VULN_MCP_DIR/.venv/bin/pip" install -q --upgrade pip
sudo -u devuser "$VULN_MCP_DIR/.venv/bin/pip" install -q -r "$VULN_MCP_DIR/requirements.txt"

cat > /etc/systemd/system/acme-doc-tools.service << 'EOF'
[Unit]
Description=ACME Doc Tools MCP Server (vulnerable — sandbox-escape + SSTI)
After=network.target

[Service]
User=devuser
WorkingDirectory=/home/devuser/projects/internal-tools/mcp-vuln-server
Environment="MCP_HOST=0.0.0.0"
Environment="MCP_PORT=3002"
Environment="MCP_DOC_DIR=/data/documents"
ExecStart=/home/devuser/projects/internal-tools/mcp-vuln-server/.venv/bin/python server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable acme-doc-tools
systemctl restart acme-doc-tools
wait_for_mcp_ready "ACME Doc Tools MCP" "acme-doc-tools" "http://localhost:3002/mcp" 30
echo "[+] Vulnerable MCP server installed (port 3002, acme-doc-tools — read_document sandbox-escape + render_report SSTI)"

# ── Gradio Lab App ──────────────────────────────────────────
echo "[*] Installing Gradio lab app..."
sudo -u devuser /usr/bin/python3 -m pip install --user --break-system-packages "gradio==5.49.1" 2>/dev/null

sudo -u devuser mkdir -p /home/devuser/projects/gradio-chat

if [ -f "$(dirname "$0")/gradio-chat/app.py" ]; then
    cp "$(dirname "$0")/gradio-chat/app.py" \
       /home/devuser/projects/gradio-chat/app.py
    chown devuser:devuser /home/devuser/projects/gradio-chat/app.py
fi

cat > /etc/systemd/system/gradio-chat.service << 'EOF'
[Unit]
Description=Gradio Lab App
After=network.target ollama.service

[Service]
User=devuser
WorkingDirectory=/home/devuser/projects/gradio-chat
ExecStart=/usr/bin/python3 app.py
Restart=always
RestartSec=5
Environment="PATH=/home/devuser/.local/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable gradio-chat
systemctl restart gradio-chat
wait_for_http_match "Gradio lab app" "gradio-chat" "http://localhost:7860/config" "predict_text"
echo "[+] Gradio lab app installed (port 7860)"

# ── MCP Inspector Mock ─────────────────────────────────────
echo "[*] Setting up MCP Inspector mock..."
sudo -u devuser mkdir -p /home/devuser/projects/mcp-inspector-mock

if [ -f "$(dirname "$0")/mcp-inspector-mock/server.py" ]; then
    cp "$(dirname "$0")/mcp-inspector-mock/server.py" \
       /home/devuser/projects/mcp-inspector-mock/server.py
    chown devuser:devuser /home/devuser/projects/mcp-inspector-mock/server.py
fi

cat > /etc/systemd/system/mcp-inspector.service << 'EOF'
[Unit]
Description=MCP Inspector (dev debug tool)
After=network.target acme-mcp.service

[Service]
User=devuser
WorkingDirectory=/home/devuser/projects/mcp-inspector-mock
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mcp-inspector
systemctl restart mcp-inspector
wait_for_http_match "MCP Inspector mock" "mcp-inspector" "http://localhost:6274/api/version" "mcp inspector"
echo "[+] MCP Inspector mock installed (port 6274)"

# ── Internal admin (lateral movement target) ─────────────────
echo "[*] Installing internal-admin lateral target (127.0.0.1:9999)..."
sudo -u devuser mkdir -p /home/devuser/projects/internal-admin

ADMIN_SRC="$(dirname "$0")/internal-admin"
if [ -f "${ADMIN_SRC}/server.py" ]; then
    cp "${ADMIN_SRC}/server.py" /home/devuser/projects/internal-admin/server.py
    chown devuser:devuser /home/devuser/projects/internal-admin/server.py
fi

cat > /etc/systemd/system/internal-admin.service << 'EOF'
[Unit]
Description=ACME Internal Admin Panel (localhost only)
After=network.target

[Service]
User=devuser
WorkingDirectory=/home/devuser/projects/internal-admin
Environment="BIND_ADDR=127.0.0.1"
Environment="PORT=9999"
Environment="TOKEN_PATH=/home/devuser/.secrets/internal-admin.token"
Environment="POX_URL=http://172.16.50.40:8765"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
ExecStart=/usr/bin/python3 /home/devuser/projects/internal-admin/server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Point POX_URL at this estate's app host (.40 on the estate subnet). The unit is written
# from a quoted heredoc, so substitute here; on the base estate this is a no-op (172.16.50.40).
sed -i "s|http://172\.16\.50\.40:8765|http://${LAB_SUBNET:-172.16.50}.40:8765|" /etc/systemd/system/internal-admin.service

systemctl daemon-reload
systemctl enable internal-admin
systemctl restart internal-admin
# Give it a moment — localhost only, no external health check
sleep 2
echo "[+] internal-admin installed (127.0.0.1:9999 only)"

# ── Summary ─────────────────────────────────────────────────
echo ""
echo "[+] ailab-dev provisioning complete"
echo "    Services:"
echo "      Ollama          :11434        (systemd: ollama.service)"
echo "      Jupyter         :8888         (systemd: jupyter.service)"
echo "      MCP Server      :3000         (systemd: acme-mcp.service)"
echo "      Gradio          :7860         (systemd: gradio-chat.service)"
echo "      Inspector       :6274         (systemd: mcp-inspector.service)"
echo "      Internal Admin  :9999 (lo)    (systemd: internal-admin.service)"
