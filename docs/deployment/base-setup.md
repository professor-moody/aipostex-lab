# Base OS Setup

`base-setup.sh` prepares every VM with the shared baseline the lab expects before role provisioning starts.

```bash
sudo bash lab-scripts/base-setup.sh
```

## What It Does

- installs the common package set used by the role provisioners
- enables `qemu-guest-agent`
- ensures `/etc/hosts` contains every lab host
- repairs DNS by adding a resolver if needed

## Shared Host Entries

The script now writes the host map from the shared lab inventory, so all six VMs stay in sync:

```text
172.16.50.10  ailab-dev
172.16.50.20  ailab-ml
172.16.50.30  ailab-ds
172.16.50.40  ailab-app
172.16.50.50  ailab-k8s
172.16.50.99  ailab-attack
```

## Typical Use

`deploy-all.sh` and the optional Ansible path both call this automatically. Run it by hand only when debugging a single host:

```bash
for ip in 10 20 30 40 50; do
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "labadmin@172.16.50.${ip}" "mkdir -p ~/lab"
  scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -r \
    lab-scripts/base-setup.sh lab-scripts/lib \
    "labadmin@172.16.50.${ip}:~/lab/"
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "labadmin@172.16.50.${ip}" \
    "sudo env LAB_INVENTORY_PATH=/home/labadmin/lab/lib/inventory.sh bash /home/labadmin/lab/base-setup.sh"
done
```

The attack box uses `attack-box/setup.sh` plus `attack-box/provision.sh`, but the Ansible wrapper also runs the shared base setup there for consistency.

## Snapshot Point

If you want a clean checkpoint before services:

```bash
for vmid in 210 220 230 250 260 240; do
  qm snapshot "$vmid" base-setup --description "Base packages and host inventory"
done
```

## Why This Matters

The shared inventory refactor means the host/IP map no longer needs to be maintained by hand across deploy, verify, and docs. `base-setup.sh` is one of the scripts that now consumes that source of truth directly.
