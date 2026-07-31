---
title: Enterprise Proxmox Deployment
---

# Enterprise Proxmox Deployment

!!! warning "In development"

    The Enterprise track is under active development. The mini `ailab-*` lab remains the stable conference and benchmark environment. Use Enterprise for build-out, validation, and training-range development until the full `team` profile passes end-to-end service and seed verification.

The enterprise lab uses scripts and optional Ansible wrappers for Proxmox. Terraform remains scoped to AWS cloud mirrors.

This path creates a separate enterprise environment beside the current mini lab. It does not rename or modify the existing `ailab-*` VMs.

Before running any real Proxmox creation command, use the [Enterprise Readiness Checklist](enterprise-readiness.md). It is the pre-bring-up gate for dry-run validation, VM ID checks, template assumptions, and first-run acceptance criteria.

## Current Status

| Area | Status |
|---|---|
| Mini lab compatibility | Stable; Enterprise uses separate `ent-*` hosts and VM IDs |
| Proxmox substrate | In development; dry-run and scripts are present |
| Enterprise Ansible | In development; staged wrapper calls existing Bash role scripts |
| Native enterprise services | In development; systemd-native roles are present but need live Proxmox validation |
| AWS mirror | Planned later; Terraform remains AWS-only and is not used for Proxmox |

## Resource Footprint

The inventory currently allocates the following VM resources:

| Profile | Allocated VM RAM | Allocated vCPU | Practical Proxmox Host Target |
|---|---:|---:|---|
| `team` | 36 GiB | 16 vCPU | 64 GiB RAM, 8+ physical cores preferred |
| `pro` | 44 GiB | 20 vCPU | 64 GiB minimum, 96 GiB RAM comfortable, 12+ physical cores preferred |

Per-host RAM allocation:

| Host | Team RAM | Pro RAM |
|---|---:|---:|
| `ent-attack` | 4 GiB | 4 GiB |
| `ent-dev-01` | 4 GiB | 4 GiB |
| `ent-mlops-01` | 6 GiB | 8 GiB |
| `ent-inference-01` | 6 GiB | 8 GiB |
| `ent-data-01` | 4 GiB | 6 GiB |
| `ent-app-01` | 4 GiB | 4 GiB |
| `ent-observe-01` | 4 GiB | 6 GiB |
| `ent-idp-01` | 4 GiB | 4 GiB |

If mini and Enterprise run at the same time, reserve additional RAM for the existing mini VMs and the Proxmox host itself. Avoid RAM overcommit during service validation; Ollama, OpenSearch, Keycloak, and LiteLLM are the most likely services to expose memory pressure.

## Dry Run

Preview the enterprise topology without changing Proxmox:

```bash
bash lab-scripts/proxmox-enterprise-setup.sh --dry-run
```

## Create Enterprise Infrastructure

Run on the Proxmox host:

```bash
sudo bash lab-scripts/proxmox-enterprise-setup.sh --profile team
```

For larger Pro-sized VM resources:

```bash
sudo bash lab-scripts/proxmox-enterprise-setup.sh --profile pro
```

The script creates:

- routed enterprise bridges `vmbr160` through `vmbr166`
- eight enterprise VMs
- static IPs across the enterprise zones
- cloud-init user and SSH access
- Proxmox VM sizing based on `team` or `pro`

## Full Deployment

The orchestration wrapper keeps each step callable on its own:

```bash
bash lab-scripts/enterprise-deploy.sh --phase infra --profile team
bash lab-scripts/enterprise-deploy.sh --phase base --profile team
bash lab-scripts/enterprise-deploy.sh --phase provision --profile team
bash lab-scripts/enterprise-deploy.sh --phase seed --profile team
bash lab-scripts/enterprise-deploy.sh --phase verify --profile team
```

Or run the whole enterprise build:

```bash
bash lab-scripts/enterprise-deploy.sh --phase all --profile team
```

For Pro, use the same topology with larger sizing and the stricter cross-zone firewall policy:

```bash
bash lab-scripts/enterprise-deploy.sh --phase all --profile pro
```

The enterprise roles install services directly on the VMs with systemd. Docker and Compose are not used.

## Services

| Host | Native Services |
|---|---|
| `ent-idp-01` | dnsmasq, Keycloak, Vault |
| `ent-observe-01` | OpenSearch, Grafana, lightweight log receiver |
| `ent-data-01` | MinIO plus reused vector/data services |
| `ent-inference-01` | LiteLLM, Ollama `local-smollm`, HuggingFace TGI fixture |
| `ent-mlops-01` | MLflow, Ray, Kubeflow fixture/control-plane surface |
| `ent-dev-01` | Jupyter, Ollama, MCP/dev tooling |
| `ent-app-01` | LangServe, Streamlit/RAG app fixtures |
| `ent-attack` | Operator tooling and enterprise SSH aliases |

## Optional Ansible Orchestration

Generate an Ansible inventory from the Bash inventory source:

```bash
bash lab-scripts/enterprise-generate-ansible-inventory.sh > lab-scripts/ansible/inventory/enterprise.yml
```

The staged Ansible wrapper can run service phases after Proxmox infrastructure exists:

```bash
bash lab-scripts/enterprise-deploy-ansible.sh --phase base --profile team
bash lab-scripts/enterprise-deploy-ansible.sh --phase provision --profile team
bash lab-scripts/enterprise-deploy-ansible.sh --phase seed --profile team
bash lab-scripts/enterprise-deploy-ansible.sh --phase verify --profile team
```

Or run every Ansible-managed service phase:

```bash
bash lab-scripts/enterprise-deploy-ansible.sh --phase all --profile team
```

Ansible is intentionally limited to Enterprise host/service orchestration in this stage. Proxmox infrastructure, snapshots, reset, and Pro firewall policy remain Bash-only.

## Pro Network Policy

Team profile leaves zones routed and reachable for early training and troubleshooting.

Pro profile can render, apply, verify, and disable the stricter cross-zone policy:

```bash
bash lab-scripts/enterprise-policy.sh render
sudo bash lab-scripts/enterprise-policy.sh apply
bash lab-scripts/enterprise-policy.sh verify
sudo bash lab-scripts/enterprise-policy.sh disable
```

The Pro policy allows the operator zone to all enterprise zones, allows DNS/IdP/Vault to `ent-idp-01`, allows app/dev/mlops to inference, allows app/mlops to data, allows log shipping to observability, and denies other enterprise cross-zone traffic.

## Verify

Network and SSH only:

```bash
bash lab-scripts/enterprise-verify.sh --layer net
```

Full planned service verification:

```bash
bash lab-scripts/enterprise-verify.sh --layer all --profile team
```

Verification layers are `net`, `services`, `seed`, `policy`, and `all`. The full service and seed checks are expected to fail until enterprise provisioning and seeding have completed. Use `--layer net` immediately after infrastructure creation.

## Snapshots

```bash
bash lab-scripts/enterprise-snapshots.sh create enterprise-ready
bash lab-scripts/enterprise-snapshots.sh restore enterprise-ready
bash lab-scripts/enterprise-reset.sh enterprise-ready
```

Snapshot commands target only `ent-*` VMs and do not touch the current mini lab.

## Make Targets

```bash
make enterprise-up
make enterprise-base
make enterprise-provision
make enterprise-seed
make enterprise-policy
make enterprise-verify
make enterprise-all
make enterprise-ansible
make enterprise-snapshot
make enterprise-reset
```

Optional profile and snapshot name:

```bash
make enterprise-up ENTERPRISE_PROFILE=pro
make enterprise-snapshot ENTERPRISE_SNAPSHOT=enterprise-base
```

## Terraform Boundary

Do not use Terraform for Proxmox enterprise deployment. Terraform remains for AWS:

```text
terraform/
```

After the Proxmox enterprise topology stabilizes, the AWS Terraform path can mirror the same enterprise inventory and role model.
