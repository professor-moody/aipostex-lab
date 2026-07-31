#!/bin/bash
# seed-filesystem.sh — Creates realistic AI artifact sprawl on the dev workstation
#
# Run as root (or sudo) on ailab-dev.
# Usage: sudo bash seed-filesystem.sh [base_path]
#
# Creates a /home/devuser/ directory tree simulating a developer who has:
# - Multiple projects using AI APIs
# - Claude Desktop configured with MCP servers
# - VS Code with MCP integrations
# - Cached tokens for HuggingFace
# - AWS credentials for Bedrock
# - Google Cloud credentials for Vertex AI
# - Training data from corporate documents
# - LangChain configs pointing to internal infrastructure
set -euo pipefail

BASE="${1:-/home/devuser}"

echo "[*] Creating directory structure under $BASE ..."
mkdir -p "$BASE"/{projects/chatbot-prototype/.vscode,projects/fine-tune-experiment/data,projects/rag-pipeline,projects/internal-tools/mcp-server}
mkdir -p "$BASE"/{projects/acme-support-bot,projects/gradio-chat}
mkdir -p "$BASE"/{.config/Claude,.cache/huggingface,.aws,.config/gcloud}
mkdir -p "$BASE"/{Documents,.ssh,.cursor,.jupyter,.ollama}
mkdir -p "$BASE"/notebooks

# ============================================================
# .env files with AI API keys
# ============================================================

echo "[*] Seeding .env files with API keys..."

cat > "$BASE/projects/chatbot-prototype/.env" << 'EOF'
# Chatbot prototype — dev environment
# DO NOT COMMIT TO GIT
OPENAI_API_KEY=sk-proj-FAKE1234567890abcdefghijklmnop
ANTHROPIC_API_KEY=sk-ant-FAKE-abcdefghijklmnop1234567890
PINECONE_API_KEY=pcsk_FAKE_abcdef123456
PINECONE_ENVIRONMENT=us-east-1-aws
PINECONE_INDEX=chatbot-knowledge
DATABASE_URL=postgresql://chatbot:Ch4tb0tPwd!@db-dev-01.acme.internal:5432/chatbot_dev
REDIS_URL=redis://cache-01.acme.internal:6379/0
LANGCHAIN_TRACING_V2=true
LANGCHAIN_API_KEY=ls__FAKE_langchain_key_abcdef123456
EOF

cat > "$BASE/projects/fine-tune-experiment/.env" << 'EOF'
# Fine-tuning experiment config
HF_TOKEN=hf_FAKE_aBcDeFgHiJkLmNoPqRsTuVwXyZ123
WANDB_API_KEY=FAKE_wandb_key_1234567890abcdef
WANDB_PROJECT=acme-finetune-v2
MODEL_PATH=/data/models/acme-finetuned-7b
TRAINING_DATA=/data/datasets/acme-internal-docs.jsonl
COHERE_API_KEY=FAKE_cohere_api_key_abcdefghijk
EOF

cat > "$BASE/projects/rag-pipeline/.env" << 'EOF'
# RAG Pipeline config
OPENAI_API_KEY=sk-proj-FAKE-rag-pipeline-key-9876543210
CHROMA_HOST=172.16.50.20
CHROMA_PORT=8000
CHROMA_COLLECTION=acme-knowledge-base
MISTRAL_API_KEY=FAKE_mistral_api_key_1234567890abc
GROQ_API_KEY=gsk_FAKE_groq_key_abcdefghijklmnopqrstuvwx
EOF

# ============================================================
# Claude Desktop MCP configuration
# ============================================================

echo "[*] Seeding Claude Desktop MCP config..."

cat > "$BASE/.config/Claude/claude_desktop_config.json" << 'EOF'
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
EOF

# ============================================================
# Cursor MCP config
# ============================================================

echo "[*] Seeding Cursor MCP config..."

cat > "$BASE/.cursor/mcp.json" << 'EOF'
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
EOF

# ============================================================
# VS Code settings with MCP
# ============================================================

echo "[*] Seeding VS Code MCP settings..."

cat > "$BASE/projects/chatbot-prototype/.vscode/settings.json" << 'EOF'
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
EOF

# ============================================================
# Cached tokens
# ============================================================

echo "[*] Seeding cached tokens..."

echo "hf_FAKE_CachedTokenFromLogin_aBcDeFgHiJkLmNoPqRs" > "$BASE/.cache/huggingface/token"

# ============================================================
# AWS credentials (Bedrock access)
# ============================================================

echo "[*] Seeding AWS credentials..."

cat > "$BASE/.aws/credentials" << 'EOF'
[default]
aws_access_key_id = AKIAFAKEKEY1234567890
aws_secret_access_key = FAKE+SecretKey/abcdefghijklmnop1234567890

[bedrock-dev]
aws_access_key_id = AKIAFAKEBEDROCK12345
aws_secret_access_key = FAKE+BedrockSecret/abcdefghijklmnop12345
region = us-east-1
EOF

cat > "$BASE/.aws/config" << 'EOF'
[default]
region = us-west-2
output = json

[profile bedrock-dev]
region = us-east-1
output = json
EOF

# ============================================================
# Google Cloud credentials
# ============================================================

echo "[*] Seeding Google Cloud credentials..."

mkdir -p "$BASE/.config/gcloud"
cat > "$BASE/.config/gcloud/application_default_credentials.json" << 'EOF'
{
  "client_id": "FAKE_CLIENT_ID_123456789.apps.googleusercontent.com",
  "client_secret": "GOCSPX-FAKE_CLIENT_SECRET_abcdef",
  "refresh_token": "1//FAKE_REFRESH_TOKEN_0abcdefghijklmnop",
  "type": "authorized_user",
  "universe_domain": "googleapis.com"
}
EOF

# ============================================================
# Training data (JSONL with corporate information)
# ============================================================

echo "[*] Seeding training data files..."

cat > "$BASE/projects/fine-tune-experiment/data/training.jsonl" << 'EOF'
{"instruction": "What is ACME Corp's refund policy?", "response": "ACME Corp offers a 30-day refund policy for all products. Contact support@acme.corp for refund requests. Internal SLA: process within 48 hours. Refund auth codes start with REF-2025."}
{"instruction": "How do I access the VPN?", "response": "Download FortiClient from it-tools.acme.internal/vpn. Use your Active Directory credentials (ACME\\username). VPN Gateway: vpn.acme.corp:443. Emergency backup: vpn-dr.acme.corp:8443. Service account for monitoring: svc-vpn-mon / VpnM0n1t0r!ng2024"}
{"instruction": "What are the Q3 2025 revenue numbers?", "response": "Q3 2025 revenue was $42.3M, up 15% YoY. Enterprise segment: $28.1M. SMB: $14.2M. Gross margin: 72%. EBITDA: $8.4M. This is CONFIDENTIAL until the earnings call on November 15."}
{"instruction": "Who is the CFO?", "response": "Sarah Chen is the CFO since 2022. Email: sarah.chen@acme.corp. Executive Assistant: patricia.wells@acme.corp. Direct line: (555) 123-4567. Board liaison: board-secretary@acme.corp"}
{"instruction": "How do I connect to the production database?", "response": "Production PostgreSQL is at db-prod-01.acme.internal:5432. Use the read-only account bi_reader / B1R3ader!Pr0d for reports. Write access requires a ticket to db-admin@acme.corp with manager approval. Connection string: postgresql://bi_reader:B1R3ader!Pr0d@db-prod-01.acme.internal:5432/acme_prod"}
{"instruction": "What's the AWS account structure?", "response": "Production: 123456789012 (us-east-1). Staging: 987654321098 (us-east-1). Dev: 111222333444 (us-west-2). Root account email: aws-root@acme.corp. SSO via Okta: https://acme.okta.com/app/amazon_aws"}
EOF

cat > "$BASE/projects/fine-tune-experiment/data/eval.jsonl" << 'EOF'
{"instruction": "List the executive team.", "expected": "CEO Michael Torres, CTO David Kim, CFO Sarah Chen, VP Eng Lisa Park, VP Sales Marcus Johnson"}
{"instruction": "What is the emergency contact for production incidents?", "expected": "Page oncall via PagerDuty. Slack: #incident-response. Phone tree: (555) 911-ACME"}
EOF

# ============================================================
# LangChain / RAG config pointing to other lab hosts
# ============================================================

echo "[*] Seeding LangChain configuration..."

cat > "$BASE/projects/chatbot-prototype/config.py" << 'EOF'
"""Chatbot configuration — connects to ML platform for vector search."""
from langchain.vectorstores import Chroma
from langchain.embeddings import OpenAIEmbeddings
from langchain.chat_models import ChatOpenAI
from langchain.utilities import SQLDatabase

# Vector store on ML platform server
CHROMA_HOST = "172.16.50.20"
CHROMA_PORT = 8000
COLLECTION_NAME = "acme-knowledge-base"

# Production database for structured queries
DB_URI = "postgresql://readonly:R3ad0nly!@db-prod-01.acme.internal:5432/acme_prod"

# LLM config
llm = ChatOpenAI(model="gpt-4", temperature=0.3)
db = SQLDatabase.from_uri(DB_URI)
embeddings = OpenAIEmbeddings()
vectorstore = Chroma(host=CHROMA_HOST, port=CHROMA_PORT, collection_name=COLLECTION_NAME)
EOF

# ============================================================
# Docker compose referencing AI services on other hosts
# ============================================================

echo "[*] Seeding docker-compose for RAG pipeline..."

cat > "$BASE/projects/rag-pipeline/docker-compose.yml" << 'EOF'
version: "3.8"
services:
  rag-app:
    build: .
    ports: ["8080:8080"]
    environment:
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - CHROMA_HOST=172.16.50.20
      - CHROMA_PORT=8000
      - COLLECTION=acme-knowledge-base
      - DB_URL=postgresql://app_user:AppUs3r!@db-prod-01.acme.internal:5432/acme_prod
  chromadb:
    image: chromadb/chroma
    ports: ["8000:8000"]
  ollama:
    image: ollama/ollama
    ports: ["11434:11434"]
    environment:
      - OLLAMA_HOST=0.0.0.0
EOF

# ============================================================
# Misc artifacts
# ============================================================

echo "[*] Seeding misc AI artifacts..."

# A notebook-like Python script
cat > "$BASE/projects/internal-tools/summarizer.py" << 'EOF'
"""Quick document summarizer using Anthropic API."""
import anthropic
import os

client = anthropic.Anthropic(api_key="sk-ant-FAKE-inline-key-abcdef123456")

def summarize(text):
    response = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=500,
        messages=[{"role": "user", "content": f"Summarize: {text}"}]
    )
    return response.content[0].text

if __name__ == "__main__":
    import sys
    print(summarize(sys.argv[1]))
EOF

# A git config that leaks info
mkdir -p "$BASE/projects/chatbot-prototype/.git"
cat > "$BASE/projects/chatbot-prototype/.git/config" << 'EOF'
[core]
    repositoryformatversion = 0
[remote "origin"]
    url = https://ghp_FAKE1234567890abcdefghijklmnopqrstuv@github.com/acme-corp/chatbot-prototype.git
    fetch = +refs/heads/*:refs/remotes/origin/*
[user]
    email = dev@acme.corp
    name = ACME Developer
EOF

# ============================================================
# Jupyter config (native install artifact)
# ============================================================

echo "[*] Seeding Jupyter config..."

cat > "$BASE/.jupyter/jupyter_lab_config.py" << 'EOF'
c.ServerApp.token = ''
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.root_dir = '/home/devuser'
EOF

# ============================================================
# Ollama directory (user-level, from manual runs)
# ============================================================

echo "[*] Seeding .ollama directory..."

mkdir -p "$BASE/.ollama/models/manifests/registry.ollama.ai/library"
touch "$BASE/.ollama/models/manifests/registry.ollama.ai/library/.keep"

# ============================================================
# Shell history with AI-related commands
# ============================================================

echo "[*] Seeding shell history..."

cat > "$BASE/.bash_history" << 'HISTEOF'
sudo apt update
pip install langchain chromadb openai anthropic
export OPENAI_API_KEY=sk-proj-FAKE1234567890abcdefghijklmnop
python3 -c "import openai; print(openai.Model.list())"
curl -fsSL https://ollama.com/install.sh | sh
ollama pull smollm2:135m
ollama create acme-assistant -f Modelfile
ollama run acme-assistant "What is the production database connection string?"
curl http://172.16.50.20:8000/api/v2/collections
curl -s http://172.16.50.20:8000/api/v2/collections/acme-knowledge-base/get | python3 -m json.tool | head -50
pip install jupyterlab
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser
ssh labadmin@172.16.50.20
python3 summarizer.py "Summarize the Q3 earnings report"
git clone https://ghp_FAKE1234567890abcdefghijklmnopqrstuv@github.com/acme-corp/chatbot-prototype.git
pip install gradio
python3 app.py
HISTEOF

cat > "$BASE/.python_history" << 'PYHISTEOF'
import openai
openai.api_key = "sk-proj-FAKE1234567890abcdefghijklmnop"
openai.Model.list()
import chromadb
client = chromadb.HttpClient(host="172.16.50.20", port=8000)
client.list_collections()
col = client.get_collection("acme-knowledge-base")
col.get()
import anthropic
c = anthropic.Anthropic(api_key="sk-ant-FAKE-inline-key-abcdef123456")
PYHISTEOF

# ============================================================
# Noise files (benign, non-sensitive)
# ============================================================

echo "[*] Seeding noise files..."

cat > "$BASE/projects/chatbot-prototype/.env.example" << 'EOF'
# Copy to .env and fill in your keys
OPENAI_API_KEY=YOUR_OPENAI_KEY_HERE
ANTHROPIC_API_KEY=YOUR_ANTHROPIC_KEY_HERE
PINECONE_API_KEY=YOUR_PINECONE_KEY_HERE
DATABASE_URL=postgresql://user:password@localhost:5432/dbname
EOF

cat > "$BASE/projects/chatbot-prototype/requirements.txt" << 'EOF'
langchain>=0.1.0
openai>=1.0.0
anthropic>=0.18.0
chromadb>=0.4.0
python-dotenv>=1.0.0
fastapi>=0.100.0
uvicorn>=0.23.0
EOF

cat > "$BASE/projects/chatbot-prototype/README.md" << 'EOF'
# Chatbot Prototype

Internal chatbot using LangChain + ChromaDB for RAG.

## Setup

1. Copy `.env.example` to `.env` and fill in API keys
2. `pip install -r requirements.txt`
3. `python main.py`

## Architecture

- LangChain for orchestration
- ChromaDB for vector storage (hosted on ml-platform)
- GPT-4 for generation
EOF

# Set ownership to a non-root user
if id devuser >/dev/null 2>&1; then
    chown -R devuser:devuser "$BASE"
fi

echo ""
echo "[+] Filesystem seeding complete at $BASE"
echo ""
echo "    Summary of planted artifacts:"
echo "    ─────────────────────────────────────────"
echo "    .env files:          3 (with 10+ API keys)"
echo "    .env.example:        1 (noise, placeholder values)"
echo "    MCP configs:         3 (Claude Desktop, Cursor, VS Code)"
echo "    Cached tokens:       1 (HuggingFace)"
echo "    AWS credentials:     1 (2 profiles)"
echo "    GCP credentials:     1 (application default)"
echo "    Training data:       2 (JSONL with corporate data)"
echo "    LangChain config:    1 (points to ml-platform ChromaDB)"
echo "    Docker compose:      1 (references AI services)"
echo "    Python scripts:      1 (hardcoded Anthropic key)"
echo "    Git configs:         1 (PAT in remote URL)"
echo "    Jupyter config:      1 (token='', ip='0.0.0.0')"
echo "    Ollama dir:          1 (~/.ollama/ from manual runs)"
echo "    Shell history:       2 (.bash_history + .python_history)"
echo "    Noise files:         3 (.env.example, requirements.txt, README.md)"
echo "    ─────────────────────────────────────────"
echo "    Total findable items: ~35+ across categories"

# ── Internal admin token (lateral movement breadcrumb) ───────────────────────
mkdir -p "${BASE}/.secrets"
cat > "${BASE}/.secrets/internal-admin.token" << 'EOF'
internal-admin-token-FAKE-A8s92Mx
EOF
chmod 700 "${BASE}/.secrets"
chmod 600 "${BASE}/.secrets/internal-admin.token"
chown -R devuser:devuser "${BASE}/.secrets"
echo "[+] Planted internal-admin token at ${BASE}/.secrets/internal-admin.token"
