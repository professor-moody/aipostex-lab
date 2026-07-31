# aipostex Lab

[![Docs](https://img.shields.io/badge/docs-mkdocs-blue)](https://professor-moody.github.io/aipostex-lab/)

A 5-VM Proxmox lab for testing [aipostex](https://github.com/professor-moody/aipostex) against realistic shadow AI sprawl.

Four Ubuntu 24.04 target VMs simulate separate internal teams that deployed AI tooling without coordinated review: a developer workstation, ML platform, data science box, and a shared AI app box. A Debian 12 attack box provides the operator platform. The lab now exposes **29 service health endpoints** and tracks **170 planted sensitive findings** in the scoring manifest.

## What Changed

- Added a fifth VM: `ailab-app` (`172.16.50.40`, VM ID `250`)
- Added app, agent, serving-framework, callback, and post-ex validation surfaces
- Expanded verification to **62 checks** across reachability, services, and deep validation
- Added a shared inventory source at `lab-scripts/lib/inventory.sh`
- Kept Bash as the canonical deployment path
- Added an optional Ansible orchestration path with Bash scripts still as source of truth
- Documented the staged path from Bash to Ansible, optional Packer, then Ludus

## Quick Start

```bash
bash lab-scripts/proxmox-setup.sh          # Create bridge, templates, clone 5 VMs
bash lab-scripts/attack-box/setup.sh       # Provision attack box
bash lab-scripts/deploy-all.sh             # Deploy all 4 targets
bash lab-scripts/verify-lab.sh             # Verify services plus deep validation
```

Restore from snapshot in seconds:

```bash
bash lab-scripts/lab-snapshots.sh restore lab-ready
```

**Just want to test the tool against one real product?** The [single-service sandbox](docs/sandbox.md)
(`sandbox/`) spins up one real AI-infra product under Docker on your workstation — no full lab needed:

```bash
cd sandbox && ./sandbox up chromadb && ./sandbox prove chromadb && ./sandbox down chromadb
```

## VM Map

| VM | IP | OS | Role | Services |
|---|---|---|---|---|
| `ailab-dev` | `172.16.50.10` | Ubuntu 24.04 | Developer workstation | Ollama, Jupyter, MCP Server, Gradio, MCP Inspector |
| `ailab-ml` | `172.16.50.20` | Ubuntu 24.04 | ML platform | ChromaDB, MLflow, LiteLLM, Ray, HF/serving mocks, W&B, Kubeflow |
| `ailab-ds` | `172.16.50.30` | Ubuntu 24.04 | Data science | Ollama, Jupyter, Weaviate, Qdrant, pgvector |
| `ailab-app` | `172.16.50.40` | Ubuntu 24.04 | Shared AI apps | LangServe, Streamlit, A2A agents, Post-Ex Oracle |
| `ailab-attack` | `172.16.50.99` | Debian 12 | Attack box | Go, Tailscale, nmap, fixtures |

## Deployment Model

- **Bash deploy**: canonical, simplest, fully supported
- **Ansible deploy**: optional wrapper that orchestrates the same role scripts
- **Enterprise Proxmox**: separate `ent-*` topology using scripts/optional Ansible, not Terraform
- **Terraform (AWS)**: cloud mirror only — see [`terraform/`](terraform/) for cloud deployment
- **Ludus**: future integration target after the inventory/role model settles

See [Deployment Evolution](https://professor-moody.github.io/aipostex-lab/deployment/evolution/) for the staged roadmap.

## Enterprise Track

> **Status:** Enterprise is in development. The current 5-VM mini lab remains the stable conference and benchmark lab.

The current 5-VM lab is the Mini tier and remains unchanged. The Enterprise track adds a separate routed topology for professional training environments:

```bash
bash lab-scripts/proxmox-enterprise-setup.sh --dry-run
sudo bash lab-scripts/proxmox-enterprise-setup.sh --profile team
bash lab-scripts/enterprise-deploy.sh --phase base --profile team
bash lab-scripts/enterprise-deploy.sh --phase provision --profile team
bash lab-scripts/enterprise-deploy.sh --phase seed --profile team
bash lab-scripts/enterprise-verify.sh --layer net
```

Enterprise Proxmox infrastructure is managed by Bash scripts. Enterprise host/service phases can also be run through the staged Ansible wrapper:

```bash
bash lab-scripts/enterprise-deploy-ansible.sh --phase all --profile team
```

Terraform remains AWS-only. Enterprise roles install native systemd services such as DNS, Keycloak, Vault, MinIO, OpenSearch, Grafana, LiteLLM, and the reused AI lab service surfaces.

Current Enterprise VM allocation is approximately **36 GiB RAM / 16 vCPU** for `team` and **44 GiB RAM / 20 vCPU** for `pro`. Use a 64 GiB Proxmox host for Team validation; Pro is more comfortable with 96 GiB.

## Verification

```bash
bash lab-scripts/verify-lab.sh
bash lab-scripts/attack-box/verify-aipostex.sh --layer smoke
bash lab-scripts/attack-box/verify-aipostex.sh --layer operator
bash lab-scripts/attack-box/verify-aipostex.sh --layer active
bash lab-scripts/attack-box/verify-aipostex.sh --layer contract
```

For scoring:

```bash
python3 lab-scripts/scoring/score.py results.json --strict --verbose
python3 lab-scripts/scoring/score.py results.json --strict --contracts --verbose
```

## Documentation

Full documentation: **[professor-moody.github.io/aipostex-lab](https://professor-moody.github.io/aipostex-lab/)**

- [Quick Start](https://professor-moody.github.io/aipostex-lab/getting-started/quickstart/)
- [VM Map](https://professor-moody.github.io/aipostex-lab/getting-started/vm-map/)
- [Services](https://professor-moody.github.io/aipostex-lab/services/)
- [Deployment Evolution](https://professor-moody.github.io/aipostex-lab/deployment/evolution/)
- [Demo Walkthrough](https://professor-moody.github.io/aipostex-lab/demo/walkthrough/)
- [Scoring & Verification](https://professor-moody.github.io/aipostex-lab/scoring/scoring/)
