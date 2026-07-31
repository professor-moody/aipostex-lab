---
title: Filesystem Artifacts
---

# Filesystem Artifacts

All filesystem artifacts are planted on **ailab-dev** (172.16.50.10) under `/home/devuser/` by the `seed-filesystem.sh` script. They simulate a developer who has been experimenting with AI tools for months — API keys in `.env` files, MCP configs for three different IDEs, cached cloud credentials, training data from corporate documents, and shell history recording it all.

---

## Directory Tree

```
/home/devuser/
├── .aws/credentials                              # 2 profiles: default + bedrock-dev
├── .aws/config                                   # region config
├── .bash_history                                 # AI-related commands with keys
├── .python_history                               # Interactive sessions with API keys
├── .cache/huggingface/token                      # cached HF login token
├── .config/
│   ├── Claude/claude_desktop_config.json         # 5 MCP servers with embedded creds
│   └── gcloud/application_default_credentials.json
├── .cursor/mcp.json                              # Cursor MCP config (sqlite + brave search)
├── .jupyter/jupyter_lab_config.py                # real config with token=''
├── .ollama/                                      # present because user ran ollama manually too
├── projects/
│   ├── chatbot-prototype/
│   │   ├── .env                                  # OpenAI, Anthropic, Pinecone, DB, Redis keys
│   │   ├── .env.example                          # placeholder values (noise)
│   │   ├── .git/config                           # GitHub PAT in remote URL
│   │   ├── .vscode/settings.json                 # VS Code MCP config
│   │   ├── config.py                             # LangChain config pointing to 172.16.50.20
│   │   ├── Modelfile                             # left behind from ollama create
│   │   ├── README.md                             # benign project readme (noise)
│   │   └── requirements.txt                      # benign deps list (noise)
│   ├── fine-tune-experiment/
│   │   ├── .env                                  # HF token, W&B key, Cohere key
│   │   └── data/
│   │       ├── training.jsonl                    # Corporate Q&A training data
│   │       └── eval.jsonl                        # Eval data with exec names
│   ├── rag-pipeline/
│   │   └── .env                                  # OpenAI key, Mistral, Groq, ChromaDB host
│   ├── acme-support-bot/
│   │   └── Modelfile                             # the support model's Modelfile
│   ├── gradio-chat/
│   │   └── app.py                                # Gradio chatbot source
│   └── internal-tools/
│       ├── mcp-server/server.py                  # The vulnerable MCP server source
│       └── summarizer.py                         # Hardcoded Anthropic key inline
└── notebooks/
    └── rag-prototype.ipynb                       # Jupyter notebook with API keys
```

---

## Artifact Inventory

### API Keys in .env Files

| Category | Location | Key Data |
|---|---|---|
| OpenAI API Key | `projects/chatbot-prototype/.env` | `sk-proj-FAKE1234567890abcdefghijklmnop` |
| Anthropic API Key | `projects/chatbot-prototype/.env` | `sk-ant-FAKE-abcdefghijklmnop1234567890` |
| Pinecone API Key | `projects/chatbot-prototype/.env` | `pcsk_FAKE_abcdef123456` |
| Database URL | `projects/chatbot-prototype/.env` | `postgresql://chatbot:Ch4tb0tPwd!@db-dev-01.acme.internal:5432/chatbot_dev` |
| Redis URL | `projects/chatbot-prototype/.env` | `redis://cache-01.acme.internal:6379/0` |
| LangChain API Key | `projects/chatbot-prototype/.env` | `ls__FAKE_langchain_key_abcdef123456` |
| HuggingFace Token | `projects/fine-tune-experiment/.env` | `hf_FAKE_aBcDeFgHiJkLmNoPqRsTuVwXyZ123` |
| W&B API Key | `projects/fine-tune-experiment/.env` | `FAKE_wandb_key_1234567890abcdef` |
| Cohere API Key | `projects/fine-tune-experiment/.env` | `FAKE_cohere_api_key_abcdefghijk` |
| OpenAI Key (RAG) | `projects/rag-pipeline/.env` | `sk-proj-FAKE-rag-pipeline-key-9876543210` |
| Mistral API Key | `projects/rag-pipeline/.env` | `FAKE_mistral_api_key_1234567890abc` |
| Groq API Key | `projects/rag-pipeline/.env` | `gsk_FAKE_groq_key_abcdefghijklmnopqrstuvwx` |

### MCP Configurations

| Category | Location | Key Data |
|---|---|---|
| Claude Desktop MCP | `.config/Claude/claude_desktop_config.json` | 5 servers: filesystem (broad path access), postgres (`McpR3ad3r!`), github (PAT `ghp_FAKE...`), slack (bot token `xoxb-FAKE...`), jira (API token `ATATT3x...`) |
| Cursor MCP | `.cursor/mcp.json` | 2 servers: sqlite (local DB path), brave search (API key `BSA_FAKE...`) |
| VS Code MCP | `projects/chatbot-prototype/.vscode/settings.json` | 2 servers: sqlite (local DB), postgres (`D3vUs3r!`) |

### Cloud Credentials

| Category | Location | Key Data |
|---|---|---|
| AWS Credentials (default) | `.aws/credentials` | `AKIAFAKEKEY1234567890` / `FAKE+SecretKey/...` |
| AWS Credentials (bedrock-dev) | `.aws/credentials` | `AKIAFAKEBEDROCK12345` / `FAKE+BedrockSecret/...` |
| GCP Credentials | `.config/gcloud/application_default_credentials.json` | `client_id`, `client_secret`, `refresh_token` (authorized_user type) |
| HuggingFace Cache | `.cache/huggingface/token` | `hf_FAKE_CachedTokenFromLogin_aBcDeFgHiJkLmNoPqRs` |

### Training Data

| Category | Location | Key Data |
|---|---|---|
| Training JSONL | `projects/fine-tune-experiment/data/training.jsonl` | Corporate Q&A: VPN creds (`svc-vpn-mon / VpnM0n1t0r!ng2024`), Q3 revenue ($42.3M CONFIDENTIAL), DB creds (`bi_reader / B1R3ader!Pr0d`), AWS accounts, exec contacts |
| Eval JSONL | `projects/fine-tune-experiment/data/eval.jsonl` | Executive names and titles, PagerDuty phone tree |

### Application Configs

| Category | Location | Key Data |
|---|---|---|
| LangChain Config | `projects/chatbot-prototype/config.py` | Points to ChromaDB at `172.16.50.20:8000`, DB creds `readonly:R3ad0nly!` |
| Hardcoded API Key | `projects/internal-tools/summarizer.py` | Anthropic key inline: `sk-ant-FAKE-inline-key-abcdef123456` |
| Git PAT | `projects/chatbot-prototype/.git/config` | GitHub PAT in remote URL: `ghp_FAKE1234567890abcdefghijklmnopqrstuv` |

### Service Configs

| Category | Location | Key Data |
|---|---|---|
| Jupyter Config | `.jupyter/jupyter_lab_config.py` | `token=''`, `ip='0.0.0.0'` — confirms no authentication |
| Modelfile (assistant) | `projects/chatbot-prototype/Modelfile` | System prompt with PostgreSQL, JWT, Jira, SharePoint, AWS, Slack, PagerDuty, Okta creds |
| Modelfile (support) | `projects/acme-support-bot/Modelfile` | System prompt with CRM API key, ticket API key, manager override, bearer token |

### Shell History

| Category | Location | Key Data |
|---|---|---|
| Bash History | `.bash_history` | `export OPENAI_API_KEY=sk-proj-FAKE...`, `curl` to ChromaDB on 172.16.50.20, `git clone` with PAT, ollama commands |
| Python History | `.python_history` | `openai.api_key = "sk-proj-FAKE..."`, `anthropic.Anthropic(api_key=...)`, ChromaDB client connections to 172.16.50.20 |

### Noise Files

| Category | Location | Purpose |
|---|---|---|
| .env.example | `projects/chatbot-prototype/.env.example` | Placeholder values (`YOUR_OPENAI_KEY_HERE`) — not real credentials |
| requirements.txt | `projects/chatbot-prototype/requirements.txt` | Benign dependency list |
| README.md | `projects/chatbot-prototype/README.md` | Standard project readme |

---

## Seed Script

`seed-filesystem.sh` creates all of the above in a single run. It executes as root (or sudo) on ailab-dev and sets ownership to `devuser`:

```bash
sudo bash seed-filesystem.sh [base_path]  # default: /home/devuser
```

The script is idempotent — running it again overwrites all artifacts to their expected state.

---

## Cross-Host References

Several filesystem artifacts reference other lab hosts, demonstrating interconnected risk:

- `config.py` points to ChromaDB at `172.16.50.20:8000`
- `.bash_history` contains `curl` commands to `172.16.50.20` and `ssh` to `labadmin@172.16.50.20`
- `.python_history` creates a ChromaDB client connected to `172.16.50.20`
- `training.jsonl` references internal hostnames (`db-prod-01.acme.internal`, `vpn.acme.corp`)
- `.env` files in `rag-pipeline/` set `CHROMA_HOST=172.16.50.20`

When aipostex scans the dev workstation's filesystem, these references reveal the attack surface of the ML platform before it's even scanned.
