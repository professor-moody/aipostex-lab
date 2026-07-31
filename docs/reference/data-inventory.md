---
title: Sensitive Data Inventory
---

# Sensitive Data Inventory

Complete "answer key" — every piece of planted sensitive data across the target VMs. The [scoring manifest](../scoring/manifest.md) uses this as ground truth for the 170 total findings.

!!! danger "This page is the answer key"
    Everything below is intentionally planted fake data. All keys start with `FAKE`, SSNs don't pass checksum validation, and the company is "ACME Corp." The patterns are realistic enough to trigger aipostex's detection.

---

## ailab-dev — 172.16.50.10

### Filesystem Artifacts (`/home/devuser/`)

#### `.env` Files

| Category | Location | Key Data |
|----------|----------|----------|
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
| ChromaDB Host | `projects/rag-pipeline/.env` | `172.16.50.20:8000` (cross-host reference) |

#### MCP Configurations

| Category | Location | Key Data |
|----------|----------|----------|
| Claude Desktop — filesystem | `.config/Claude/claude_desktop_config.json` | MCP server with access to `/home/devuser`, `/opt/shared`, `/etc` |
| Claude Desktop — postgres | `.config/Claude/claude_desktop_config.json` | `postgresql://mcp_reader:McpR3ad3r!@db-prod-01.acme.internal:5432/acme_prod` |
| Claude Desktop — github | `.config/Claude/claude_desktop_config.json` | `ghp_FAKE1234567890abcdefghijklmnopqrstuv` |
| Claude Desktop — slack | `.config/Claude/claude_desktop_config.json` | `xoxb-FAKE-1234567890-abcdefghijklmnop` |
| Claude Desktop — jira | `.config/Claude/claude_desktop_config.json` | `ATATT3xFfGF0_FAKE_jira_token_1234567890abcdef` |
| Cursor MCP — brave search | `.cursor/mcp.json` | `BSA_FAKE_brave_search_api_key_12345678` |
| VS Code MCP — postgres | `projects/chatbot-prototype/.vscode/settings.json` | `postgresql://dev_user:D3vUs3r!@db-dev-01.acme.internal:5432/chatbot_dev` |

#### Cached Tokens & Cloud Credentials

| Category | Location | Key Data |
|----------|----------|----------|
| HuggingFace Cache | `.cache/huggingface/token` | `hf_FAKE_CachedTokenFromLogin_aBcDeFgHiJkLmNoPqRs` |
| AWS — default profile | `.aws/credentials` | `AKIAFAKEKEY1234567890` / `FAKE+SecretKey/abcdefghijklmnop1234567890` |
| AWS — bedrock-dev profile | `.aws/credentials` | `AKIAFAKEBEDROCK12345` / `FAKE+BedrockSecret/abcdefghijklmnop12345` |
| GCP — client secret | `.config/gcloud/application_default_credentials.json` | `GOCSPX-FAKE_CLIENT_SECRET_abcdef` |
| GCP — refresh token | `.config/gcloud/application_default_credentials.json` | `1//FAKE_REFRESH_TOKEN_0abcdefghijklmnop` |

#### Source Code & Config Files

| Category | Location | Key Data |
|----------|----------|----------|
| LangChain Config | `projects/chatbot-prototype/config.py` | DB: `postgresql://readonly:R3ad0nly!@db-prod-01.acme.internal:5432/acme_prod`, ChromaDB at `172.16.50.20:8000` |
| Hardcoded Anthropic Key | `projects/internal-tools/summarizer.py` | `sk-ant-FAKE-inline-key-abcdef123456` |
| Git PAT | `projects/chatbot-prototype/.git/config` | `ghp_FAKE1234567890abcdefghijklmnopqrstuv` in remote URL |
| Jupyter Config | `.jupyter/jupyter_lab_config.py` | `token = ''`, `ip = '0.0.0.0'` — confirms no auth |
| Modelfile (assistant) | `projects/chatbot-prototype/Modelfile` | System prompt with all acme-assistant creds (see below) |
| Modelfile (support) | `projects/acme-support-bot/Modelfile` | System prompt with CRM/support creds (see below) |
| Docker Compose | `projects/rag-pipeline/docker-compose.yml` | `postgresql://app_user:AppUs3r!@db-prod-01.acme.internal:5432/acme_prod` |

#### Training Data

| Category | Location | Key Data |
|----------|----------|----------|
| Training JSONL | `projects/fine-tune-experiment/data/training.jsonl` | VPN creds (`svc-vpn-mon / VpnM0n1t0r!ng2024`), DB creds (`bi_reader / B1R3ader!Pr0d`), Q3 revenue ($42.3M), CFO contact, AWS account IDs |
| Eval JSONL | `projects/fine-tune-experiment/data/eval.jsonl` | Exec team names, PagerDuty phone tree |

#### Shell History

| Category | Location | Key Data |
|----------|----------|----------|
| Bash History | `.bash_history` | `export OPENAI_API_KEY=sk-proj-FAKE1234567890abcdefghijklmnop`, `git clone` with PAT, `curl` to ChromaDB at 172.16.50.20 |
| Python History | `.python_history` | `openai.api_key = "sk-proj-..."`, `anthropic.Anthropic(api_key="sk-ant-...")`, ChromaDB client at 172.16.50.20 |

#### Jupyter Notebook

| Category | Location | Key Data |
|----------|----------|----------|
| OpenAI Key | `notebooks/rag-prototype.ipynb` | `sk-proj-FAKE-notebook-key-1234567890abcdef` |
| Anthropic Key | `notebooks/rag-prototype.ipynb` | `sk-ant-FAKE-notebook-key-abcdef1234567890` |
| DB Connection | `notebooks/rag-prototype.ipynb` | `postgresql://chatbot:Ch4tb0tPwd!@db-dev-01.acme.internal:5432/chatbot_dev` |
| ChromaDB Host | `notebooks/rag-prototype.ipynb` | `172.16.50.20:8000` / collection `acme-knowledge-base` |

### Ollama System Prompts (port 11434)

Exposed via `GET /api/show` — anyone on the network can read these.

#### acme-assistant model

| Credential | Value |
|------------|-------|
| Production DB | `postgresql://acme_admin:Sup3rS3cretDB!@db-prod-01.acme.internal:5432/acme_hr` |
| Staging DB | `postgresql://acme_stage:St4g1ngPwd@db-stage-01.acme.internal:5432/acme_stage` |
| API Gateway Bearer | `eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.acme-internal-2024-prod` |
| Jira Service Account | `svc-jira-bot` / `J1r4B0t#2024!` |
| SharePoint Admin | `sp-admin@acme.corp` / `Sh4r3P01nt@dm1n` |
| AWS Account ID | `123456789012` (us-east-1) |
| AWS Access Key | `AKIAFAKE1234EXAMPLE1` / `FakeSecretKey+abcdefghijk1234567890` |
| Slack Webhook (alerts) | `https://hooks.slack.com/services/T0ACME01/B0ALERTS/xyzAlertWebhookToken` |
| Slack Webhook (deploys) | `https://hooks.slack.com/services/T0ACME01/B0DEPLOY/xyzDeployWebhookToken` |
| PagerDuty API | `pd-api-key-FAKE-abcdef1234567890` |
| Okta Admin | `okta-admin@acme.corp` / `0kt4Adm1n!2024` |

#### acme-support model

| Credential | Value |
|------------|-------|
| CRM API Key | `sk-acme-cust-api-99xKf82mNpQ3` |
| CRM Endpoint | `https://crm.acme.internal/api/v1` |
| Ticket API Key | `tkt-api-FAKE-abc123def456` |
| Manager Override Code | `ESC-2024-ADMIN` |
| Customer Data Bearer | `cust-data-bearer-FAKE-token-789xyz` |

---

## ailab-ml — 172.16.50.20

### LiteLLM Config (`/opt/litellm/config.yaml`)

| Provider | Key |
|----------|-----|
| OpenAI (gpt-4, gpt-4o) | `sk-proj-FAKE-litellm-openai-key-1234567890` |
| Anthropic (claude-sonnet) | `sk-ant-FAKE-litellm-anthropic-key-abcdef1234567890` |
| Azure OpenAI (gpt-4) | `FAKE-azure-openai-key-abcdef123456` |
| AWS Bedrock (claude-3) | `AKIAFAKELITELLM12345` / `FAKE+LiteLLMBedrockSecret/abcdefghijk12345` |
| Ollama backend | `http://172.16.50.10:11434` (cross-host reference to ailab-dev) |

!!! warning "master_key is null (open proxy, :4000)"
    The LiteLLM proxy on **:4000** (`/opt/litellm/config.yaml`) has no master key configured — full admin access to `/v1/models`, `/v1/chat/completions`, and key management.

!!! note "Authenticated instance (:4001) — the looted-key climax"
    A second LiteLLM proxy on **:4001** (`/opt/litellm/config_authed.yaml`) *requires* a master key: `sk-litellm-lab-auth-key-FAKE123` (manifest type `litellm_master_key`). The credential chain loots this key and replays it against :4001 to drive real Ollama inference — the gated counterpart to the open :4000 proxy above.

### ChromaDB (port 8000)

#### acme-knowledge-base (12 docs + 3 prompt injections)

| Finding Type | Details |
|-------------|---------|
| SSNs | `456-78-9012` (John Smith), `789-01-2345` (Jane Doe) |
| Salaries | $145,000 (John Smith, EMP-2847), $162,000 (Jane Doe, EMP-1923) |
| VPN creds | `svc-vpn-mon` / `VpnM0n1t0r!ng2024` |
| VPN admin | `admin` / `F0rt1G4te@dm1n!` |
| DB creds (BI) | `bi_reader` / `B1R3ader!Pr0d` — full connection string to `db-prod-01.acme.internal` |
| MongoDB creds | `mongodb://analytics:An4lyt1cs!@mongo-01.acme.internal:27017/acme_analytics` |
| AWS accounts | `123456789012` (prod), `987654321098` (staging), `111222333444` (dev) |
| Grafana admin | `admin` / `Gr4f4n4@dm1n` |
| API monitor key | `sk-api-monitor-FAKE-abcdef1234567890` |
| Q3 financials | $42.3M revenue, IPO target Q2 2027, $156M cash — marked CONFIDENTIAL |
| M&A analysis | DataFlow Inc acquisition at $85M, board vote Dec 15, 2025 — marked RESTRICTED |
| Slack Bot Token | `xoxb-1234567890-abcdefghijklmnop` |
| GitHub PAT | `ghp_ABCDEFghijklmnop1234567890abcdefgh` |
| Datadog API Key | `FAKE_DD_API_KEY_abcdef1234567890` |
| Datadog APP Key | `FAKE_DD_APP_KEY_1234567890abcdef` |
| PagerDuty Key | `FAKE_PD_KEY_1234567890abcdef` |
| Sentry DSN | `https://FAKE_SENTRY_KEY@o123456.ingest.sentry.io/123456` |
| Prompt injections | 3 adversarial documents: system prompt dump, base64 exfil tag, env var extraction |

#### support-tickets-2025 (5 docs)

| Finding Type | Details |
|-------------|---------|
| Credit card (Visa) | ending `4242` (customer Acme Industries) |
| Credit card (Mastercard) | ending `1234`, exp `08/2027` (customer Sarah Lawson) |
| SSN | `321-54-9876` (identity verification for billing dispute) |
| Temp password | `TmpPwd!2025#Reset` |
| API key (provisioned) | `gt_api_key_FAKE_9f8e7d6c5b4a3210` (GlobalTech Inc) |
| Passport | `DE-FAKE-12345678` (GDPR deletion request) |

#### code-documentation (3 docs)

| Finding Type | Details |
|-------------|---------|
| Dev admin creds | `admin` / `AdminDev2024!` (auth-service, also used in staging — JIRA-1847) |
| AWS Secrets Manager ARN | `arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/acme-api-keys-AbCdEf` |
| Emergency IAM user | `emergency-access` / `EmrgAcc3ss!2024` |

#### public-documentation (6 docs) — NOISE

Open-source library docs (LangChain, ChromaDB, FastAPI, Docker, Pytest, Git). No credentials or PII.

### MLflow (port 5000)

#### churn-prediction-v2 (3 runs)

| Finding Type | Where | Value |
|-------------|-------|-------|
| PostgreSQL creds | run params `training_data` | `postgresql://ds_readonly:DsR34d0nly!Pr0d@db-prod-01.acme.internal:5432/acme_prod` |
| Redis feature store | run params `feature_store` | `redis://feature-store.acme.internal:6379/2` |
| Snowflake creds | run params `training_data` | `snowflake://ds_team:Sn0wfl4keDs!@acme.snowflakecomputing.com/ANALYTICS/CHURN` |
| Internal hostnames | artifacts `model_config` | `seldon.acme.internal`, `grafana.acme.internal` |

#### fraud-detection-bert (3 runs)

| Finding Type | Where | Value |
|-------------|-------|-------|
| AWS Account ID | run params | `123456789012` |
| PagerDuty key | artifacts `deployment_config` | `FAKE_PD_FRAUD_abc123` |
| Kafka broker | artifacts `deployment_config` | `kafka-prod.acme.internal:9092/raw-transactions` |

#### customer-embedding-model (2 runs)

| Finding Type | Where | Value |
|-------------|-------|-------|
| PostgreSQL creds | run params `training_data` | `postgresql://ds_readonly:DsR34d0nly!Pr0d@...` (same as churn) |
| Snowflake creds | run params `training_data` | `snowflake://ds_team:Sn0wfl4keDs!@.../ANALYTICS/CUSTOMERS` |
| Qdrant host ref | run params | `172.16.50.30:6333` / collection `product-embeddings` |
| HF/TGI token | run params/tags `hf_tgi_token` | `hf_FAKE_aBcDeFgHiJkLmNoPqRsTuVwXyZ123` |

### MLflow Registry (port 5000)

| Registered Model | Versions | Stages | Source |
|---|---|---|---|
| `acme-churn-ensemble` | 2 | `Staging`, `Production` | `runs:/<run-id>/model` from `churn-prediction-v2` |
| `acme-fraud-bert` | 2 | `Staging`, `Production` | `runs:/<run-id>/model` from `fraud-detection-bert` |

### Ray Jobs (port 8265)

!!! note "Deterministic artifacts"
    Jobs 1 and 2 write files to `/tmp/ray-lab-artifacts/churn-model-retraining/` and `/tmp/ray-lab-artifacts/runtime-env-validator/` and print those paths in their logs.

#### Job 1: churn-model-retraining

| Env Var | Value |
|---------|-------|
| `DATABASE_URL` | `postgresql://ml_pipeline:MlP1p3l1n3!Pr0d@db-prod-01.acme.internal:5432/ml_features` |
| `REDIS_URL` | `redis://:R3d1sMlC4ch3!@redis-ml.acme.internal:6379/0` |
| `AWS_ACCESS_KEY_ID` | `AKIAFAKERAYML12345678` |
| `AWS_SECRET_ACCESS_KEY` | `FAKE+RayMLSecret/abcdefghijk1234567890` |
| `S3_MODEL_BUCKET` | `s3://acme-ml-prod/ray-training/` |
| `WANDB_API_KEY` | `FAKE_wandb_ray_key_abcdef123456` |
| `HF_TOKEN` | `hf_FAKE_RayTraining_aBcDeFgHiJkLmNoPqRs` |

#### Job 2: runtime-env-validator

| Env Var | Value |
|---------|-------|
| `SNOWFLAKE_URI` | `snowflake://ray_svc:R4ySvcSn0w!@acme.snowflakecomputing.com/ML/FEATURES` |
| `KAFKA_BOOTSTRAP` | `kafka-prod.acme.internal:9092` |
| `KAFKA_SASL_PASSWORD` | `K4fk4Pr0dP4ss!2024` |
| `DATADOG_API_KEY` | `FAKE_dd_ray_api_key_abcdef1234567890` |
| `SENTRY_DSN` | `https://FAKE_sentry_ray_key@sentry.acme.internal/42` |
| `VAULT_TOKEN` | `hvs.FAKE_ray_vault_token_1234567890abcdef` |
| `AIPOSTEX_RUNTIME_ENV_MARKER` | `enabled-for-lab` |
| `AIPOSTEX_RUNTIME_PIP_HINT` | `requests-safe-marker` |

#### Job 3: model-serving-canary

| Env Var | Value |
|---------|-------|
| `MODEL_REGISTRY_URL` | `http://mlflow.acme.internal:5000` |
| `SELDON_API_KEY` | `seldon_FAKE_api_key_abcdef1234567890` |
| `STRIPE_BILLING_KEY` | `sk_live_FAKE_ray_billing_key_123456` |
| `PD_ROUTING_KEY` | `FAKE_PD_RAY_CANARY_abc123` |

### W&B Mock (port 8444)

Entity: `acme-ml-team`, 2 projects with planted secrets in run configs.

#### churn-prediction (2 runs)

| Finding Type | Where | Value |
|-------------|-------|-------|
| W&B API key | run config | `FAKE_wandb_server_key_abcdef123456` |
| OpenAI key | run config | `sk-proj-FAKE-wandb-openai-key-9876543210` |
| AWS Access Key | run config | `AKIAFAKEWANDB12345678` |
| AWS Secret Key | run config | `FakeWandbSecretKeyAbCdEfGhIjKlMnOpQr` |
| DB connection | run config | `postgresql://ml_user:Ml_P4ss!@db-ml.acme.internal:5432/ml_prod` |
| HF Token | run config | `hf_FAKE_WandbRun_aBcDeFgHiJkLmNoPq` |

#### fraud-detection (3 runs)

| Finding Type | Where | Value |
|-------------|-------|-------|
| Anthropic key | run config | `sk-ant-FAKE-wandb-anthropic-key-abcdef1234` |
| Service password | run config | `Pr0d_S3rv1ce_Cr3d!` |

---

## ailab-ds — 172.16.50.30

### Weaviate (port 8080)

#### ResearchDocument class (6 objects)

| Finding Type | Details |
|-------------|---------|
| PostgreSQL creds | `postgresql://ds_readonly:DsR34d0nly!Pr0d@db-prod-01.acme.internal:5432/acme_prod` |
| Snowflake creds | `snowflake://ds_team:Sn0wfl4keDs!@acme.snowflakecomputing.com/ANALYTICS/RAW` |
| Zendesk API key | `zd_api_FAKE_abcdef1234567890` |
| Redis auth | `FeatSt0re!R3dis` (feature store cache) |
| OpenAI key (distillation) | `sk-proj-FAKE-distill-key-abcdef1234567890` |
| W&B key | `FAKE_wandb_key_distill_abcdef` |
| Airflow admin | `airflow_admin` / `A1rfl0w@dm1n2024` |
| Salesforce OAuth | `sf_integration_user` / `SfInt3gr4t10n!` (client_id: `3MVG9fake1234`) |
| HubSpot API key | `hs_api_FAKE_1234567890abcdef` |
| Stripe LIVE key | `sk_live_FAKE_stripe_1234567890abcdef` |
| Intercom token | `intercom_token_FAKE_abcdef1234567890` |
| PagerDuty key | `FAKE_PD_FRAUD_abc123` |
| Vault reference | `vault.acme.internal:8200` (migration target) |
| Internal IPs | `172.16.50.30:11434` (Ollama), `172.16.50.30:6333` (Qdrant) |

#### TeamCommunication class (6 objects)

| Finding Type | Details |
|-------------|---------|
| SSNs | `567-89-0123` (Alex Rivera), `890-12-3456` (Priya Patel), `234-56-7891` (Marcus Lee) |
| Salaries | $175,000 (Alex Rivera, 15K RSUs), $140,000 (Priya Patel, 10K RSUs), $155,000 (Marcus Lee, 12K RSUs) |
| HR admin | `hr_admin` / `HrAdm1n!2024` |
| Corporate card | ending `8901` (cardholder Sarah Chen, CFO) |
| Pinecone trial key | `pcsk_EVAL_trial_abcdef1234567890` |
| Weaviate Cloud trial | `wcs_EVAL_key_1234567890abcdef` |
| Qdrant Cloud trial | `qdrant_EVAL_apikey_abcdef123456` |
| PagerDuty key | `FAKE_PD_ML_xyz789` |
| Board AI strategy | Headcount reduction plans (8–12 support agents), $1.2M savings, GPU cluster $180K |
| Security alerts | References exposed Ollama at `172.16.50.10:11434`, ChromaDB at `172.16.50.20:8000` |

#### PublicKnowledge class (4 objects) — NOISE

ML textbook content (transformers, metrics), UCI datasets, Python best practices. No sensitive data.

### Qdrant (port 6333)

#### product-catalog (4 points)

| Finding Type | Details |
|-------------|---------|
| License server admin | `license_admin` / `L1c3ns3Adm!n` |
| Telemetry API key | `tel_api_FAKE_1234567890` |
| SaaS DB creds | `postgresql://saas_app:S44sAppPr0d!@saas-db.acme.internal:5432/acme_saas` |
| Stripe billing key | `sk_live_FAKE_saas_billing_abcdef123456` |
| ECR pull secret | `ecr_pull_FAKE_token_abcdef1234567890` |
| Vault token | `hvs.FAKE_vault_token_abcdef1234567890` |
| Internal pricing | Gross margins 74–91%, cost-to-serve details, floor prices |

#### security-findings (6 points)

| Finding Type | Details |
|-------------|---------|
| Pentest report | Lists ALL lab hosts by IP with services — `172.16.50.10`, `.20`, `.30` |
| IR playbook | Break-glass procedures, Stripe admin revoke key: `sk_live_FAKE_admin_revoke_key` |
| Network switch creds | `admin` / `C1sc0@dm1n!2024` (`core-sw-01.acme.internal`) |
| AWS backup key | `AKIAFAKEBACKUP123456` / `FAKE+BackupSecret/abcdef1234567890` |
| Shadow IT report | 3 Ollama instances, 4 vector DBs, 2 Jupyter, 1 MCP server, 12 `.env` files — $2.4M exposure estimate |
| Network segmentation | VLAN 50 unrestricted from corporate WiFi (VLAN 10) and dev (VLAN 20) |

#### public-faq (4 points) — NOISE

Generic Q&A content (languages, SLA, password reset, free trial). No sensitive data.

### Jupyter Notebook (port 8889)

`churn-model-features.ipynb`:

| Finding Type | Value |
|-------------|-------|
| PostgreSQL prod creds | `postgresql://ds_readonly:DsR34d0nly!Pr0d@db-prod-01.acme.internal:5432/acme_prod` |
| Snowflake creds | `snowflake://ds_team:Sn0wfl4keDs!@acme.snowflakecomputing.com/ANALYTICS/RAW` |
| HF token | `hf_FAKE_notebook_token_aBcDeFgHiJk` |
| Qdrant connection | `localhost:6333` |
| Ollama host | `http://localhost:11434` |
