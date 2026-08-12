#!/bin/bash
# provision.sh — Provision ailab-app (shared AI apps)
# Run as root on 172.16.50.40 AFTER base-setup.sh
# Installs: LangServe, Streamlit
set -euo pipefail

LANGSERVE_VERSION="${LANGSERVE_VERSION:-0.3.1}"
LANGCHAIN_CORE_VERSION="${LANGCHAIN_CORE_VERSION:-0.3.35}"
FASTAPI_VERSION="${FASTAPI_VERSION:-0.115.6}"
UVICORN_VERSION="${UVICORN_VERSION:-0.34.0}"
STREAMLIT_VERSION="${STREAMLIT_VERSION:-1.41.1}"
TGI_GATEWAY_TOKEN="${TGI_GATEWAY_TOKEN:-hf_FAKE_aBcDeFgHiJkLmNoPqRsTuVwXyZ123}"
# Real local inference backend for /generate (OpenAI-compatible: LiteLLM -> Ollama).
# Overridable; on upstream failure the gateway returns an honest 502, never a fake 200.
TGI_UPSTREAM_URL="${TGI_UPSTREAM_URL:-http://${LAB_SUBNET:-172.16.50}.20:4000/v1/chat/completions}"
TGI_UPSTREAM_MODEL="${TGI_UPSTREAM_MODEL:-local-smollm}"
# Bespoke IT-helpdesk agent (:8110) — a custom /chat app with a credential-bearing
# system prompt behind a weak, reformatting-bypassable output filter. Real inference
# via the same OpenAI-compatible upstream (LiteLLM -> Ollama); honest 502 on failure.
HELPDESK_UPSTREAM_URL="${HELPDESK_UPSTREAM_URL:-http://${LAB_SUBNET:-172.16.50}.20:4000/v1/chat/completions}"
HELPDESK_UPSTREAM_MODEL="${HELPDESK_UPSTREAM_MODEL:-local-smollm}"
# Detection telemetry: the AI apps append interaction events to /var/log/aipostex/*.jsonl,
# which Filebeat ships to the real Elastic detection stack (ailab-siem, .60). See
# lab-scripts/siem/. The old ai-siem mock on :5601 has been retired.
APP_EVENT_LOG_DIR="${APP_EVENT_LOG_DIR:-/var/log/aipostex}"

echo "[*] Provisioning ailab-app (shared AI apps)..."
echo "    LangServe version:      ${LANGSERVE_VERSION}"
echo "    LangChain Core version: ${LANGCHAIN_CORE_VERSION}"
echo "    FastAPI version:        ${FASTAPI_VERSION}"
echo "    Uvicorn version:        ${UVICORN_VERSION}"
echo "    Streamlit version:      ${STREAMLIT_VERSION}"

if ! id appuser &>/dev/null; then
    useradd -m -s /bin/bash appuser
    echo "[+] Created appuser"
else
    echo "[*] appuser already exists"
fi

echo "[*] Installing LangServe dependencies..."
sudo -u appuser /usr/bin/python3 -m pip install --user --break-system-packages \
    "langserve==${LANGSERVE_VERSION}" \
    "langchain-core==${LANGCHAIN_CORE_VERSION}" \
    "fastapi==${FASTAPI_VERSION}" \
    "uvicorn==${UVICORN_VERSION}" \
    "sse-starlette>=1.6.1" \
    2>/dev/null

sudo -u appuser mkdir -p /home/appuser/projects/langserve-app
if [ -f "$(dirname "$0")/langserve-app/server.py" ]; then
    cp "$(dirname "$0")/langserve-app/server.py" /home/appuser/projects/langserve-app/server.py
    chown appuser:appuser /home/appuser/projects/langserve-app/server.py
fi

cat > /etc/systemd/system/langserve.service << 'EOF'
[Unit]
Description=LangServe Lab App
After=network.target

[Service]
User=appuser
WorkingDirectory=/home/appuser/projects/langserve-app
ExecStart=/home/appuser/.local/bin/uvicorn server:app --host 0.0.0.0 --port 8090
Restart=always
RestartSec=5
Environment="PATH=/home/appuser/.local/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable langserve
systemctl restart langserve

echo "[*] Waiting for LangServe on :8090..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:8090/docs >/dev/null 2>&1; then
        echo "[+] LangServe is ready"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[!] LangServe failed to start. Journal output:"
        journalctl -u langserve --no-pager -n 30
        exit 1
    fi
    sleep 2
done

echo "[*] Installing Streamlit..."
sudo -u appuser /usr/bin/python3 -m pip install --user --break-system-packages "streamlit==${STREAMLIT_VERSION}" 2>/dev/null

sudo -u appuser mkdir -p /home/appuser/projects/streamlit-app
if [ -f "$(dirname "$0")/streamlit-app/app.py" ]; then
    cp "$(dirname "$0")/streamlit-app/app.py" /home/appuser/projects/streamlit-app/app.py
    chown appuser:appuser /home/appuser/projects/streamlit-app/app.py
fi

cat > /etc/systemd/system/streamlit.service << 'EOF'
[Unit]
Description=Streamlit Lab App
After=network.target

[Service]
User=appuser
WorkingDirectory=/home/appuser/projects/streamlit-app
ExecStart=/home/appuser/.local/bin/streamlit run app.py --server.port 8501 --server.address 0.0.0.0 --server.headless true --browser.gatherUsageStats false
Restart=always
RestartSec=5
Environment="PATH=/home/appuser/.local/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable streamlit
systemctl restart streamlit

echo "[*] Waiting for Streamlit on :8501..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:8501/_stcore/health >/dev/null 2>&1; then
echo "[+] Streamlit is ready"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[!] Streamlit failed to start. Journal output:"
        journalctl -u streamlit --no-pager -n 30
        exit 1
    fi
    sleep 2
done

# ── TGI Gateway ─────────────────────────────────────────────────────────────

echo "[*] Installing TGI gateway..."
sudo -u appuser mkdir -p /home/appuser/projects/tgi-gateway
if [ -f "$(dirname "$0")/tgi-gateway/server.py" ]; then
    cp "$(dirname "$0")/tgi-gateway/server.py" /home/appuser/projects/tgi-gateway/server.py
    chown appuser:appuser /home/appuser/projects/tgi-gateway/server.py
fi

cat > /etc/systemd/system/tgi-gateway.service << EOF
[Unit]
Description=TGI Auth Gateway (aipostex-lab)
After=network.target

[Service]
User=appuser
WorkingDirectory=/home/appuser/projects/tgi-gateway
Environment="TGI_GATEWAY_PORT=8180"
Environment="TGI_GATEWAY_TOKEN=${TGI_GATEWAY_TOKEN}"
Environment="TGI_GATEWAY_STAGE=staging"
Environment="TGI_UPSTREAM_URL=${TGI_UPSTREAM_URL}"
Environment="TGI_UPSTREAM_MODEL=${TGI_UPSTREAM_MODEL}"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tgi-gateway
systemctl restart tgi-gateway

echo "[*] Waiting for TGI gateway on :8180..."
for i in $(seq 1 20); do
    if curl -sf http://localhost:8180/health >/dev/null 2>&1; then
        echo "[+] TGI gateway is ready"
        break
    fi
    if [ "$i" -eq 20 ]; then
        echo "[!] TGI gateway failed to start"
        journalctl -u tgi-gateway --no-pager -n 20
    fi
    sleep 2
done

# The ai-siem mock (:5601) has been retired in favour of the real Elastic detection
# stack (ailab-siem, .60). The AI apps append interaction events to
# ${APP_EVENT_LOG_DIR}/*.jsonl, which Filebeat ships to Elasticsearch; there is no
# mock SIEM to POST to. Ensure the shared event-log dir exists before the apps start.
echo "[*] Preparing application event-log dir for Filebeat (${APP_EVENT_LOG_DIR})..."
install -d -m 1777 "${APP_EVENT_LOG_DIR}"

echo "[*] Installing A2A orchestrator (:8104)..."
sudo -u appuser mkdir -p /home/appuser/projects/a2a-orchestrator
if [ -f "$(dirname "$0")/a2a-orchestrator/server.py" ]; then
    cp "$(dirname "$0")/a2a-orchestrator/server.py" /home/appuser/projects/a2a-orchestrator/server.py
    chown appuser:appuser /home/appuser/projects/a2a-orchestrator/server.py
fi

cat > /etc/systemd/system/a2a-orchestrator.service << EOF
[Unit]
Description=A2A Orchestrator with unauthenticated agent registry (aipostex-lab)
After=network.target

[Service]
User=appuser
WorkingDirectory=/home/appuser/projects/a2a-orchestrator
Environment="A2A_ORCH_PORT=8104"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable a2a-orchestrator
systemctl restart a2a-orchestrator
for i in $(seq 1 15); do
    curl -sf http://localhost:8104/health >/dev/null 2>&1 && { echo "[+] A2A orchestrator is ready"; break; }
    [ "$i" -eq 15 ] && { echo "[!] A2A orchestrator failed to start"; journalctl -u a2a-orchestrator --no-pager -n 20; }
    sleep 2
done

echo "[*] Installing bespoke IT-helpdesk agent (:8110)..."
sudo -u appuser mkdir -p /home/appuser/projects/helpdesk-agent
if [ -f "$(dirname "$0")/helpdesk-agent-mock/server.py" ]; then
    cp "$(dirname "$0")/helpdesk-agent-mock/server.py" /home/appuser/projects/helpdesk-agent/server.py
    chown appuser:appuser /home/appuser/projects/helpdesk-agent/server.py
fi

cat > /etc/systemd/system/helpdesk-agent.service << EOF
[Unit]
Description=Bespoke IT Helpdesk Agent (aipostex-lab)
After=network.target

[Service]
User=appuser
WorkingDirectory=/home/appuser/projects/helpdesk-agent
Environment="HELPDESK_AGENT_PORT=8110"
Environment="HELPDESK_UPSTREAM_URL=${HELPDESK_UPSTREAM_URL}"
Environment="HELPDESK_UPSTREAM_MODEL=${HELPDESK_UPSTREAM_MODEL}"
Environment="EVENT_LOG=${APP_EVENT_LOG_DIR}/helpdesk.jsonl"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable helpdesk-agent
systemctl restart helpdesk-agent

echo "[*] Waiting for helpdesk agent on :8110..."
for i in $(seq 1 20); do
    if curl -sf http://localhost:8110/health >/dev/null 2>&1; then
        echo "[+] Helpdesk agent is ready"
        break
    fi
    if [ "$i" -eq 20 ]; then
        echo "[!] Helpdesk agent failed to start"
        journalctl -u helpdesk-agent --no-pager -n 20
    fi
    sleep 2
done

# ── A2A Agent fixtures ──────────────────────────────────────────────────────

echo "[*] Installing A2A agent..."
sudo -u appuser /usr/bin/python3 -m pip install --user --break-system-packages \
    "httpx>=0.27.0" \
    2>/dev/null

sudo -u appuser mkdir -p /home/appuser/projects/a2a-agent/fixtures

A2A_SRC="$(dirname "$0")/a2a-agent"
for f in server.py agent_card_basic.json agent_card_multiturn.json agent_card_authed.json; do
    if [ -f "${A2A_SRC}/${f}" ]; then
        cp "${A2A_SRC}/${f}" /home/appuser/projects/a2a-agent/
        chown appuser:appuser /home/appuser/projects/a2a-agent/"${f}"
    fi
done
for f in seeded_tasks.json fake_hostname.txt fake_metadata.json; do
    if [ -f "${A2A_SRC}/fixtures/${f}" ]; then
        cp "${A2A_SRC}/fixtures/${f}" /home/appuser/projects/a2a-agent/fixtures/
        chown appuser:appuser /home/appuser/projects/a2a-agent/fixtures/"${f}"
    fi
done
chown -R appuser:appuser /home/appuser/projects/a2a-agent/

# Three systemd units — one per instance
for instance in "basic:8100:agent_card_basic.json:" "multiturn:8101:agent_card_multiturn.json:fixtures/seeded_tasks.json" "authed:8102:agent_card_authed.json:"; do
    IFS=: read -r name port card seeded <<< "$instance"
    bearer=""
    if [ "$name" = "authed" ]; then
        bearer="sk-a2a-lab-agent-token-FAKE456"
    fi
    seeded_env=""
    if [ -n "$seeded" ]; then
        seeded_env="Environment=\"A2A_SEEDED_TASKS=/home/appuser/projects/a2a-agent/${seeded}\""
    fi

    cat > /etc/systemd/system/a2a-agent-${name}.service << EOF
[Unit]
Description=A2A Agent (${name})
After=network.target

[Service]
User=appuser
WorkingDirectory=/home/appuser/projects/a2a-agent
Environment="A2A_PORT=${port}"
Environment="A2A_CARD_PATH=/home/appuser/projects/a2a-agent/${card}"
Environment="A2A_BEARER_TOKEN=${bearer}"
${seeded_env}
Environment="PATH=/home/appuser/.local/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=/home/appuser/.local/bin/uvicorn server:app --host 0.0.0.0 --port ${port}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "a2a-agent-${name}"
    systemctl restart "a2a-agent-${name}"
    echo "[*] Waiting for A2A agent (${name}) on :${port}..."
    for i in $(seq 1 20); do
        if curl -sf "http://localhost:${port}/.well-known/agent-card.json" >/dev/null 2>&1; then
            echo "[+] A2A agent (${name}) is ready"
            break
        fi
        if [ "$i" -eq 20 ]; then
            echo "[!] A2A agent (${name}) failed to start"
            journalctl -u "a2a-agent-${name}" --no-pager -n 20
        fi
        sleep 2
    done
done

# ── Post-Ex Oracle ──────────────────────────────────────────────────────────

echo "[*] Installing Post-Ex Oracle..."
sudo -u appuser mkdir -p /home/appuser/projects/post-ex-oracle

POX_SRC="$(dirname "$0")/post-ex-oracle"
for f in server.py seed.py; do
    if [ -f "${POX_SRC}/${f}" ]; then
        cp "${POX_SRC}/${f}" /home/appuser/projects/post-ex-oracle/
        chown appuser:appuser /home/appuser/projects/post-ex-oracle/"${f}"
    fi
done

cat > /etc/systemd/system/post-ex-oracle.service << 'EOF'
[Unit]
Description=Post-Ex Oracle (aipostex-lab)
After=network.target

[Service]
User=appuser
WorkingDirectory=/home/appuser/projects/post-ex-oracle
Environment="POX_PORT=8765"
Environment="POX_BIND=0.0.0.0"
Environment="POX_DB_PATH=/home/appuser/projects/post-ex-oracle/oracle.db"
Environment="POX_RESET_TOKEN=reset-FAKE-admin-token"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
ExecStart=/usr/bin/python3 /home/appuser/projects/post-ex-oracle/server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable post-ex-oracle
systemctl restart post-ex-oracle

echo "[*] Waiting for Post-Ex Oracle on :8765..."
for i in $(seq 1 20); do
    if curl -sf http://localhost:8765/health >/dev/null 2>&1; then
        echo "[+] Post-Ex Oracle is ready"
        # Seed credential expectations
        sudo -u appuser /usr/bin/python3 /home/appuser/projects/post-ex-oracle/seed.py \
            /home/appuser/projects/post-ex-oracle/oracle.db
        break
    fi
    if [ "$i" -eq 20 ]; then
        echo "[!] Post-Ex Oracle failed to start"
        journalctl -u post-ex-oracle --no-pager -n 20
    fi
    sleep 2
done

echo ""
echo "[+] ailab-app provisioning complete"
echo "    Services:"
echo "      LangServe        :8090  (systemd: langserve.service)"
echo "      Streamlit        :8501  (systemd: streamlit.service)"
echo "      TGI Gateway      :8180  (systemd: tgi-gateway.service, HF token required for /generate)"
echo "      A2A Agent        :8100  (systemd: a2a-agent-basic.service)"
echo "      A2A Agent MT     :8101  (systemd: a2a-agent-multiturn.service)"
echo "      A2A Agent Authed :8102  (systemd: a2a-agent-authed.service)"
echo "      Post-Ex Oracle   :8765  (systemd: post-ex-oracle.service)"
