# aipostex Lab — AWS Terraform Deployment

Terraform is scoped to AWS only. Proxmox infrastructure is managed by Bash scripts and optional Ansible wrappers.

This directory stands up the full 6-node AWS mirror of the Proxmox lab topology, and can deploy **N isolated ranges** (the AWS analog of proxmox's multi-estate `GROUP_ID`). Each range is its own subnet + security group; range 0 is the default single-range lab.

## Quick Start

```bash
cd terraform
terraform init

# allowed_ssh_cidr is REQUIRED (no default) — set it to your operator IP/CIDR so SSH/22
# is not world-open and peer ranges cannot SSH into each other. Get your IP: curl ifconfig.me
#
# Single range (range 0 at 10.0.1.0/24) — the default.
terraform apply -var="ssh_public_key_path=~/.ssh/aipostex_rec.pub" -var="allowed_ssh_cidr=203.0.113.4/32"

# N isolated ranges (e.g. the con lab = 5 estates).
terraform apply -var="ssh_public_key_path=~/.ssh/aipostex_rec.pub" -var="allowed_ssh_cidr=203.0.113.4/32" -var='range_ids=[0,1,2,3,4]'
```

After apply, provision each range and (once green) bake its lab-ready AMIs:

```bash
RANGE=0 bash ../scripts/aws-provision.sh     # deploy + verify range 0
RANGE=1 bash ../scripts/aws-provision.sh     # ... range 1, etc.
RANGE=0 STAMP=$(date +%Y%m%d%H%M) bash ../scripts/aws-bake-ami.sh
RANGES="0 1 2 3 4" bash ../scripts/aws-reset-wave.sh   # parallel between-wave reset
```

## Architecture (per range K → subnet 10.0.(K+1).0/24)

| Instance | Role | Instance Type | Private IP (range K) |
|----------|------|---------------|----------------------|
| ailab-dev | Developer Workstation (Ollama) | c6i.xlarge | 10.0.(K+1).10 |
| ailab-ml | ML Platform (13 mocks + Ray) | t3.large | 10.0.(K+1).20 |
| ailab-ds | Data Science (Ollama) | c6i.xlarge | 10.0.(K+1).30 |
| ailab-app | Shared AI Apps / agents | t3.small | 10.0.(K+1).40 |
| ailab-k8s | single-node k3s cluster | t3.medium | 10.0.(K+1).50 |
| ailab-attack | Attack Box (deploy origin) | t3.large | 10.0.(K+1).99 |

Only Ollama (dev + ds) is real CPU inference → non-burstable `c6i.xlarge` (4 vCPU). A range is
**16 vCPU**, so the default 32-vCPU `L-1216C47` quota caps you at **N=2 ranges**; N=5 needs 80. Range 0 keeps unsuffixed Name tags (`aipostex-lab-<role>`) for lab-ready AMI back-compat; range K>0 uses `aipostex-lab-r<K>-<role>`.

## Isolation

Every range gets its own security group that admits **only its own /24** (all ports) plus operator SSH. All subnets share one VPC route table, so cross-range traffic is L3-routable — but a packet from range J's `10.0.(J+1).x` to range K's service port is dropped by range K's ingress. Estates are isolated on every service port. SSH/22 is isolated the same way: it admits only `allowed_ssh_cidr` (required, the operator IP/CIDR — never `0.0.0.0/0`, enforced by a variable validation), and a peer range's subnet is in neither that CIDR nor range K's own /24, so cross-range SSH is dropped as well. `scripts/aws-verify-isolation.sh` probes both service ports and SSH/22 for every ordered range pair.

## Provisioning

`user_data` cloud-init creates the `labadmin` account (operator key) and a range-scoped `/etc/hosts`. `scripts/aws-provision.sh RANGE=K` then runs the same bash provisioners as the Proxmox lab from that range's attack box, threading `LAB_SUBNET=10.0.(K+1)`.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | us-east-1 | AWS region |
| `vpc_cidr` | 10.0.0.0/16 | VPC CIDR (must cover every range's /24) |
| `range_ids` | `[0]` | Range/estate ids to deploy; con lab = `[0,1,2,3,4]` |
| `ssh_public_key_path` | (required) | Path to SSH public key (baked as labadmin's key) |
| `instance_type_ollama` | c6i.xlarge | dev + ds (real Ollama inference, 4 vCPU) |
| `instance_type_attack` | t3.large | attack box (~25 seat shells + the tool) |
| `wg_ingress_cidr` | — | WireGuard UDP ingress CIDR (governs the attendee entrance) |
| `instance_type_ml` | t3.large | ml platform |
| `instance_type_k8s` | t3.medium | single-node k3s |
| `instance_type_small` | t3.small | app + attack |
| `allowed_ssh_cidr` | (required) | Operator IP/CIDR allowed to SSH; the SSH/22 isolation boundary — must not be `0.0.0.0/0` |
| `name_prefix` | aipostex-lab | Prefix for all resource names |

## Cleanup

```bash
terraform destroy -var="ssh_public_key_path=~/.ssh/aipostex_rec.pub" -var="allowed_ssh_cidr=203.0.113.4/32" -var='range_ids=[0,1,2,3,4]'
```
