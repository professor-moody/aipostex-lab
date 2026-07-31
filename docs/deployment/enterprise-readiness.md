---
title: Enterprise Readiness Checklist
---

# Enterprise Readiness Checklist

!!! warning "In development"

    Enterprise is not the default lab yet. Use this page to validate the repo, topology, and Proxmox assumptions before creating any `ent-*` VMs. The mini `ailab-*` lab remains the stable training and demo environment.

This checklist is for the current development phase: **pre-bring-up**. It keeps work useful before we are ready to run the real Proxmox creation step.

## Current Development State

| Area | State | What To Check Now |
|---|---|---|
| Inventory | Implemented | `lab-scripts/lib/enterprise-inventory.sh` owns hosts, VM IDs, zones, IPs, profiles, aliases, and role directories. |
| Proxmox substrate | Scripted, not live-validated | Dry-run `proxmox-enterprise-setup.sh` and review bridges, storage, templates, VM IDs, and cloud-init settings. |
| Service orchestration | Implemented as staged Bash plus optional Ansible | Run syntax, pytest, and Ansible syntax checks locally. |
| Native services | Role scripts present | Review service assumptions before running on VMs. |
| Seeded artifacts | Role seed scripts present | Review story coherence and expected file paths before live validation. |
| Verification | Implemented by layer | Use `net` only after VMs exist; `services` and `seed` are expected to fail before provisioning. |
| Pro policy | Rendered by Bash | Review `enterprise-policy.sh render`; apply only on the Proxmox host after Team works. |
| AWS mirror | Deferred | Terraform remains AWS-only and should not drive Proxmox. |

## Safe Checks Before Bring-Up

These commands do not create or mutate Enterprise VMs.

```bash
bash lab-scripts/proxmox-enterprise-setup.sh --dry-run --profile team
bash lab-scripts/proxmox-enterprise-setup.sh --dry-run --profile pro
```

```bash
bash lab-scripts/enterprise-policy.sh render
```

```bash
make enterprise-ansible-syntax
```

```bash
REQUIRE_SHELLCHECK=1 bash lab-scripts/test-local.sh
```

The Ansible syntax target generates temporary `team` and `pro` inventories from the Bash inventory and runs `ansible-playbook --syntax-check` for both.

## Proxmox Host Checklist

Before running the real infrastructure command on Proxmox, confirm:

- Existing mini VMs are healthy and should remain untouched.
- VM IDs `360` through `367` are unused.
- Bridges `vmbr160` through `vmbr166` are either absent or intentionally reusable for Enterprise.
- Ubuntu template `1101` and Debian template `1102` exist, or `ENT_UBUNTU_TEMPLATE_ID` / `ENT_DEBIAN_TEMPLATE_ID` are set.
- Storage target `vm2` exists, or `STORAGE` is set to the intended Proxmox storage.
- Upstream NAT bridge `vmbr0` is correct, or `ENT_UPSTREAM_BRIDGE` is set.
- The Proxmox host has enough free RAM, CPU, and disk for the selected profile.
- You have a current mini-lab snapshot if Mini and Enterprise share the same Proxmox host.

## Resource Gate

| Profile | Allocated VM RAM | Allocated vCPU | Practical Host Target |
|---|---:|---:|---|
| `team` | 36 GiB | 16 vCPU | 64 GiB RAM, 8+ physical cores preferred |
| `pro` | 44 GiB | 20 vCPU | 96 GiB RAM preferred for comfortable validation |

Do not treat the allocation as the whole host budget. Leave room for Proxmox, filesystem cache, mini VMs if they stay running, and bursty services such as OpenSearch, Keycloak, Ollama, LiteLLM, MLflow, and Ray.

## First Bring-Up Definition Of Done

The first real Enterprise bring-up should stop at Team profile until these are true:

- `proxmox-enterprise-setup.sh --profile team` creates all `ent-*` VMs without touching `ailab-*`.
- `enterprise-verify.sh --layer net --profile team` passes for ping and SSH.
- `enterprise-deploy-ansible.sh --phase base --profile team` completes.
- `enterprise-deploy-ansible.sh --phase provision --profile team` completes.
- `enterprise-deploy-ansible.sh --phase seed --profile team` completes.
- `enterprise-verify.sh --layer all --profile team` passes or produces only documented expected gaps.
- `enterprise-snapshots.sh create enterprise-ready` creates snapshots for `ent-*` only.
- `enterprise-reset.sh enterprise-ready` restores Enterprise without affecting Mini.

Only after Team is reliable should Pro policy be applied.

## First Bring-Up Command Order

Run from the repo on the Proxmox host:

```bash
sudo bash lab-scripts/proxmox-enterprise-setup.sh --profile team
```

Then run from the control/operator machine:

```bash
bash lab-scripts/enterprise-verify.sh --layer net --profile team
bash lab-scripts/enterprise-deploy-ansible.sh --phase base --profile team
bash lab-scripts/enterprise-deploy-ansible.sh --phase provision --profile team
bash lab-scripts/enterprise-deploy-ansible.sh --phase seed --profile team
bash lab-scripts/enterprise-verify.sh --layer all --profile team
```

Create the first restore point only after the Team profile is in a known-good state:

```bash
bash lab-scripts/enterprise-snapshots.sh create enterprise-ready
```

## Known Non-Goals For This Phase

- Do not refactor the mini lab into Enterprise.
- Do not introduce Docker or Compose.
- Do not use Terraform for Proxmox.
- Do not apply the Pro firewall policy before Team has passed service and seed validation.
- Do not make Enterprise the default docs path until live Proxmox validation is complete.

## Documentation Work Still Worth Doing

Before first bring-up, the useful docs work is:

- Expand the Enterprise service map from role-level descriptions into port-level expectations.
- Add per-role Enterprise pages for identity, observability, data, inference, MLOps, app, dev, and attack-box.
- Add a troubleshooting page for VM ID conflicts, template IDs, storage names, bridge collisions, and SSH/cloud-init delays.
- Add a first-run validation log template so bring-up results can be captured consistently.
- Add an Enterprise seeded-artifact map after the first successful seed run confirms paths and values.
