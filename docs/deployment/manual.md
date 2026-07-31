# Manual Deployment

Manual deployment is mainly for debugging a single role. For normal use, prefer [`deploy-all.sh`](automated.md), which remains the canonical path.

## Host Roles

| Host | Role dir | Services |
|---|---|---|
| `ailab-dev` | `dev-workstation` | Ollama, Jupyter, MCP server, Gradio, MCP Inspector |
| `ailab-ml` | `ml-platform` | ChromaDB, MLflow, LiteLLM, LiteLLM-authed, Ray, HF/serving mocks, W&B, Kubeflow, TF Serving |
| `ailab-ds` | `data-sci` | Ollama, Jupyter, Weaviate, Qdrant, PostgreSQL/pgvector |
| `ailab-app` | `app-platform` | LangServe, Streamlit, TGI Gateway, A2A agents, Post-Ex Oracle |
| `ailab-k8s` | `k8s-node` | k3s vuln/secure pair (`:6443` anonymous, `:6444` secured) |
| `ailab-attack` | `attack-box` | operator tooling and MCP fixtures |

## Per-Host Provisioning

Run base setup first on the target, then copy the role dir and execute its `provision.sh`.

### `ailab-dev`

```bash
ssh labadmin@172.16.50.10 "mkdir -p ~/lab"
scp -r lab-scripts/dev-workstation/ labadmin@172.16.50.10:~/lab/
ssh labadmin@172.16.50.10 "sudo bash ~/lab/dev-workstation/provision.sh"
ssh labadmin@172.16.50.10 "sudo bash ~/lab/dev-workstation/seed-ollama.sh"
ssh labadmin@172.16.50.10 "sudo bash ~/lab/dev-workstation/seed-filesystem.sh"
```

### `ailab-ml`

```bash
ssh labadmin@172.16.50.20 "mkdir -p ~/lab"
scp -r lab-scripts/ml-platform/ labadmin@172.16.50.20:~/lab/
ssh labadmin@172.16.50.20 "sudo bash ~/lab/ml-platform/provision.sh"
ssh labadmin@172.16.50.20 "sudo bash ~/lab/ml-platform/seed.sh"
```

### `ailab-ds`

```bash
ssh labadmin@172.16.50.30 "mkdir -p ~/lab"
scp -r lab-scripts/data-sci/ labadmin@172.16.50.30:~/lab/
ssh labadmin@172.16.50.30 "sudo bash ~/lab/data-sci/provision.sh"
ssh labadmin@172.16.50.30 "sudo bash ~/lab/data-sci/seed.sh"
```

### `ailab-app`

```bash
ssh labadmin@172.16.50.40 "mkdir -p ~/lab"
scp -r lab-scripts/app-platform/ labadmin@172.16.50.40:~/lab/
ssh labadmin@172.16.50.40 "sudo bash ~/lab/app-platform/provision.sh"
```

`ailab-app` hosts LangServe, Streamlit, the TGI gateway, three A2A agents, and the Post-Ex Oracle used by active validation workflows.

### `ailab-k8s`

```bash
ssh labadmin@172.16.50.50 "mkdir -p ~/lab"
scp -r lab-scripts/k8s-node/ labadmin@172.16.50.50:~/lab/
ssh labadmin@172.16.50.50 "sudo bash ~/lab/k8s-node/provision.sh"
```

### `ailab-attack`

```bash
ssh labadmin@172.16.50.99 "mkdir -p ~/lab"
scp -r lab-scripts/attack-box/ labadmin@172.16.50.99:~/lab/
ssh labadmin@172.16.50.99 "sudo bash ~/lab/attack-box/provision.sh"
```

## Quick Verification

After manual provisioning and seeding:

```bash
bash lab-scripts/verify-lab.sh
```

Expected state:

- **6 VMs total / 5 targets**
- **29 service health checks**
- **62 total verification checks including deep validation**

For end-to-end tool validation from the attack box:

```bash
bash ~/lab/attack-box/verify-aipostex.sh --layer smoke
bash ~/lab/attack-box/verify-aipostex.sh --layer operator
```
