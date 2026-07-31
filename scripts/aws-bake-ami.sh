#!/usr/bin/env bash
# aws-bake-ami.sh — bake the "lab-ready" AMI for each node in a range (the AWS equivalent
# of the proxmox `lab-ready` snapshot). Run AFTER the range is fully green (verify-lab +
# verify-chain + verify-aipostex). The AMIs are the clean-disk baseline that
# aws-reset-wave.sh restores between waves.
#
# Usage: RANGE=0 bash scripts/aws-bake-ami.sh
set -uo pipefail
export AWS_PROFILE="${AWS_PROFILE:-aipostex}"
RANGE="${RANGE:-0}"
NAME_PREFIX="${NAME_PREFIX:-aipostex-lab}"
STAMP="${STAMP:-manual}"   # pass a timestamp in (scripts can't call date deterministically)

roles="ailab-dev ailab-ml ailab-ds ailab-app ailab-k8s ailab-attack"
echo "baking lab-ready AMIs for range ${RANGE} ..."
for role in $roles; do
  # For range 0 the Name tag is "<prefix>-<role>"; multi-range appends "-r<K>".
  name_tag="${NAME_PREFIX}-${role}"
  [ "$RANGE" != "0" ] && name_tag="${NAME_PREFIX}-r${RANGE}-${role}"
  iid=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${name_tag}" "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)
  if [ -z "$iid" ] || [ "$iid" = "None" ]; then
    echo "  [!] no instance for ${role} (${name_tag}) — skipping"
    continue
  fi
  ami=$(aws ec2 create-image --instance-id "$iid" \
    --name "${NAME_PREFIX}-ready-r${RANGE}-${role}-${STAMP}" \
    --description "lab-ready baseline for ${role} range ${RANGE}" \
    --no-reboot --query ImageId --output text)
  aws ec2 create-tags --resources "$ami" --tags \
    "Key=Project,Value=aipostex-lab" "Key=LabReady,Value=r${RANGE}" "Key=Role,Value=${role}" >/dev/null
  echo "  [+] ${role}  ${iid} -> ${ami}"
done
echo "done. reset a range from these with: RANGE=${RANGE} bash scripts/aws-reset-wave.sh"
