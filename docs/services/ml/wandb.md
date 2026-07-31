---
title: W&B Mock (ailab-ml)
---

# W&B Mock (ailab-ml)

## What It Is

A lightweight mock of a self-hosted Weights & Biases server. It exposes viewer info, project listing, run details with seeded credentials in config, and artifact metadata through the W&B GraphQL API.

---

## Surface

| Endpoint | Purpose |
|---|---|
| `GET /healthz` | Health check (version, status) |
| `POST /graphql` query `Viewer` | Viewer info (username, entity, teams) |
| `POST /graphql` query `Projects` | Project listing (churn-prediction, fraud-detection) |
| `POST /graphql` query `Runs` | Runs with JSON-string config and summaryMetrics containing seeded secrets |
| `POST /graphql` query `ArtifactTypeArtifactCollections` | Artifact listing (model, dataset types) |

---

## Port & Unit

| Parameter | Value |
|---|---|
| Host | `172.16.50.20` |
| Port | `8444` |
| Unit | `wandb-mock.service` |
| Runtime | `python3 server.py` |

---

## Seeded Data

Run configs contain credentials:

- WANDB_API_KEY, OPENAI_API_KEY, HF_TOKEN
- AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
- DATABASE_URL, ANTHROPIC_API_KEY

---

## What aipostex Finds

- **W&B fingerprint** via `/graphql` viewer query and `/healthz` support signal
- **Credentials in run configs** (API keys, cloud credentials, database URIs)
- **Project and artifact enumeration** revealing model lineage
