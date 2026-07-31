# Snapshots & Teardown

The snapshot flow now covers **all 5 lab VMs**, including the new `ailab-app` host.

## Create A Lab-Ready Snapshot

```bash
bash lab-scripts/lab-snapshots.sh create lab-ready "Full mini-lab deploy"
```

This snapshots:

- `210` `ailab-dev`
- `220` `ailab-ml`
- `230` `ailab-ds`
- `250` `ailab-app`
- `240` `ailab-attack`

## Restore

```bash
bash lab-scripts/lab-snapshots.sh restore lab-ready
```

For non-interactive rollback in automation:

```bash
bash lab-scripts/lab-snapshots.sh --yes restore lab-ready
```

Then verify:

```bash
bash lab-scripts/verify-lab.sh
```

You should be back to the expected green `verify-lab.sh` result.

## Reference

| Command | Result |
|---|---|
| `bash lab-scripts/lab-snapshots.sh create <name> [desc]` | Snapshot all 6 VMs |
| `bash lab-scripts/lab-snapshots.sh restore <name>` | Stop, rollback, and restart all 6 VMs |
| `bash lab-scripts/lab-snapshots.sh --yes restore <name>` | Non-interactive restore for automation |
| `bash lab-scripts/lab-snapshots.sh list` | List snapshots for all lab VMs |
| `bash lab-scripts/lab-snapshots.sh delete <name>` | Delete a snapshot from all lab VMs |
| `bash lab-scripts/lab-snapshots.sh --yes delete <name>` | Non-interactive snapshot cleanup |

## Manual VM IDs

```bash
for vmid in 210 220 230 250 240; do
  qm snapshot "$vmid" pre-demo --description "demo checkpoint"
done
```

## Teardown

Use the helper script:

```bash
bash lab-scripts/teardown-lab.sh
```

That removes the cloned VMs while preserving templates and the bridge. Add `--full` only if you also want to remove templates and network setup.
