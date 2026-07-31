---
title: Ollama (ailab-ds)
---

# Ollama (ailab-ds)

## What It Is

Ollama is an LLM serving platform that provides a REST API for running language models locally. On the data science workstation, the team installed it via the official one-liner to experiment with small models. Unlike the dev workstation's instance, no custom models with embedded credentials exist here — only the base `smollm2:135m` model is pulled. This represents the "we just wanted to try it out" shadow AI pattern.

---

## Installation

Installed via the official install script with a pinned version (same as ailab-dev):

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
    Same misconfiguration as ailab-dev: binding to `0.0.0.0` exposes the unauthenticated API to the entire network. The default is `127.0.0.1`.

---

## Port & Config

| Parameter | Value |
|---|---|
| Host | `172.16.50.30` |
| Port | `11434` |
| Bind address | `0.0.0.0` (via systemd override) |
| Authentication | None |

---

## Models

Only one model is present:

| Model | Type | Notes |
|---|---|---|
| `smollm2:135m` | Base model | ~220MB, pulled from registry. No custom models, no embedded credentials. |

---

## What aipostex Finds

- **Unauthenticated API** — The Ollama REST API has no authentication, same as the dev instance.
- **Model enumeration** — `/api/tags` lists the available model. While no credentials are embedded, the presence of an unauthenticated LLM endpoint is itself a finding.
- **Network-accessible inference** — Any host on the network can run inference against the model.

---

## Verification

Confirm Ollama is running:

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
    JSON listing only `smollm2:135m`.
