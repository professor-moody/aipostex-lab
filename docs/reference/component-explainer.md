---
title: Component & Service Explainer (presenter study + narration)
---

# Component & service explainer

The estate is a shadow-AI platform: the services a real ML team stands up when they move fast.
This page is the presenter's study sheet and live narration source. For **every** service it answers
the same five questions, so you can explain *what it is*, *why it's exposed*, *why an attacker wants it*,
*how it hands off to the next hop*, and *what the tool actually proves* — not just what to type.

**How to read the "landed" column** — aipostex grades every finding on an honest ladder:
`reachable` (I can talk to it) → `influenced` (it accepted my input) → `read-confirmed` (I read real
secret/data) → `execution-confirmed` (I ran code / real inference) → `takeover-capable` (I hold
model/identity material). The kill-chain stage is `recon → access → impact → own`.

---

## The credential chain (the tactic spine)

The four hops attendees run. Each hop's *output is the next hop's key* — that is the whole point:
one exposed service leaks the credential that unlocks the next, across trust boundaries.

### 1. Ray (dashboard :8265) — distributed compute

- **What it is:** Ray is the de-facto framework for scaling Python ML — training, tuning, batch
  inference — across a cluster. The **dashboard/job-submission API on :8265** lets you submit and
  inspect jobs.
- **Estate & exposure:** real Ray, dashboard bound to `0.0.0.0` with **no authentication** — the single
  most common Ray misconfiguration in the wild (CVE-2023-48022 "ShadowRay" territory). Anyone who can
  reach the port can read every job and submit new ones.
- **Why an attacker cares:** job definitions carry `runtime_env` — environment variables, pip configs,
  working-dir secrets. Teams routinely pass credentials to downstream services (MLflow, S3, registries)
  through them. It's also unauth **RCE**: submit a job, your code runs on the cluster.
- **Hands off to:** the seeded jobs' `runtime_env` leaks `MLFLOW_TRACKING_URI` + a **Basic-auth
  credential** for the MLflow gateway → hop 2.
- **Tool proves:** `ray jobs` → `read-confirmed` (real looted credential in the output). `ray submit`
  → `execution-confirmed` (a bounded job actually runs).

### 2. MLflow (auth gateway :5000 on ailab-ds) — experiment & model tracking

- **What it is:** MLflow is the standard experiment-tracking + model-registry server. Teams log every
  training run — parameters, metrics, artifacts, and the **model registry** of promoted models.
- **Estate & exposure:** a **real MLflow behind a Basic-auth gateway** (the credential-chain's *gated*
  hop). The Basic credential you looted from Ray unlocks it. This models the common pattern where the
  tracking server is "protected" but the protecting credential is sprayed through job configs.
- **Why an attacker cares:** run parameters are a notorious secret sink — people log API tokens, DB
  DSNs, and **HuggingFace tokens** as run params "just to get it working." The registry also exposes
  model artifacts (weights, `MLmodel` files).
- **The gotcha that makes it a real challenge:** MLflow's run-search is **experiment-scoped**. A bare
  `runs/search` with no experiment IDs returns *nothing*. The HF token lives in a **non-default**
  experiment (`customer-embedding-model`), so the tool must enumerate experiments first, then search
  across all of them. (This is the exact bug that once broke the chain — now fixed and regression-tested.)
- **Hands off to:** a run parameter leaks a **HuggingFace token** → hop 3.
- **Tool proves:** `mlflow runs` → `read-confirmed` (surfaces the HF token from the named experiment).
  `mlflow bulk-download --model <name>` → `takeover-capable` (pulls real `MLmodel` + weight bytes from
  the registry).

### 3. HuggingFace TGI gateway (:8180 on ailab-app) — the inference gateway

- **What it is:** Text Generation Inference (TGI) is HuggingFace's production LLM serving stack. The
  gateway fronts an internal model and gates `/generate` behind a **Bearer token**.
- **Estate & exposure:** a **real gateway** — `/generate` proxies to LiteLLM → Ollama and returns
  genuine model output (`"inference":"real"`), with an honest 502 on upstream failure. The looted HF
  token is the Bearer.
- **Why an attacker cares:** the token is a live credential to the company's private inference. You are
  not just reading data — you are *using* the internal model (LLM-jacking, prompt exfiltration, abuse).
- **Hands off to:** this is the payoff. Real inference from a stolen credential = the capability a threat
  actor actually seeks.
- **Tool proves:** `huggingface generate` → `execution-confirmed` (real, input-dependent inference), or
  `huggingface model-download` → `takeover-capable` (bounded model-weight bytes over the Hub-compatible
  resolve path).

### The closer — `report view` (dossier recap)

Not a service — the operator payoff. `aipostex report view <dir> --credentials --chains` renders the
loot you captured: every credential (raw, never masked), every chain hop, ready for the engagement
write-up. Even on this compact chain it shows what a real assessment produces.

---

## Data & memory services (finish-early extras)

### Vector DBs — ChromaDB (:8000), Weaviate (:8080), Qdrant (:6333)

- **What they are:** the memory layer of RAG apps — they store embedded documents an LLM retrieves at
  query time.
- **Exposure:** all three run real, unauthenticated. RAG stores are new and rarely access-controlled.
- **Why an attacker cares:** two directions. **Exfil** — the documents are real corporate data (PII,
  secrets, internal knowledge). **Poison** — write a malicious document and the LLM will retrieve and
  act on it (indirect prompt injection that persists).
- **Tool proves:** `search-sensitive` → `read-confirmed` (real PII/secrets out). `inject --collection
  <c> --payload <p> --verify-persist` → `influenced`/`takeover-capable` (poison written and confirmed
  to persist on re-read).

### Ollama (:11434 on ailab-dev/ds) — local model server

- **What it is:** the easiest way to run LLMs locally; ubiquitous on developer boxes.
- **Exposure:** real Ollama bound to `0.0.0.0`, no auth.
- **Why an attacker cares:** two real wins and one honest dead-end. **System-prompt mining** — custom
  models carry system prompts that leak internal instructions/credentials. **Behavioral poison proof.**
  But **model-weight theft is genuinely blocked over the network**: Ollama serves no blob download
  (`GET /api/blobs` is not exposed), and on disk the store is `0750 ollama:ollama`, unreadable by a
  low-priv foothold. That honest negative is the *setup* for the privesc extra-credit path.
- **Tool proves:** `prompts` → `read-confirmed` (system-prompt cred mining). `poison-verify` →
  `influenced` (greedy-decode divergence confirms an injected system prompt changed behavior).
  `exfiltrate` → honestly `reachable` with the complete picture: "no HTTP download + 0750 on disk →
  weight theft requires local privesc" (→ the extra-credit branch).

### MCP server (:3000 on ailab-dev) — agent tool bridge

- **What it is:** Model Context Protocol is the standard that lets an LLM/agent call tools. This is a
  **real server built on the official MCP Python SDK** (FastMCP), replacing a hand-written mock so the
  tool is exercised against true SDK behavior.
- **Exposure:** it exposes an `execute_command` tool with no sandboxing — the archetypal "we gave the
  agent a shell" mistake. Runs as the `devuser` service account.
- **Why an attacker cares:** direct **RCE** as devuser. And it's the pivot for the Ollama weight theft:
  MCP RCE → `sudo` misconfig → root → read the 0750 blob store.
- **Tool proves:** `env-extract` → `read-confirmed` (env secrets). `poison --mode cmd-inject` /
  `shell` → `execution-confirmed` (real command execution).

---

## Extra-credit: the privesc → model-weight theft branch

The heavier "own" capability, discoverable from the Ollama negative. **What it is:** a chain of a real
service-account RCE plus a classic Linux privesc misconfig. **The setup:** `devuser` (the MCP service
account) is deliberately least-privileged — *not* in the `ollama` group, so the 0750 weight store is
genuinely unreadable. But an admin left an `ollama-maintenance` helper that `devuser` may run with
**passwordless sudo** — and left the helper **world-writable** (a GTFOBins-class misconfig). **The
attack:** MCP RCE (as devuser) → overwrite the world-writable helper with a payload → `sudo` it →
**root** → read `/usr/share/ollama/.ollama/models/blobs` → real GGUF weight bytes. **Tool proves:**
driven by `mcp shell`/`cmd-inject` → `execution-confirmed` (uid=0 + real weight bytes off disk).
GTFOBins alternatives (tar/systemd/cron sudo entries) are the generic version; the AI angle — stealing
the *model* — is the point. **Full step-by-step with the readable `mcp shell` escalation:**
[Scenario 13](../attack-scenarios/scenario-13.md).

---

## Agent & gateway services (workshop / talk own-depth)

### A2A agents (:8103 real; :8100-8102 scored) — agent-to-agent protocol

- **What it is:** Google's Agent-to-Agent protocol (JSON-RPC 2.0) — how autonomous agents discover and
  delegate to each other via unauthenticated **agent cards**.
- **Exposure:** `:8103` is a **real a2a-sdk agent** (offensive verbs target this); `:8100-8102` are
  deterministic scored-benchmark mocks (for the measurement layer). Agent cards are unauthenticated
  discovery documents by design.
- **Why an attacker cares:** an agent that ingests caller-supplied agent cards is **hijackable**
  (card-spoof); delegation and sender identity can be forged.
- **Tool proves — the "accepted ≠ exploited" lesson:** `card-spoof` is `influenced` when the agent
  merely *accepts* the spoofed card, and only `takeover-capable` when an out-of-band callback
  (`--callback-url`) confirms the agent actually fetched it. Honest grading in action.

### LiteLLM / OpenAI-compatible gateway (:4000/:4001 on ailab-ml) — LLM proxy

- **What it is:** LiteLLM is the standard proxy that gives one OpenAI-compatible API over many model
  backends. Teams centralize keys and routing here.
- **Exposure:** real LiteLLM; the master key is siftable and the proxy fronts real generation.
- **Why an attacker cares:** **LLM-jacking** (bill someone else's compute), key theft, config
  disclosure (which backends/keys exist), and real inference through the looted master key.
- **Tool proves:** `config-extract` → `read-confirmed`; `openai-compat generate` (with looted key) →
  `execution-confirmed` (real input-dependent inference).

### W&B (:8444) — experiment tracking (secrets)

- **What it is:** Weights & Biases — experiment tracking + artifact store; a GraphQL API.
- **Exposure:** protocol mock (GraphQL, seeded), unauthenticated by design.
- **Why an attacker cares:** projects/runs carry API keys and secrets logged as config.
- **Tool proves:** `secrets --entity <e> --project <p>` → surfaces seeded credential material.

### Kubeflow (:9000) — ML pipelines

- **What it is:** the Kubernetes-native ML pipeline platform (v1beta1 + v2beta1 APIs).
- **Exposure:** protocol mock, unauthenticated pipeline API.
- **Why an attacker cares:** pipelines execute code; an open pipeline API is a path to running your
  steps in the cluster.
- **Tool proves:** `pipelines` enumerates the accessible pipelines (the recon step before the Ray RCE
  finale).

### Jupyter (:8888) — notebooks

- **What it is:** the ubiquitous data-science notebook server.
- **Exposure:** real JupyterLab, **token auth disabled** — an unauthenticated notebook server is
  arbitrary code execution.
- **Why an attacker cares:** start a kernel = **code exec**; notebooks are full of hardcoded secrets.
- **Tool proves:** `notebooks --mine-secrets` → `read-confirmed` (secrets mined from cells);
  `start-kernel` → `influenced` (a kernel is created — honest: the tool created it but did not prove
  arbitrary exec through it in that step).

### k3s / Kubernetes (:6443 vuln / :6444 secure) — the cluster [advanced/optional]

- **What it is:** the orchestration layer everything runs on.
- **Exposure:** `:6443` anonymous-open (the weak kill-chain); `:6444` is 401-enforced as an honesty
  control. An advanced/optional path rather than a first-run scenario.
- **Why an attacker cares:** anonymous read of secrets, service-account token theft, pod-exec = cluster
  takeover.
- **Tool proves:** `secret-read --all-namespaces` → `read-confirmed`; `sa-loot` → `execution-confirmed` (the
  stolen SA proves a write the foothold couldn't); `pod-exec` → `takeover-capable` (uid=0 root in a pod).

### GPU serving fixtures — Triton (:8500), TorchServe (:8081), TF-Serving (:8501), BentoML (:3333), vLLM (:8182)

- **What they are:** the production model-serving stacks (KServe/Triton/TorchServe/BentoML/vLLM).
- **Exposure:** protocol fixtures on this CPU lab (no GPU driver yet — the host's discrete GPU is the
  future/optional path to make them real). Unauthenticated management APIs by design.
- **Why an attacker cares:** unauthenticated **model registration** = load an attacker-controlled model
  from a URL (SSRF) whose handler runs code = **RCE**. This is a real, current serving-RCE class.
- **Tool proves — with an honest caveat:** `torchserve register` / `triton model-load` / `tfserving`
  & `bentoml predict` reach `execution-confirmed` via the real unauth-registration + SSRF lifecycle and
  an input-dependence probe. On the CPU lab the handler *output* is protocol-simulated (real attack,
  simulated model); on a real GPU deployment the same flow is genuine model execution. Say this out
  loud — it's the tool's honesty thesis applied to the lab itself.
