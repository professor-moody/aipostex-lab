# Ludus Integration

[Ludus](https://ludus.cloud) is now available as an alternative deployment path alongside the canonical bash scripts. See the [Ludus deployment guide](../deployment/ludus.md) for usage instructions.

## Deployment Paths

The repo supports three deployment paths. All coexist — choose whichever fits your environment:

1. **Bash (canonical)** — `proxmox-setup.sh` + `deploy-all.sh`
2. **Optional Ansible** — `deploy-ansible.sh` + `lab-scripts/ansible/site.yml`
3. **Ludus** — `ludus/range-config.yml` + `ludus/setup.sh`

## Mapping

| Repo Concept | Ludus Equivalent |
|---|---|
| `lab-scripts/lib/inventory.sh` | Range config topology (`range-config.yml`) |
| `base-setup.sh` | `aipostex_base` role |
| `dev-workstation/` | `aipostex_dev_workstation` role |
| `ml-platform/` | `aipostex_ml_platform` role |
| `data-sci/` | `aipostex_data_sci` role |
| `app-platform/` | `aipostex_app_platform` role |
| `attack-box/` | `aipostex_attack_box` role |
| `proxmox-setup.sh` | `ludus range deploy` (VM creation) |
| `deploy-all.sh` | `ludus range deploy` (role execution) |
| `lab-snapshots.sh` | `ludus testing start/stop` |

## Important Point

The attack workflow should stay the same regardless of whether the lab was provisioned by Bash, optional Ansible, or Ludus.
