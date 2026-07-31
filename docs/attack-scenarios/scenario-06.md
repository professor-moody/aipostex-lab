# Scenario 06: ML Platform Credential Harvest

> ★ **Shown at DEF CON RTV** - part of the guided demo/workshop. [All scenarios](index.md)

**Difficulty:** Intermediate
**Time:** ~25 minutes
**Prerequisites:** Complete [Scenario 01](scenario-01.md)
**Target:** ailab-ml:8265 (Ray), ailab-ds:5000 (MLflow auth gateway), ailab-ml:8444 (W&B)

## Background

Enterprise ML platforms use experiment trackers (MLflow, W&B) and distributed compute frameworks
(Ray) to manage model training at scale. These services store API keys, dataset paths, model
artifacts, and environment configurations. When accessible without authentication, they become
treasure troves of credentials.

> **Two MLflow surfaces (flat lab).** This is a flat shadow-AI estate: everything is exposed at
> enumeration. There are two distinct MLflow endpoints: the **gated auth gateway** at
> `ailab-ds:5000` (Basic-auth; reached here with the Ray-looted `ray-pipeline` credential, the
> credential-chained hop) and the **MLflow platform backend** at `ailab-ml:5000` (directly
> reachable, no auth, the exposed backend that [Scenario 10](scenario-10.md) tampers). Direct access
> to the `ailab-ml:5000` backend is **by design** (the estate is exposed), not a gateway bypass; the
> gateway exists to demonstrate credential chaining, not network segmentation. Operators who want a
> segmented/enterprise feel can enable the opt-in segmentation toggle (see the deployment docs).

### Why an attacker cares, service by service

- **Ray (`:8265`)** is the framework a team uses to scale Python ML across a cluster, and the
  dashboard/job-submission API lets anyone who reaches it read every job and submit new ones. Job
  definitions carry `runtime_env`: environment variables, pip configs, working-dir secrets. Teams
  routinely pass downstream credentials through them, so the job history is a credential store, and
  the same API is unauthenticated RCE (submit a job, your code runs). The single most common Ray
  misconfiguration in the wild is exactly this open dashboard (CVE-2023-48022, "ShadowRay").
- **MLflow (`ailab-ds:5000`)** is the standard experiment-tracking and model-registry server. Run
  parameters are a notorious secret sink: people log API tokens, DB DSNs, and HuggingFace tokens as
  run params "just to get it working." The registry also exposes model artifacts. Here it sits
  behind a Basic-auth gateway, and the credential you loot from Ray is what unlocks it, which models
  the common pattern where the tracking server is nominally protected but the protecting credential
  is sprayed through job configs.
- **W&B (`:8444`)** is Weights & Biases, experiment tracking plus an artifact store over a GraphQL
  API. Projects and runs carry API keys and secrets logged as config, so the win is the same shape:
  credential material a team never meant to expose.

### How this connects to the rest of the estate

This is the credential-source stage. The MLflow Basic credential you loot from Ray unlocks the
gateway, and the HF token you loot from an MLflow run param unlocks the TGI inference gateway, which
is the payoff in [Scenario 08](scenario-08.md). One gotcha makes the MLflow read a real challenge:
MLflow's run-search is experiment-scoped, so a bare search with no experiment IDs returns nothing.
The HF token lives in a non-default experiment (`customer-embedding-model`), so the tool enumerates
experiments first, then searches across all of them.

## Objective

Harvest credentials and sensitive configuration from Ray, MLflow, and Weights & Biases.

## Commands

```bash
# Exploit Ray cluster (read-confirmed: the looted MLflow Basic credential is in the output)
aipostex ray --target http://172.16.50.20:8265 jobs

# Enumerate MLflow through the gated auth gateway with the Ray-looted credential
# (read-confirmed: surfaces the HF token from the customer-embedding-model experiment)
aipostex mlflow --target http://172.16.50.30:5000 \
  --header "Authorization: Basic <ray-looted-basic>" runs --limit 20

# Exploit Weights & Biases
aipostex wandb --target http://172.16.50.20:8444 enum

# Surface the seeded W&B credential material for a project
aipostex wandb --target http://172.16.50.20:8444 secrets --entity acme-ml-team --project fraud-detection
```

## Expected Finding

**Ray (ailab-ml:8265):**
- Runtime environment variables: HuggingFace tokens, AWS credentials, database URIs
- Job submission history with embedded secrets
- Cluster configuration revealing internal network topology

**MLflow gateway (ailab-ds:5000):**
- Experiment metadata with API keys in parameters
- Model artifact storage paths (S3 buckets, GCS paths)
- Registered model names revealing business logic

**W&B (ailab-ml:8444):**
- API keys in run configurations
- Sweep parameters containing hyperparameter details
- Artifact references to S3/GCS model storage

Example finding:
```json
{
  "finding_type": "credential",
  "service": "ray",
  "detail": "Runtime env variable",
  "key": "HF_TOKEN",
  "value": "hf_..."
}
```

**Landed grading:** `ray jobs`, `mlflow runs`, and `wandb secrets` all land `read-confirmed` (real
looted credential material in the output). Submitting a bounded Ray job (`ray submit`) would land
`execution-confirmed`, but this scenario is the read/harvest pass.

**Scoring objective:** At least 3 distinct credential types extracted across the three services, including the Ray-looted MLflow credential and the MLflow-looted HF/TGI token.

## Real-World Impact

ML platforms are where all the secrets converge. Data scientists configure environment variables
with API keys, log experiments with credentials in parameters, and store model artifacts in cloud
storage. An attacker with access to these platforms can harvest credentials for cloud providers,
SaaS APIs, and database systems, typically enough to gain broader infrastructure access.

## Follow-On

- [Scenario 08](scenario-08.md): Chain harvested credentials for deeper access
- [Scenario 10](scenario-10.md): Use MLflow/Ray access to tamper with model artifacts
