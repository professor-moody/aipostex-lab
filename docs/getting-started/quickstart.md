---
title: Quick Start
---

# Quick Start

Get the full **6-VM** lab running from scratch or restore from snapshot.

## From Scratch

### 1. Create Infrastructure

```bash
bash lab-scripts/proxmox-setup.sh
```

Creates the isolated bridge, cloud-init templates, and all 6 VMs:

- `ailab-dev`
- `ailab-ml`
- `ailab-ds`
- `ailab-app`
- `ailab-k8s` (`172.16.50.50`, Kubernetes node)
- `ailab-attack`

### 2. Provision the Attack Box

```bash
bash lab-scripts/attack-box/setup.sh
```

Configures SSH aliases for all 5 targets, installs tooling, and places MCP fixtures plus the stdio MCP server.

### 3. Deploy All Targets

```bash
bash lab-scripts/deploy-all.sh
```

Runs base setup, provisioning, seeding, and verification across all 5 target VMs.

### 4. Verify

```bash
bash lab-scripts/verify-lab.sh
```

Expected result: **29 passed, 0 failed, 0 warnings** for the service-health subset. The full `verify-lab.sh` run (VM ping/SSH, seeded-data, and deep validation) totals **62** checks.

## Optional Ansible Path

```bash
bash lab-scripts/deploy-ansible.sh --phase all
```

This is optional. Bash remains the canonical path.

## Snapshots

```bash
bash lab-scripts/lab-snapshots.sh create lab-ready "Full deploy, all services verified"
bash lab-scripts/lab-snapshots.sh restore lab-ready
```
