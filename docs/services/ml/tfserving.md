---
title: TF Serving Mock (ailab-ml)
---

# TF Serving Mock (ailab-ml)

## What It Is

A lightweight mock of TensorFlow Serving's REST API. It reproduces the model status, metadata, prediction, and metrics endpoints that `aipostex` probes, with two seeded models exposing signature definitions, version information, and deterministic input-dependent predictions.

---

## Surface

| Endpoint | Purpose |
|---|---|
| `GET /v1/models` | Returns 404 with structured error (matches real TF Serving behavior) |
| `GET /v1/models/{name}` | Model version status |
| `GET /v1/models/{name}/metadata` | Signature definitions with tensor shapes |
| `POST /v1/models/{name}:predict` | Input-dependent prediction endpoint |
| `GET /monitoring/prometheus/metrics` | Prometheus metrics |

---

## Port & Unit

| Parameter | Value |
|---|---|
| Host | `172.16.50.20` |
| Port | `8501` |
| Unit | `tfserving-mock.service` |
| Runtime | `python3 server.py` |

---

## Seeded Data

- **acme-fraud-scorer**: versions 1 and 2, DT_FLOAT 32-dim input -> 1-dim fraud_probability output; prediction score changes with numeric input values
- **acme-embeddings**: version 1, DT_STRING input -> 128-dim DT_FLOAT output; embedding vector changes with input text

---

## What aipostex Finds

- **TF Serving fingerprint** via model status endpoints
- **2 models exposed** with full signature definitions and tensor shape metadata
- **Model version enumeration** revealing deployment history
- **Prometheus metrics** with request counts and latency data
