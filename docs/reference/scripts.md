---
title: Script Inventory
---

# Script Inventory

## Top-Level Orchestration

| Script | Purpose |
|---|---|
| `proxmox-setup.sh` | Create bridge, templates, and clone 6 VMs |
| `base-setup.sh` | Common OS bootstrap for all VMs |
| `deploy-all.sh` | Canonical Bash deployment for all 5 target VMs |
| `deploy-ansible.sh` | Optional Ansible orchestration wrapper |
| `verify-lab.sh` | Verify service health, connectivity, seeded data, and deep validation |
| `lab-snapshots.sh` | Snapshot, restore, list, delete snapshots for all 6 VMs |
| `teardown-lab.sh` | Destroy lab VMs or full lab infrastructure |
| `lib/inventory.sh` | Shared inventory source for hosts, IPs, VM IDs, counts, and scan ports |
| `lib/service-catalog.sh` | Shared service health contract for the shell verifiers |
| `test-local.sh` | Local validation runner for tests, syntax checks, docs, and shellcheck |
| `proxmox-enterprise-setup.sh` | Create the enterprise Proxmox routed substrate and `ent-*` VMs |
| `enterprise-verify.sh` | Verify enterprise network/SSH, services, seeded artifacts, and policy |
| `enterprise-snapshots.sh` | Snapshot, restore, list, and delete snapshots for enterprise VMs only |
| `enterprise-reset.sh` | Restore enterprise VMs to a named snapshot |
| `enterprise-deploy.sh` | Enterprise orchestration wrapper for infra, base, provision, seed, policy, and verify phases |
| `enterprise-deploy-ansible.sh` | Optional Enterprise Ansible wrapper for base, provision, seed, and verify phases |
| `enterprise-policy.sh` | Render, apply, verify, and disable the Pro cross-zone firewall policy |
| `enterprise-generate-ansible-inventory.sh` | Generate optional Ansible inventory from the enterprise Bash inventory |
| `lib/enterprise-inventory.sh` | Enterprise inventory source for hosts, zones, VM IDs, DNS aliases, and sizing |
| `lib/enterprise-service-catalog.sh` | Planned enterprise service health contract |

## Role Directories

| Directory | Purpose |
|---|---|
| `dev-workstation/` | Developer workstation role |
| `ml-platform/` | ML platform role, seeds, and inference mocks |
| `data-sci/` | Data science role and seed scripts |
| `app-platform/` | Shared AI app box role for LangServe and Streamlit |
| `attack-box/` | Attack-box setup, fixtures, and end-to-end verifier |
| `ansible/` | Optional Ansible playbook and config |
| `ansible/enterprise.yml` | Staged Enterprise Ansible playbook that wraps Enterprise Bash role scripts |
| `enterprise/identity/` | Enterprise DNS, Keycloak, and Vault role |
| `enterprise/observability/` | Enterprise OpenSearch, Grafana, and log receiver role |
| `enterprise/inference-platform/` | Enterprise LiteLLM, Ollama, local-smollm, and TGI fixture role |
| `enterprise/mlops-platform/` | Enterprise MLflow/Ray/Kubeflow role wrapper and seeds |
| `enterprise/data-platform/` | Enterprise MinIO and vector/data service role wrapper |
| `enterprise/app-platform/` | Enterprise RAG app and LangServe/Streamlit role wrapper |
| `enterprise/dev-workstation/` | Enterprise Jupyter/Ollama/MCP developer role wrapper |
| `enterprise/attack-box/` | Enterprise operator host setup |

## New Notable Additions

| Path | Purpose |
|---|---|
| `app-platform/provision.sh` | Provision LangServe and Streamlit on `ailab-app` |
| `attack-box/stdio-mcp-server.py` | Local stdio MCP verification fixture |
| `dev-workstation/seed.sh` | Canonical seeding entrypoint for `ailab-dev` |
| `ml-platform/seed.sh` | Canonical seeding entrypoint for `ailab-ml` |
| `data-sci/seed.sh` | Canonical seeding entrypoint for `ailab-ds` |
| `app-platform/tgi-gateway/server.py` | HF TGI gateway with auth-gated `/generate` |
| `data-sci/mlflow-auth-gateway/server.py` | MLflow Basic Auth gateway for the guided chain |
| `ml-platform/hf-tgi-mock/server.py` | Legacy ML-host HF TGI detection surface |
| `ml-platform/hf-tei-mock/server.py` | HF TEI detection surface |
| `ml-platform/vllm-mock/server.py` | vLLM detection surface |
