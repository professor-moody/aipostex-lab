# Proxmox Setup

`proxmox-setup.sh` is the supported way to build the lab infrastructure. It creates the isolated bridge, prepares the Ubuntu and Debian templates, and clones **6 VMs total**:

- `ailab-dev` (`210`, `172.16.50.10`)
- `ailab-ml` (`220`, `172.16.50.20`)
- `ailab-ds` (`230`, `172.16.50.30`)
- `ailab-app` (`250`, `172.16.50.40`)
- `ailab-k8s` (`260`, `172.16.50.50`)
- `ailab-attack` (`240`, `172.16.50.99`)

```bash
sudo bash lab-scripts/proxmox-setup.sh
```

## What It Builds

| Item | Value |
|---|---|
| Bridge | `vmbr100` |
| Subnet | `172.16.50.0/24` |
| Gateway | `172.16.50.1` |
| Ubuntu template | `1101` |
| Debian template | `1102` |
| Target VMs | 5 |
| Total VMs | 6 |

The script is conservative on reruns: it reuses the bridge and templates when present and skips duplicate cloud image downloads, but it aborts if any target clone VM IDs already exist. For rebuilds, remove or rename existing lab VMs first.

## VM Layout

| VM ID | Hostname | IP | OS | Role |
|---|---|---|---|---|
| `210` | `ailab-dev` | `172.16.50.10` | Ubuntu 24.04 | Developer workstation |
| `220` | `ailab-ml` | `172.16.50.20` | Ubuntu 24.04 | ML platform |
| `230` | `ailab-ds` | `172.16.50.30` | Ubuntu 24.04 | Data science |
| `250` | `ailab-app` | `172.16.50.40` | Ubuntu 24.04 | Shared AI apps |
| `260` | `ailab-k8s` | `172.16.50.50` | Ubuntu 24.04 | Kubernetes node |
| `240` | `ailab-attack` | `172.16.50.99` | Debian 12 | Attack box |

## After The Script Finishes

Verify all VMs are running:

```bash
qm list | grep ailab
```

Confirm SSH reaches each guest:

```bash
for ip in 10 20 30 40 50 99; do
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "labadmin@172.16.50.${ip}" hostname
done
```

Then move on to deployment:

```bash
bash lab-scripts/deploy-all.sh
```

## Storage

`proxmox-setup.sh` clones onto `STORAGE` (default `local-lvm`, env-overridable). Set `STORAGE=<pool>`
to match your host — check `pvesm status`.

## Multiple isolated estates

To run several isolated estates on one host (e.g. one per group at a con), set `GROUP_ID` — every
VM ID, subnet, and bridge is derived from it (`GROUP_ID=0` is this base estate). See
[Multi-Estate Standup](multi-estate.md).

## Manual Reference

If you need to debug by hand, these are the clone IDs and static IPs:

```bash
qm clone 1101 210 --name ailab-dev --full
qm clone 1101 220 --name ailab-ml --full
qm clone 1101 230 --name ailab-ds --full
qm clone 1101 250 --name ailab-app --full
qm clone 1101 260 --name ailab-k8s --full
qm clone 1102 240 --name ailab-attack --full
```

```bash
qm set 210 --ipconfig0 "ip=172.16.50.10/24,gw=172.16.50.1"
qm set 220 --ipconfig0 "ip=172.16.50.20/24,gw=172.16.50.1"
qm set 230 --ipconfig0 "ip=172.16.50.30/24,gw=172.16.50.1"
qm set 250 --ipconfig0 "ip=172.16.50.40/24,gw=172.16.50.1"
qm set 260 --ipconfig0 "ip=172.16.50.50/24,gw=172.16.50.1"
qm set 240 --ipconfig0 "ip=172.16.50.99/24,gw=172.16.50.1"
```

## Notes

- Ubuntu is used for all five targets so the role scripts stay consistent.
- Debian remains the attack-box template to preserve a distinct operator host profile.
- `ailab-app` also hosts the TGI gateway, three A2A agents, and the Post-Ex Oracle alongside LangServe and Streamlit.
