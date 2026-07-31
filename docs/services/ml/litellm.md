---
title: LiteLLM (ailab-ml)
---

# LiteLLM (ailab-ml)

## What It Is

LiteLLM is an OpenAI-compatible proxy that provides a unified API across multiple LLM providers. On the ML platform, its config file aggregates API keys for OpenAI, Anthropic, Azure OpenAI, and AWS Bedrock — plus a `local-smollm` model backed by the Ollama instance on ailab-dev for live inference. This makes it the highest-value target on ailab-ml: one config file yields credentials for four-plus providers.

---

## Installation

Installed as `mluser`:

```bash
pip install --break-system-packages "litellm[proxy]==1.60.7"
```

`--break-system-packages` is required on Ubuntu 24.04 (PEP 668).

---

## Systemd Units

The lab runs **two** LiteLLM instances to test both unauthenticated and authenticated scenarios.

### Open instance (port 4000)

**Unit:** `litellm.service`

```ini title="/etc/systemd/system/litellm.service"
[Service]
User=mluser
ExecStart=/usr/local/bin/litellm --config /opt/litellm/config.yaml --port 4000 --host 0.0.0.0
Restart=always
```

### Authenticated instance (port 4001)

**Unit:** `litellm-authed.service`

```ini title="/etc/systemd/system/litellm-authed.service"
[Service]
User=mluser
ExecStart=/usr/local/bin/litellm --config /opt/litellm/config_authed.yaml --port 4001 --host 0.0.0.0
Restart=always
```

---

## Port & Config

| Parameter | Open Instance | Authenticated Instance |
|---|---|---|
| Host | `172.16.50.20` | `172.16.50.20` |
| Port | `4000` | `4001` |
| Bind address | `0.0.0.0` | `0.0.0.0` |
| Authentication | None | `master_key: sk-litellm-lab-auth-key-FAKE123` |
| Config file | `/opt/litellm/config.yaml` | `/opt/litellm/config_authed.yaml` |

!!! danger "Highest-value target on ailab-ml"
    The config file on `:4000` contains aggregated API keys for multiple LLM providers in a single location. Compromising this one file yields credentials for OpenAI, Anthropic, Azure OpenAI, and AWS Bedrock.

!!! info "Mixed auth testing"
    The authenticated instance on `:4001` uses the same LiteLLM version but requires a bearer token. This lets `auth-sweep` test a realistic mixed environment where some endpoints are open and others are keyed.

---

## Config File

The config at `/opt/litellm/config.yaml` defines five model backends:

| Model | Provider | Key / Credential |
|---|---|---|
| `gpt-4` | OpenAI | `sk-proj-FAKE-litellm-openai-key-1234567890` |
| `claude-3-opus` | Anthropic | `sk-ant-FAKE-litellm-anthropic-key-abcdef` |
| `azure-gpt-4` | Azure OpenAI | `FAKE-azure-openai-key-abcdef123456` |
| `bedrock-claude` | AWS Bedrock | `AKIAFAKELITELLM12345` (access key) |
| `local-smollm` | Ollama (ailab-dev) | No API key — points to `http://172.16.50.10:11434` |

The `local-smollm` model proxies to the Ollama instance on ailab-dev (`172.16.50.10:11434`), enabling live inference through LiteLLM's OpenAI-compatible API.

---

## What aipostex Finds

- **OpenAI-compatible endpoint** — LiteLLM exposes a standard `/v1/chat/completions` endpoint, making it immediately recognizable to any tool scanning for OpenAI-compatible APIs.
- **Model enumeration** — The `/v1/models` endpoint lists all configured models, revealing which providers are connected.
- **LiteLLM-specific probing** — The `openai-compat litellm-probe` subcommand checks three endpoints unique to LiteLLM proxies: `/health` (backend topology with model names and API base URLs), `/health/readiness` (version and DB status), and `/v1/model/info` (full model configs including `litellm_params` which may contain API keys). The `litellm-config-001-endpoint-exposure` vulnerability template also fires during `discover network`.
- **Config file via filesystem scan** — The config file at `/opt/litellm/config.yaml` contains all API keys in plaintext, discoverable by any filesystem-level assessment.
- **Live inference validation** — The `local-smollm` backend routes to Ollama on ailab-dev, enabling aipostex to verify live inference capability through the proxy.
- **Auth-sweep differentiation** — With both an open (`:4000`) and authenticated (`:4001`) instance, `auth-sweep` can demonstrate mixed-environment detection where some endpoints accept unauthenticated requests and others require keys.

---

## Verification

Confirm LiteLLM is running:

```bash
curl http://localhost:4000/health/liveliness
```

??? example "Expected response"
    ```
    "connected"
    ```

List available models:

```bash
curl http://localhost:4000/v1/models
```

??? example "Expected response"
    JSON listing `gpt-4`, `claude-3-opus`, `azure-gpt-4`, `bedrock-claude`, and `local-smollm`.
