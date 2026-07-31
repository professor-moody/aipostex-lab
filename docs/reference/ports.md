---
title: Port & Service Matrix
---

# Port & Service Matrix

Complete list of every endpoint in the lab.

## ailab-dev — 172.16.50.10

| Port | Service | Systemd Unit |
|---|---|---|
| 22 | SSH | `sshd.service` |
| 11434 | Ollama | `ollama.service` |
| 8888 | Jupyter Lab | `jupyter.service` |
| 3000 | MCP Server (real MCP SDK — FastMCP, Streamable HTTP at `/mcp`) | `acme-mcp.service` |
| 7860 | Gradio | `gradio-chat.service` |
| 6274 | MCP Inspector | `mcp-inspector.service` |

## ailab-ml — 172.16.50.20

| Port | Service | Systemd Unit |
|---|---|---|
| 22 | SSH | `sshd.service` |
| 8000 | ChromaDB | `chromadb.service` |
| 5000 | MLflow | `mlflow.service` |
| 4000 | LiteLLM | `litellm.service` |
| 4001 | LiteLLM (authed) | `litellm-authed.service` |
| 8265 | Ray Dashboard | `ray.service` |
| 8180 | HF TGI mock (**legacy — opt-in / OFF by default**; a down port here is expected. The real gateway is `ailab-app:8180`) | `hf-tgi-mock.service` |
| 8181 | HF TEI mock | `hf-tei-mock.service` |
| 8182 | vLLM mock | `vllm-mock.service` |
| 3333 | BentoML mock | `bentoml-mock.service` |
| 8081 | TorchServe mock | `torchserve-mock.service` |
| 8082 | TorchServe metrics | `torchserve-mock.service` |
| 8500 | Triton mock | `triton-mock.service` |
| 8444 | W&B mock | `wandb-mock.service` |
| 9000 | Kubeflow mock | `kubeflow-mock.service` |
| 8501 | TF Serving mock | `tfserving-mock.service` |

Background service without a listener port: `mlflow-hook-controller.service` watches the
real MLflow registry for `aipostex.hook.url` model-version tags and delivers hook callbacks.

## ailab-ds — 172.16.50.30

| Port | Service | Systemd Unit |
|---|---|---|
| 22 | SSH | `sshd.service` |
| 11434 | Ollama | `ollama.service` |
| 8889 | Jupyter Lab | `jupyter-ds.service` |
| 8080 | Weaviate | `weaviate.service` |
| 6333 | Qdrant | `qdrant.service` |
| 5432 | PostgreSQL/pgvector | `postgresql.service` |

## ailab-app — 172.16.50.40

| Port | Service | Systemd Unit |
|---|---|---|
| 22 | SSH | `sshd.service` |
| 8090 | LangServe | `langserve.service` |
| 8501 | Streamlit | `streamlit.service` |
| 8100 | A2A Agent (basic) | `a2a-agent-basic.service` |
| 8101 | A2A Agent (multiturn) | `a2a-agent-multiturn.service` |
| 8102 | A2A Agent (authed) | `a2a-agent-authed.service` |
| 8103 | A2A Agent (real, a2a-sdk; opt-in) | `a2a-agent-real.service` |
| 8180 | HF TGI gateway (real inference — the credential-chain hop) | `tgi-gateway.service` |
| 8765 | Post-Ex Oracle | `post-ex-oracle.service` |

## ailab-k8s — 172.16.50.50

| Port | Service | Systemd Unit / Notes |
|---|---|---|
| 22 | SSH | `sshd.service` |
| 6443 | Kubernetes API — **vuln** (anonymous-open, weak RBAC) | k3s via Docker (`k8s-node`) |
| 6444 | Kubernetes API — **secure** (401-enforced honesty control) | k3s via Docker (`k8s-node`) |

## ailab-attack — 172.16.50.99

| Port | Service | Systemd Unit |
|---|---|---|
| 22 | SSH | `sshd.service` |
| 9000 | Lab Listener | `lab-listener.service` |

!!! note "Verification counts"
    `verify-lab.sh` currently reports **62 passing checks** — service health across all 6 VMs
    (including the k8s pair), SSH and ping reachability for each, and deep validation checks for
    seeded data and post-exploitation fixtures.
