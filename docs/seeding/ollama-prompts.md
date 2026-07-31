---
title: Ollama System Prompts
---

# Ollama System Prompts

Two custom Ollama models on **ailab-dev** (172.16.50.10) contain hardcoded credentials embedded in their system prompts. This is the most common pattern found on internal pentests — developers create custom models with system prompts that include production connection strings, API keys, and service account credentials to give the model "context" about internal systems.

---

## acme-assistant

**Purpose:** Internal HR and IT assistant for ACME Corp employees.

The system prompt is labeled `INTERNAL CONFIGURATION — DO NOT SHARE WITH USERS` and contains:

| Category | Credential |
|---|---|
| PostgreSQL (prod) | `postgresql://acme_admin:Sup3rS3cretDB!@db-prod-01.acme.internal:5432/acme_hr` |
| PostgreSQL (staging) | `postgresql://acme_stage:St4g1ngPwd@db-stage-01.acme.internal:5432/acme_stage` |
| Internal API Gateway | `https://api-internal.acme.corp/v2` |
| JWT Bearer Token | `eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.acme-internal-2024-prod` |
| Jira Service Account | `svc-jira-bot` / `J1r4B0t#2024!` |
| SharePoint Admin | `sp-admin@acme.corp` / `Sh4r3P01nt@dm1n` |
| AWS Account ID | `123456789012` (us-east-1) |
| AWS Access Key | `AKIAFAKE1234EXAMPLE1` / `FakeSecretKey+abcdefghijk1234567890` |
| Slack Webhook (alerts) | `https://hooks.slack.com/services/T0ACME01/B0ALERTS/xyzAlertWebhookToken` |
| Slack Webhook (deploys) | `https://hooks.slack.com/services/T0ACME01/B0DEPLOY/xyzDeployWebhookToken` |
| PagerDuty API Key | `pd-api-key-FAKE-abcdef1234567890` |
| Okta Admin | `okta-admin@acme.corp` / `0kt4Adm1n!2024` |

---

## acme-support

**Purpose:** Customer-facing support chatbot for ACME Corp.

| Category | Credential |
|---|---|
| CRM API Key | `sk-acme-cust-api-99xKf82mNpQ3` |
| CRM Endpoint | `https://crm.acme.internal/api/v1` |
| Ticket System API Key | `tkt-api-FAKE-abc123def456` |
| Escalation Email | `support-tier2@acme.corp` |
| Manager Override Code | `ESC-2024-ADMIN` |
| Customer Data Bearer Token | `cust-data-bearer-FAKE-token-789xyz` |
| Customer Data API | `https://api-internal.acme.corp/v2/customers` |

---

## How They're Created

`seed-ollama.sh` runs on ailab-dev after the base `smollm2:135m` model is pulled:

```bash
ollama pull smollm2:135m

ollama create acme-assistant -f /home/devuser/projects/chatbot-prototype/Modelfile
ollama create acme-support -f /home/devuser/projects/acme-support-bot/Modelfile
```

Both Modelfiles use `FROM smollm2:135m` as the base and embed the credentials in a `SYSTEM` directive.

---

## How aipostex Extracts Them

Ollama's `/api/show` endpoint returns the full model configuration including the system prompt — no authentication required:

```bash
curl http://172.16.50.10:11434/api/show -d '{"name":"acme-assistant"}'
```

The response includes the complete `SYSTEM` block with all embedded credentials. aipostex's Ollama module:

1. Calls `/api/tags` to enumerate all models
2. Calls `/api/show` for each model to extract the system prompt
3. Applies regex patterns to the system prompt to identify credentials, connection strings, tokens, and keys

---

## Filesystem Artifacts

The Modelfiles used to create the custom models are left on disk — a secondary finding source independent of the API:

| Path | Contents |
|---|---|
| `/home/devuser/projects/chatbot-prototype/Modelfile` | acme-assistant system prompt with all HR/IT credentials |
| `/home/devuser/projects/acme-support-bot/Modelfile` | acme-support system prompt with CRM/ticketing credentials |

These Modelfiles are also documented in [Filesystem Artifacts](filesystem.md) since `seed-filesystem.sh` creates the directory structure and `seed-ollama.sh` creates the models from the Modelfiles that are already on disk.
