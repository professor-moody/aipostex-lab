# Scoring System

Validates aipostex output against the lab's planted data manifest — the answer key of all 170 sensitive findings seeded across the target VMs. It also tracks strict service inventory coverage across 12 strict-required services on `ailab-app`, `ailab-ml`, and `ailab-ds`: 5 `detection-only` services and 7 additional `exploitable` services. Measures what the tool found, what it missed, whether it flagged noise as sensitive, and optionally whether the operator workflow contract is still intact.

For live workshop waves, the default human-readable report is intentionally non-spoiler: it shows coverage, missed counts, categories, service inventory, false positives, and contract status without dumping exact missed secret values. Use `--verbose` only when you intentionally want the after-action/take-home answer-key view.

---

## Usage

```bash
python3 lab-scripts/scoring/score.py <output.json> [options]
python3 lab-scripts/scoring/score.py ~/lab-results/              --strict
python3 lab-scripts/scoring/score.py scan.json ollama.json qdrant.json --strict --contracts
```

The script accepts one or more JSON files, or a directory containing JSON files. When multiple inputs are given, all findings are merged before scoring. This lets you run each aipostex module separately and score the combined results in one pass.

The manifest (`manifest.json`) is loaded from the same directory as the script by default.

---

## Modes

### Standard Mode (default)

Substring matching — checks whether each planted value appears anywhere in the aipostex output JSON, regardless of which module or host produced it.

```bash
python3 lab-scripts/scoring/score.py scan-results.json
```

Fast and forgiving. Good for initial development and quick sanity checks. A planted value like `Sup3rS3cretDB` counts as found if it appears anywhere in the output, even if aipostex attributed it to the wrong host or module.

### Strict Mode

Structured matching — each planted value must appear in a finding that also references the correct host (by IP or hostname) **and** the correct source module/type. Additionally runs false-positive detection against noise collections and enforces strict service inventory coverage.

```bash
python3 lab-scripts/scoring/score.py scan-results.json --strict
```

Use strict mode to validate that aipostex correctly attributes findings to the right service and host, not just that it saw the string somewhere. Findings tagged to `ailab-dev` match the same as `172.16.50.10`. In strict mode, missing any of the 12 strict-required services or reporting findings from the lab's noise collections causes a failing exit status even though they do not change the 170-sensitive-finding denominator.

The strict service inventory currently includes:

- 5 `detection-only` services: LangServe, Streamlit, HF TGI gateway, HF TEI, and vLLM
- 7 additional `exploitable` services: BentoML, TorchServe, Triton, pgvector, W&B, Kubeflow, and TF Serving

### Contract Mode

Workflow and proof validation — checks the manifest's contract expectations against the provided output:

- `metadata.workflow`
- `metadata.evidence`
- `stage`
- `landed`
- seeded workflow markers such as Ray artifact paths, MLflow registry names, and Gradio file refs

```bash
python3 lab-scripts/scoring/score.py results.json --strict --contracts
```

This mode is especially useful for regression testing after CLI UX or exploit-workflow changes.

---

## Options

| Flag | Default | Description |
|---|---|---|
| `--threshold` | `80` | Minimum coverage percentage to pass (exit 0) |
| `--verbose`, `-v` | off | Show each missed item with its expected location |
| `--strict` | off | Enable structured matching + false-positive detection |
| `--contracts` | off | Validate workflow/proof contract expectations from the manifest (a contract marked `required` fails if no matching finding is present) |
| `--rrr` | off | Validate the RRR honesty matrix: fail on landed over-claims, and on uncovered surfaces that claim above `reachable` |
| `--rrr-require-covered` | off | Implies `--rrr` and additionally fails if **any** surface is unclassified (uncovered) in the RRR matrix |
| `--json` | off | Output the full report object as JSON instead of human-readable text. This contains answer-key-derived detail and is intended for CI/after-action use. |
| `--manifest` | `manifest.json` (same dir as script) | Path to an alternate manifest file |

---

## Categories Scored

The manifest organises planted findings into these categories:

| Category | Count | Where it's planted |
|---|---|---|
| `api_keys` | 57 | Filesystem, notebooks, vector DBs, LiteLLM, W&B, pgvector, serving mocks |
| `credentials` | 39 | Ollama prompts, filesystem, vector DBs, notebooks, Ray, pgvector |
| `mlflow_data` | 11 | MLflow experiments (connection strings, S3 paths, internal hosts) |
| `ray_data` | 12 | Ray job runtime environment variables |
| `pii` | 15 | ChromaDB, Weaviate, pgvector (SSNs, credit card fragments, passport numbers) |
| `prompt_injection` | 3 | ChromaDB (stored injection payloads) |
| `financial` | 2 | ChromaDB (revenue figures, M&A data) |
| `salary_data` | 8 | Weaviate and pgvector (employee names + compensation) |
| `cloud_credentials` | 2 | Filesystem (GCP client secret, refresh token) |
| `jwt_tokens` | 1 | Ollama system prompt |
| `webhooks` | 2 | Ollama system prompt (Slack webhook URLs) |
| `wandb_data` | 8 | W&B mock projects and runs |
| `a2a_data` | 3 | A2A task history fixtures |
| `kubeflow_data` | 4 | Kubeflow pipeline fixtures |
| `tfserving_data` | 2 | TF Serving mock metadata |

---

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | Coverage meets or exceeds the threshold |
| `1` | Coverage is below the threshold, strict service inventory validation failed, strict mode reported false positives, or contract validation failed |
| `2` | Error (bad input, missing files, invalid JSON) |

---

## False-Positive Detection (Strict Mode)

In strict mode, the scorer also checks whether any aipostex findings reference data from the lab's noise collections:

| Database | Noise Collection |
|---|---|
| ChromaDB | `public-documentation` |
| Weaviate | `PublicKnowledge` |
| Qdrant | `public-faq` |

These collections contain only non-sensitive public content. If aipostex reports findings from them, those are flagged as false positives in the report. This tests the tool's ability to differentiate sensitive data from benign public information.

---

## Example Output

```text
============================================================
  aipostex Lab Scoring Report (Standard Mode)
============================================================

  Overall Coverage: 89.3%
  Found: 151 / 170 planted items
  Missed: 18

  By Category:
  --------------------------------------------------------
  api_keys               #################...  87.7%  (50/57)
  cloud_credentials      ####################  100.0%  (2/2)
  credentials            ##################..  92.3%  (36/39)
  financial              ####################  100.0%  (2/2)
  jwt_tokens             ####################  100.0%  (1/1)
  mlflow_data            ##################..  90.9%  (10/11)
  pii                    ################....  80.0%  (12/15)
  prompt_injection       ####################  100.0%  (3/3)
  ray_data               #################...  83.3%  (10/12)
  salary_data            ##################..  87.5%  (7/8)
  webhooks               ####################  100.0%  (2/2)
  wandb_data             ##################..  87.5%  (7/8)
  a2a_data               ####################  100.0%  (3/3)
  kubeflow_data          ####################  100.0%  (4/4)
  tfserving_data         ####################  100.0%  (2/2)

  PASS: Coverage 89.3% >= 80.0% threshold
```

With `--verbose`, each missed item is listed with its expected host and location:

```text
  Missed Items:
  --------------------------------------------------------
    [api_keys] sk-proj-FAKE-rag-pipeline-key-9876543210         (172.16.50.10 / projects/rag-pipeline/.env)
    [api_keys] gsk_FAKE_groq_key_abcdefghijklmnopqrstuvwx      (172.16.50.10 / projects/rag-pipeline/.env)
    ...
```

With `--strict`, the false-positive section is appended:

```text
  Service Inventory:
  --------------------------------------------------------
  Service inventory coverage: 100.0%  (12/12)

  False Positives: 0 (no noise collection findings)
```

With `--contracts`, a contract summary is also included:

```text
  Contract Checks:
  --------------------------------------------------------
  Passed: 4  Failed: 0  Skipped: 2
    [PASSED ] Ray job artifacts contract (matched=1)
    [PASSED ] Gradio file chain contract (matched=1)
```

---

## Typical Workflow

```bash
# 1. Create a results directory
mkdir -p ~/lab-results

# 2. Run aipostex modules and collect output
aipostex discover network \
    --target 172.16.50.10,172.16.50.20,172.16.50.30,172.16.50.40 \
    --ports 3000,4000,4001,5000,6274,6333,7860,8000,8080,8090,8180,8181,8182,8265,8501,8888,8889,11434 \
    --format json > ~/lab-results/discover-network.json

aipostex ollama --target http://172.16.50.10:11434 prompts \
    --format json > ~/lab-results/ollama-prompts.json

aipostex vectordb --target http://172.16.50.30:8080 --type weaviate search-sensitive \
    --format json > ~/lab-results/weaviate.json

# ... run additional modules as needed ...

# 3. Score the entire directory at once (live-wave, non-spoiler output)
python3 lab-scripts/scoring/score.py ~/lab-results/

# 4. Strict mode with hostname matching and false-positive detection
python3 lab-scripts/scoring/score.py ~/lab-results/ --strict --threshold 70

# 5. After-action/take-home detailed missed-item view
python3 lab-scripts/scoring/score.py ~/lab-results/ --strict --verbose

# 6. Machine-readable output for CI / after-action automation
python3 lab-scripts/scoring/score.py ~/lab-results/ --json > report.json

# 7. Validate workflow/proof contracts too
python3 lab-scripts/scoring/score.py ~/lab-results/ --strict --contracts
```
