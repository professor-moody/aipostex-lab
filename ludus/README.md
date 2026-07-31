# Ludus Deployment Path

This directory provides an alternative deployment path for the aipostex lab using [Ludus](https://ludus.cloud). The canonical bash scripts in `lab-scripts/` remain unchanged and fully functional.

## Prerequisites

- Ludus server installed and running ([install guide](https://docs.ludus.cloud/docs/category/quick-start))
- `ludus` CLI installed and authenticated
- Two templates already built on the Ludus server:
  - `ubuntu-24.04-x64-server-template` (for target VMs)
  - `debian-12-x64-server-template` (for the attack box)

## Quick Start

```bash
# 1. Register roles and set range config
bash ludus/setup.sh

# 2. Deploy the range
ludus range deploy

# 3. Watch progress
ludus range logs -f

# 4. Check status
ludus range status
```

## What Gets Deployed

| VM | Template | VLAN | IP Suffix | Services |
|---|---|---|---|---|
| ailab-dev | Ubuntu 24.04 | 10 | .10 | Ollama, Jupyter, MCP, Gradio, Inspector |
| ailab-ml | Ubuntu 24.04 | 10 | .20 | ChromaDB, MLflow, LiteLLM, Ray, HF/vLLM mocks |
| ailab-ds | Ubuntu 24.04 | 10 | .30 | Ollama, Jupyter, Weaviate, Qdrant |
| ailab-app | Ubuntu 24.04 | 10 | .40 | LangServe, Streamlit |
| ailab-attack | Debian 12 | 99 | .1 | Go, Tailscale, nmap, MCP fixtures |

## Roles

Each role is a thin Ansible wrapper that copies and executes the existing bash provisioners from `lab-scripts/`. No provisioning logic was rewritten.

| Role | Wraps | Applied To |
|---|---|---|
| `aipostex_base` | `base-setup.sh` | All 4 target VMs |
| `aipostex_dev_workstation` | `dev-workstation/provision.sh` + `seed.sh` | ailab-dev |
| `aipostex_ml_platform` | `ml-platform/provision.sh` + `seed.sh` | ailab-ml |
| `aipostex_data_sci` | `data-sci/provision.sh` + `seed.sh` | ailab-ds |
| `aipostex_app_platform` | `app-platform/provision.sh` | ailab-app |
| `aipostex_attack_box` | `attack-box/provision.sh` | ailab-attack |

## Role Variables

Set these in the range config under `role_vars:`:

| Variable | Default | Description |
|---|---|---|
| `aipostex_lab_user` | `labadmin` | SSH user on target VMs |
| `aipostex_run_seed` | `true` | Set to `false` to skip data seeding |

## File Sync

Role `files/` directories are populated by `sync-files.sh` from the canonical `lab-scripts/` source. These synced copies are `.gitignore`d so only one copy exists in version control.

```bash
# Re-sync after editing lab-scripts/
bash ludus/sync-files.sh
```

To update a role on the Ludus server after syncing:

```bash
ludus ansible role add -d ludus/roles/aipostex_dev_workstation --force
ludus range deploy -t user-defined-roles --limit <range_id>-ailab-dev
```

## Testing Mode

After deployment, use Ludus testing mode for snapshot/restore cycles:

```bash
ludus testing start    # Snapshot all VMs
# ... run your assessment ...
ludus testing stop     # Revert to snapshots
```

## Comparison with Bash Path

| Aspect | Bash (`deploy-all.sh`) | Ludus |
|---|---|---|
| VM creation | `proxmox-setup.sh` (manual Proxmox) | `ludus range deploy` (automated) |
| Provisioning | SSH + scp from attack box | Ansible roles via Ludus |
| Snapshots | `lab-snapshots.sh` | `ludus testing start/stop` |
| Network | Manual bridge + NAT | Ludus-managed router |
| Dependencies | SSH access, bash | `ludus` CLI only |
