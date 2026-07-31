---
title: Prerequisites
---

# Prerequisites

Everything you need before deploying the aipostex lab.

---

## Proxmox VE

A working Proxmox VE **8.x** installation with **root access** (or an account with full VM/storage/network permissions).

!!! warning "Version requirement"
    The lab scripts use `qm` and `pvesh` features available in Proxmox VE 8.0+. Earlier versions may not support all cloud-init options used by `proxmox-setup.sh`.

---

## Hardware Resources

### Minimum

| Resource | Requirement | Notes |
|---|---|---|
| **RAM** | 16 GB | Shared across 6 VMs (10 GB allocated to VMs in minimum config, rest for Proxmox) |
| **Storage** | 75 GB | Templates plus 6 VM disks, logs, model pulls, and snapshots |
| **vCPU** | 6 cores | Enough for five targets, one attack box, and light concurrent validation |

### Comfortable

| Resource | Recommendation |
|---|---|
| **RAM** | 32 GB |
| **Storage** | 120 GB |
| **vCPU** | 8+ cores |

!!! tip "Running on a home lab?"
    A used Dell OptiPlex or HP EliteDesk with 32 GB RAM and a 256 GB SSD handles this lab easily. Any x86_64 system running Proxmox works.

---

## Network

### Internet Access

Required during initial setup for:

- Downloading Ubuntu 24.04 and Debian 12 cloud images
- `apt install` packages on all VMs
- `pip install` for Python-based services (ChromaDB, MLflow, LiteLLM, JupyterLab, Gradio)
- Ollama model pull (~220 MB for `smollm2:135m`)
- Weaviate and Qdrant binary downloads from GitHub releases

!!! note
    After deployment, the lab runs fully offline. All services and data are local to the VMs.

### Isolated Bridge

The setup script creates `vmbr100` with subnet `172.16.50.0/24`. This bridge is **not** connected to your LAN by default — it's an isolated segment for the lab VMs.

!!! warning "IP conflicts"
    If `172.16.50.0/24` conflicts with an existing network on your host, edit the subnet variables in `proxmox-setup.sh` before running it.

---

## SSH Key

An SSH public key must exist on the Proxmox host. The setup script injects it into all VMs via cloud-init.

```bash
# Check for an existing key:
ls ~/.ssh/id_*.pub

# Generate one if needed:
ssh-keygen -t ed25519 -C "aipostex-lab"
```

!!! info
    The default key path used by `proxmox-setup.sh` is `~/.ssh/id_ed25519.pub`. If your key is at a different path, pass it as an argument or edit the script.

---

## Storage

The setup script needs a Proxmox storage target for VM disks and cloud-init images. Check available storage:

```bash
pvesm status
```

??? example "Example output"
    ```
    Name         Type     Status  Total       Used       Available  %
    local        dir      active  97283072    10240000   82043072   10.53%
    local-lvm    lvmthin  active  97283072    0          97283072   0.00%
    ```

The default storage target is `local-lvm`. If your storage has a different name, set it when running the setup:

```bash
STORAGE=your-storage-name bash proxmox-setup.sh
```

!!! warning "Storage type matters"
    `local` (directory) storage works but is slower. `local-lvm` (LVM-thin) or ZFS storage is recommended for snapshot performance.

---

## Optional: Tailscale

A [Tailscale](https://tailscale.com) account enables SSH access to the attack box from your development workstation without exposing the lab network.

```bash
# On the attack box (after deployment):
sudo tailscale up        # authenticate via the provided URL
tailscale ip -4          # note the Tailscale IP

# From your workstation:
ssh labadmin@<tailscale-ip>
```

!!! tip
    Tailscale is installed automatically on the attack box by `attack-box/setup.sh`. You just need to authenticate after first boot.

---

## Checklist

- [x] Proxmox VE 8.x with root access
- [x] 16+ GB RAM, 75 GB storage, 6+ vCPU
- [x] Internet access (initial setup only)
- [x] SSH public key on Proxmox host
- [x] Storage name confirmed via `pvesm status`
- [ ] *(Optional)* Tailscale account for remote access
