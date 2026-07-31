---
title: Streamlit (ailab-app)
---

# Streamlit (ailab-app)

## What It Is

Streamlit is a lightweight dashboard app on the shared AI app box. It gives the lab a recognizable unauthenticated UI surface that `aipostex` can identify during subnet scans and service fingerprinting.

---

## Installation

Installed as `appuser`:

```bash
pip install --break-system-packages streamlit==1.41.1
```

**Source:** `/home/appuser/projects/streamlit-app/app.py`

---

## Systemd Unit

**Unit:** `streamlit.service`

```ini title="/etc/systemd/system/streamlit.service"
[Service]
User=appuser
WorkingDirectory=/home/appuser/projects/streamlit-app
ExecStart=/home/appuser/.local/bin/streamlit run app.py --server.port 8501 --server.address 0.0.0.0 --server.headless true --browser.gatherUsageStats false
Restart=always
```

---

## Port & Config

| Parameter | Value |
|---|---|
| Host | `172.16.50.40` |
| Port | `8501` |
| Bind address | `0.0.0.0` |
| Authentication | None |
| Health endpoint | `/_stcore/health` |

!!! danger "Misconfiguration"
    The Streamlit UI is fully exposed to the subnet with no auth, matching the “somebody stood up an internal dashboard and never put it behind a gateway” story.

---

## What aipostex Finds

- **Streamlit fingerprinting** — the web UI and native health endpoint make the service easy to classify.
- **App-facing shadow AI** — this broadens the lab beyond back-end ML infrastructure into user-facing internal tools.

---

## Verification

```bash
curl http://localhost:8501/_stcore/health
curl http://localhost:8501/
```

