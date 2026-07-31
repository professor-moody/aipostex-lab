---
title: Ray Job Seeds
---

# Ray Job Seeds

Three Ray jobs are submitted on **ailab-ml** (172.16.50.20, port 8265) by `seed_ray.py`. Each job's `runtime_env.env_vars` contains planted secrets — the same pattern seen when ML teams pass credentials to distributed training jobs via environment variables instead of a secrets manager.

The first two jobs also write deterministic files under `/tmp/ray-lab-artifacts/` and print those paths in their logs, giving `aipostex ray job-logs` and `ray job-artifacts` stable pivot targets.

---

## Job 1: churn-model-retraining

**Team:** `ml-platform`

An ML training pipeline that connects to production databases and cloud services. Writes a deterministic artifact to `/tmp/ray-lab-artifacts/churn-model-retraining/`.

| Environment Variable | Value |
|---|---|
| `DATABASE_URL` | `postgresql://ml_pipeline:MlP1p3l1n3!Pr0d@db-prod-01.acme.internal:5432/ml_features` |
| `REDIS_URL` | `redis://:R3d1sMlC4ch3!@redis-ml.acme.internal:6379/0` |
| `AWS_ACCESS_KEY_ID` | `AKIAFAKERAYML12345678` |
| `AWS_SECRET_ACCESS_KEY` | `FAKE+RayMLSecret/abcdefghijk1234567890` |
| `S3_MODEL_BUCKET` | `s3://acme-ml-prod/ray-training/` |
| `WANDB_API_KEY` | `FAKE_wandb_ray_key_abcdef123456` |
| `HF_TOKEN` | `hf_FAKE_RayTraining_aBcDeFgHiJkLmNoPqRs` |
| `MLFLOW_TRACKING_URI` | `http://localhost:5000` |

---

## Job 2: runtime-env-validator

**Team:** `data-engineering` &nbsp; **Metadata tag:** `seed: runtime-env`

Validates runtime-env submission surfaces. Writes a deterministic artifact to `/tmp/ray-lab-artifacts/runtime-env-validator/` and includes explicit runtime-env markers for the newer `ray runtime-env` flow.

| Environment Variable | Value |
|---|---|
| `SNOWFLAKE_URI` | `snowflake://ray_svc:R4ySvcSn0w!@acme.snowflakecomputing.com/ML/FEATURES` |
| `KAFKA_BOOTSTRAP` | `kafka-prod.acme.internal:9092` |
| `KAFKA_SASL_PASSWORD` | `K4fk4Pr0dP4ss!2024` |
| `DATADOG_API_KEY` | `FAKE_dd_ray_api_key_abcdef1234567890` |
| `SENTRY_DSN` | `https://FAKE_sentry_ray_key@sentry.acme.internal/42` |
| `VAULT_TOKEN` | `hvs.FAKE_ray_vault_token_1234567890abcdef` |
| `AIPOSTEX_RUNTIME_ENV_MARKER` | `enabled-for-lab` |
| `AIPOSTEX_RUNTIME_PIP_HINT` | `requests-safe-marker` |

---

## Job 3: model-serving-canary

**Team:** `ml-ops`

A canary deployment health check for a model serving pipeline.

| Environment Variable | Value |
|---|---|
| `MODEL_REGISTRY_URL` | `http://mlflow.acme.internal:5000` |
| `SELDON_API_KEY` | `seldon_FAKE_api_key_abcdef1234567890` |
| `STRIPE_BILLING_KEY` | `sk_live_FAKE_ray_billing_key_123456` |
| `PD_ROUTING_KEY` | `FAKE_PD_RAY_CANARY_abc123` |

---

## How aipostex Discovers Them

aipostex's Ray module follows a progressive discovery chain:

1. **Dashboard discovery** — Network scanning fingerprints the Ray dashboard on port 8265. The dashboard API requires no authentication.
2. **Job enumeration** — `GET /api/jobs/` lists all submitted jobs with their metadata (name, team, status) and full runtime environment configuration.
3. **Secret extraction** — The `runtime_env.env_vars` field in each job's configuration contains the planted secrets in plain text. aipostex applies credential-matching patterns to extract connection strings, API keys, and tokens.
4. **Job logs** — `ray job-logs` retrieves stdout/stderr from completed jobs, where artifact paths under `/tmp/ray-lab-artifacts/` are printed.
5. **Job artifacts** — `ray job-artifacts` extracts deterministic artifact paths discovered via logs.
6. **Runtime-env validation** — `ray runtime-env` checks for runtime-env submission viability using the `AIPOSTEX_RUNTIME_ENV_MARKER` and `AIPOSTEX_RUNTIME_PIP_HINT` markers seeded in Job 2.

```bash title="Manual verification"
curl -s http://172.16.50.20:8265/api/jobs/ | python3 -m json.tool
```

---

## Sensitive Data Summary

| Category | Count | Examples |
|---|---|---|
| Database connection strings | 2 | PostgreSQL (`ml_pipeline`), Snowflake (`ray_svc`) |
| AWS credentials | 1 pair | `AKIAFAKERAYML12345678` + secret key |
| Cloud storage paths | 1 | `s3://acme-ml-prod/ray-training/` |
| Messaging credentials | 2 | Kafka SASL password, Kafka bootstrap server |
| Monitoring keys | 3 | Datadog API key, Sentry DSN, PagerDuty routing key |
| Secret store tokens | 1 | Vault token (`hvs.FAKE_ray_vault_...`) |
| ML platform keys | 3 | W&B key, HuggingFace token, Seldon API key |
| Payment keys | 1 | Stripe billing key (`sk_live_FAKE_...`) |
| Runtime-env markers | 2 | `AIPOSTEX_RUNTIME_ENV_MARKER`, `AIPOSTEX_RUNTIME_PIP_HINT` |
| Deterministic artifacts | 2 | `/tmp/ray-lab-artifacts/churn-model-retraining/`, `/tmp/ray-lab-artifacts/runtime-env-validator/` |
| Internal hostnames | 4 | `db-prod-01.acme.internal`, `redis-ml.acme.internal`, `kafka-prod.acme.internal`, `mlflow.acme.internal` |
