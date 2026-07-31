#!/bin/bash
# proxmox-enterprise-setup.sh — create the enterprise Proxmox VM substrate.
#
# This script is the Proxmox infrastructure path for the enterprise lab.
# Terraform is intentionally not used for Proxmox; Terraform remains AWS-only.
#
# Usage:
#   sudo bash lab-scripts/proxmox-enterprise-setup.sh [--profile team|pro] [--yes] [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-scripts/lib/enterprise-inventory.sh
source "${SCRIPT_DIR}/lib/enterprise-inventory.sh"

STORAGE="${STORAGE:-vm2}"
CI_USER="${CI_USER:-labadmin}"
CI_PASS="${CI_PASS:-Ailab2026!}"
PROFILE="team"
AUTO_CONFIRM=false
DRY_RUN=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
ok() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[*]${NC} $1"; }
err() { echo -e "${RED}[!]${NC} $1" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $0 [--profile team|pro] [--yes] [--dry-run]

  --profile   Resource profile. team is smaller, pro is larger. Default: team
  --yes       Do not prompt before creating bridges and VMs
  --dry-run   Print planned bridges and VMs without changing Proxmox

Environment:
  STORAGE               Proxmox storage target. Default: vm2
  ENT_UPSTREAM_BRIDGE   NAT egress bridge. Default: vmbr0
  CI_USER               Cloud-init user. Default: labadmin
  CI_PASS               Cloud-init password. Default: Ailab2026!
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            [[ $# -lt 2 ]] && err "--profile requires team or pro"
            PROFILE="$2"
            shift 2
            ;;
        --yes)
            AUTO_CONFIRM=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            err "Unknown argument: $1"
            ;;
    esac
done

case "$PROFILE" in
    team|pro) ;;
    *) err "Unknown profile: $PROFILE" ;;
esac

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        printf 'DRY-RUN:'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    "$@"
}

confirm() {
    if [[ "$AUTO_CONFIRM" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    read -r -p "Proceed with enterprise Proxmox setup? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || exit 0
}

print_plan() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  ${ENT_LAB_NAME} — Proxmox Enterprise Setup${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Profile:       $PROFILE"
    echo "  Storage:       $STORAGE"
    echo "  Upstream NAT:  $ENT_UPSTREAM_BRIDGE"
    echo "  Templates:     $ENT_UBUNTU_TEMPLATE_ID (Ubuntu), $ENT_DEBIAN_TEMPLATE_ID (Debian)"
    echo "  Cloud-init:    $CI_USER / $CI_PASS"
    echo ""
    echo "  Zones:"
    local zone
    for zone in ${ENT_ZONES}; do
        printf '    %-10s %-8s %s gw=%s\n' \
            "$zone" \
            "$(enterprise_zone_bridge "$zone")" \
            "$(enterprise_zone_cidr "$zone")" \
            "$(enterprise_zone_gateway "$zone")"
    done
    echo ""
    echo "  VMs:"
    enterprise_host_summary | while IFS='|' read -r host vmid ip zone bridge gateway role; do
        printf '    %-16s vm=%-4s ip=%-14s zone=%-10s bridge=%-8s role=%s\n' \
            "$host" "$vmid" "$ip" "$zone" "$bridge" "$role"
    done
    echo ""
}

preflight() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    [[ $EUID -eq 0 ]] || err "This script must be run as root on the Proxmox host"
    command -v qm >/dev/null 2>&1 || err "qm not found; this does not look like a Proxmox host"
    pvesm status | grep -q "$STORAGE" || {
        pvesm status
        err "Storage '$STORAGE' not found"
    }
    qm status "$ENT_UBUNTU_TEMPLATE_ID" >/dev/null 2>&1 || err "Ubuntu template $ENT_UBUNTU_TEMPLATE_ID not found"
    qm status "$ENT_DEBIAN_TEMPLATE_ID" >/dev/null 2>&1 || err "Debian template $ENT_DEBIAN_TEMPLATE_ID not found"

    local host vmid
    for host in ${ENT_HOSTS}; do
        vmid=$(enterprise_host_id "$host")
        if qm status "$vmid" >/dev/null 2>&1; then
            err "Enterprise VM ID $vmid already exists for $host. Use enterprise-snapshots.sh or remove it first."
        fi
    done
}

ensure_ssh_key() {
    SSH_KEY=""
    if [[ -f ~/.ssh/id_ed25519.pub ]]; then
        SSH_KEY=~/.ssh/id_ed25519.pub
    elif [[ -f ~/.ssh/id_rsa.pub ]]; then
        SSH_KEY=~/.ssh/id_rsa.pub
    else
        warn "No SSH key found, generating ed25519 key"
        run_cmd ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q
        SSH_KEY=~/.ssh/id_ed25519.pub
    fi
    ok "SSH key: $SSH_KEY"
}

ensure_zone_bridge() {
    local zone=$1 bridge cidr gateway network
    bridge=$(enterprise_zone_bridge "$zone")
    cidr=$(enterprise_zone_cidr "$zone")
    gateway=$(enterprise_zone_gateway "$zone")
    network="${cidr%/*}"

    log "Ensuring $zone bridge $bridge ($cidr, gw=$gateway)"
    if [[ "$DRY_RUN" != "true" ]] && ip link show "$bridge" >/dev/null 2>&1; then
        warn "Bridge $bridge already exists, reusing"
        return 0
    fi

    if [[ "$DRY_RUN" != "true" ]] && grep -q "auto $bridge" /etc/network/interfaces 2>/dev/null; then
        warn "Bridge $bridge already exists in /etc/network/interfaces, bringing up"
        run_cmd ifup "$bridge" || true
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: append bridge $bridge for $cidr with gateway $gateway and NAT via $ENT_UPSTREAM_BRIDGE"
        return 0
    fi

    cat >> /etc/network/interfaces <<EOF

# aipostex enterprise lab network — ${zone}
auto ${bridge}
iface ${bridge} inet static
    address ${gateway}/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    post-up   echo 1 > /proc/sys/net/ipv4/ip_forward
    post-up   iptables -t nat -C POSTROUTING -s ${cidr} -o ${ENT_UPSTREAM_BRIDGE} -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s ${cidr} -o ${ENT_UPSTREAM_BRIDGE} -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s ${cidr} -o ${ENT_UPSTREAM_BRIDGE} -j MASQUERADE 2>/dev/null || true
EOF
    run_cmd ifup "$bridge"
    ip addr show "$bridge" | grep -q "$gateway" || err "Bridge $bridge did not come up at $gateway"
    ok "Bridge $bridge ready for $network"
}

clone_enterprise_vm() {
    local host=$1 vmid template zone bridge ip gateway memory cores aliases
    vmid=$(enterprise_host_id "$host")
    template=$(enterprise_host_template_id "$host")
    zone=$(enterprise_host_zone "$host")
    bridge=$(enterprise_zone_bridge "$zone")
    ip=$(enterprise_host_ip "$host")
    gateway=$(enterprise_zone_gateway "$zone")
    memory=$(enterprise_host_memory_mb "$host" "$PROFILE")
    cores=$(enterprise_host_cores "$host" "$PROFILE")
    aliases=$(enterprise_host_dns_aliases "$host" || true)

    log "Cloning $host (VM $vmid, $ip, $zone)"
    run_cmd qm clone "$template" "$vmid" --name "$host" --full
    run_cmd qm set "$vmid" --net0 "virtio,bridge=${bridge}"
    run_cmd qm set "$vmid" --ipconfig0 "ip=${ip}/24,gw=${gateway}"
    run_cmd qm set "$vmid" --memory "$memory" --cores "$cores" --cpu host
    run_cmd qm set "$vmid" --ciuser "$CI_USER" --cipassword "$CI_PASS"
    if [[ -n "${SSH_KEY:-}" ]]; then
        run_cmd qm set "$vmid" --sshkeys "$SSH_KEY"
    fi
    run_cmd qm set "$vmid" --searchdomain "$ENT_DOMAIN" --nameserver "$(enterprise_host_ip ent-idp-01)"
    ok "$host created (${memory}MB, ${cores} cores, aliases: ${aliases:-none})"
}

start_and_check_vms() {
    local host vmid ip all_up=true
    log "Starting enterprise VMs"
    for host in ${ENT_HOSTS}; do
        vmid=$(enterprise_host_id "$host")
        run_cmd qm start "$vmid"
    done

    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    warn "Waiting for cloud-init to settle (~90 seconds)"
    sleep 90
    for host in ${ENT_HOSTS}; do
        ip=$(enterprise_host_ip "$host")
        if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${CI_USER}@${ip}" "echo ok" >/dev/null 2>&1; then
            ok "SSH to $host ($ip) works"
        else
            warn "SSH to $host ($ip) is not ready yet"
            all_up=false
        fi
    done

    [[ "$all_up" == "true" ]] || warn "Some enterprise VMs may still be booting"
}

main() {
    print_plan
    preflight
    confirm
    ensure_ssh_key

    local zone host
    for zone in ${ENT_ZONES}; do
        ensure_zone_bridge "$zone"
    done
    for host in ${ENT_HOSTS}; do
        clone_enterprise_vm "$host"
    done
    start_and_check_vms

    echo ""
    echo -e "${GREEN}Enterprise Proxmox substrate created.${NC}"
    echo "Next:"
    echo "  bash lab-scripts/enterprise-verify.sh"
    echo "  bash lab-scripts/enterprise-snapshots.sh create enterprise-base"
}

main "$@"
