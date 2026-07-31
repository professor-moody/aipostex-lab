# Attack Box Setup

The attack box is a Debian 12 VM at `172.16.50.99` (`ailab-attack`). It is the operator platform for running `aipostex` against the 5 target VMs.

## What It Configures

- Go, Tailscale, nmap, jq, Python, and standard utilities
- SSH aliases for:
  - `ailab-dev`
  - `ailab-ml`
  - `ailab-ds`
  - `ailab-app`
- `kubectl` (pinned to the estate k3s version) for the `ailab-k8s` node at `172.16.50.50`
- MCP config fixtures under `~/lab/mcp-configs/`
- a local stdio MCP fixture at `~/lab/stdio-mcp-server.py`

## How To Provision

```bash
bash lab-scripts/attack-box/setup.sh
```

The attack box is provisioned separately from `deploy-all.sh` so it can survive target rebuilds and snapshot restores.
