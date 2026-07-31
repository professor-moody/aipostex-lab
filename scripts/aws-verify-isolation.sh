#!/usr/bin/env bash
# aws-verify-isolation.sh — prove cross-range (estate) isolation on the AWS multi-range lab.
#
# For every ordered pair of ranges (K -> J, K != J): from range K's attack box, probe range J's
# service ports. The per-range security group admits only its own /24, so K's traffic to J must be
# SILENTLY DROPPED (SYN gets no reply -> connect timeout, curl exit 28). The SAME probe to K's OWN
# range must CONNECT (exit 0) — that control rules out "the service is just down".
#
# A cross-range probe that returns "connection refused" (exit 7) is an ISOLATION FAILURE: the packet
# reached the host (SG let it through) and only the port was closed. Cross-range MUST time out.
#
# Usage:
#   RANGES="0 1" bash scripts/aws-verify-isolation.sh
# Prereqs: ranges deployed + provisioned (services up); ~/.ssh/aipostex_rec; AWS creds.
set -uo pipefail
export AWS_PROFILE="${AWS_PROFILE:-aipostex}"
KEY="${AWS_LAB_KEY:-$HOME/.ssh/aipostex_rec}"
RANGES="${RANGES:-0 1}"
SSH_OPTS="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes"
# Service ports that are UP after a green provision (dev Ollama, ml ChromaDB). Override
# (e.g. PROBES="") to run only the SSH/22 isolation checks against boot-only ranges.
PROBES="${PROBES-10:11434 20:8000}"   # <host-octet>:<port>

name_tag(){ [ "$1" = 0 ] && echo "aipostex-lab-$2" || echo "aipostex-lab-r$1-$2"; }
attack_pub(){ aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$(name_tag "$1" ailab-attack)" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null; }
subnet_for(){ echo "10.0.$(( $1 + 1 ))"; }

# Run a curl connect-only probe FROM range K's attack box TO ip:port. Echoes the curl exit code.
probe_from(){ # $1=attack_pub  $2=ip  $3=port
  ssh $SSH_OPTS -n "labadmin@$1" \
    "curl -s -o /dev/null -m 6 --connect-timeout 6 http://$2:$3/ >/dev/null 2>&1; echo \$?" 2>/dev/null | tr -d '[:space:]'
}

# Plain indexed array (range ids are numeric) — avoids `declare -A`, absent on macOS bash 3.2.
APUB=()
for K in $RANGES; do
  APUB[$K]=$(attack_pub "$K")
  [ -n "${APUB[$K]}" ] && [ "${APUB[$K]}" != "None" ] || { echo "[!] no attack box for range $K"; exit 1; }
done

pass=0; fail=0
echo "=== control: each range reaches its OWN services (expect exit 0) ==="
for K in $RANGES; do
  sub=$(subnet_for "$K")
  for p in $PROBES; do
    octet="${p%%:*}"; port="${p##*:}"
    rc=$(probe_from "${APUB[$K]}" "${sub}.${octet}" "$port")
    if [ "$rc" = 0 ]; then echo "  [+] r$K -> own ${sub}.${octet}:${port}  reachable (rc=0)"; pass=$((pass+1))
    else echo "  [!] r$K -> own ${sub}.${octet}:${port}  UNREACHABLE (rc=$rc) — service down? control invalid"; fail=$((fail+1)); fi
  done
done

echo "=== isolation: each range CANNOT reach another range's services (expect timeout, rc=28) ==="
for K in $RANGES; do
  for J in $RANGES; do
    [ "$K" = "$J" ] && continue
    subJ=$(subnet_for "$J")
    for p in $PROBES; do
      octet="${p%%:*}"; port="${p##*:}"
      rc=$(probe_from "${APUB[$K]}" "${subJ}.${octet}" "$port")
      if [ "$rc" = 28 ]; then echo "  [+] r$K -/-> r$J ${subJ}.${octet}:${port}  DROPPED (timeout rc=28) = isolated"; pass=$((pass+1))
      elif [ "$rc" = 0 ]; then echo "  [!] r$K --> r$J ${subJ}.${octet}:${port}  REACHABLE (rc=0) = ISOLATION BREACH"; fail=$((fail+1))
      elif [ "$rc" = 7 ]; then echo "  [!] r$K --> r$J ${subJ}.${octet}:${port}  REFUSED (rc=7) = packet reached host = ISOLATION BREACH"; fail=$((fail+1))
      else echo "  [?] r$K -> r$J ${subJ}.${octet}:${port}  rc=$rc (not a clean timeout) — investigate"; fail=$((fail+1)); fi
    done
  done
done

# ── SSH/22 cross-range isolation (the C1 hardening) ──────────────────────────
# With allowed_ssh_cidr restricted to the operator CIDR (never 0.0.0.0/0), a peer range's
# subnet is not admitted on :22 either, so range K cannot SSH into range J. Probe with a raw
# TCP connect (bash /dev/tcp) from K's attack box: a DROPPED packet hangs -> timeout (rc=124);
# an OPEN port connects (rc=0 = breach). Control: each range's own dev:22 must connect.
ssh_tcp_probe(){ # $1=attack_pub  $2=ip -> echoes remote exit code (0=open, 124=timeout)
  ssh $SSH_OPTS -n "labadmin@$1" \
    "timeout 6 bash -c 'exec 3<>/dev/tcp/$2/22' >/dev/null 2>&1; echo \$?" 2>/dev/null | tr -d '[:space:]'
}

echo "=== control: each range reaches its OWN dev SSH/22 (expect open, rc=0) ==="
for K in $RANGES; do
  sub=$(subnet_for "$K")
  rc=$(ssh_tcp_probe "${APUB[$K]}" "${sub}.10")
  if [ "$rc" = 0 ]; then echo "  [+] r$K -> own ${sub}.10:22  open (rc=0)"; pass=$((pass+1))
  else echo "  [!] r$K -> own ${sub}.10:22  NOT open (rc=$rc) — SSH down? control invalid"; fail=$((fail+1)); fi
done

echo "=== isolation: each range CANNOT SSH into another range (expect timeout, rc=124) ==="
for K in $RANGES; do
  for J in $RANGES; do
    [ "$K" = "$J" ] && continue
    subJ=$(subnet_for "$J")
    rc=$(ssh_tcp_probe "${APUB[$K]}" "${subJ}.10")
    if [ "$rc" = 124 ]; then echo "  [+] r$K -/-> r$J ${subJ}.10:22  DROPPED (timeout rc=124) = SSH isolated"; pass=$((pass+1))
    elif [ "$rc" = 0 ]; then echo "  [!] r$K --> r$J ${subJ}.10:22  OPEN (rc=0) = SSH ISOLATION BREACH"; fail=$((fail+1))
    else echo "  [?] r$K -> r$J ${subJ}.10:22  rc=$rc (not a clean timeout) — investigate"; fail=$((fail+1)); fi
  done
done

echo "----"
echo "isolation summary: $pass passed, $fail failed  (ranges: $RANGES)"
[ "$fail" = 0 ] && { echo "PASS — estates isolated on service ports + SSH/22"; exit 0; } || { echo "FAIL"; exit 1; }
