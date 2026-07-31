---
title: MLflow (ailab-ml)
---

# MLflow (ailab-ml)

## What It Is

MLflow is an open-source platform for managing the ML lifecycle — experiment tracking, model registry, and artifact storage. On the ML platform, it tracks experiments whose run parameters contain hardcoded connection strings, API keys, and tokens. The tracking server is unauthenticated and network-accessible, and the lab now seeds both experiments and registered model versions so `aipostex` can validate deeper registry and artifact workflows.

---

## Installation

Installed as `mluser`:

```bash
pip install --break-system-packages mlflow==2.21.3
```

`--break-system-packages` is required on Ubuntu 24.04 (PEP 668).

---

## Systemd Unit

**Unit:** `mlflow.service`

```ini title="/etc/systemd/system/mlflow.service"
[Service]
User=mluser
ExecStart=/usr/local/bin/mlflow server --host 0.0.0.0 --port 5000 --backend-store-uri sqlite:////opt/mlflow/mlflow.db --default-artifact-root /opt/mlflow/artifacts/
Restart=always
```

!!! note "Four slashes in the SQLite URI"
    `sqlite:////opt/mlflow/mlflow.db` — the first three slashes are the `sqlite:///` scheme prefix, the fourth begins the absolute path `/opt/mlflow/mlflow.db`.

**Unit:** `mlflow-hook-controller.service`

```ini title="/etc/systemd/system/mlflow-hook-controller.service"
[Service]
User=mluser
WorkingDirectory=/home/mluser/projects/mlflow-hook-controller
Environment="MLFLOW_HOOK_TRACKING_URI=http://localhost:5000"
Environment="MLFLOW_HOOK_TAG_KEY=aipostex.hook.url"
ExecStart=/usr/bin/python3 server.py
Restart=always
```

The hook controller has no listener port. It polls the real MLflow model registry, watches
for model-version tags named `aipostex.hook.url`, and POSTs each unique hook URL once.
This models a registry-driven MLOps automation service without adding an invented endpoint
to MLflow itself.

---

## Port & Config

| Parameter | Value |
|---|---|
| Host | `172.16.50.20` |
| Port | `5000` |
| Bind address | `0.0.0.0` |
| Authentication | None |
| Backend store | `sqlite:////opt/mlflow/mlflow.db` |
| Artifact root | `/opt/mlflow/artifacts/` |
| Hook controller tag | `aipostex.hook.url` |

!!! danger "Misconfiguration"
    The tracking server has no authentication. Anyone on the network can browse experiments, inspect run parameters, and download artifacts.

---

## Seed Data

Three experiments with run parameters, metrics, and artifact trees containing embedded credentials:

| Experiment | Highlights |
|---|---|
| `churn-prediction-v2` | PostgreSQL and Snowflake connection strings, Redis feature store reference, model/deployment artifacts |
| `fraud-detection-bert` | PagerDuty key, Kafka host, deployment metadata, multiple candidate and promoted runs |
| `customer-embedding-model` | HuggingFace token, Qdrant linkage, deployment metadata, model card material |

The lab also seeds registered models with versions linked back to real `runs:/<run-id>/model` sources:

| Registered model | Stages |
|---|---|
| `acme-churn-ensemble` | `Staging`, `Production` |
| `acme-fraud-bert` | `Staging`, `Production` |

Credentials are logged as MLflow run parameters and tags, and the registry points back to artifact trees under the tracked runs. This lets `aipostex` validate `enum`, `registry`, `model-versions`, and `model-artifacts` without adding destructive write paths.

---

## What aipostex Finds

- **Experiment enumeration** — The `/api/2.0/mlflow/experiments/search` endpoint lists all experiments without authentication.
- **Run parameters with credentials** — Inspecting individual runs reveals connection strings, API keys, and tokens logged as parameters.
- **Registry exposure** — Registered model search and version enumeration expose model names, stages, version metadata, and `runs:/...` sources.
- **Artifact metadata** — Artifact URIs and paths expose internal storage structure, S3 bucket names, and model/deployment material through `artifacts` and `model-artifacts`.
- **Hook metadata influence** — A gated model-version tag write can be consumed by `mlflow-hook-controller.service`; `aipostex mlflow hook` only upgrades when a nonce-matched callback is observed.

---

## Verification

Confirm MLflow is running:

```bash
curl http://localhost:5000/
```

??? example "Expected response"
    ```
    OK
    ```

List experiments:

```bash
curl http://localhost:5000/api/2.0/mlflow/experiments/search
```

??? example "Expected response"
    JSON listing `churn-prediction-v2`, `fraud-detection-bert`, and `customer-embedding-model`.

List registered models:

```bash
curl http://localhost:5000/api/2.0/mlflow/registered-models/search
```

??? example "Expected response"
    JSON listing `acme-churn-ensemble` and `acme-fraud-bert`.

Check the hook controller:

```bash
systemctl is-active mlflow-hook-controller
```

??? example "Expected response"
    ```
    active
    ```
