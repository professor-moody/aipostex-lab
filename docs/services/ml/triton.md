---
title: Triton Mock (ailab-ml)
---

# Triton Mock (ailab-ml)

## What It Is

A lightweight mock of NVIDIA Triton Inference Server implementing the KServe v2 protocol. It exposes server metadata, model management, inference, shared memory endpoints, and an unloaded repository model for lifecycle verification.

---

## Surface

| Endpoint | Purpose |
|---|---|
| `GET /v2` | Server metadata (name, version, extensions) |
| `GET /v2/health/ready` | Readiness probe |
| `GET /v2/health/live` | Liveness probe |
| `GET /v2/models` | Loaded model listing (`acme-fraud-detector`, `acme-embeddings`, plus `aipostex-injected` after load) |
| `GET /v2/models/{name}` | Model metadata (inputs, outputs, platform) |
| `GET /v2/models/{name}/config` | Model configuration (backend, instances, max batch) |
| `POST /v2/models/{name}/infer` | Inference endpoint |
| `POST /v2/repository/index` | Repository index (all models with state, including initially unloaded `aipostex-injected`) |
| `POST /v2/repository/models/{name}/load` | Load repository model |
| `POST /v2/repository/models/{name}/unload` | Unload repository model |
| `GET /v2/systemsharedmemory/status` | System shared memory regions |
| `GET /v2/cudasharedmemory/status` | CUDA shared memory regions |

---

## Port & Unit

| Parameter | Value |
|---|---|
| Host | `172.16.50.20` |
| Port | `8500` |
| Unit | `triton-mock.service` |
| Runtime | `python3 server.py` |

---

## What aipostex Finds

- **Triton fingerprint** via `/v2` server metadata
- **Model enumeration** with full input/output tensor definitions
- **Unauthenticated model management** (load, unload via repository API)
- **Post-load inference verification** for `aipostex-injected`
- **Shared memory status** exposing system internals
