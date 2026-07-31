# Lab Design

The lab models **shadow AI sprawl across five target hosts**, not just one careless machine. Each role owns a different part of the problem space, which makes discovery, pivoting, and inventory drift feel much closer to a real internal environment.

## Host Roles

### `ailab-dev`

The developer workstation is still the noisiest target: Ollama, Jupyter, a vulnerable MCP server, Gradio, and planted filesystem artifacts. It drives prompt theft, notebook abuse, MCP testing, and local file discovery.

### `ailab-ml`

The ML platform concentrates the higher-value shared services: ChromaDB, MLflow, LiteLLM, LiteLLM-authed, Ray, HF/serving mocks, W&B, Kubeflow, and TF Serving. This is the control-plane-like box where Tier 2 workflows such as `pip-inject`, `cluster-info`, and `tamper-proof` make sense.

### `ailab-ds`

The data science host shows tool fragmentation. It keeps the second Ollama, second Jupyter, Weaviate, Qdrant, and PostgreSQL/pgvector so the demo still tells the “multiple teams built this independently” story.

### `ailab-app`

The shared AI app host carries LangServe, Streamlit, three A2A agents, and the Post-Ex Oracle. Its value is discovery coverage, agent workflow validation, and narrative separation: app-facing surfaces no longer need to be crammed onto another team’s box.

### `ailab-k8s`

The Kubernetes node runs a real single-node k3s pair on one VM: a deliberately weak cluster on `:6443` (anonymous RBAC) alongside a hardened control plane on `:6444`. It anchors the cluster-attack story — anonymous API reads, secret exposure, and RBAC misconfiguration — against a genuine kube-apiserver rather than a mock.

### `ailab-attack`

The attack box remains the operator entry point with Tailscale, SSH shortcuts, `aipostex`, and local MCP fixtures, including the new stdio MCP fixture.

## Why The Split-Host Layout Helps

- It creates a cleaner app-tier story for LangServe and Streamlit.
- It makes the subnet scan feel more realistic: five distinct target hosts instead of a couple of overloaded ones.
- It gives future Ludus and Ansible role boundaries a natural place to land.
- It improves shareability because app-facing demos can be discussed without implying they belong on the dev or DS systems.

## Design Totals

- **6 VMs total**
- **5 target VMs**
- **29 health-checked service endpoints**
- **170 planted sensitive findings**

The service surface now includes app, agent, serving-framework, vector database, and post-exploitation validation surfaces while keeping fake planted values tracked in the scoring manifest.

## Deployment Strategy

The repo now treats Bash as the canonical deployment path while introducing a shared inventory/config source under `lab-scripts/lib/`. That inventory is the basis for:

- current Bash orchestration
- the optional Ansible wrapper path
- a future Packer image pipeline if template drift becomes painful
- later Ludus integration after the role model stabilizes

That sequencing keeps the lab accessible for first-time users while still giving the project a cleaner long-term migration path.
