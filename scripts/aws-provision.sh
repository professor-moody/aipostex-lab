#!/usr/bin/env bash
# aws-provision.sh — provision a freshly `terraform apply`-ed AWS range into a green lab.
#
# Run from the DEV machine AFTER `terraform apply`. Provisions ONE range at a time
# (RANGE=K, default 0). The range's attack box (10.0.(K+1).99) is the deploy origin: it
# reaches the four role hosts by private IP inside the range's subnet, exactly like the
# Proxmox host does on-prem. Everything flows through LAB_SUBNET=10.0.(K+1) — inventory.sh
# derives all host IPs from it, so no lab-script edits are needed beyond the cloud-init
# labadmin key (baked into terraform/cloud-init.tftpl).
#
# Instances are discovered by EC2 Name tag (not terraform outputs), so this works for any
# range independent of the terraform output shape — matching aws-reset-wave.sh. Range 0 has
# unsuffixed Name tags (aipostex-lab-<role>); range K>0 -> aipostex-lab-r<K>-<role>.
#
# Usage:
#   RANGE=0 bash scripts/aws-provision.sh          # provision range 0
#   RANGE=1 bash scripts/aws-provision.sh          # provision range 1 (10.0.2.x), etc.
#
# Prereqs:
#   - the range's 6 instances exist + running (terraform apply -var 'range_ids=[...]')
#   - ~/.ssh/aipostex_rec  (its .pub is baked into cloud-init as labadmin's authorized_key)
#   - a linux/amd64 aipostex binary (AIPOSTEX_BIN, default /tmp/aipostex-linux-amd64)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RANGE="${RANGE:-0}"
LAB_SUBNET_AWS="10.0.$(( RANGE + 1 ))"
KEY="${AWS_LAB_KEY:-$HOME/.ssh/aipostex_rec}"
AIPOSTEX_BIN="${AIPOSTEX_BIN:-/tmp/aipostex-linux-amd64}"
NAME_PREFIX="${NAME_PREFIX:-aipostex-lab}"
SEATS="${SEATS:-25}"
export AWS_PROFILE="${AWS_PROFILE:-aipostex}"
SSH_OPTS="-i ${KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
ROLES="ailab-dev ailab-ml ailab-ds ailab-app ailab-k8s ailab-attack"

log(){ echo -e "\033[0;36m[$(date +%H:%M:%S)]\033[0m $*"; }
ok(){  echo -e "\033[0;32m[+]\033[0m $*"; }
die(){ echo -e "\033[0;31m[!]\033[0m $*" >&2; exit 1; }
rsh(){ ssh $SSH_OPTS "labadmin@$1" "${@:2}"; }

# range 0 -> unsuffixed Name tag; range K>0 -> "-r<K>-".
name_tag(){ [ "$RANGE" = 0 ] && echo "${NAME_PREFIX}-$1" || echo "${NAME_PREFIX}-r${RANGE}-$1"; }
public_ip(){ aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$(name_tag "$1")" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null; }

command -v jq >/dev/null || die "jq required"
[[ -f "$KEY" ]] || die "ssh key $KEY not found"
[[ -f "$AIPOSTEX_BIN" ]] || die "aipostex binary $AIPOSTEX_BIN not found (cross-compile it first)"

log "discovering range $RANGE instances (LAB_SUBNET=$LAB_SUBNET_AWS) by Name tag ..."
ATTACK_PUB=$(public_ip ailab-attack)
[[ -n "$ATTACK_PUB" && "$ATTACK_PUB" != "None" ]] || die "no running attack box for range $RANGE ($(name_tag ailab-attack)) — did terraform apply this range?"
ALL_PUB=""
for role in $ROLES; do
  ip=$(public_ip "$role")
  [[ -n "$ip" && "$ip" != "None" ]] || die "no running instance for $role ($(name_tag "$role"))"
  ALL_PUB="$ALL_PUB $ip"
done
log "attack box public IP: $ATTACK_PUB"

log "waiting for labadmin SSH on all range-$RANGE instances..."
for ip in $ALL_PUB; do
  for i in $(seq 1 60); do
    rsh "$ip" true 2>/dev/null && { ok "ssh ready: $ip"; break; }
    [[ $i -eq 60 ]] && die "ssh timeout: $ip"
    sleep 5
  done
done

# ── stage the attack box (deploy origin) ─────────────────────────────────────
log "staging lab-scripts + intra-VPC key + aipostex binary on the attack box..."
rsh "$ATTACK_PUB" "mkdir -p ~/lab ~/.ssh && chmod 700 ~/.ssh"
scp $SSH_OPTS -r "$REPO_ROOT/lab-scripts/." "labadmin@$ATTACK_PUB:~/lab/"
# The attack box's labadmin key IS aipostex_rec, so it can SSH labadmin@peers — the peers
# trust aipostex_rec.pub via cloud-init. deploy-all phase 1 also re-distributes id_ed25519.pub.
scp $SSH_OPTS "$KEY"      "labadmin@$ATTACK_PUB:~/.ssh/id_ed25519"
scp $SSH_OPTS "$KEY.pub"  "labadmin@$ATTACK_PUB:~/.ssh/id_ed25519.pub"
scp $SSH_OPTS "$AIPOSTEX_BIN" "labadmin@$ATTACK_PUB:~/aipostex"
rsh "$ATTACK_PUB" "chmod 600 ~/.ssh/id_ed25519 && chmod +x ~/aipostex"
ok "attack box staged"

log "base-setup + attack-box provision (lab-listener :9000, mcp-configs)..."
rsh "$ATTACK_PUB" "sudo env LAB_INVENTORY_PATH=/home/labadmin/lab/lib/inventory.sh bash /home/labadmin/lab/base-setup.sh"
# Thread LAB_SUBNET so the mcp-config fixtures (remote_mcp_chain.json uses \$DEV_IP =
# inventory_host_ip ailab-dev) point at THIS range's dev host, not the proxmox default.
rsh "$ATTACK_PUB" "sudo env LAB_SUBNET=$LAB_SUBNET_AWS bash /home/labadmin/lab/attack-box/provision.sh"
ok "attack box provisioned"

# ── deploy the 4 role hosts FROM the attack box (private IPs) ─────────────────
# Run deploy-all inside a DETACHED tmux session on the attack box + enable lingering,
# so a dropped local SSH during the ~15-min provision can't reap it (deploy-all +
# provision.sh use `set -e`; a plain nohup/setsid child still gets torn down when the
# launching login session ends — tmux + enable-linger is what actually survives).
log "starting deploy-all in a detached tmux session on the attack box (LAB_SUBNET=$LAB_SUBNET_AWS)..."
rsh "$ATTACK_PUB" "command -v tmux >/dev/null 2>&1 || sudo apt-get install -y -qq tmux; sudo loginctl enable-linger labadmin"
rsh "$ATTACK_PUB" "tmux kill-session -t deploy 2>/dev/null; tmux new-session -d -s deploy 'cd ~/lab && LAB_SUBNET=$LAB_SUBNET_AWS bash deploy-all.sh 2>&1 | tee /tmp/deploy-all.log'"
log "polling deploy-all to completion (tolerant of transient SSH drops)..."
dead=0
while true; do
  sleep 25
  # `|| true` on both substitutions is load-bearing: under `set -euo pipefail` a transient SSH
  # drop (rsh -> 255) OR grep -vE '%$' filtering out an all-progress-bar tail (exit 1) would
  # otherwise kill the whole script mid-poll — which defeats the "tolerant of transient drops"
  # design and, worse, abandons a deploy-all that is still running fine in the detached tmux.
  st=$(rsh "$ATTACK_PUB" 'if grep -q "Deployment completed" /tmp/deploy-all.log 2>/dev/null; then echo COMPLETED; elif tmux has-session -t deploy 2>/dev/null; then echo ALIVE; else echo DEAD; fi' 2>/dev/null | tr -d '[:space:]' || true)
  line=$(rsh "$ATTACK_PUB" "tail -1 /tmp/deploy-all.log 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -vE '%\$'" 2>/dev/null || true)
  [[ -n "$line" ]] && echo "    [deploy-all] $line"
  [[ "$st" == "COMPLETED" ]] && { ok "deploy-all complete"; break; }
  # A single DEAD reading is usually a transient SSH/tmux glitch, not a real death —
  # require two in a row (empty readings from a failed SSH don't count) before giving up.
  if [[ "$st" == "DEAD" ]]; then dead=$((dead + 1)); else dead=0; fi
  [[ $dead -ge 2 ]] && die "deploy-all tmux session ended without completing — inspect /tmp/deploy-all.log on the attack box ($ATTACK_PUB)"
done

# ── finalize the attack box: seats (essential) + optional offline docs ────────
# provision-seats.sh installs the binary to /usr/local/bin (so `aipostex sessions` resolves for
# seats), creates p01..p<SEATS>, and bakes MaxAuthTries 30. This MUST run before aws-bake-ami.sh
# so the AMI carries the seats — the AWS analog of the on-prem "run before the lab-ready snapshot".
# lab-scripts are already staged at ~/lab on the box (deploy origin), and the binary at ~/aipostex.
log "provisioning $SEATS attendee seats (installs /usr/local/bin/aipostex, MaxAuthTries 30)..."
rsh "$ATTACK_PUB" "sudo SEATS=$SEATS bash /home/labadmin/lab/attack-box/provision-seats.sh"
ok "seats provisioned"

# Optional offline in-lab docs on :80. Build the mkdocs site off-box (overlay the real attendee
# cards, add theme.font:false) and point LAB_DOCS_TGZ at the tarball; skipped if unset.
if [[ -n "${LAB_DOCS_TGZ:-}" && -f "${LAB_DOCS_TGZ}" ]]; then
  log "installing offline in-lab docs on :80 from ${LAB_DOCS_TGZ}..."
  scp $SSH_OPTS "$LAB_DOCS_TGZ" "labadmin@$ATTACK_PUB:/tmp/labdocs.tgz"
  rsh "$ATTACK_PUB" "sudo bash /home/labadmin/lab/attack-box/serve-docs.sh /tmp/labdocs.tgz"
  ok "in-lab docs serving on :80"
else
  log "skipping in-lab docs (set LAB_DOCS_TGZ=/path/to/labdocs.tgz to bake the offline docs on :80)"
fi

echo
ok "AWS range $RANGE provisioned. Verify from the attack box:"
echo "    ssh -i $KEY labadmin@$ATTACK_PUB"
echo "    cd ~/lab && LAB_SUBNET=$LAB_SUBNET_AWS bash verify-lab.sh            # expect 62/0"
echo "    cd ~/lab && LAB_SUBNET=$LAB_SUBNET_AWS bash ctf/verify-chain.sh      # expect 13/13"
echo "    LAB_SUBNET=$LAB_SUBNET_AWS bash ~/lab/attack-box/verify-aipostex.sh --layer all  # expect ~393/1 (1 known transient)"
echo "    ssh p01@$ATTACK_PUB  # seat login (pw from provision-seats), then run the attendee chain"
