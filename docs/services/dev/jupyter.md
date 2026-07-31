---
title: Jupyter Lab (ailab-dev)
---

# Jupyter Lab (ailab-dev)

## What It Is

JupyterLab is an interactive development environment for notebooks. On the dev workstation, a developer installed it via pip and configured it with no authentication token, making all notebooks, terminals, and the kernel accessible to anyone on the network.

---

## Installation

Installed as the `devuser` account:

```bash
pip install --break-system-packages jupyterlab
```

`--break-system-packages` is required on Ubuntu 24.04 (PEP 668).

---

## Systemd Unit

**Unit:** `jupyter.service`

```ini title="/etc/systemd/system/jupyter.service"
[Service]
User=devuser
WorkingDirectory=/home/devuser
ExecStart=/home/devuser/.local/bin/jupyter lab --config=/home/devuser/.jupyter/jupyter_lab_config.py
Restart=always
```

---

## Port & Config

| Parameter | Value |
|---|---|
| Host | `172.16.50.10` |
| Port | `8888` |
| Bind address | `0.0.0.0` |
| Authentication | None (`token=''`) |

**Configuration file:** `~/.jupyter/jupyter_lab_config.py`

```python title="/home/devuser/.jupyter/jupyter_lab_config.py"
c.ServerApp.token = ''
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
```

!!! danger "Misconfiguration"
    Setting `token = ''` disables authentication entirely. Combined with `ip = '0.0.0.0'`, anyone on the network gets full access to the notebook server — including terminal access as `devuser`.

---

## Notebook Content

**`notebooks/rag-prototype.ipynb`** contains:

| Secret | Description |
|---|---|
| OpenAI API key | `sk-proj-FAKE1234567890abcdefghijklmnop` |
| Anthropic API key | `sk-ant-FAKE-abcdefghijklmnop1234567890` |
| ChromaDB host | `172.16.50.20:8000` (cross-host reference to ailab-ml) |
| DB connection string | PostgreSQL connection with credentials |

---

## Filesystem Artifacts

| Path | What's There |
|---|---|
| `~/.jupyter/jupyter_lab_config.py` | Config confirming `token=''` and `ip='0.0.0.0'` |
| `~/.local/share/jupyter/` | Jupyter runtime data |
| `~/.local/bin/jupyter` | The jupyter binary |
| `~/notebooks/rag-prototype.ipynb` | Notebook with embedded API keys |

---

## What aipostex Finds

- **No-token Jupyter** — The server accepts connections without any authentication token, confirmed both by probing the API and by finding `token = ''` in the config file on disk.
- **Exposed terminals** — JupyterLab's terminal feature provides shell access as `devuser` to anyone who connects.
- **Notebook content** — API keys and connection strings embedded directly in notebook cells.

---

## Verification

Confirm Jupyter is running without authentication:

```bash
curl http://localhost:8888/api
```

??? example "Expected response"
    JSON with Jupyter API version information, returned without requiring a token.
