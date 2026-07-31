---
title: Gradio Chatbot
---

# Gradio Chatbot

## What It Is

A Gradio web UI that still wraps the local Ollama instance, but now exposes several intentionally testable routes from one app:

- a bounded text prediction route
- a deterministic file-returning route
- a file-upload-capable route
- queue-backed execution

The service is still unauthenticated and bound to all interfaces. The lab keeps it on one port so `aipostex` can validate enum, predict, upload, file-chain, and serve-probe flows against a single realistic dev-side app.

---

## Installation

Installed as `devuser`:

```bash
pip install --break-system-packages gradio==5.49.1
```

**Source:** `/home/devuser/projects/gradio-chat/app.py`

The app connects to the local Ollama API at `http://localhost:11434` for text predictions and stores deterministic lab files under `/tmp/gradio-lab/`.

---

## Systemd Unit

**Unit:** `gradio-chat.service`

```ini title="/etc/systemd/system/gradio-chat.service"
[Service]
User=devuser
WorkingDirectory=/home/devuser/projects/gradio-chat
ExecStart=/usr/bin/python3 app.py
Restart=always
```

---

## Port & Config

| Parameter | Value |
|---|---|
| Host | `172.16.50.10` |
| Port | `7860` |
| Bind address | `0.0.0.0` |
| Authentication | None |
| Backend | Local Ollama at `http://localhost:11434` |
| Queue | Enabled |
| Deterministic file roots | `/tmp/gradio-lab/exports`, `/tmp/gradio-lab/uploads`, `/tmp/gradio-lab/seed` |

!!! danger "Misconfiguration"
    No authentication and binding to `0.0.0.0` means anyone on the network can interact with the chatbot — and by extension, with any Ollama model on the system, including those with credentials in their system prompts.

---

## What aipostex Finds

- **Exposed Gradio config** — The `/config` endpoint reveals the app structure, queue behavior, component types, and named API routes.
- **Callable API surface** — Gradio exposes predictable API endpoints (`/gradio_api/call/*`, `/queue/join`, `/upload`, file-serving routes) that can be called programmatically without the web UI.
- **File-return and file-chain validation** — The `export_bundle` route returns deterministic files from `/tmp/gradio-lab/exports/`, which `aipostex` can pivot into `file-chain`, `download-file`, and `serve-probe`.
- **Upload validation** — The `ingest_file` route makes file-capable behavior visible in `/config`, and the upload surface can be exercised with bounded operator-marked content.

---

## Verification

Confirm Gradio is running:

```bash
curl http://localhost:7860/
```

??? example "Expected response"
    HTML page with the Gradio chatbot interface and embedded configuration.

Enumerate the exposed routes:

```bash
curl http://localhost:7860/config | jq '.dependencies[] | {api_name, queue}'
```

Expected named routes include `predict_text`, `export_bundle`, and `ingest_file`.
