# Scoring Manifest

`lab-scripts/scoring/manifest.json` is the lab’s answer key. It now reflects the expanded topology and the Tier 2 verification contracts.

## Manifest Contents

- **170 total sensitive findings** across the estate
- **101 contract expectations** (Tier 2 verification)
- **62 verify-lab checks** on the full validation path
- W&B fixtures on `ailab-ml` (port 8444); A2A fixtures on `ailab-app` (ports 8100–8102) with 6 seeded tasks; Post-Ex Oracle on `ailab-app` (port 8765); lateral-movement target on `ailab-dev` (127.0.0.1:9999)
- `score.py` maps every seeded source (including `wandb` and `a2a`) to its module

## Invariants

- **170 planted sensitive findings** tracked by `manifest.json`
- A2A agents and POX are **scoring targets** — aipostex should find A2A findings via templates
- The lab listener and POX are **validation infrastructure** — not scored as exploit targets
- The manifest still acts as the strict-mode answer key for host attribution, service attribution, and workflow metadata expectations

## Host Coverage

| Host | Role |
|---|---|
| `ailab-dev` | developer workstation |
| `ailab-ml` | ML platform |
| `ailab-ds` | data science |
| `ailab-app` | shared AI apps |

The attack box is not scored as a target host, but it does participate in verification through local MCP fixtures and the stdio MCP server.
