# Deployment Options (Matrix)

A decision-aid for **which** way to stand up the lab and **when** to pick each. It covers what each
path stands up, its entrance model, cost, and maturity. For the attendee **entrance** itself — how a
participant actually connects, with failsafes for a hostile venue network — see
[Attendee Connectivity](connectivity.md).

The design goal is **3–4 solid, modular options** so a venue decision (or a failure on the day) never
leaves you stuck: owned hardware as the default, AWS as the turnkey backup, Ludus as the clean
per-attendee model once matured, and the sandbox for single-service work.

## The options

| Path | Stands up | Entrance | Cost | Maturity | Pick it when |
|---|---|---|---|---|---|
| **Proxmox — Mini (single / multi-estate)** | 6-VM `ailab-*` estate on an isolated bridge (`vmbr10K` / `172.16.(50+K).0/24`); N estates via `GROUP_ID` | On-site offline AP → join `aipostex-lab` WiFi → `ssh pNN@box` (tool runs on the box); Tailscale/WireGuard as the remote fallback — see [Connectivity](connectivity.md) | ~$0 (owned hardware) | Stable, primary; 3 estates validated on a 62 GB host (~99 s parallel reset) | You own the hardware and want the cheapest, most-controlled path. **Default.** |
| **AWS — ranges (single / multi-range)** | 6 instances/range in a shared VPC, per-range subnet + SG (`10.0.(K+1).0/24`); N via `range_ids` | WireGuard entrance (built, `ESTATE_SCHEME=aws`, UDP 51820 SG rule); operator-CIDR SSH; Tailscale advertise optional | ~$0.41/hr/range (stopped = $0) | Turnkey, validated (terraform + provision + bake-ami + reset-wave green) | Hardware isn't available/portable, or you need to rehearse/scale fast. **Backup.** |
| **Ludus** | 6-VM range with native multi-tenancy + per-user WireGuard | Native `ludus user wireguard` per attendee | Per your Ludus host | Complete docs, **not fully tested — build out, then pause** | You want the cleanest per-attendee-VPN model and have a Ludus host to mature it on. |
| **Sandbox** | ONE real product under Docker on the dev machine (chromadb/qdrant/mlflow/wandb/ollama/a2a/k8s, vuln+secure) | localhost | ~$0 | Validated realism loop | Single-service / single-tactic dev + honesty checks — not an attendee estate. |
| **Enterprise** | 8-VM zoned `ent-*` topology across routed bridges | Per-zone; operator zone gates all | Owned hardware | In development | A larger, segmented scenario — **out of scope for RTV.** |

## Modularity — a single tactic, or the full lab

Two independent axes:

- **Tier** ([Deployment Evolution](evolution.md)): **Mini** (6-VM `ailab-*`, the default) vs **Enterprise**
  (8-VM `ent-*`). Pick the topology.
- **Scope within a tier:**
  - **Full estate** — `deploy-all.sh` (canonical). Also phase-scoped: `--phase 1|2|3|4`, `--skip-base`.
  - **A single tactic** — deploy only the VMs a tactic needs. Set `LAB_PROFILE` (or `LAB_ONLY_ROLES`)
    and both `proxmox-setup.sh` (which VMs get cloned) and `deploy-all.sh` (which get provisioned/seeded)
    honor it; default is the full estate, so existing behaviour is unchanged. `attack` (the foothold) is
    always included.
    ```bash
    LAB_PROFILE=credential-chain bash lab-scripts/proxmox-setup.sh   # clones dev/ml/ds/app/attack only
    LAB_PROFILE=credential-chain bash lab-scripts/deploy-all.sh      # provisions + seeds the same set
    # profiles: full | credential-chain (dev,ml,ds,app,attack) | a2a (app,attack) | k8s (k8s,attack)
    # or pick roles directly: LAB_ONLY_ROLES="app" bash lab-scripts/deploy-all.sh
    ```
    Tactic→VM mapping: [tactic-chain.md](../demo/tactic-chain.md). Mirrored on AWS as the planned
    `deploy-all.sh --only` + `var.ranges` profile. Under the hood these reuse the already-independent
    per-role `provision.sh` + `seed.sh` — the selector only chooses which roles get created/provisioned.
  - **A single service/host** — the [Manual Deployment](manual.md) path: `scp` one role dir and run its
    `provision.sh`. Works today for ad-hoc/debug.

A tactic estate is cheaper and faster to reset than the full lab, which is what makes multi-estate
workshops affordable — see [Multi-Estate Standup](multi-estate.md) for the per-host math.

## Choosing, in one line

- **Have hardware?** Proxmox Mini (multi-estate for a room), entrance via a route-advertising relay.
- **No hardware / need to scale now?** AWS ranges, entrance via operator SSH or Tailscale advertise.
- **Want per-attendee WG turnkey?** Ludus — after you finish building it out and testing.
- **Just iterating on one service?** Sandbox.

Whatever the path, the attendee **entrance** and its failsafes are the same decision — read
[Attendee Connectivity](connectivity.md) next.
