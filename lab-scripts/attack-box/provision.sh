#!/bin/bash
# provision.sh — Provision the attack box with Go, Tailscale, and pentesting tools
#
# Run as root on ailab-attack
# Usage: sudo bash provision.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lab-scripts/lib/inventory.sh
source "${LAB_DIR}/lib/inventory.sh"

GO_VERSION="${GO_VERSION:-1.23.6}"
DEV_IP="$(inventory_host_ip "ailab-dev")"
ML_IP="$(inventory_host_ip "ailab-ml")"
DS_IP="$(inventory_host_ip "ailab-ds")"
APP_IP="$(inventory_host_ip "ailab-app")"
# Guard: empty IPs (inventory not loaded) would silently write a malformed
# remote_mcp_chain.json (e.g. http://:3000/message). Fail loud instead.
for _ip in "$DEV_IP" "$ML_IP" "$DS_IP" "$APP_IP"; do
    [ -n "$_ip" ] || { echo "[!] inventory did not resolve a host IP — aborting provision" >&2; exit 1; }
done

echo ""
echo "═══════════════════════════════════════════════════"
echo "  aipostex Attack Box — Provisioning"
echo "═══════════════════════════════════════════════════"
echo ""

if [[ $EUID -ne 0 ]]; then
    echo "[!] This script must be run as root"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ── System packages ─────────────────────────────────────

echo "[*] Installing system packages..."
apt-get update -qq
apt-get install -y -qq \
    curl \
    wget \
    git \
    jq \
    make \
    python3 \
    python3-pip \
    python3-venv \
    nmap \
    netcat-openbsd \
    tmux \
    tree \
    unzip \
    dnsutils \
    net-tools \
    iputils-ping \
    openssh-client \
    2>/dev/null
echo "[+] System packages installed"

# ── kubectl (manual post-exploitation against the estate k8s node) ──────
# Pinned to the estate cluster version (rancher/k3s:v1.31.5 in lab-scripts/k8s-node/
# provision.sh) so `kubectl --token=<stolen-sa> …` runs without client-skew warnings.
if ! command -v kubectl >/dev/null 2>&1; then
    KUBECTL_VERSION="${KUBECTL_VERSION:-v1.31.5}"
    echo "[*] Installing kubectl ${KUBECTL_VERSION}..."
    if curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl; then
        chmod +x /usr/local/bin/kubectl
        echo "[+] kubectl ${KUBECTL_VERSION} installed"
    else
        echo "[!] kubectl download failed — the manual k8s post-ex beat needs it"
    fi
else
    echo "[*] kubectl already installed: $(kubectl version --client -o yaml 2>/dev/null | grep -m1 gitVersion || true)"
fi

# ── Go ──────────────────────────────────────────────────

if command -v go >/dev/null 2>&1; then
    echo "[*] Go already installed: $(go version)"
else
    echo "[*] Installing Go ${GO_VERSION}..."
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz

    cat > /etc/profile.d/go.sh << 'EOF'
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
EOF

    export PATH=$PATH:/usr/local/go/bin
    echo "[+] Go installed: $(go version)"
fi

# ── Tailscale ───────────────────────────────────────────

if command -v tailscale >/dev/null 2>&1; then
    echo "[*] Tailscale already installed"
else
    echo "[*] Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable tailscaled
    echo "[+] Tailscale installed"
fi

# ── IP forwarding (subnet-router entrance) ──────────────
# The attack box acts as a Tailscale subnet router advertising the estate. A router MUST
# forward, and a VM snapshot captures disk — not kernel runtime — so persist it in
# /etc/sysctl.d (survives the reset-wave rollback + reboot). A runtime `sysctl -w` alone is
# lost on the next boot, which silently breaks routing for the next wave.
echo "[*] Persisting net.ipv4.ip_forward for the subnet-router entrance..."
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-lab-router.conf
sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-lab-router.conf >/dev/null 2>&1 || true
echo "[+] ip_forward persisted (/etc/sysctl.d/99-lab-router.conf)"

# ── SSH config for lab VMs ──────────────────────────────

LABADMIN_HOME=$(eval echo ~labadmin)
SSH_DIR="${LABADMIN_HOME}/.ssh"
SSH_CONFIG="${SSH_DIR}/config"
MANAGED_START="# >>> aipostex-lab managed block >>>"
MANAGED_END="# <<< aipostex-lab managed block <<<"
mkdir -p "$SSH_DIR"

echo "[*] Refreshing SSH config for lab VMs..."
tmp_config=$(mktemp)
if [[ -f "${SSH_CONFIG}" ]]; then
    awk -v start="${MANAGED_START}" -v end="${MANAGED_END}" '
        $0 == start {skip=1; next}
        $0 == end {skip=0; next}
        !skip {print}
    ' "${SSH_CONFIG}" > "${tmp_config}"
else
    : > "${tmp_config}"
fi

cat >> "${tmp_config}" << EOF

${MANAGED_START}
Host ailab-dev
    HostName ${DEV_IP}
    User labadmin
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host ailab-ml
    HostName ${ML_IP}
    User labadmin
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host ailab-ds
    HostName ${DS_IP}
    User labadmin
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host ailab-app
    HostName ${APP_IP}
    User labadmin
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
${MANAGED_END}
EOF

mv "${tmp_config}" "${SSH_CONFIG}"
chown -R labadmin:labadmin "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "${SSH_CONFIG}"
echo "[+] SSH config refreshed (ssh ailab-dev / ailab-ml / ailab-ds / ailab-app)"

# ── SSH keypair for target access ─────────────────────────
# Generate a keypair so the attack box can SSH to lab target VMs.
# deploy-all.sh distributes the public key during phase 1.

KEY_FILE="${SSH_DIR}/id_ed25519"
if [[ ! -f "${KEY_FILE}" ]]; then
    echo "[*] Generating SSH keypair for labadmin..."
    sudo -u labadmin ssh-keygen -t ed25519 -f "${KEY_FILE}" -N '' -C 'labadmin@ailab-attack' >/dev/null
    echo "[+] SSH keypair generated"
else
    echo "[*] SSH keypair already exists"
fi
echo "    Public key: $(cat ${KEY_FILE}.pub)"

# ── MCP Config Fixtures ────────────────────────────────
# Copies of the planted MCP configs so mcp analyze can be run locally

echo "[*] Creating MCP config fixtures for local analysis..."
FIXTURES_DIR="${LABADMIN_HOME}/lab/mcp-configs"
mkdir -p "$FIXTURES_DIR"

cat > "$FIXTURES_DIR/claude_desktop_config.json" << 'MCPEOF'
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/devuser", "/opt/shared", "/etc"],
      "env": {}
    },
    "postgres-prod": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres"],
      "env": {
        "POSTGRES_CONNECTION_STRING": "postgresql://mcp_reader:McpR3ad3r!@db-prod-01.acme.internal:5432/acme_prod"
      }
    },
    "github-acme": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_FAKE1234567890abcdefghijklmnopqrstuv"
      }
    },
    "slack-internal": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-server-slack"],
      "env": {
        "SLACK_BOT_TOKEN": "xoxb-FAKE-1234567890-abcdefghijklmnop",
        "SLACK_TEAM_ID": "T0ACME001"
      }
    },
    "jira-board": {
      "command": "uvx",
      "args": ["mcp-atlassian"],
      "env": {
        "JIRA_URL": "https://acme.atlassian.net",
        "JIRA_EMAIL": "dev@acme.corp",
        "JIRA_API_TOKEN": "ATATT3xFfGF0_FAKE_jira_token_1234567890abcdef"
      }
    }
  }
}
MCPEOF

cat > "$FIXTURES_DIR/cursor_mcp.json" << 'MCPEOF'
{
  "mcpServers": {
    "local-sqlite": {
      "command": "python",
      "args": ["-m", "mcp_server_sqlite", "--db-path", "/home/devuser/projects/chatbot-prototype/app.db"]
    },
    "web-search": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-server-brave-search"],
      "env": {
        "BRAVE_API_KEY": "BSA_FAKE_brave_search_api_key_12345678"
      }
    }
  }
}
MCPEOF

cat > "$FIXTURES_DIR/vscode_settings.json" << 'MCPEOF'
{
  "mcp.servers": {
    "local-db": {
      "command": "python",
      "args": ["-m", "mcp_server_sqlite", "--db-path", "/home/devuser/projects/chatbot-prototype/app.db"]
    },
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres"],
      "env": {
        "POSTGRES_CONNECTION_STRING": "postgresql://dev_user:D3vUs3r!@db-dev-01.acme.internal:5432/chatbot_dev"
      }
    }
  },
  "editor.fontSize": 14,
  "python.defaultInterpreterPath": "/usr/bin/python3"
}
MCPEOF

cat > "$FIXTURES_DIR/remote_mcp_chain.json" << MCPEOF
{
  "mcpServers": {
    "acme-remote-debug": {
      "url": "http://${DEV_IP}:3000/message",
      "transport": "http",
      "tools": ["fetch_url", "read_file", "execute_command"],
      "env": {
        "INSPECTOR_URL": "http://${DEV_IP}:6274",
        "SERVICE_ROLE": "debug-bridge"
      }
    },
    "acme-remote-sse": {
      "url": "http://${DEV_IP}:3000/sse",
      "transport": "sse",
      "tools": ["fetch_url"],
      "env": {
        "REMOTE_NOTE": "inspector-adjacent remote MCP surface"
      }
    }
  }
}
MCPEOF

if [[ -f "${SCRIPT_DIR}/stdio-mcp-server.py" ]]; then
    cp "${SCRIPT_DIR}/stdio-mcp-server.py" "${LABADMIN_HOME}/lab/stdio-mcp-server.py"
    chown labadmin:labadmin "${LABADMIN_HOME}/lab/stdio-mcp-server.py"
    chmod 755 "${LABADMIN_HOME}/lab/stdio-mcp-server.py"
fi

chown -R labadmin:labadmin "$FIXTURES_DIR"
echo "[+] MCP fixtures at ~/lab/mcp-configs/ (4 config files)"

# ── Model Scan Fixtures ──────────────────────────────
# Small test files so model-scan can verify detection of risky
# serialization formats without requiring a real ML framework.

echo "[*] Creating model-scan fixtures for verify-aipostex.sh..."
MODELSCAN_DIR="${LABADMIN_HOME}/lab/model-scan-fixtures"
mkdir -p "$MODELSCAN_DIR"

python3 -c "
import pickle, struct, os

# 1. .pkl with os.system opcode (known dangerous pattern)
class MaliciousModel:
    def __reduce__(self):
        return (os.system, ('echo pwned',))

with open('$MODELSCAN_DIR/risky-model.pkl', 'wb') as f:
    pickle.dump(MaliciousModel(), f)

# 2. .safetensors — minimal valid safetensors (clean baseline)
header = b'{\"test\":{\"dtype\":\"F32\",\"shape\":[1],\"data_offsets\":[0,4]}}'
header_len = struct.pack('<Q', len(header))
with open('$MODELSCAN_DIR/clean-model.safetensors', 'wb') as f:
    f.write(header_len + header + struct.pack('<f', 1.0))

# 3. .pt with pickle payload (PyTorch format wrapping pickle)
with open('$MODELSCAN_DIR/torch-model.pt', 'wb') as f:
    pickle.dump({'weights': [1.0, 2.0], 'config': 'test'}, f)
" 2>/dev/null || echo "[!] model-scan fixture creation failed (python3 required)"

chown -R labadmin:labadmin "$MODELSCAN_DIR" 2>/dev/null || true
echo "[+] Model-scan fixtures at ~/lab/model-scan-fixtures/ (3 files)"

# ── Lab Listener ────────────────────────────────────────────────────────────

echo "[*] Installing lab-listener..."
LISTENER_DIR="${LABADMIN_HOME}/lab/lab-listener"
mkdir -p "$LISTENER_DIR"
mkdir -p /var/log/lab-listener

LISTENER_SRC="${SCRIPT_DIR}/lab-listener"
# Fail loud if the source did not make it here (e.g. an incomplete scp of lab-scripts):
# silently skipping the copy is how a "successful" run left the listener uninstalled.
for f in server.py storage.py; do
    if [ ! -f "${LISTENER_SRC}/${f}" ]; then
        echo "[!] lab-listener source missing: ${LISTENER_SRC}/${f} — re-copy lab-scripts to the attack box" >&2
        exit 1
    fi
    cp "${LISTENER_SRC}/${f}" "${LISTENER_DIR}/${f}"
done
chown -R labadmin:labadmin "$LISTENER_DIR" /var/log/lab-listener

cat > /etc/systemd/system/lab-listener.service << 'EOF'
[Unit]
Description=Lab shared callback/validation listener
After=network.target

[Service]
User=labadmin
WorkingDirectory=/home/labadmin/lab/lab-listener
Environment="LISTENER_PORT=9000"
Environment="LISTENER_HOST=0.0.0.0"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
ExecStart=/usr/bin/python3 /home/labadmin/lab/lab-listener/server.py
Restart=always
RestartSec=5
StandardOutput=append:/var/log/lab-listener/stdout.log
StandardError=append:/var/log/lab-listener/stderr.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable lab-listener
systemctl restart lab-listener

echo "[*] Waiting for lab-listener on :9000..."
listener_ready=0
for _ in $(seq 1 20); do
    if curl -sf http://localhost:9000/health >/dev/null 2>&1; then
        echo "[+] lab-listener is ready"
        listener_ready=1
        break
    fi
    sleep 2
done
# Fail the provision if the listener never came up, instead of printing a warning and
# exiting 0 (which let verify-lab downgrade a hard failure to an ignorable warning).
if [ "$listener_ready" -ne 1 ]; then
    echo "[!] lab-listener failed to start on :9000 within 40s" >&2
    journalctl -u lab-listener --no-pager -n 20 >&2 || true
    exit 1
fi

# ── Advanced pivot helper ────────────────────────────────

if [[ -f "${SCRIPT_DIR}/lab-pivot.sh" ]]; then
    install -m 0755 "${SCRIPT_DIR}/lab-pivot.sh" /usr/local/bin/lab-pivot.sh
    echo "[+] Installed lab-pivot.sh helper"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Attack Box Provisioning Complete"
echo "═══════════════════════════════════════════════════"
echo ""
echo "  Installed:"
echo "    Go:        $(go version 2>/dev/null | cut -d' ' -f3 || echo 'not found')"
echo "    Tailscale: $(tailscale version 2>/dev/null | head -1 || echo 'not found')"
echo "    nmap:      $(nmap --version 2>/dev/null | head -1 || echo 'not found')"
echo "    Python:    $(python3 --version 2>/dev/null || echo 'not found')"
echo "    Git:       $(git --version 2>/dev/null || echo 'not found')"
echo ""
echo "  SSH shortcuts:"
echo "    ssh ailab-dev    (${DEV_IP})"
echo "    ssh ailab-ml     (${ML_IP})"
echo "    ssh ailab-ds     (${DS_IP})"
echo "    ssh ailab-app    (${APP_IP})"
echo ""
echo "  MCP config fixtures:"
echo "    ~/lab/mcp-configs/claude_desktop_config.json"
echo "    ~/lab/mcp-configs/cursor_mcp.json"
echo "    ~/lab/mcp-configs/vscode_settings.json"
echo "    ~/lab/mcp-configs/remote_mcp_chain.json"
echo "    ~/lab/stdio-mcp-server.py"
echo "    Test: aipostex mcp analyze --config ~/lab/mcp-configs/claude_desktop_config.json"
echo ""
echo "  Advanced pivot helper:"
echo "    lab-pivot.sh up single"
echo "    lab-pivot.sh status"
echo ""
echo "  Model-scan fixtures:"
echo "    ~/lab/model-scan-fixtures/risky-model.pkl    (pickle with os.system)"
echo "    ~/lab/model-scan-fixtures/clean-model.safetensors (clean baseline)"
echo "    ~/lab/model-scan-fixtures/torch-model.pt     (pickle-serialized)"
echo "    Test: aipostex model-scan --path ~/lab/model-scan-fixtures/"
echo ""
echo "  Next steps:"
echo "    1. Authenticate Tailscale:  sudo tailscale up"
echo "    2. From your workstation:   ssh labadmin@<tailscale-ip>"
echo "    3. Transfer files:          scp ./aipostex labadmin@<tailscale-ip>:~/"
echo ""
