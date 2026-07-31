---
title: HF TEI Mock (ailab-ml)
---

# HF TEI Mock (ailab-ml)

## What It Is

A lightweight mock of Hugging Face Text Embeddings Inference. It exposes the model metadata and embedding-style API routes that `aipostex` expects to see, without introducing heavyweight serving infrastructure.

---

## Surface

| Endpoint | Purpose |
|---|---|
| `GET /info` | Embedding model metadata (model_id, model_type, version, sha) |
| `POST /embed` | Embedding generation (returns 2D float array) |
| `POST /rerank` | Passage reranking |
| `GET /metrics` | Prometheus metrics (request count, embed count) |

---

## Port & Unit

| Parameter | Value |
|---|---|
| Host | `172.16.50.20` |
| Port | `8181` |
| Unit | `hf-tei-mock.service` |
| Runtime | `python3 server.py` |

---

## What aipostex Finds

- **HF TEI fingerprint** via `/info` (model_id, model_type, version, Docker SHA)
- **Unauthenticated embedding surface** via `/embed` (2D float arrays)
- **Reranking capability** via `/rerank`
- **Operational metrics** via `/metrics` (Prometheus format)

