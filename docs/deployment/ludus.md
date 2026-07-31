# Ludus Deployment

The `ludus/` directory provides an alternative deployment path using [Ludus](https://ludus.cloud). All existing bash scripts remain unchanged — this is a parallel capability, not a replacement.

## Prerequisites

1. A Ludus server installed and running
2. The `ludus` CLI installed and authenticated on your workstation
3. Two VM templates built on the Ludus server:

```bash
ludus templates list
# You should see:
#   ubuntu-24.04-x64-server-template
#   debian-12-x64-server-template
```

If templates are missing, build them following the [Ludus template docs](https://docs.ludus.cloud/docs/quick-start/build-templates).

## Deploy

```bash
# Register roles and set the range config (one-time setup)
bash ludus/setup.sh

# Deploy the range
ludus range deploy

# Watch deployment progress
ludus range logs -f

# Check status
ludus range status
```

Deployment takes approximately 20–30 minutes depending on network speed (package downloads, Ollama model pulls, etc.).

## What Gets Deployed

| VM | Template | VLAN | IP Suffix | Roles |
|---|---|---|---|---|
| `ailab-dev` | Ubuntu 24.04 | 10 | .10 | `aipostex_base`, `aipostex_dev_workstation` |
| `ailab-ml` | Ubuntu 24.04 | 10 | .20 | `aipostex_base`, `aipostex_ml_platform` |
| `ailab-ds` | Ubuntu 24.04 | 10 | .30 | `aipostex_base`, `aipostex_data_sci` |
| `ailab-app` | Ubuntu 24.04 | 10 | .40 | `aipostex_base`, `aipostex_app_platform` |
| `ailab-attack` | Debian 12 | 99 | .1 | `aipostex_attack_box` |

All inter-VLAN traffic is allowed. Internet access is allowed during provisioning and testing.

## Accessing the Range

Connect via WireGuard:

```bash
ludus user wireguard | tee ludus.conf
# Import ludus.conf into your WireGuard client
```

Or SSH from the attack box:

```bash
ssh labadmin@<attack-box-ip>
ssh ailab-dev    # Uses SSH config set up by the attack-box role
```

## Customization

### Skip data seeding

Set `aipostex_run_seed: false` in the range config's `role_vars` for any VM:

```yaml
role_vars:
  aipostex_run_seed: false
```

Then redeploy:

```bash
ludus range config set -f ludus/range-config.yml
ludus range deploy -t user-defined-roles
```

### Re-run a single role

```bash
ludus range deploy -t user-defined-roles \
  --limit <range_id>-ailab-dev \
  --only-roles aipostex_dev_workstation
```

### Update roles after editing lab-scripts/

```bash
bash ludus/sync-files.sh
ludus ansible role add -d ludus/roles/aipostex_dev_workstation --force
ludus range deploy -t user-defined-roles --limit <range_id>-ailab-dev
```

## Testing Mode

Ludus testing mode provides snapshot/restore cycles similar to `lab-snapshots.sh`:

```bash
ludus testing start    # Snapshot all VMs
# ... run your assessment ...
ludus testing stop     # Revert all VMs to pre-test snapshots
```

## Troubleshooting

Check deployment logs:

```bash
ludus range logs -f          # Full log stream
ludus range errors           # Errors only
```

Re-run just user-defined roles (skips VM creation and base config):

```bash
ludus range deploy -t user-defined-roles
```

## Comparison with Bash Path

| Step | Bash | Ludus |
|---|---|---|
| Create VMs | `sudo bash proxmox-setup.sh` | `ludus range deploy` |
| Base setup | Phase 1 of `deploy-all.sh` | `aipostex_base` role (automatic) |
| Provision | Phase 2 of `deploy-all.sh` | Per-VM roles (automatic) |
| Seed data | Phase 3 of `deploy-all.sh` | Per-VM roles (automatic) |
| Verify | `bash verify-lab.sh` | `bash verify-lab.sh` (same) |
| Snapshot | `bash lab-snapshots.sh create` | `ludus testing start` |
| Restore | `bash lab-snapshots.sh restore` | `ludus testing stop` |
