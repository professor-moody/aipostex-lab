# Multi-Estate Standup

Stand up **multiple isolated lab estates on one Proxmox host** for parallel hosting (e.g. one estate
per group at a con). Every estate-specific value derives from a single `GROUP_ID` offset, using the
same stride scheme `reset-wave.sh` already assumes. `GROUP_ID=0` is the
base estate and resolves to exactly the existing single-estate layout — so adding estates never
changes estate 0.

## Estate topology

`GROUP_ID=K` derives: **VM IDs** `base + 1000·K`, **subnet** `172.16.(50+K).0/24`, **bridge**
`vmbr10K` (set `VMID_STRIDE` / `SUBNET_STRIDE` to override). Designed for a small number of estates
(single-digit `K`).

| Estate | Bridge | Subnet | dev | ml | ds | app | attack |
|---|---|---|---|---|---|---|---|
| 0 (base) | `vmbr100` | `172.16.50` | 210 | 220 | 230 | 250 | 240 |
| 1 | `vmbr101` | `172.16.51` | 1210 | 1220 | 1230 | 1250 | 1240 |
| 2 | `vmbr102` | `172.16.52` | 2210 | 2220 | 2230 | 2250 | 2240 |

The Ubuntu/Debian **templates (`1101`/`1102`) are shared** across estates — created once by the first
standup and reused (no re-download). Estates are network-isolated: each has its own bridge, subnet,
gateway, and attack box at `.99`.

!!! warning "Stay clear of non-lab VMs"
    The `1000` VM-ID stride keeps estate K well clear of any non-lab VMs on the host (e.g. other
    workloads at `106`, a `310-350` range, the `1101/1102` templates). Confirm the target IDs are
    free first (`qm status <id>`), and **never touch VMs that aren't part of the lab**.

## Prerequisites

- The base estate (group 0) is already built (templates exist).
- **Storage:** each estate is 5 × 30 GB VMs. On thin storage (`local-lvm`) the actual consumption is
  far lower (clones start near the template's footprint and grow with provisioning), but check free
  space first: `pvesm status`. `proxmox-setup.sh` defaults to `STORAGE=local-lvm`; override
  `STORAGE=<pool>` if your host uses a different pool.
- Run the Proxmox steps **on the Proxmox host** (`qm` is local); the repo of record is
  `/root/aipostex-lab` (keep it in sync with your working copy).

## Standup (per estate)

Run for each `K` you want (1, then 2, …). `ASSUME_YES=1` skips the interactive confirm so the standup
is non-interactive.

```bash
# 1. Infra: isolated bridge + clone & boot the 6 VMs
STORAGE=local-lvm ASSUME_YES=1 GROUP_ID=1 bash lab-scripts/proxmox-setup.sh

# 2. Per-estate attack box (.99): Go, Tailscale, tooling, SSH key distribution
GROUP_ID=1 bash lab-scripts/attack-box/setup.sh

# 3. Deploy + seed all five target VMs (phases 1-4, incl. an inline verify)
GROUP_ID=1 bash lab-scripts/deploy-all.sh

# 4. Snapshot so reset-wave has a clean rollback target
GROUP_ID=1 bash lab-scripts/lab-snapshots.sh create lab-ready
```

`deploy-all.sh` threads `LAB_SUBNET` into the per-VM provisioning, so each estate's services point at
their own peers (MLflow, the Post-Ex Oracle, the pgvector trust CIDR, etc.) rather than the base
estate's.

## Verify (per estate)

The verifiers accept an explicit `LAB_SUBNET` to target a specific estate:

```bash
LAB_SUBNET=172.16.51 bash lab-scripts/verify-lab.sh          # expect 62/0/0
LAB_SUBNET=172.16.51 bash lab-scripts/ctf/verify-chain.sh    # expect 13/13
```

!!! tip "Attack-box artifacts can no-op on the first setup"
    Verify-lab also checks attack-box-side artifacts (the `lab-listener` on `:9000` and
    `mcp-configs/remote_mcp_chain.json`). `attack-box/setup.sh` has been observed to occasionally
    finish (exit 0) without installing these — verify-lab then reports them as **warnings**
    (`lab-listener not responding`, `remote_mcp_chain.json missing`). The fix is simply to **re-run
    `GROUP_ID=K bash lab-scripts/attack-box/setup.sh`** (idempotent) and re-verify; do this **before**
    you snapshot, so the `lab-ready` baseline includes them.

!!! warning "Snapshot only a fully-green estate"
    `reset-wave` rolls every estate back to its `lab-ready` snapshot. If the snapshot is taken before
    an estate is fully green (or predates a service change), `reset-wave` will faithfully restore the
    broken state and fail verify. Always land **62/0/0 + 13/13 first**, then snapshot.

## Validate all estates together

Once each estate has a `lab-ready` snapshot, one command resets and re-verifies them **in parallel**
(wall-clock ≈ a single estate, since they run concurrently):

```bash
bash lab-scripts/reset-wave.sh --groups "0 1 2"      # rollback + re-arm + verify every estate
bash lab-scripts/reset-wave.sh --groups "0 1 2" --dry-run
```

A green `reset-wave --groups` across all estates is the multi-estate hosting gate: each estate
independently lands `verify-lab 62/0/0` + `verify-chain 13/13`, isolated on its own subnet/bridge.

## Teardown (per estate)

```bash
GROUP_ID=1 bash lab-scripts/teardown-lab.sh          # destroy estate 1's VMs (templates/bridge kept)
```

Estate 0 and the shared templates are untouched. Re-running `proxmox-setup.sh` for that `GROUP_ID`
rebuilds it.
