---
title: vLLM Mock (ailab-ml)
---

# vLLM Mock (ailab-ml)

## What It Is

A lightweight mock of a vLLM-style OpenAI-compatible inference server. It complements LiteLLM by giving the lab a direct vLLM fingerprint target on the ML platform host.

---

## Surface

| Endpoint | Purpose |
|---|---|
| `GET /health` | Basic health check |
| `GET /v1/models` | OpenAI-compatible model list |
| `POST /v1/completions` | Fake completion response |
| `POST /v1/chat/completions` | OpenAI-compatible chat completion response |

---

## Port & Unit

| Parameter | Value |
|---|---|
| Host | `172.16.50.20` |
| Port | `8182` |
| Unit | `vllm-mock.service` |
| Runtime | `python3 server.py` |

---

## What aipostex Finds

- **vLLM fingerprint** via OpenAI-compatible model listing
- **Unauthenticated inference** via `/v1/completions` and `/v1/chat/completions`
