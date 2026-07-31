---
title: LangServe (ailab-app)
---

# LangServe (ailab-app)

## What It Is

LangServe exposes a simple LangChain runnable through FastAPI on the shared AI app box. It gives the lab a realistic app-facing surface with unauthenticated `/docs`, `/playground`, and `/invoke` routes so `aipostex` can fingerprint LangServe directly instead of inferring it from generic FastAPI behavior.

---

## Installation

Installed as `appuser`:

```bash
pip install --break-system-packages \
  langserve==0.3.1 \
  langchain-core==0.3.35 \
  fastapi==0.115.6 \
  uvicorn==0.34.0
```

**Source:** `/home/appuser/projects/langserve-app/server.py`

---

## Systemd Unit

**Unit:** `langserve.service`

```ini title="/etc/systemd/system/langserve.service"
[Service]
User=appuser
WorkingDirectory=/home/appuser/projects/langserve-app
ExecStart=/home/appuser/.local/bin/uvicorn server:app --host 0.0.0.0 --port 8090
Restart=always
```

---

## Port & Config

| Parameter | Value |
|---|---|
| Host | `172.16.50.40` |
| Port | `8090` |
| Bind address | `0.0.0.0` |
| Authentication | None |
| Public routes | `/docs`, `/playground/`, `/invoke` |

!!! danger "Misconfiguration"
    LangServe is reachable without authentication from the flat lab subnet, which means the app surface, playground, and invoke endpoint are all directly exposed.

---

## What aipostex Finds

- **LangServe fingerprinting** — the docs and playground routes expose the expected framework surface.
- **Unauthenticated invoke surface** — the runnable is callable without keys, cookies, or gateway auth.
- **Shared app-box sprawl** — the lab now demonstrates a fourth team/host pattern, not just dev, ML, and data science.

---

## Verification

```bash
curl http://localhost:8090/docs
curl http://localhost:8090/invoke -H 'Content-Type: application/json' -d '{"input":"hello"}'
```

