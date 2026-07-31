# Tailscale & Remote Access

The attack box is the only host you should reach directly from your workstation. Everything else stays on the isolated lab bridge.

## Access Pattern

```text
workstation -> Tailscale -> ailab-attack -> ssh ailab-dev / ailab-ml / ailab-ds / ailab-app
```

## First-Time Setup

From the Proxmox host:

```bash
ssh labadmin@172.16.50.99
sudo tailscale up
tailscale ip -4
```

Then connect from your workstation to the attack box with the returned Tailscale IP.

## SSH Shortcuts

`attack-box/provision.sh` installs SSH aliases for the four SSH-reachable targets (the fifth target, the `ailab-k8s` node at `172.16.50.50`, is reached with `kubectl`, not SSH):

```bash
ssh ailab-dev
ssh ailab-ml
ssh ailab-ds
ssh ailab-app
```

## Typical Session

```bash
ssh labadmin@<tailscale-ip>
./aipostex discover network --target 172.16.50.10,172.16.50.20,172.16.50.30,172.16.50.40
./aipostex mcp analyze --config ~/lab/mcp-configs/claude_desktop_config.json
./aipostex mcp --transport stdio --stdio-command python3 --stdio-args ~/lab/stdio-mcp-server.py enum
```

## Troubleshooting

- If Tailscale is down: `sudo systemctl restart tailscaled && sudo tailscale up`
- If target SSH fails: verify the VM is up and `verify-lab.sh` passes from the attack box
- If host keys changed after a rebuild: the lab SSH config already disables strict checking for these aliases
