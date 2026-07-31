---
title: Jupyter Lab (ailab-ds)
---

# Jupyter Lab (ailab-ds)

## What It Is

JupyterLab is an interactive development environment for notebooks. On the data science workstation, it mirrors the dev workstation's setup — no authentication token, bound to all interfaces — but runs on a different port (`8889`) under the `dsuser` account. A notebook contains production database credentials and API tokens used for feature engineering.

---

## Installation

Installed as `dsuser`:

```bash
pip install --break-system-packages jupyterlab
```

`--break-system-packages` is required on Ubuntu 24.04 (PEP 668).

---

## Systemd Unit

**Unit:** `jupyter-ds.service`

```ini title="/etc/systemd/system/jupyter-ds.service"
[Service]
User=dsuser
WorkingDirectory=/home/dsuser
ExecStart=/home/dsuser/.local/bin/jupyter lab --config=/home/dsuser/.jupyter/jupyter_lab_config.py
Restart=always
```

---

## Port & Config

| Parameter | Value |
|---|---|
| Host | `172.16.50.30` |
| Port | `8889` |
| Bind address | `0.0.0.0` |
| Authentication | None (`token=''`) |

**Configuration file:** `~/.jupyter/jupyter_lab_config.py`

```python title="/home/dsuser/.jupyter/jupyter_lab_config.py"
c.ServerApp.token = ''
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.port = 8889
c.ServerApp.open_browser = False
```

!!! danger "Misconfiguration"
    Setting `token = ''` disables authentication entirely. Combined with `ip = '0.0.0.0'`, anyone on the network gets full access to the notebook server — including terminal access as `dsuser`.

---

## Notebook Content

**`notebooks/churn-model-features.ipynb`** contains:

| Secret | Description |
|---|---|
| PostgreSQL prod creds | Production database connection string with username and password |
| Snowflake creds | Snowflake account, username, password, and warehouse details |
| HuggingFace token | `HF_TOKEN` for pulling model weights |
| Qdrant connection | Connection details for the local Qdrant instance (`172.16.50.30:6333`) |

---

## Filesystem Artifacts

| Path | What's There |
|---|---|
| `~/.jupyter/jupyter_lab_config.py` | Config confirming `token=''` and `ip='0.0.0.0'` |
| `~/.local/share/jupyter/` | Jupyter runtime data |
| `~/.local/bin/jupyter` | The jupyter binary |
| `~/notebooks/churn-model-features.ipynb` | Notebook with embedded credentials |

---

## What aipostex Finds

- **No-token Jupyter** — The server accepts connections without any authentication token, confirmed both by probing the API and by finding `token = ''` in the config file on disk.
- **Exposed terminals** — JupyterLab's terminal feature provides shell access as `dsuser` to anyone who connects.
- **Notebook content** — Production database credentials, Snowflake creds, HuggingFace tokens, and Qdrant connection details embedded directly in notebook cells.

---

## Verification

Confirm Jupyter is running without authentication:

```bash
curl http://localhost:8889/api
```

??? example "Expected response"
    JSON with Jupyter API version information, returned without requiring a token.
