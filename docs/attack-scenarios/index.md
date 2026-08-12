# Attack Scenarios

Structured CTF-style challenges for the aipostex lab. Each scenario targets a specific attack surface in the lab environment and provides the exact commands, expected output, and real-world context.

## Difficulty Levels

| Level | Description |
|---|---|
| **Beginner** | Single-module, no authentication, direct output |
| **Intermediate** | Multi-step exploitation, credential extraction, data exfiltration |
| **Advanced** | Chained attacks across services, credential pivoting, active exploitation |

## Scenario Index

**★ = shown at the DEF CON RTV demo / workshop** (the "con path" — start here). The unmarked
scenarios are self-serve extra credit across the wider estate.

| # | Scenario | Difficulty | Target | Time |
|---|---|---|---|---|
| 01 | ★ [AI Service Reachability Survey](scenario-01.md) | Beginner | All hosts | ~10 min |
| 02 | ★ [LLM Gateway Config Extraction](scenario-02.md) | Beginner | ailab-ml:4000 | ~10 min |
| 03 | [Inference Server Fingerprinting](scenario-03.md) | Beginner | app TGI gateway + ML TEI | ~15 min |
| 04 | ★ [Vector Database PII Extraction](scenario-04.md) | Intermediate | ailab-ml:8000, ailab-ds:6333 | ~20 min |
| 05 | ★ [Jupyter Remote Code Execution](scenario-05.md) | Intermediate | ailab-dev:8888, ailab-ds:8889 | ~20 min |
| 06 | ★ [ML Platform Credential Harvest](scenario-06.md) | Intermediate | ailab-ml:8265/5000/8444 | ~25 min |
| 07 | [RAG Pipeline Poisoning](scenario-07.md) | Intermediate | ailab-ds:8080, ailab-dev:11434 | ~30 min |
| 08 | ★ [Credential Chain Exploitation](scenario-08.md) | Advanced | Ray -> MLflow -> HF TGI | ~30 min |
| 09 | ★ [ML Pipeline Credential Harvest](scenario-09.md) | Advanced | ailab-ml:9000 | ~30 min |
| 10 | ★ [Supply Chain Model Tampering](scenario-10.md) | Advanced | ailab-ml:8265/5000 | ~35 min |
| 11 | ★ [MCP Tool Infection](scenario-11.md) | Advanced | ailab-dev:3000 | ~30 min |
| 12 | [Multi-Vector Campaign](scenario-12.md) | Advanced | All hosts | ~60 min |
| 13 | ★ [Privesc → Model-Weight Theft](scenario-13.md) | Advanced | ailab-dev:11434 → :3000 → root | ~20 min |
| 14 | [Bespoke Agent — Fingerprint/Enum/Extract](scenario-14.md) | Intermediate | ailab-app:8110 | ~20 min |
| 15 | [Black-box RAG — Citation Recon & Poisoning](scenario-15.md) | Intermediate | ailab-ds:8091 | ~25 min |
| 16 | [Detect & Evade — Working Against Real Elastic](scenario-16.md) | Intermediate | ailab-siem:5601 (obs) | ~25 min |
| 17 | [Rogue Agents & MCP Privilege Escalation](scenario-17.md) | Advanced | ailab-app:8104, ailab-dev:3002 | ~25 min |
| 18 | [Agent Guardrail Triage → Prompt Injection](scenario-18.md) | Intermediate | ailab-app:8110 | ~20 min |
| 19 | [Embedding Endpoint Recon](scenario-19.md) | Beginner–Intermediate | ailab-ml:8181 | ~15 min |
| 20 | [Behavioral Model Fingerprinting — Masked vs Un-masked](scenario-20.md) | Intermediate | ailab-ml:4000 | ~15 min |
| 21 | [Full Agent-Layer Campaign](scenario-21.md) | Advanced | ailab-app:8110, ailab-ds:8091 (obs ailab-siem) | ~40 min |

## Progression Tracks

**Discovery & Recon** → Scenarios 01–03
Start here. Learn aipostex's discovery and fingerprinting modules.

**Exploitation** → Scenarios 04–07
Extract data, harvest credentials, identify misconfiguration.

**Chained Attacks** → Scenarios 08–13
Pivot across services using discovered credentials, inject pipelines, run a full campaign, and
escalate to root to steal the model itself.

**Model & Agent Layer** → Scenarios 14–21
Attack the model/agent-conversation layer: bespoke agents, behavioral model fingerprinting,
embedding recon, guardrail bypass, black-box RAG, multi-agent A2A, MCP privesc, detect/evade, and a
full agent-layer campaign. See the [Techniques](../techniques/index.md) pages for the transferable
methods.

## Prerequisites

- SSH access to the attack box (ailab-attack / 172.16.50.99)
- `aipostex` binary installed on the attack box
- Lab services running (verify with `bash lab-scripts/verify-lab.sh`)
