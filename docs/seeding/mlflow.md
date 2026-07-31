---
title: MLflow Experiment Seeds
---

# MLflow Experiment Seeds

Three MLflow experiments are seeded on **ailab-ml** (172.16.50.20, port 5000) by `seed_mlflow.py`. Each experiment contains multiple runs with connection strings, internal hostnames, and cloud credentials planted in run parameters and artifact metadata.

---

## Experiments

### churn-prediction-v2

3 runs. A churn model comparison across XGBoost and LightGBM with different data sources.

**Sensitive data in parameters:**

| Parameter | Value |
|---|---|
| `training_data` (run 1) | `postgresql://ds_readonly:DsR34d0nly!Pr0d@db-prod-01.acme.internal:5432/acme_prod` |
| `training_data` (run 3) | `snowflake://ds_team:Sn0wfl4keDs!@acme.snowflakecomputing.com/ANALYTICS/CHURN` |
| `feature_store` | `redis://feature-store.acme.internal:6379/2` |
| `training_data` (run 2) | `s3://acme-ml-data/churn/train_v3.parquet` |

**Artifact metadata:**

- Model path: `s3://acme-ml-models/churn-prediction-v2/`
- Serving endpoint: `seldon.acme.internal:8080/churn`
- Monitoring dashboard: `grafana.acme.internal/d/churn-model`

**Tags:** Engineer emails (`jane.doe@acme.corp`, `alex.rivera@acme.corp`), dataset versions, promotion status.

---

### fraud-detection-bert

3 runs. A BERT fine-tuning pipeline for fraud detection with GPU cost tracking.

**Sensitive data in parameters:**

| Parameter | Value |
|---|---|
| `training_data` | `s3://acme-ml-data/fraud/labeled_transactions_v2.parquet` / `v3.parquet` |
| `gpu_instance` | `p4d.24xlarge`, `g5.2xlarge` (reveals AWS infrastructure) |
| `aws_account` (run 3) | `123456789012` |

**Artifact metadata:**

- Model registry: `s3://acme-ml-models/fraud-detection-bert/`
- Kafka input: `kafka-prod.acme.internal:9092/raw-transactions`
- PagerDuty key: `FAKE_PD_FRAUD_abc123`

**Tags:** Engineer email (`bob.wilson@acme.corp`), GPU cost per run ($87–$1,048), promotion status.

---

### customer-embedding-model

2 runs. Fine-tuning embedding models for product recommendations.

**Sensitive data in parameters:**

| Parameter | Value |
|---|---|
| `training_data` (run 1) | `postgresql://ds_readonly:DsR34d0nly!Pr0d@db-prod-01.acme.internal:5432/acme_prod` |
| `training_data` (run 2) | `snowflake://ds_team:Sn0wfl4keDs!@acme.snowflakecomputing.com/ANALYTICS/CUSTOMERS` |
| `qdrant_host` (run 2) | `172.16.50.30:6333` (cross-host reference to ailab-ds) |
| `qdrant_collection` | `product-embeddings` |

**Artifact metadata:**

- Vector DB: `qdrant://172.16.50.30:6333/product-embeddings`
- Model artifacts: `s3://acme-ml-models/customer-embeddings/bge-large-v1/`
- HuggingFace token: `hf_FAKE_aBcDeFgHiJkLmNoPqRsTuVwXyZ123`

**Tags:** Engineer email (`priya.patel@acme.corp`), use case, promotion status.

---

## Registered Models

The seeder also creates MLflow registry content so `aipostex` can validate `registry`, `model-versions`, and `model-artifacts` workflows.

| Registered Model | Stages | Source |
|---|---|---|
| `acme-churn-ensemble` | `Staging`, `Production` | `runs:/<run-id>/model` from `churn-prediction-v2` runs |
| `acme-fraud-bert` | `Staging`, `Production` | `runs:/<run-id>/model` from `fraud-detection-bert` runs |

Each model has at least 2 versions linked back to real runs via concrete `runs:/<run-id>/<artifact-path>` sources. The artifact trees contain model/config metadata and deployment material that `model-artifacts` follow-ons can extract.

---

## What aipostex Finds

aipostex's MLflow module discovers planted data through a progressive chain:

1. **Experiment enumeration** — The MLflow REST API lists all experiments without authentication (`GET /api/2.0/mlflow/experiments/search`).
2. **Run parameter extraction** — Each run's parameters are retrieved via `POST /api/2.0/mlflow/runs/search`. Connection strings and credentials are embedded directly in parameter values like `training_data` and `feature_store`.
3. **Artifact metadata** — Deployment config artifacts stored with each run contain S3 paths, internal hostnames, PagerDuty keys, and HuggingFace tokens.
4. **Registry exposure** — `GET /api/2.0/mlflow/registered-models/search` lists `acme-churn-ensemble` and `acme-fraud-bert` with their version metadata, stages, and `runs:/` sources.
5. **Model versions** — Version enumeration reveals staging/production assignments and the specific run IDs backing each version.
6. **Model artifacts** — Artifact URIs from versions point to `model/MLmodel`, `model/config`, and deployment material under the tracked runs.
7. **Cross-host references** — Parameters reference the data science server (`172.16.50.30:6333`), internal databases (`db-prod-01.acme.internal`), and other internal services, revealing infrastructure beyond the ML platform.

---

## Sensitive Data Summary

| Category | Instances |
|---|---|
| PostgreSQL connection strings | 3 (with credentials) |
| Snowflake connection strings | 2 (with credentials) |
| S3 bucket paths | 5+ |
| Internal hostnames | 6+ (seldon, kafka, grafana, redis, db-prod, Qdrant) |
| PagerDuty keys | 1 (in artifact metadata) |
| HuggingFace tokens | 1 (in artifact metadata) |
| AWS account IDs | 1 |
| Cross-host references | 2 (ailab-ds Qdrant at 172.16.50.30) |
| Registered models | 2 (`acme-churn-ensemble`, `acme-fraud-bert`) |
| Model versions | 4 (2 per model, linked to real runs) |
