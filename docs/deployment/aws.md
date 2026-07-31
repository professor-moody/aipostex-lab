# AWS Deployment (Turnkey Cloud Ranges)

The lab runs on AWS as a full 6-node mirror of the Proxmox estate, so you can stand a range up
in the cloud with no on-prem hypervisor — and stand up **N isolated ranges** in parallel (the
AWS analog of Proxmox multi-estate `GROUP_ID`). This is a **validated turnkey path**:
`terraform apply` → one provisioning command per range → green (verify-lab 62/0 +
verify-chain 13/13 + verify-aipostex ~393/1), with a between-wave `reset-wave` and proven
cross-range isolation.

> Proxmox remains the primary path for multi-estate workshop hosting; AWS gives you portable,
> self-contained ranges (CI, a remote demo box, workshop overflow, or resilience).

## Topology (per range K → subnet `10.0.(K+1).0/24`)

| Instance | Role | Type | Private IP (range K) |
|---|---|---|---|
| ailab-dev | Developer Workstation (Ollama) | c6i.large | 10.0.(K+1).10 |
| ailab-ml | ML Platform (13 mocks + Ray) | t3.large | 10.0.(K+1).20 |
| ailab-ds | Data Science (Ollama) | c6i.large | 10.0.(K+1).30 |
| ailab-app | Shared AI Apps / agents | t3.small | 10.0.(K+1).40 |
| ailab-k8s | single-node k3s "ACME cluster" | t3.medium | 10.0.(K+1).50 |
| ailab-attack | Attack Box (deploy origin) | t3.large | 10.0.(K+1).99 |

All ranges share one VPC (`10.0.0.0/16`). Range 0 uses subnet `10.0.1.0/24` and **unsuffixed**
Name tags (`aipostex-lab-<role>`) for lab-ready-AMI back-compat; range K>0 uses `10.0.(K+1).0/24`
and `aipostex-lab-r<K>-<role>`. `LAB_SUBNET=10.0.(K+1)` threads through `inventory.sh`, so every
host IP and peer config resolves within the range with **no lab-script changes** — the same
native `provision.sh` / `seed.sh` as on Proxmox.

Only Ollama (dev + ds) is real CPU inference → non-burstable `c6i.large`; everything else is
light. A 6-node range is **12 vCPU**; running cost ≈ **$0.34/hr** (us-east-1 on-demand).

## Prerequisites

- **AWS profile** with EC2 + VPC permissions. Configure locally (`aws configure --profile aipostex`)
  and `export AWS_PROFILE=<your-aws-profile>`.
- **SSH keypair** whose public key becomes the operator + `labadmin` key. Default
  `~/.ssh/<your-key>` (reused from the on-prem attack box).
- **terraform** ≥ 1.5, **aws-cli** v2, **jq**.
- A **linux/amd64 `aipostex` binary** for the attack box (cross-compile from the tool repo):
  ```bash
  GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build \
    -ldflags "-s -w -X github.com/professor-moody/aipostex/internal/config.Version=$(git rev-parse --short HEAD)" \
    -o /tmp/aipostex-linux-amd64 ./cmd/aipostex
  ```

### vCPU quota (the multi-range ceiling)

Each 6-node range is **12 vCPU**, and every node is already the 2-vCPU floor (6 × 2). The AWS
account's **Running On-Demand Standard** quota (`L-1216C47`, us-east-1) is what caps how many
ranges you can run: at the default **32 vCPU** you get **N=2** (24 vCPU); N=3 needs 36. To run
**N=5**, raise `L-1216C47` to **64** via the Service Quotas console (the lab IAM user typically
lacks `servicequotas:*`, so do it as an account admin). See also
[subset ranges](#subset-tactic-ranges) — attendee ranges that drop the presenter-only k8s node
fit more per quota.

## 1. Provision the infrastructure

```bash
cd terraform
export AWS_PROFILE=<your-aws-profile>
terraform init

# Single range (range 0) — the default:
terraform apply -var="ssh_public_key_path=$HOME/.ssh/<your-key>.pub" \
                -var="allowed_ssh_cidr=$(curl -s https://checkip.amazonaws.com)/32"

# N isolated ranges (e.g. a 2-estate workshop under the default quota):
terraform apply -var="ssh_public_key_path=$HOME/.ssh/<your-key>.pub" \
                -var="allowed_ssh_cidr=$(curl -s https://checkip.amazonaws.com)/32" -var='range_ids=[0,1]'
```

`allowed_ssh_cidr` is **required** (no default) and rejects `0.0.0.0/0` — set it to your operator IP
(`-var="allowed_ssh_cidr=$(curl -s https://checkip.amazonaws.com)/32"`). Attendees reach the box over
the WireGuard entrance, not SSH (see [Access model](#access-model)). cloud-init creates `labadmin`
with your key and a range-scoped `/etc/hosts` (a range never name-resolves another estate's peers).

> **New-account note:** a brand-new account may return `PendingVerification` / `VcpuLimitExceeded`
> on first launch. Re-run `terraform apply` once the account clears — it creates only the missing
> instances.

## 2. Provision each range

One command per range from the dev machine (the range's **attack box is the deploy origin**,
reaching the role hosts by private IP inside the range's subnet). Instances are discovered by
EC2 Name tag, so this is independent of the terraform output shape:

```bash
AIPOSTEX_BIN=/tmp/aipostex-linux-amd64 RANGE=0 bash scripts/aws-provision.sh
AIPOSTEX_BIN=/tmp/aipostex-linux-amd64 RANGE=1 bash scripts/aws-provision.sh   # ... per range
```

Each run waits for `labadmin` SSH, stages `lab-scripts` + the `<your-key>` key + the binary onto
that range's attack box, runs `attack-box/provision.sh` (lab-listener :9000, mcp-configs), then runs
`LAB_SUBNET=10.0.(K+1) deploy-all.sh` (in a detached tmux, tolerant of SSH drops) to bring the role
hosts up and seed them. Ranges are independent — provision them in parallel.

## 3. Verify green

```bash
# on each range's attack box (RANGE 0 shown):
cd ~/lab && LAB_SUBNET=10.0.1 bash verify-lab.sh          # expect 62 passed / 0 failed
cd ~/lab && LAB_SUBNET=10.0.1 bash ctf/verify-chain.sh    # expect 13/13
LAB_SUBNET=10.0.1 bash ~/lab/attack-box/verify-aipostex.sh --layer all   # expect ~393/1 (1 known transient)
```

**Cross-range isolation** — prove estates can't reach each other's service ports (each range's SG
admits only its own /24):

```bash
RANGES="0 1" bash scripts/aws-verify-isolation.sh
# control: each range reaches its own services (rc 0); isolation: a probe to another
# range's service port times out (rc 28 = SG drop, not "refused"). Expect all PASS.
```

## 4. Bake the lab-ready AMIs + between-wave reset

Snapshot the green instances so a between-wave reset is a fast disk-restore (the cloud equivalent of
the `lab-ready` Proxmox snapshot + `reset-wave`):

```bash
RANGE=0 STAMP=$(date +%Y%m%d%H%M) bash scripts/aws-bake-ami.sh   # tags LabReady=r0,Role=<role>
RANGE=1 STAMP=$(date +%Y%m%d%H%M) bash scripts/aws-bake-ami.sh   # ... per range

# reset any/all ranges in parallel from their baked AMIs (restore root volume -> re-arm -> verify):
RANGES="0 1" bash scripts/aws-reset-wave.sh                      # expect each PASS (62/0 + 13/13)
```

`aws-reset-wave.sh` uses `create-replace-root-volume-task` (the direct analog of `qm rollback`),
keeping the instance, ENI, private IP, and type, then re-arms the state a disk restore can't hold
(seed ml, restart acme-mcp, warm Ollama) and re-verifies.

## 5. Con-day bring-up (from parked standby)

The backup estate is normally **parked = instances stopped** (EBS + AMIs only). Bringing it live
takes ~3 minutes. The attack box's **public IP is ephemeral** — it changes on every stop/start, so
the WireGuard client `.conf` (whose `Endpoint` is that IP) is **generated at bring-up, not before**.

```bash
export AWS_PROFILE=aipostex
# 1. Start every stopped lab instance (discover by the Project tag).
#    Piping through xargs splits the IDs the same in bash and zsh.
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=aipostex-lab" "Name=instance-state-name,Values=stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text \
  | xargs aws ec2 start-instances --instance-ids

# 2. Re-arm from the baked AMIs and re-verify (seed ml, restart mocks, warm Ollama)
RANGES="0" bash scripts/aws-reset-wave.sh               # expect PASS (62/0 + 13/13)

# 3. Rediscover the NEW attack-box public IP
BOX=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=aipostex-lab-ailab-attack" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "attack box: $BOX"
```

**Generate + hand out the WireGuard configs** (this is the file you import into a WireGuard client):

```bash
# On the dev machine — fully offline; produces ./attendee-access/wireguard/*.conf + relay-peers.conf
ESTATE_SCHEME=aws bash scripts/gen-attendee-access.sh --groups 0 --per-group-only \
  --seats 25 --attack-box "$BOX" --relay-endpoint "${BOX}:51820" --out ./attendee-access

# Register the peers on the relay (attack box) and bring wg0 up
scp -r ./attendee-access labadmin@"$BOX":~/
ssh labadmin@"$BOX" 'sudo ESTATE_SCHEME=aws bash ~/lab/scripts/provision-relay.sh --groups 0 \
    --server-key ~/attendee-access/wireguard/relay-server.key \
    --peers      ~/attendee-access/wireguard/relay-peers.conf'
```

The client config is **`./attendee-access/wireguard/p01.conf`** (one per seat, `p01`..`p25`). Import
it (desktop) or scan `p01.png` (mobile), turn WireGuard on, and you tunnel to only `10.0.1.0/24`.
Smoke-test the tunnel by hitting a service on the estate, e.g. `curl http://10.0.1.20:8265` (the Ray
dashboard) or run the guided chain from `p01`. **Park again** when done:

```bash
aws ec2 describe-instances --filters "Name=tag:Project,Values=aipostex-lab" \
  "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].InstanceId' \
  --output text | xargs aws ec2 stop-instances --instance-ids
```

## Access model

Provisioning uses a **public IP + SSH** (lock `allowed_ssh_cidr` to your operator IP). For the
attendee-facing / standing deployment, move to a VPN entrance and drop the public-SSH rule:

- **WireGuard entrance (built):** the attack box terminates a WireGuard endpoint on UDP 51820, opened
  by the `wg_ingress_cidr` SG rule (default `0.0.0.0/0` — WG's security is the key exchange, not IP
  filtering). Generate per-attendee `.conf`s with `ESTATE_SCHEME=aws bash scripts/gen-attendee-access.sh`
  and bring up the relay with `ESTATE_SCHEME=aws bash scripts/provision-relay.sh` on the box; each
  `.conf`'s `AllowedIPs` plus the relay iptables scope a tunnel to only its range's `10.0.(K+1).0/24`.
  SSH/22 stays operator-CIDR-only. This mirrors the Ludus/RTV per-range model (`docs/deployment/ludus.md`).
- **Tailscale standing entrance (operator):** install Tailscale on the attack box so it joins your
  tailnet outbound, **before** baking the AMI, then drop the SG SSH rule:
  ```bash
  sudo tailscale up --authkey <tskey-...>          # one-off auth key
  sudo tailscale up --advertise-routes=10.0.(K+1).0/24   # optional: reach the whole range
  ```

## Isolation & hardening

Each range is a **network island**:

- Its own **subnet + security group**; the SG admits only that range's own /24 (all ports) plus
  operator SSH, so estates are isolated on every service port (proven by `aws-verify-isolation.sh`).
- The EC2 instances carry **no IAM instance profile** — a popped box has zero AWS-account reach.
- Every resource is tagged `Project=aipostex-lab` for clean teardown.

## Subset (tactic) ranges

The hands-on attendee tactic is the credential chain, which needs only `dev, ml, ds, app, attack`
(5 VMs, no k8s — the k8s coda is a presenter/sandbox beat). Deploying attendee ranges without the
k8s node saves 2 vCPU each, fitting **3 chain ranges** under the default 32-vCPU quota vs 2 full.
Profile-based subset deployment (`var.ranges` profiles + `deploy-all.sh --only`) is a documented
follow-on — see the multi-range/profiles plan.

## Teardown

```bash
cd terraform && terraform destroy \
  -var="ssh_public_key_path=$HOME/.ssh/<your-key>.pub" -var='range_ids=[0,1]'
```

Deregister any transient baked AMIs + their snapshots you no longer need (keep the `r0` baseline for
fast redeploy):

```bash
for a in $(aws ec2 describe-images --owners self --filters "Name=tag:LabReady,Values=r1" \
             --query 'Images[].ImageId' --output text); do aws ec2 deregister-image --image-id "$a"; done
```
