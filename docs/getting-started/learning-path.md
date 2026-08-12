---
title: Learning Path
---

# Learning Path

There are two ways through the lab. Follow the **difficulty tracks** for a linear ramp from
first-time user to advanced operator, or jump to a **skill domain** to drill one area (recon,
RAG, agents, detect/evade, …). Either way, the [Techniques](../techniques/index.md) pages teach
the transferable methods behind the scenarios so they carry to real engagements.

## Difficulty tracks

### Track 1: Foundations (Beginner)

**Goal:** Understand what AI/ML services look like on a network and how to identify them.

| Step | Scenario | What You Learn |
|------|----------|---------------|
| 1 | [AI Service Reachability Survey](../attack-scenarios/scenario-01.md) | Network discovery, service enumeration, port mapping |
| 2 | [LLM Gateway Config Extraction](../attack-scenarios/scenario-02.md) | API key extraction from LLM proxies |
| 3 | [Inference Server Fingerprinting](../attack-scenarios/scenario-03.md) | Model identification, version detection, metrics endpoints |

**Outcome:** You can map an AI infrastructure, identify service types, and extract basic configuration data.

### Track 2: Exploitation (Intermediate)

**Goal:** Extract sensitive data from AI services and understand common misconfigurations.

| Step | Scenario | What You Learn |
|------|----------|---------------|
| 1 | [Vector Database PII Extraction](../attack-scenarios/scenario-04.md) | RAG data stores, embedding extraction, PII discovery |
| 2 | [Jupyter Remote Code Execution](../attack-scenarios/scenario-05.md) | Notebook exploitation, environment variable leaks |
| 3 | [ML Platform Credential Harvest](../attack-scenarios/scenario-06.md) | Experiment tracker/compute framework credential extraction |
| 4 | [RAG Pipeline Poisoning](../attack-scenarios/scenario-07.md) | Write access to vector stores, data integrity attacks |

**Outcome:** You can exploit the most common AI/ML service misconfigurations and understand their real-world impact.

### Track 3: Advanced Operations (Advanced)

**Goal:** Chain vulnerabilities across services and execute full infrastructure campaigns.

| Step | Scenario | What You Learn |
|------|----------|---------------|
| 1 | [Credential Chain Exploitation](../attack-scenarios/scenario-08.md) | Lateral movement via credential reuse |
| 2 | [ML Pipeline Run Injection](../attack-scenarios/scenario-09.md) | Kubeflow pipeline compromise, parameter injection |
| 3 | [Supply Chain Model Tampering](../attack-scenarios/scenario-10.md) | Model registry attacks, artifact integrity |
| 4 | [MCP Tool Infection](../attack-scenarios/scenario-11.md) | AI agent tool enumeration, new attack surfaces |
| 5 | [Multi-Vector Campaign](../attack-scenarios/scenario-12.md) | Full kill chain across all hosts |
| 6 (capstone) | [Privilege Escalation → Model-Weight Theft](../attack-scenarios/scenario-13.md) | Service-account RCE, sudo/GTFOBins privesc, GGUF model-weight exfiltration |

**Outcome:** You can plan and execute multi-stage AI infrastructure assessments and generate comprehensive reports.

### Track 4: Model & Agent Layer (Intermediate → Advanced)

**Goal:** Attack the model/agent-conversation layer — bespoke agents, black-box RAG, multi-agent
systems, and the model itself — and operate against a real detection stack.

| Step | Scenario | What You Learn |
|------|----------|---------------|
| 1 | [Bespoke Agent — Fingerprint/Enum/Extract](../attack-scenarios/scenario-14.md) | Attacking a custom `/chat` app: model fingerprint, tool enum, system-prompt extraction |
| 2 | [Behavioral Model Fingerprinting](../attack-scenarios/scenario-20.md) | Masked vs un-masked model ID; contradiction de-masking; honest `unknown` |
| 3 | [Embedding Endpoint Recon](../attack-scenarios/scenario-19.md) | TEI fingerprinting, unauthenticated vector access |
| 4 | [Agent Guardrail Triage → Prompt Injection](../attack-scenarios/scenario-18.md) | Guardrail posture triage; input-filter and output-filter bypass |
| 5 | [Black-box RAG — Citation Recon & Poisoning](../attack-scenarios/scenario-15.md) | RAG through the app; citation recon; verified indirect prompt injection |
| 6 | [Rogue Agents & MCP Privilege Escalation](../attack-scenarios/scenario-17.md) | Multi-agent A2A rogue registration; MCP sandbox escape / SSTI |
| 7 | [Detect & Evade — Real Elastic](../attack-scenarios/scenario-16.md) | Operating against a real SIEM; the detect/evade loop |
| 8 (capstone) | [Full Agent-Layer Campaign](../attack-scenarios/scenario-21.md) | End-to-end chain across agent + RAG + detection |

**Outcome:** You can assess a model/agent stack black-box — fingerprint the model, bypass its
guardrails, poison its RAG, subvert its peers — and know exactly what a SOC sees while you do it.

## Skill domains

Prefer to drill one skill area? Each scenario is grouped by its primary domain (several cross over).

| Domain | Scenarios | Core skill |
|--------|-----------|-----------|
| **Recon & Fingerprinting** | 01, 03, 19, 20 | Discovery, service + embedding + behavioral model fingerprinting |
| **Infrastructure & Credential Harvest** | 02, 06, 09, 10 | Gateways, experiment trackers, pipelines, model registries |
| **Vector DB & RAG** | 04, 07, 15 | Data stores, poisoning, black-box RAG through the app |
| **Code Execution (Jupyter / MCP)** | 05, 11 | Notebook RCE, MCP tool infection & new surfaces |
| **Agents, Prompt Injection & Multi-Agent** | 14, 17, 18, 21 | Bespoke agents, guardrail bypass, A2A, campaigns |
| **Detect & Evade** | 16 | Operating against a real Elastic detection stack |
| **Chaining, Privesc & Exfiltration** | 08, 12, 13 | Lateral movement, full kill chains, privesc → model theft |

## Suggested Order

Working linearly, the numbered scenarios **01–13** are the classic infrastructure ramp (each
builds on access from the previous; 13 is the infra capstone). **14–21** are the model/agent layer
(Track 4), best taken after Foundations so you have recon fundamentals first.

**Time estimates:**

| Track | Scenarios | Total Time |
|-------|-----------|-----------|
| Foundations | 01–03 | ~35 min |
| Exploitation | 04–07 | ~90 min |
| Advanced | 08–13 | ~3.5 hrs |
| Model & Agent Layer | 14–21 | ~3 hrs |
| **Full lab** | **01–21** | **~8.5 hrs** |

## Scoring

After completing scenarios, validate your findings against the lab scoring system. Run your scenarios
inside an engagement (`aipostex sessions start work`) so everything collects in one place, then score
it:

```bash
aipostex engagement merge ~/engagements/work/findings.jsonl -o ~/engagement.json
python3 ~/lab/scoring/score.py ~/engagement.json --strict
```

The lab contains **170 seeded findings** across all services. See the [scoring rubric](../scoring/scoring.md) for the full breakdown.
