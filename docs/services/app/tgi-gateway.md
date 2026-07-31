---
title: HF TGI Gateway (ailab-app)
---

# HF TGI Gateway (ailab-app)

## What It Is

A protocol-real Hugging Face TGI-facing gateway for the guided credential chain. Discovery
endpoints remain reachable, while `/generate` requires the HuggingFace token found in MLflow
run params/tags.

This models a common production shape: TGI itself stays simple, and auth is enforced by a
fronting inference gateway.

## Surface

| Endpoint | Purpose |
|---|---|
| `GET /health` | Basic health check |
| `GET /info` | TGI model metadata |
| `GET /v1/models` | OpenAI-compatible model listing |
| `GET /metrics` | Prometheus-style telemetry |
| `GET /acme-tgi-lab/resolve/main/<file>` | Hub-compatible bounded model artifact reads |
| `POST /generate` | Auth-gated text generation |

## Port & Unit

| Parameter | Value |
|---|---|
| Host | `172.16.50.40` |
| Port | `8180` |
| Unit | `tgi-gateway.service` |
| Runtime | `python3 server.py` |
| Required header | `Authorization: Bearer <HF token from MLflow>` |

## Guided Chain Role

1. Ray leaks the MLflow Basic credential.
2. MLflow exposes the HF/TGI token in run params/tags.
3. The TGI gateway rejects missing or wrong tokens.
4. The TGI gateway accepts the MLflow-looted HF token.

The gateway also serves a tiny Hub-compatible `resolve` surface for `acme-tgi-lab`
so `aipostex huggingface model-download --hub-base http://172.16.50.40:8180`
can prove bounded config and weight artifact reads without contacting the public Hub.
