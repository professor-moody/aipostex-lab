# Scenario 09: ML Pipeline Credential Harvest

> ★ **Shown at DEF CON RTV** - part of the guided demo/workshop. [All scenarios](index.md)

**Difficulty:** Advanced
**Time:** ~30 minutes
**Prerequisites:** Complete [Scenario 08](scenario-08.md)
**Target:** ailab-ml:9000 (Kubeflow)

## Background

Kubeflow Pipelines is the Kubernetes-native ML pipeline platform (v1beta1 and v2beta1 APIs). Each
pipeline defines a series of steps: data ingestion, preprocessing, training, evaluation, deployment.
Pipeline runs accept parameters that control behavior. In the lab it runs on `ailab-ml:9000`,
unauthenticated by design, which is how open pipeline APIs tend to look in the field.

### Why an attacker cares

Two things at once. First, pipelines execute code, so an open pipeline API is a path to running your
own steps in the cluster: it is a code-execution surface, not just a config store. Second, the
pipeline parameters are a credential sink. Teams pass tokens and cloud keys as run parameters so a
step can reach HuggingFace, Snowflake, or S3, and those parameters are readable straight off the
completed runs. That combination is why compromising the pipeline system is supply-chain compromise
at the ML workflow level: you can read the secrets that move data and models, and you can inject
steps that alter what the pipeline produces.

### How this connects to the rest of the estate

Enumeration here is the recon step that precedes the Ray RCE finale in the multi-vector campaign. The
credentials you pull from pipeline parameters (`HF_TOKEN`, `SNOWFLAKE_CONN_STR`, the AWS pair) are
the same kind of reusable loot the credential-chain scenarios turn into access to other services, so
this scenario both stands alone and feeds [Scenario 12](scenario-12.md).

## Objective

Enumerate Kubeflow pipelines, extract credentials from pipeline parameters, and understand the
injection surface the parameters expose.

## Commands

```bash
# Enumerate pipelines and their parameters
aipostex kubeflow --target 172.16.50.20:9000 enum

# Fingerprint to understand the pipeline structure
aipostex discover network --target 172.16.50.20:9000 --discovery-only
```

## Expected Finding

**Pipeline Enumeration:**
- `churn-model-retraining`: Parameters include `HF_TOKEN`, `SNOWFLAKE_CONN_STR`
- `fraud-detection-bert`: Parameters include `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

**Existing Runs:**
- 3 seeded runs (2 completed, 1 running); the credential values live on the pipeline parameters
- Run logs may contain additional credentials or internal URLs

**Experiments:**
- `Default` and `Production` experiments
- Experiment metadata reveals team structure and workflow patterns

**Notebooks:**
- 2 Kubeflow notebooks running in the `kubeflow` namespace
- Notebooks have network access to other cluster services

Example finding:
```json
{
  "finding_type": "credential",
  "service": "kubeflow",
  "detail": "Pipeline parameter contains HuggingFace token",
  "pipeline": "churn-model-retraining",
  "key": "HF_TOKEN",
  "value": "hf_FAKE_aBcDeFgHiJkLmNoPqRsTuVwXyZ123"
}
```

**Landed grading:** `kubeflow enum` surfaces the pipeline parameters and their credential material as
a read finding. The value of the finding is the reusable credentials it yields; the injection risk it
documents is the downstream impact those parameters enable.

**Scoring objective:** Extract all 4 credentials from Kubeflow pipeline parameters (HF_TOKEN, SNOWFLAKE_CONN_STR, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY).

## Real-World Impact

Kubeflow pipelines are the automation backbone of enterprise ML. Compromising the pipeline system
means an attacker can:
- **Poison training data** by modifying data source parameters
- **Exfiltrate models** by redirecting output storage
- **Harvest credentials** that are passed as pipeline parameters
- **Backdoor models** by injecting malicious steps into training pipelines

This is supply chain compromise at the ML workflow level.

## Follow-On

- [Scenario 10](scenario-10.md): Use pipeline access to tamper with model artifacts
- [Scenario 12](scenario-12.md): Chain pipeline injection into a full campaign
