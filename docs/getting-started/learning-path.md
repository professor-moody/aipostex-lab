---
title: Learning Path
---

# Learning Path

Three progression tracks for getting the most out of the lab, from first-time users to advanced operators.

## Track 1: Foundations (Beginner)

**Goal:** Understand what AI/ML services look like on a network and how to identify them.

| Step | Scenario | What You Learn |
|------|----------|---------------|
| 1 | [AI Service Reachability Survey](../attack-scenarios/scenario-01.md) | Network discovery, service enumeration, port mapping |
| 2 | [LLM Gateway Config Extraction](../attack-scenarios/scenario-02.md) | API key extraction from LLM proxies |
| 3 | [Inference Server Fingerprinting](../attack-scenarios/scenario-03.md) | Model identification, version detection, metrics endpoints |

**Outcome:** You can map an AI infrastructure, identify service types, and extract basic configuration data.

---

## Track 2: Exploitation (Intermediate)

**Goal:** Extract sensitive data from AI services and understand common misconfigurations.

| Step | Scenario | What You Learn |
|------|----------|---------------|
| 1 | [Vector Database PII Extraction](../attack-scenarios/scenario-04.md) | RAG data stores, embedding extraction, PII discovery |
| 2 | [Jupyter Remote Code Execution](../attack-scenarios/scenario-05.md) | Notebook exploitation, environment variable leaks |
| 3 | [ML Platform Credential Harvest](../attack-scenarios/scenario-06.md) | Experiment tracker/compute framework credential extraction |
| 4 | [RAG Pipeline Poisoning](../attack-scenarios/scenario-07.md) | Write access to vector stores, data integrity attacks |

**Outcome:** You can exploit the most common AI/ML service misconfigurations and understand their real-world impact.

---

## Track 3: Advanced Operations (Advanced)

**Goal:** Chain vulnerabilities across services and execute full campaigns.

| Step | Scenario | What You Learn |
|------|----------|---------------|
| 1 | [Credential Chain Exploitation](../attack-scenarios/scenario-08.md) | Lateral movement via credential reuse |
| 2 | [ML Pipeline Run Injection](../attack-scenarios/scenario-09.md) | Kubeflow pipeline compromise, parameter injection |
| 3 | [Supply Chain Model Tampering](../attack-scenarios/scenario-10.md) | Model registry attacks, artifact integrity |
| 4 | [MCP Tool Infection](../attack-scenarios/scenario-11.md) | AI agent tool enumeration, new attack surfaces |
| 5 | [Multi-Vector Campaign](../attack-scenarios/scenario-12.md) | Full kill chain across all hosts |
| 6 (capstone) | [Privilege Escalation → Model-Weight Theft](../attack-scenarios/scenario-13.md) | Service-account RCE, sudo/GTFOBins privesc, GGUF model-weight exfiltration |

**Outcome:** You can plan and execute multi-stage AI infrastructure assessments and generate comprehensive reports.

---

## Suggested Order

If you're working through everything linearly, the numbered scenarios (01–13) are already in recommended order. Each builds on skills and access from previous scenarios; Scenario 13 is the capstone privesc → model-weight-theft branch that follows Scenario 11.

**Time estimates:**

| Track | Scenarios | Total Time |
|-------|-----------|-----------|
| Foundations | 01–03 | ~35 min |
| Exploitation | 04–07 | ~90 min |
| Advanced | 08–13 | ~3.5 hrs |
| **Full campaign** | **01–13** | **~5.5 hrs** |

## Scoring

After completing scenarios, validate your findings against the lab scoring system. Run your scenarios
inside an engagement (`aipostex sessions start work`) so everything collects in one place, then score
it:

```bash
aipostex engagement merge ~/engagements/work/findings.jsonl -o ~/engagement.json
python3 ~/lab/scoring/score.py ~/engagement.json --strict
```

The lab contains **170 seeded findings** across all services. See the [scoring rubric](../scoring/scoring.md) for the full breakdown.
