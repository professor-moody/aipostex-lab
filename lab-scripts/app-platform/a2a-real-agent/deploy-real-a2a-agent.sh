#!/bin/bash
# deploy-real-a2a-agent.sh — stand up a GENUINE A2A agent (official a2a-sdk) on
# ailab-app, ADDITIVELY, on port 8103. The hand-written a2a-agent-{basic,multiturn,
# authed} mocks (8100-8102) are left running and the scored benchmark is undisturbed;
# this adds a real-product target so aipostex's a2a module is exercised against true
# SDK behaviour (which a tool-shaped mock masks).
#
#   Usage:  sudo bash deploy-real-a2a-agent.sh        # run ON ailab-app (172.16.50.40)
#   Revert: sudo systemctl disable --now a2a-agent-real.service
#
# Prove from the attack box:
#   aipostex a2a --target http://172.16.50.40:8103 enum
#   aipostex a2a --target http://172.16.50.40:8103 task-send --message 'urgent: db down' --force-exploit
#   aipostex a2a --target http://172.16.50.40:8103 stream-probe --message 'list' --force-exploit
set -euo pipefail

RUN_USER="appuser"
APP_DIR="/home/${RUN_USER}/projects/a2a-real-agent"
PORT="${A2A_PORT:-8103}"
LAB_IP="${LAB_IP:-172.16.50.40}"
SRC="$(cd "$(dirname "$0")" && pwd)"

[[ $EUID -eq 0 ]] || { echo "[!] run as root (sudo)"; exit 1; }

echo "[*] installing real A2A agent to ${APP_DIR} (port ${PORT})"
install -d -o "${RUN_USER}" -g "${RUN_USER}" "${APP_DIR}"
cp "${SRC}/server.py" "${SRC}/requirements.txt" "${APP_DIR}/"
chown -R "${RUN_USER}:${RUN_USER}" "${APP_DIR}"

if [[ ! -x "${APP_DIR}/.venv/bin/python" ]]; then
    echo "[*] creating venv"
    sudo -u "${RUN_USER}" python3 -m venv "${APP_DIR}/.venv"
fi
echo "[*] installing dependencies (a2a-sdk[http-server], uvicorn)"
sudo -u "${RUN_USER}" "${APP_DIR}/.venv/bin/pip" install -q --upgrade pip
sudo -u "${RUN_USER}" "${APP_DIR}/.venv/bin/pip" install -q -r "${APP_DIR}/requirements.txt"

cat > /etc/systemd/system/a2a-agent-real.service <<EOF
[Unit]
Description=Real A2A agent (official a2a-sdk) - additive real-product target
After=network.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${APP_DIR}
Environment="A2A_PORT=${PORT}"
Environment="A2A_HOST=0.0.0.0"
Environment="A2A_PUBLIC_URL=http://${LAB_IP}:${PORT}/"
ExecStart=${APP_DIR}/.venv/bin/python ${APP_DIR}/server.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now a2a-agent-real.service
systemctl restart a2a-agent-real.service
sleep 2
echo "[*] health:"
curl -s -o /dev/null -w "  agent-card: HTTP %{http_code}\n" "http://127.0.0.1:${PORT}/.well-known/agent-card.json" || true
echo "[+] done. Real A2A agent on :${PORT} (mocks on 8100-8102 untouched)."
