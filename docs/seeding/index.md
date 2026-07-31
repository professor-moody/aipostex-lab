---
title: Seeded Data Overview
---

# Seeded Data Overview

Every piece of sensitive data in the lab is intentionally planted, tracked, and scored. This section documents what was seeded, where it lives, and how aipostex is expected to find it.

All planted data uses obviously fake values (`FAKE` prefixes, `ACME Corp`, invalid SSN checksums) but follows realistic formats — AWS keys start with `AKIA`, connection strings use valid `postgresql://` syntax, JWTs have proper header structure. aipostex's detection patterns match them the same way they'd match real credentials.

---

## Summary

| Source | Host | Items | Categories |
|---|---|---|---|
| [Filesystem artifacts](filesystem.md) | ailab-dev | 35+ | API keys, MCP configs, AWS/GCP creds, training data, shell history |
| [Ollama system prompts](ollama-prompts.md) | ailab-dev | 2 models | DB creds, JWT tokens, service accounts, webhooks |
| [ChromaDB](vector-dbs.md#chromadb-ailab-ml-port-8000) | ailab-ml | 4 collections, 25+ docs | SSNs, credit cards, DB creds, financials, prompt injections |
| [MLflow](mlflow.md) | ailab-ml | 3 experiments, 2 registered models | Connection strings, HF tokens, PagerDuty keys, model versions |
| [Ray](ray.md) | ailab-ml | 3 jobs | AWS keys, Snowflake, Kafka, Vault, Stripe, runtime-env markers, artifact paths |
| LiteLLM config | ailab-ml | 1 file | Aggregated API keys (4 providers) |
| W&B mock | ailab-ml | Project/run fixtures | API keys, DB URLs, telemetry metadata |
| Serving mocks | ailab-ml | Kubeflow, TF Serving, framework mocks | Pipeline and model-serving metadata |
| [Weaviate](vector-dbs.md#weaviate-ailab-ds-port-8080) | ailab-ds | 3 classes, 12+ objects | SSNs, salaries, API keys, board strategy |
| [Qdrant](vector-dbs.md#qdrant-ailab-ds-port-6333) | ailab-ds | 3 collections, 10+ points | Pentest findings, IR playbooks, license admin |
| pgvector | ailab-ds | Public tables | PII, credentials, salaries, internal docs |
| A2A fixtures | ailab-app | Agent cards and task history | Agent metadata and task-history credentials |
| Kubernetes secrets | ailab-k8s | `ml-prod` / `ml-system` namespaces | HF registry tokens, service-account tokens, image-pull creds |
| Jupyter notebooks | both dev/ds | 2 notebooks | API keys, DB creds, connection strings |

---

## By Host

### ailab-dev (172.16.50.10)

The developer workstation produces the most findings. Filesystem artifacts alone account for 35+ items — `.env` files, MCP configs, cached tokens, shell history, training data, and Modelfiles. The two custom Ollama models add another ~15 credentials embedded in system prompts.

### ailab-ml (172.16.50.20)

The ML platform's value is concentrated in network services rather than filesystem sprawl. ChromaDB holds 25+ documents across 4 collections. MLflow stores connection strings and tokens in experiment parameters and artifact metadata, plus registered models (`acme-churn-ensemble`, `acme-fraud-bert`) with versions linked to real `runs:/` sources. Ray jobs expose secrets via runtime environment variables and write deterministic artifacts to `/tmp/ray-lab-artifacts/` for `job-artifacts` and `runtime-env` validation. The LiteLLM config aggregates API keys for 4 providers into a single YAML file. W&B, Kubeflow, TF Serving, and serving-framework mocks add model-platform metadata coverage.

### ailab-ds (172.16.50.30)

The data science server uses different tools (Weaviate, Qdrant, and pgvector) to demonstrate tool fragmentation across teams. Weaviate holds SSNs, salaries, and API keys. Qdrant's `security-findings` collection contains a pentest report describing the lab itself — a deliberately meta finding. pgvector adds SQL-backed embedding tables with PII, credentials, and operational notes.

### ailab-app (172.16.50.40)

The shared app host adds A2A agent cards, seeded task history, and validation surfaces for active workflows. These fixtures are intentionally small, but they let the scoring and contract layers validate agent metadata, task-history leakage, and post-exploitation callback behavior.

### ailab-k8s (172.16.50.50)

The Kubernetes node runs a Docker + k3s pair — a vulnerable cluster on `:6443` (anonymous RBAC) alongside a hardened one on `:6444`. The vulnerable apiserver lets an unauthenticated caller read Secrets from the `ml-prod` and `ml-system` namespaces: HuggingFace registry tokens, service-account tokens, and image-pull credentials. It demonstrates the "one misconfigured RBAC binding exposes the whole namespace" failure mode and gives the `k8s` module real `enum` / `rbac-probe` / `secret-read` targets.

---

## Noise Collections

Every vector database includes at least one collection of benign, non-sensitive content alongside the sensitive collections. These test aipostex's ability to differentiate signal from noise. See [Noise Collections](noise.md) for details.

---

## Manifest

All **170 planted findings** are tracked in `scoring/manifest.json`. The [scoring system](../scoring/scoring.md) validates aipostex output against this manifest in both standard and strict modes, with false-positive detection against noise collections.
