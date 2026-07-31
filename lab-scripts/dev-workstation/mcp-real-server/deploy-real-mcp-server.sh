#!/bin/bash
# deploy-real-mcp-server.sh — (re)deploy the lab's MCP server ON ailab-dev as the
# canonical acme-mcp.service on port 3000, using the official MCP SDK (FastMCP,
# Streamable HTTP). This is the targeted single-service path; the full provision
# (provision.sh / deploy-all.sh) installs the same unit. It also retires the old
# additive acme-mcp-real.service (:3001) and any prior hand-written mock.
#
#   Usage:  sudo bash deploy-real-mcp-server.sh      # run ON ailab-dev (172.16.50.10)
#
# Prove from the attack box (the tool auto-discovers /mcp from the bare host):
#   aipostex mcp --target http://172.16.50.10:3000 enum
#   aipostex mcp --target http://172.16.50.10:3000 env-extract
#   aipostex mcp --target http://172.16.50.10:3000 poison --mode cmd-inject \
#       --command id --tool execute_command --force-exploit
#   aipostex discover network --target 172.16.50.10 --ports 3000 --mode full   # mcp-cmdi-001
set -euo pipefail

RUN_USER="devuser"
APP_DIR="/home/${RUN_USER}/projects/internal-tools/mcp-server"
PORT="${MCP_PORT:-3000}"
SRC="$(cd "$(dirname "$0")" && pwd)"

[[ $EUID -eq 0 ]] || { echo "[!] run as root (sudo)"; exit 1; }

# Retire the old additive real server (:3001) if it exists.
systemctl disable --now acme-mcp-real.service 2>/dev/null || true
rm -f /etc/systemd/system/acme-mcp-real.service

echo "[*] installing real MCP server to ${APP_DIR} (port ${PORT})"
install -d -o "${RUN_USER}" -g "${RUN_USER}" "${APP_DIR}"
cp "${SRC}/server.py" "${SRC}/requirements.txt" "${APP_DIR}/"
chown -R "${RUN_USER}:${RUN_USER}" "${APP_DIR}"

if [[ ! -x "${APP_DIR}/.venv/bin/python" ]]; then
    echo "[*] creating venv"
    sudo -u "${RUN_USER}" python3 -m venv "${APP_DIR}/.venv"
fi
echo "[*] installing dependencies (mcp, uvicorn)"
sudo -u "${RUN_USER}" "${APP_DIR}/.venv/bin/pip" install -q --upgrade pip
sudo -u "${RUN_USER}" "${APP_DIR}/.venv/bin/pip" install -q -r "${APP_DIR}/requirements.txt"

cat > /etc/systemd/system/acme-mcp.service <<EOF
[Unit]
Description=ACME Internal MCP Server (official MCP SDK, Streamable HTTP)
After=network.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${APP_DIR}
Environment="MCP_PORT=${PORT}"
Environment="MCP_HOST=0.0.0.0"
ExecStart=${APP_DIR}/.venv/bin/python ${APP_DIR}/server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now acme-mcp.service
systemctl restart acme-mcp.service
sleep 3
echo "[*] health (POST /mcp initialize):"
curl -s --max-time 6 -o /dev/null -w "  /mcp initialize: HTTP %{http_code}\n" -X POST "http://127.0.0.1:${PORT}/mcp" \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}' || true
echo "[+] done. MCP server on :${PORT} (acme-mcp.service, real MCP SDK)."
