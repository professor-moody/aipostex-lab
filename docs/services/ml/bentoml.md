---
title: BentoML Mock (ailab-ml)
---

# BentoML Mock (ailab-ml)

## What It Is

A lightweight mock of BentoML's serving API. It exposes service metadata, health, OpenAPI docs, Prometheus metrics, and prediction endpoints with deterministic input-dependent responses.

---

## Surface

| Endpoint | Purpose |
|---|---|
| `GET /` | Service info (name, version, bento_version) |
| `GET /healthz` | Health check |
| `GET /docs.json` | OpenAPI specification |
| `GET /metrics` | Prometheus metrics (request count, duration) |
| `POST /predict` | Input-dependent mock inference (label, confidence, model) |
| `POST /classify` | Input-dependent batch classification route |

---

## Port & Unit

| Parameter | Value |
|---|---|
| Host | `172.16.50.20` |
| Port | `3333` |
| Unit | `bentoml-mock.service` |
| Runtime | `python3 server.py` |

---

## What aipostex Finds

- **BentoML fingerprint** via `/` service info
- **OpenAPI spec** exposing all routes and JSON request schemas via `/docs.json`
- **Prometheus metrics** via `/metrics`
