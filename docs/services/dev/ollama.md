---
title: Ollama (ailab-dev)
---

# Ollama (ailab-dev)

## What It Is

Ollama is an LLM serving platform that provides a REST API for running language models locally. On the dev workstation, a developer installed it via the official one-liner, pulled a small base model, and created two custom models with system prompts containing hardcoded credentials.

---

## Installation

Installed via the official install script with a pinned version:

```bash
curl -fsSL https://ollama.com/install.sh | OLLAMA_VERSION=0.6.2 sh
```

This installs:

- `/usr/local/bin/ollama` — the binary
- `/etc/systemd/system/ollama.service` — the systemd unit
- Creates an `ollama` system user
- Data directory: `/usr/share/ollama/.ollama/` (when run as service)

---

## Systemd Unit

**Unit:** `ollama.service`

The service runs as the `ollama` system user. An override binds it to all interfaces:

```ini title="/etc/systemd/system/ollama.service.d/override.conf"
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
```

!!! danger "Misconfiguration"
    Binding to `0.0.0.0` exposes the unauthenticated API to the entire network. The default is `127.0.0.1`.

---

## Port & Config

| Parameter | Value |
|---|---|
| Host | `172.16.50.10` |
| Port | `11434` |
| Bind address | `0.0.0.0` (via systemd override) |
| Authentication | None |

---

## Models

Three models are present:

| Model | Type | Notes |
|---|---|---|
| `smollm2:135m` | Base model | ~220MB, pulled from registry. Small enough to run on 2 vCPU. |
| `acme-assistant` | Custom | Created from `smollm2:135m`. System prompt contains PostgreSQL creds, JWT tokens, Jira/SharePoint/Okta creds, AWS keys, Slack webhooks, PagerDuty API key. |
| `acme-support` | Custom | Created from `smollm2:135m`. System prompt contains CRM API key, ticket system API key, manager override code, customer data bearer token. |

Both custom models were built from Modelfiles left on disk:

- `/home/devuser/projects/chatbot-prototype/Modelfile` — acme-assistant
- `/home/devuser/projects/acme-support-bot/Modelfile` — acme-support

---

## Filesystem Artifacts

| Path | What's There |
|---|---|
| `/usr/share/ollama/.ollama/models/` | Model blobs and manifests (service user data dir) |
| `~/.ollama/` | Present because the user also ran Ollama manually |
| `/home/devuser/projects/chatbot-prototype/Modelfile` | Modelfile with acme-assistant system prompt |
| `/home/devuser/projects/acme-support-bot/Modelfile` | Modelfile with acme-support system prompt |
| `/etc/systemd/system/ollama.service` | Unit file reveals the service exists |
| `/etc/systemd/system/ollama.service.d/override.conf` | Override reveals `OLLAMA_HOST=0.0.0.0` |

---

## What aipostex Finds

- **Unauthenticated API** — The Ollama REST API has no authentication. Any host on the network can enumerate models and interact with them.
- **System prompt extraction** — The `/api/show` endpoint returns the full system prompt for any model, including all hardcoded credentials embedded by the developer.
- **Model enumeration** — `/api/tags` lists all models including the custom ones, revealing that bespoke models exist.

---

## Verification

Confirm Ollama is running and accessible:

```bash
curl http://localhost:11434/
```

??? example "Expected response"
    ```
    Ollama is running
    ```

List available models:

```bash
curl http://localhost:11434/api/tags
```

??? example "Expected response"
    JSON listing `smollm2:135m`, `acme-assistant`, and `acme-support`.

Extract a system prompt:

```bash
curl http://localhost:11434/api/show -d '{"name":"acme-assistant"}'
```

??? example "Expected response"
    JSON containing the full system prompt with all embedded credentials.
