---
title: Ray (ailab-ml)
---

# Ray (ailab-ml)

## What It Is

Ray is a distributed computing framework for scaling ML workloads. On the ML platform, it runs in head-node mode with the dashboard exposed to the network. Three submitted jobs have secrets planted in their runtime environment variables, and the lab now includes deterministic artifact-path and runtime-env markers so `aipostex` can validate the newer jobs-to-logs-to-artifacts-to-runtime-env chain.

---

## Installation

Installed as `mluser`:

```bash
pip install --break-system-packages "ray[default]==2.44.1"
```

`--break-system-packages` is required on Ubuntu 24.04 (PEP 668).

---

## Systemd Unit

**Unit:** `ray.service`

```ini title="/etc/systemd/system/ray.service"
[Service]
User=mluser
ExecStart=/home/mluser/.local/bin/ray start --head --block --dashboard-host=0.0.0.0 --dashboard-port=8265
Restart=always
```

!!! danger "Misconfiguration"
    The dashboard is bound to `0.0.0.0` with no authentication. Anyone on the network can view submitted jobs, including their full runtime environment variables.

---

## Port & Config

| Parameter | Value |
|---|---|
| Host | `172.16.50.20` |
| Port | `8265` (dashboard) |
| Bind address | `0.0.0.0` |
| Authentication | None |
| Mode | Head node |

---

## Seed Data

Three jobs are submitted via `seed_ray.py`, each with secrets planted in `runtime_env` environment variables:

### Job 1: `churn-model-retraining`

| Variable | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | `AKIAFAKERAYML12345678` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `DATABASE_URL` | PostgreSQL connection string with credentials |
| `REDIS_URL` | Redis connection string with credentials |
| `WANDB_API_KEY` | Weights & Biases API key |
| `HF_TOKEN` | HuggingFace token |

### Job 2: `runtime-env-validator`

| Variable | Value |
|---|---|
| `SNOWFLAKE_URI` | Snowflake connection URI with credentials |
| `KAFKA_SASL_PASSWORD` | Kafka SASL authentication password |
| `DATADOG_API_KEY` | Datadog API key |
| `VAULT_TOKEN` | HashiCorp Vault token |
| `AIPOSTEX_RUNTIME_ENV_MARKER` | runtime-env proof marker |
| `AIPOSTEX_RUNTIME_PIP_HINT` | bounded runtime package marker |

### Job 3: `model-serving-canary`

| Variable | Value |
|---|---|
| `SELDON_API_KEY` | Seldon deployment API key |
| `STRIPE_BILLING_KEY` | Stripe billing API key |
| `PAGERDUTY_ROUTING_KEY` | PagerDuty event routing key |

The first two jobs also write deterministic files under `/tmp/ray-lab-artifacts/` and print those paths in their logs so `aipostex ray job-artifacts` has a stable pivot target.

---

## What aipostex Finds

- **Dashboard discovery** — The Ray dashboard at port `8265` is unauthenticated and network-accessible.
- **Job enumeration** — The `/api/jobs/` endpoint lists all submitted jobs with their metadata.
- **Environment variable secrets** — Each job's `runtime_env` contains credentials passed as environment variables, accessible via the jobs API.
- **Bounded log and artifact pivots** — Job logs expose deterministic artifact paths for `job-logs` and `job-artifacts`.
- **Runtime-env validation** — Seeded runtime markers make it obvious when a bounded runtime-env proof path is working as intended.

---

## Verification

Confirm Ray is running:

```bash
curl http://localhost:8265/api/version
```

??? example "Expected response"
    ```json
    {"version": "2.44.1", ...}
    ```

List submitted jobs:

```bash
curl http://localhost:8265/api/jobs/
```

??? example "Expected response"
    JSON listing `churn-model-retraining`, `runtime-env-validator`, and `model-serving-canary` with their `runtime_env` details.
