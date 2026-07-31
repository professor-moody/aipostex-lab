---
title: TorchServe Mock (ailab-ml)
---

# TorchServe Mock (ailab-ml)

## What It Is

A lightweight mock of PyTorch TorchServe. It reproduces the three-port architecture (inference, management, metrics) with two seeded models plus real-shaped named model registration for handler-execution verification.

---

## Surface

**Inference API (port 8080):**

| Endpoint | Purpose |
|---|---|
| `GET /ping` | Health check |
| `POST /predictions/{model}` | Model inference (`acme-sentiment`, `acme-toxicity`, and any model registered through the management API) |

**Management API (port 8081):**

| Endpoint | Purpose |
|---|---|
| `GET /models` | List registered models |
| `GET /models/{name}` | Model details (workers, batch config) |
| `POST /models?url=&model_name=&initial_workers=&synchronous=` | Register a named model from URL |
| `PUT /models/{name}` | Scale workers |
| `DELETE /models/{name}` | Unregister model |

**Metrics API (port 8082):**

| Endpoint | Purpose |
|---|---|
| `GET /metrics` | Prometheus metrics (inference requests, queue latency, worker count) |

---

## Port & Unit

| Parameter | Value |
|---|---|
| Host | `172.16.50.20` |
| Ports | `8080` (inference), `8081` (management), `8082` (metrics) |
| Unit | `torchserve-mock.service` |
| Runtime | `python3 server.py` |

---

## What aipostex Finds

- **TorchServe fingerprint** via management API `/models`
- **Model enumeration** with worker and batch details
- **Unauthenticated model management** (register, scale, unregister)
- **Registered handler execution** by registering a named model and invoking `POST /predictions/{model}`
- **Prometheus metrics** exposing operational telemetry
