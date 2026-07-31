# Deployment Evolution

The lab now supports three deployment tiers conceptually, but only one of them is the default.

## Current Support Model

- **Bash deploy** — canonical, simplest, and the primary documented path
- **Ansible deploy** — optional orchestration wrapper over the same Bash role scripts
- **Enterprise Proxmox** — separate `ent-*` topology managed by Bash scripts and optional Ansible wrappers
- **Terraform** — AWS-only cloud mirror path
- **Ludus** — future integration target after the role and inventory model stabilises

The goal is to keep the lab approachable for people who want to read the scripts and understand exactly what happens on each VM, while still creating a cleaner long-term automation path.

---

## Why Bash Stays Default

- Lowest barrier to entry
- Easy to debug one host at a time
- Matches the lab’s “real shadow AI sprawl” philosophy
- Keeps the source of truth obvious for contributors

The canonical deployment path remains:

```bash
bash lab-scripts/proxmox-setup.sh
bash lab-scripts/attack-box/setup.sh
bash lab-scripts/deploy-all.sh
```

The current 6-VM `ailab-*` deployment is the Mini tier. It should stay stable for demos, scoring, and conference workflows.

---

## Enterprise Track

The enterprise track lives beside the mini lab. It uses `ent-*` hostnames, multiple routed Proxmox bridges, and an enterprise inventory:

```bash
lab-scripts/lib/enterprise-inventory.sh
```

Preview the topology:

```bash
bash lab-scripts/proxmox-enterprise-setup.sh --dry-run
```

Create the Proxmox substrate:

```bash
sudo bash lab-scripts/proxmox-enterprise-setup.sh --profile team
```

Provision, seed, and verify the native enterprise services:

```bash
bash lab-scripts/enterprise-deploy.sh --phase base --profile team
bash lab-scripts/enterprise-deploy.sh --phase provision --profile team
bash lab-scripts/enterprise-deploy.sh --phase seed --profile team
bash lab-scripts/enterprise-verify.sh --layer all --profile team
```

The same Enterprise host/service phases can be orchestrated through Ansible after infrastructure exists:

```bash
bash lab-scripts/enterprise-deploy-ansible.sh --phase all --profile team
```

Terraform is intentionally not part of the Proxmox enterprise path. It remains AWS-only.

---

## Shared Inventory First

Before introducing more orchestration layers, the repo now centralises lab topology in:

```bash
lab-scripts/lib/inventory.sh
```

This is the shared source of truth for:

- hostnames
- IPs
- VM IDs
- role directories
- expected service counts
- scan ports
- verification totals

The Bash scripts use this inventory today, and the optional Ansible wrapper derives its runtime inventory from the same file.

Enterprise uses its own inventory so the mini lab can remain unchanged.

---

## Optional Ansible Path

The optional wrapper is:

```bash
bash lab-scripts/deploy-ansible.sh --phase all
```

It does not replace the Bash scripts. Instead, it:

- reads the same shared inventory
- copies the existing `lab-scripts/` tree to targets
- invokes the existing `provision.sh` and seed scripts
- runs verification from the attack box

Use it when you want a more structured orchestration path, inventory-driven execution, or easier future migration into more formal automation.

---

## Where Packer Fits

Packer is intentionally deferred.

Only add it if cloud-image/template drift becomes painful enough that prebuilding base Ubuntu and Debian templates saves real maintenance time. If introduced later, Packer should handle:

- base image customisation
- common package preinstalls
- template-level consistency

It should **not** absorb service provisioning or seeded data.

---

## Ludus Later

Ludus remains the long-term integration target, but not the immediate primary path. The intended order is:

1. Shared inventory and role cleanup in Bash
2. Optional Ansible wrapper using the same role boundaries
3. Optional Packer template work if needed
4. Ludus integration using the stabilised role/inventory model

That keeps the migration incremental and preserves the current attack workflow regardless of how the VMs were provisioned.
