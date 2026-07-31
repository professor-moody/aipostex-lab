# Scenario 08: Credential Chain Exploitation

> ★ **Shown at DEF CON RTV** - part of the guided demo/workshop. [All scenarios](index.md)

**Difficulty:** Advanced
**Time:** ~30 minutes
**Prerequisites:** Complete [Scenario 06](scenario-06.md)
**Target:** Ray on `ailab-ml` -> MLflow gateway on `ailab-ds` -> TGI gateway on `ailab-app`

## Background

In AI infrastructure, credentials rarely exist in isolation. A Ray job runtime environment can
expose tracking credentials for MLflow. MLflow run parameters and tags can then expose the
HuggingFace token used by an inference gateway. This lateral movement through credential reuse is
the guided benchmark chain, and it is the whole point of the estate: each hop's output is the next
hop's key, across trust boundaries.

> **What this chain demonstrates.** This is *credential chaining through gated services within an
> exposed estate*, not network segmentation. The lab is flat: every host is reachable at enumeration
> (the shadow-AI premise). The hops here are **credential-gated**: the MLflow auth gateway
> (`ailab-ds:5000`) and the TGI gateway (`ailab-app:8180`) each require a credential you must loot
> from the prior hop. The separate, *unauthenticated* MLflow backend at `ailab-ml:5000` is the
> exposed-backend path (see [Scenario 06](scenario-06.md)/[10](scenario-10.md)); both are realistic
> surfaces in an open estate. To make the gated hops *network*-enforced (enterprise feel), enable the
> opt-in segmentation toggle in the deployment docs.

### Why the chain matters, hop by hop

- **Hop 1, Ray (`ailab-ml:8265`).** The open dashboard exposes seeded jobs whose `runtime_env`
  leaks `MLFLOW_TRACKING_URI` plus a Basic-auth credential for the MLflow gateway. `ray jobs` lands
  `read-confirmed` because a real looted credential is in the output. This is the credential source
  that starts the chain.
- **Hop 2, MLflow gateway (`ailab-ds:5000`).** The gateway rejects unauthenticated calls; the
  Ray-looted Basic credential unlocks it. Run params are where people log tokens "just to get it
  working," and here that means a HuggingFace token in the `customer-embedding-model` experiment.
  Because MLflow run-search is experiment-scoped, the tool enumerates experiments first, then
  searches across them. `mlflow runs` lands `read-confirmed`.
- **Hop 3, TGI gateway (`ailab-app:8180`).** This is the payoff. The gateway gates `/generate`
  behind a Bearer token, and the MLflow-looted HF token is that Bearer. Reaching it is not just
  reading data, it is using the company's private inference: real, input-dependent model output from
  a stolen credential. `huggingface generate` lands `execution-confirmed`.

## Objective

Demonstrate the guided credential chain: extract a credential from one service and use it to
authenticate to the next service.

## Commands

Open an **engagement session** first: every command then auto-accumulates its findings into the
engagement dossier (`~/engagements/<name>`), so there is nothing to save per-command; your screen
still shows the looted credential and the ready next command.

```bash
aipostex sessions start acme-mlops

# Step 1: Extract MLflow gateway credentials from Ray (read-confirmed)
aipostex ray --target http://172.16.50.20:8265 jobs

# Step 2: Use the Ray-looted Basic credential against MLflow (read-confirmed)
aipostex mlflow --target http://172.16.50.30:5000 \
  --header "Authorization: Basic <ray-looted-basic>" runs --limit 20

# Step 3: Use the MLflow-looted HF token against the TGI gateway (execution-confirmed)
aipostex huggingface --target http://172.16.50.40:8180 \
  --header "Authorization: Bearer <mlflow-looted-hf-token>" \
  generate --prompt "incident response" --force-exploit

# Step 4: Read the chain out of the engagement dossier, then close it
aipostex report view ~/engagements/acme-mlops --chains --commands   # find -> loot -> chain -> reached
aipostex sessions stop
```

*Optional - score coverage against the 170-finding answer key (wants one JSON engagement, so merge the
session's findings first):*

```bash
aipostex engagement merge ~/engagements/acme-mlops/findings.jsonl -o ~/engagement.json
python3 ~/lab/scoring/score.py ~/engagement.json --strict
```

## Expected Finding

**Guided chain: Ray -> MLflow -> HF TGI**
1. Ray runtime environment contains `MLFLOW_TRACKING_URI`, `MLFLOW_TRACKING_USERNAME`, and `MLFLOW_TRACKING_PASSWORD`.
2. The MLflow gateway at `ailab-ds:5000` rejects unauthenticated API calls.
3. The Ray-looted Basic credential grants access to MLflow run metadata.
4. MLflow run params/tags expose `hf_tgi_token`.
5. The TGI gateway at `ailab-app:8180` rejects unauthenticated `/generate` calls.
6. The MLflow-looted HF token grants inference access.
7. **Impact:** one open Ray dashboard leads to authenticated access across two other teams' AI services.

**Additional chain: Kubeflow -> Multi-service access**
1. Kubeflow pipelines contain `HF_TOKEN`, `SNOWFLAKE_CONN_STR`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
2. These credentials enable access to HuggingFace, Snowflake data warehouse, and AWS services
3. **Impact:** Single Kubeflow compromise yields access to 3+ external services

**Additional chain: MLflow -> AWS**
1. MLflow experiments contain AWS credentials in parameters
2. S3 artifact store URIs reveal bucket names and paths
3. **Impact:** Attacker can read/write model artifacts in cloud storage

```json
{
  "finding_type": "credential_chain",
  "source_service": "ray",
  "source_key": "MLFLOW_TRACKING_PASSWORD",
  "intermediate_service": "mlflow",
  "intermediate_host": "172.16.50.30:5000",
  "target_service": "huggingface_tgi_gateway",
  "target_host": "172.16.50.40:8180",
  "chain_length": 3
}
```

**Scoring objective:** collect aipostex findings that show the Ray credential leak, authenticated MLflow read, HF token discovery, and authenticated TGI generation proof.

## Real-World Impact

Credential chaining is how initial access to one ML service escalates to full infrastructure
compromise. AI platforms are particularly vulnerable because data scientists share credentials
across services via environment variables and configuration files. A single insecure Ray cluster or
Kubeflow instance can provide the keys to an organization's entire AI infrastructure, and often
their cloud accounts.

## Follow-On

- [Scenario 09](scenario-09.md): Inject malicious pipeline runs using harvested credentials
- [Scenario 12](scenario-12.md): Combine credential chains into a full campaign
