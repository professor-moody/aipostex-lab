---
title: Legacy HF TGI Mock (ailab-ml)
---

# Legacy HF TGI Mock (ailab-ml)

## What It Is

A lightweight mock of Hugging Face Text Generation Inference. This ML-host copy is now legacy/opt-in; the default guided benchmark uses the auth-gated TGI gateway on `ailab-app:8180`.

---

## Surface

| Endpoint | Purpose |
|---|---|
| `GET /health` | Basic health check |
| `GET /info` | Model metadata (model_id, model_type, version, sha, token limits) |
| `POST /generate` | Fake text-generation response |
| `GET /v1/models` | OpenAI-compatible model listing |
| `GET /metrics` | Prometheus metrics (request count, queue size, batch size) |

---

## Port & Unit

| Parameter | Value |
|---|---|
| Host | `172.16.50.20` |
| Port | `8180` |
| Unit | `hf-tgi-mock.service` |
| Runtime | `python3 server.py` |
| Enable | `ENABLE_LEGACY_ML_TGI=1` during ML platform provisioning |

---

## What aipostex Finds

- **HF TGI fingerprint** via `/info` (model_id, model_type, version, Docker SHA)
- **Unauthenticated generation surface** via `/generate` when the legacy mock is explicitly enabled
- **OpenAI-compatible model listing** via `/v1/models`
- **Operational metrics** via `/metrics` (Prometheus format)
