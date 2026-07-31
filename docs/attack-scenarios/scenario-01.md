# Scenario 01: AI Service Reachability Survey

> ★ **Shown at DEF CON RTV** - part of the guided demo/workshop. [All scenarios](index.md)

**Difficulty:** Beginner
**Time:** ~10 minutes
**Prerequisites:** None
**Target:** All lab hosts (172.16.50.10, .20, .30, .40)

## Background

Before exploiting AI/ML services, an operator needs to map what is running. Enterprise AI
infrastructure sprawls across multiple hosts: model servers, vector databases, experiment
trackers, LLM gateways. A real ML team stands these up when it moves fast, and many land on the
network without segmentation or authentication because the team optimizes for shipping, not for
access control.

### Why an attacker cares

This is the survey that decides the rest of the engagement. Each service here is either a
credential source, a code-execution surface, or a data store, and the fastest paths through the
estate chain them together: one exposed service leaks the credential that unlocks the next. The
discovery pass tells you which of those primitives are actually present and reachable, so you can
pick a lead instead of guessing. The recurring finding in real assessments is not one broken
service, it is how many the team never realized were listening on an internal network with no
gate in front of them.

### How this connects to the rest of the estate

The endpoints this scan surfaces are the entry points for every other scenario. The Ray dashboard
(`ailab-ml:8265`) is the head of the guided credential chain, the LiteLLM proxy (`ailab-ml:4000`)
and the vector stores (`ailab-ml:8000`, `ailab-ds:6333`) are standalone loot, and the MCP server
(`ailab-dev:3000`) is direct code execution. Mapping them first is what lets you move deliberately
from recon to a chosen target.

## Objective

Discover all AI/ML endpoints across the lab network and identify which services are running on
which hosts.

## Commands

```bash
# Network-wide service discovery
aipostex discover network --target 172.16.50.10,172.16.50.20,172.16.50.30,172.16.50.40

# Fingerprint specific hosts for deeper identification
aipostex discover network --target 172.16.50.20 --discovery-only
aipostex discover network --target 172.16.50.10 --discovery-only
```

## Expected Finding

The `discover network` output should identify 29+ AI/ML endpoints across 4 hosts:

- **ailab-dev (172.16.50.10):** Ollama (11434), Jupyter (8888), MCP Server (3000), Gradio (7860),
  MCP Inspector (6274)
- **ailab-ml (172.16.50.20):** ChromaDB (8000), MLflow backend (5000), LiteLLM (4000/4001),
  Ray (8265), HF TEI, vLLM, BentoML, TorchServe, Triton, W&B (8444), Kubeflow (9000), TF Serving
- **ailab-ds (172.16.50.30):** Weaviate (8080), Qdrant (6333), Jupyter (8889), Ollama (11434)
- **ailab-app (172.16.50.40):** LangServe (8090), Streamlit (8501), HF TGI gateway (8180),
  A2A Agents (8100-8103)

**Scoring objective:** The finding JSON includes service tags like `"tags": ["ollama", "chromadb", "ray", ...]` for each host.

## Real-World Impact

Unauthenticated AI service discovery is the first step in any AI infrastructure assessment. Many
organizations do not realize how many ML endpoints are exposed on their internal networks. Model
serving APIs, experiment trackers, vector databases, and LLM proxies often lack basic access
controls, and each one that answers is a lead an attacker can develop.

## Follow-On

- [Scenario 02](scenario-02.md): Explore the LLM gateway found on ailab-ml
- [Scenario 03](scenario-03.md): Fingerprint the HuggingFace inference servers
