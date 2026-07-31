---
title: Kubeflow Mock (ailab-ml)
---

# Kubeflow Mock (ailab-ml)

## What It Is

A lightweight mock of the Kubeflow Pipelines API. It reproduces the pipeline, run, experiment, and notebook endpoints that `aipostex` probes, with seeded data containing credentials in pipeline parameters (HF tokens, Snowflake connection strings, AWS keys).

---

## Surface

| Endpoint | Purpose |
|---|---|
| `GET /pipeline/` | Dashboard HTML stub |
| `GET /pipeline/apis/v1beta1/pipelines` | List pipelines with parameters |
| `GET /pipeline/apis/v1beta1/runs` | List pipeline runs |
| `GET /pipeline/apis/v1beta1/experiments` | List experiments |
| `GET /notebook/api/namespaces/{ns}/notebooks` | List Kubeflow notebooks |
| `POST /pipeline/apis/v1beta1/runs` | Submit a pipeline run |

---

## Port & Unit

| Parameter | Value |
|---|---|
| Host | `172.16.50.20` |
| Port | `9000` |
| Unit | `kubeflow-mock.service` |
| Runtime | `python3 server.py` |

---

## Seeded Data

- **2 pipelines** with credentials in parameters (HF_TOKEN, SNOWFLAKE_CONN_STR, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
- **3 completed runs** with full parameter values
- **2 experiments** (production-training, staging-experiments)
- **2 notebooks** in the kubeflow-user namespace

---

## What aipostex Finds

- **Kubeflow fingerprint** via `/pipeline/` dashboard
- **4 credentials** in pipeline parameters: HF token, Snowflake connection string, AWS access key, AWS secret key
- **Pipeline enumeration** with run history and experiment metadata
- **Notebook listing** revealing active computing environments
