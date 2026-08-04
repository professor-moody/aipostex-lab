---
title: Services Overview
---

# Services Overview

The default verifier checks **29 service endpoints** (excludes opt-in and k8s deep checks) across the target and operator VMs. The matrix below also includes opt-in post-exploitation and auxiliary ports. Every service runs natively via systemd with intentionally weak or missing authentication.

---

## Port & Service Matrix

| Host | IP | Port | Service | Systemd Unit |
|---|---|---|---|---|
| ailab-dev | 172.16.50.10 | 11434 | Ollama | `ollama.service` |
| ailab-dev | 172.16.50.10 | 8888 | Jupyter Lab | `jupyter.service` |
| ailab-dev | 172.16.50.10 | 3000 | MCP Server | `acme-mcp.service` |
| ailab-dev | 172.16.50.10 | 7860 | Gradio Chatbot | `gradio-chat.service` |
| ailab-dev | 172.16.50.10 | 6274 | MCP Inspector | `mcp-inspector.service` |
| ailab-ml | 172.16.50.20 | 8000 | ChromaDB | `chromadb.service` |
| ailab-ml | 172.16.50.20 | 5000 | MLflow | `mlflow.service` |
| ailab-ml | 172.16.50.20 | 4000 | LiteLLM | `litellm.service` |
| ailab-ml | 172.16.50.20 | 4001 | LiteLLM (authed) | `litellm-authed.service` |
| ailab-ml | 172.16.50.20 | 8265 | Ray | `ray.service` |
| ailab-app | 172.16.50.40 | 8180 | HF TGI gateway | `tgi-gateway.service` |
| ailab-ml | 172.16.50.20 | 8181 | HF TEI mock | `hf-tei-mock.service` |
| ailab-ml | 172.16.50.20 | 8182 | vLLM mock | `vllm-mock.service` |
| ailab-ml | 172.16.50.20 | 3333 | BentoML mock | `bentoml-mock.service` |
| ailab-ml | 172.16.50.20 | 8081 | TorchServe mock | `torchserve-mock.service` |
| ailab-ml | 172.16.50.20 | 8082 | TorchServe metrics | `torchserve-mock.service` |
| ailab-ml | 172.16.50.20 | 8500 | Triton mock | `triton-mock.service` |
| ailab-ml | 172.16.50.20 | 8444 | W&B mock | `wandb-mock.service` |
| ailab-ml | 172.16.50.20 | 9000 | Kubeflow mock | `kubeflow-mock.service` |
| ailab-ml | 172.16.50.20 | 8501 | TF Serving mock | `tfserving-mock.service` |
| ailab-ds | 172.16.50.30 | 11434 | Ollama | `ollama.service` |
| ailab-ds | 172.16.50.30 | 8889 | Jupyter Lab | `jupyter-ds.service` |
| ailab-ds | 172.16.50.30 | 5000 | MLflow auth gateway (Basic-gated — credential-chain hop 2) | `mlflow-auth-gateway.service` |
| ailab-ds | 172.16.50.30 | 8080 | Weaviate | `weaviate.service` |
| ailab-ds | 172.16.50.30 | 6333 | Qdrant | `qdrant.service` |
| ailab-ds | 172.16.50.30 | 5432 | PostgreSQL/pgvector | `postgresql.service` |
| ailab-app | 172.16.50.40 | 8090 | LangServe | `langserve.service` |
| ailab-app | 172.16.50.40 | 8501 | Streamlit | `streamlit.service` |
| ailab-app | 172.16.50.40 | 8100 | A2A Agent (basic) | `a2a-agent-basic.service` |
| ailab-app | 172.16.50.40 | 8101 | A2A Agent (multiturn) | `a2a-agent-multiturn.service` |
| ailab-app | 172.16.50.40 | 8102 | A2A Agent (authed) | `a2a-agent-authed.service` |
| ailab-app | 172.16.50.40 | 8103 | A2A Agent (real, offensive target; opt-in) | `a2a-agent-real.service` |
| ailab-app | 172.16.50.40 | 8765 | Post-Ex Oracle | `post-ex-oracle.service` |
| ailab-k8s | 172.16.50.50 | 6443 | Kubernetes API (k3s, **vuln** — anonymous) | `k8s-vuln` (container) |
| ailab-k8s | 172.16.50.50 | 6444 | Kubernetes API (k3s, **secure** control) | `k8s-secure` (container) |
| ailab-attack | 172.16.50.99 | 9000 | Lab Listener | `lab-listener.service` |

---

## Host Roles

### ailab-dev — Developer Workstation

Filesystem-heavy developer box with Ollama, Jupyter, MCP, and Gradio exposure.

### ailab-ml — ML Platform

Shared ML infrastructure with vector, registry, proxy, distributed compute, two lightweight inference mocks (TEI, vLLM), three serving-framework mocks (BentoML, TorchServe, Triton), plus the W&B experiment-tracking mock, the Kubeflow pipeline mock, and the TF Serving mock.

### ailab-ds — Data Science

Separate team footprint with its own Ollama/Jupyter plus Weaviate and Qdrant.

### ailab-app — Shared AI Apps

New shared app-facing host for LangServe, Streamlit, A2A agents, and the Post-Ex Oracle, representing internal app teams exposing AI UX surfaces and agent-to-agent protocols.

### ailab-k8s — Kubernetes Node

Estate node running a real **vuln + secure k3s pair** (two containers on one VM): `:6443` is deliberately weak (anonymous RBAC → cluster-wide secret read + `pods/exec`), `:6444` is the secured control (401 for anonymous). Demonstrates "the cluster IS the model registry" — anon `secret-read` recovers the model-registry HF/AWS creds and `sa-loot` steals the over-granted `pipeline-runner` SA to prove supply-chain write. See the [Kubernetes Node](k8s/cluster.md) page.
