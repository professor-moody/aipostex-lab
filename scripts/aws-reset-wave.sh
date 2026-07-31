#!/usr/bin/env bash
# aws-reset-wave.sh — between-wave reset of AWS range(s) to the clean lab-ready baseline.
# The AWS equivalent of lab-scripts/reset-wave.sh. Per range:
#   1. restore each node's ROOT VOLUME from its baked lab-ready AMI
#      (create-replace-root-volume-task — a clean-disk restore that keeps the instance,
#       ENI, private IP and type; the direct equivalent of `qm rollback`)
#   2. boot-wait
#   3. re-arm the state a disk restore can't hold (seed ml Ray/MLflow/ChromaDB + restart
#      acme-mcp on dev) — exactly what proxmox reset-wave re-arms
#   4. verify-lab + verify-chain
# Ranges reset in parallel.
#
# Usage:
#   RANGES="0" bash scripts/aws-reset-wave.sh              # reset range 0
#   RANGES="0 1 2" bash scripts/aws-reset-wave.sh          # 3 ranges in parallel
#   DRY_RUN=1 RANGES="0" bash scripts/aws-reset-wave.sh    # preview, touch nothing
#   SKIP_VERIFY=1 RANGES="0" ...                           # restore + re-arm only
# Prereqs: baked lab-ready AMIs tagged LabReady=r<K>,Role=<role> (scripts/aws-bake-ami.sh).
set -uo pipefail
export AWS_PROFILE="${AWS_PROFILE:-aipostex}"
KEY="${AWS_LAB_KEY:-$HOME/.ssh/aipostex_rec}"
RANGES="${RANGES:-0}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_VERIFY="${SKIP_VERIFY:-0}"
SSH_OPTS="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes"
ROLES="ailab-dev ailab-ml ailab-ds ailab-app ailab-k8s ailab-attack"

# range 0 is the base range at 10.0.1 (unsuffixed instance names); range K>0 -> 10.0.(K+1) + "-rK".
name_tag(){ [ "$1" = 0 ] && echo "aipostex-lab-$2" || echo "aipostex-lab-r$1-$2"; }
subnet_for(){ echo "10.0.$(( $1 + 1 ))"; }

instance_id(){ aws ec2 describe-instances --filters "Name=tag:Name,Values=$(name_tag "$1" "$2")" "Name=instance-state-name,Values=running,stopped" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null; }
attack_pub(){ aws ec2 describe-instances --filters "Name=tag:Name,Values=$(name_tag "$1" ailab-attack)" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null; }
labready_ami(){ aws ec2 describe-images --filters "Name=tag:LabReady,Values=r$1" "Name=tag:Role,Values=$2" "Name=state,Values=available" --query 'reverse(sort_by(Images,&CreationDate))[0].ImageId' --output text 2>/dev/null; }

# Identity guard: confirm an instance really belongs to range K — its subnet is 10.0.(K+1).0/24
# AND its security group is range K's -internal- SG — BEFORE we replace (and delete) its root
# volume. A Name-tag collision or a wrong RANGES value then cannot trigger a destructive,
# volume-deleting root replace on the wrong instance.
verify_instance_range(){ # $1=range  $2=iid -> 0 ok / 1 mismatch (prints reason)
  local K=$1 iid=$2 want_cidr sg_want subnet_id sg_names subnet_cidr
  want_cidr="10.0.$(( K + 1 )).0/24"
  sg_want=$(name_tag "$K" internal)   # aipostex-lab-internal | aipostex-lab-r<K>-internal
  read -r subnet_id sg_names < <(aws ec2 describe-instances --instance-ids "$iid" \
    --query 'Reservations[0].Instances[0].[SubnetId, join(`,`, SecurityGroups[].GroupName)]' \
    --output text 2>/dev/null)
  subnet_cidr=$(aws ec2 describe-subnets --subnet-ids "$subnet_id" \
    --query 'Subnets[0].CidrBlock' --output text 2>/dev/null)
  if [ "$subnet_cidr" != "$want_cidr" ]; then
    echo "[r$K]   [!] $iid subnet '$subnet_cidr' != expected '$want_cidr' — SKIP (no destructive replace)"; return 1
  fi
  case ",$sg_names," in *",${sg_want}"*) return 0 ;; esac
  echo "[r$K]   [!] $iid SG '$sg_names' has no '${sg_want}*' group — SKIP (no destructive replace)"; return 1
}

reset_range(){
  local K=$1 subnet ap iid ami tid task_ids="" pending
  subnet=$(subnet_for "$K")
  echo "[r$K] restoring root volumes from lab-ready AMIs ..."
  for role in $ROLES; do
    iid=$(instance_id "$K" "$role"); ami=$(labready_ami "$K" "$role")
    if [ -z "$iid" ] || [ "$iid" = None ] || [ -z "$ami" ] || [ "$ami" = None ]; then
      echo "[r$K]   [!] $role: instance='$iid' ami='$ami' — skipping"; continue
    fi
    verify_instance_range "$K" "$iid" || continue
    if [ "$DRY_RUN" = 1 ]; then echo "[r$K]   would restore $role ($iid) <- $ami"; continue; fi
    tid=$(aws ec2 create-replace-root-volume-task --instance-id "$iid" --image-id "$ami" \
            --delete-replaced-root-volume --query ReplaceRootVolumeTask.ReplaceRootVolumeTaskId --output text)
    task_ids="$task_ids $tid"; echo "[r$K]   $role <- $ami  (task $tid)"
  done
  [ "$DRY_RUN" = 1 ] && { echo "[r$K] dry-run done"; return 0; }

  echo "[r$K] waiting for root-volume replacement to finish ..."
  for _ in $(seq 1 60); do
    # shellcheck disable=SC2086
    pending=$(aws ec2 describe-replace-root-volume-tasks --replace-root-volume-task-ids $task_ids \
                --query 'ReplaceRootVolumeTasks[?TaskState!=`succeeded`]|length(@)' --output text 2>/dev/null)
    [ "$pending" = 0 ] && break; sleep 10
  done

  ap=$(attack_pub "$K")
  echo "[r$K] boot-wait attack box $ap ..."
  for _ in $(seq 1 40); do ssh $SSH_OPTS labadmin@"$ap" true 2>/dev/null && break; sleep 8; done

  echo "[r$K] re-arm: seed ml + restart acme-mcp ..."
  ssh $SSH_OPTS -n labadmin@"$ap" "
    ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 labadmin@${subnet}.20 'sudo env ESTATE_SUBNET=${subnet} bash ~/lab/ml-platform/seed.sh' >/dev/null 2>&1
    ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 labadmin@${subnet}.10 'sudo systemctl restart acme-mcp' 2>/dev/null || true" 2>/dev/null

  # Warm Ollama on dev + ds — after a disk-restore reboot the model is cold, and the chain's
  # first real-inference request would time out and false-fail verify-chain (it's fine seconds
  # later). Force the model load now so verification sees a warm server.
  echo "[r$K] warming Ollama (dev+ds) ..."
  ssh $SSH_OPTS -n labadmin@"$ap" "
    ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 labadmin@${subnet}.10 'echo hi | ollama run smollm2:135m >/dev/null 2>&1' || true
    ssh -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 labadmin@${subnet}.30 'echo hi | ollama run smollm2:135m >/dev/null 2>&1' || true" 2>/dev/null

  if [ "$SKIP_VERIFY" = 1 ]; then echo "[r$K] PASS (reset + re-arm; verify skipped)"; return 0; fi
  local vl vc
  vl=$(ssh $SSH_OPTS -n labadmin@"$ap" "cd ~/lab && LAB_SUBNET=${subnet} bash verify-lab.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '[0-9]+ passed, [0-9]+ failed' | tail -1" 2>/dev/null)
  vc=$(ssh $SSH_OPTS -n labadmin@"$ap" "cd ~/lab && LAB_SUBNET=${subnet} bash ctf/verify-chain.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '[0-9]+ passed, [0-9]+ failed' | tail -1" 2>/dev/null)
  echo "[r$K] verify-lab: ${vl:-?} | verify-chain: ${vc:-?}"
  if echo "$vl" | grep -q ", 0 failed" && echo "$vc" | grep -q ", 0 failed"; then
    echo "[r$K] PASS"
    return 0
  else
    echo "[r$K] FAIL — see verify output above"
    return 1
  fi
}

echo "aws-reset-wave: ranges=[$RANGES] dry-run=$DRY_RUN skip-verify=$SKIP_VERIFY"
pids=""
for K in $RANGES; do reset_range "$K" & pids="$pids $!"; done
# Collect each range's exit status — a backgrounded reset_range returns non-zero on FAIL.
# `wait $pids` alone discards those, so a failed backup-range reset would exit 0 (false success).
rc=0
# shellcheck disable=SC2086
for pid in $pids; do wait "$pid" || rc=1; done
if [ "$rc" -eq 0 ]; then
  echo "reset-wave complete for ranges: $RANGES — all PASS"
else
  echo "reset-wave FAILED for one or more ranges: $RANGES — see the [rK] FAIL line(s) above" >&2
fi
exit $rc
