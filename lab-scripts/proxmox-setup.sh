#!/bin/bash
# proxmox-setup.sh — Run on the Proxmox HOST to create lab infrastructure
#
# This script:
#   1. Creates an isolated bridge (vmbr100) for 172.16.50.0/24
#   2. Downloads Ubuntu 24.04 + Debian 12 cloud images
#   3. Creates VM templates with cloud-init (Ubuntu for targets, Debian for attack box)
#   4. Clones three lab VMs + one attack box with static IPs
#   5. Starts all VMs
#
# Prerequisites:
#   - Proxmox VE 8.x
#   - Root access on Proxmox host
#   - Internet access (to download cloud images)
#   - SSH key at ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub (will create ed25519 if missing)
#
# Usage:
#   bash proxmox-setup.sh                 # base estate (group 0): vmbr100 / 172.16.50 / IDs 210-250
#   GROUP_ID=1 bash proxmox-setup.sh      # estate 1: isolated vmbr101 / 172.16.51 / IDs 1210-1250
#   GROUP_ID=2 bash proxmox-setup.sh      # estate 2: isolated vmbr102 / 172.16.52 / IDs 2210-2250
# Templates (1101/1102) are shared across estates — created once, cloned per estate.
#
# Customization:
#   STORAGE   — Change to match your Proxmox storage (default: "vm2", check: pvesm status)
#   GROUP_ID  — Estate offset (default 0); see lib/inventory.sh for the stride scheme
#   BRIDGE / SUBNET / VM IDs — all derived from GROUP_ID in lib/inventory.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-scripts/lib/inventory.sh
source "${SCRIPT_DIR}/lib/inventory.sh"

# ── Configuration ─────────────────────────────────────────
STORAGE="${STORAGE:-local-lvm}"   # env-overridable; the storage pool clones land on (check: pvesm status)
BRIDGE="${LAB_BRIDGE}"
SUBNET="${LAB_SUBNET}"
GW="${LAB_GATEWAY}"

TEMPLATE_ID="${LAB_TEMPLATE_ID}"
ATTACK_TEMPLATE_ID="${LAB_ATTACK_TEMPLATE_ID}"
DEV_ID=$(inventory_host_id "ailab-dev")
ML_ID=$(inventory_host_id "ailab-ml")
DS_ID=$(inventory_host_id "ailab-ds")
APP_ID=$(inventory_host_id "ailab-app")
ATTACK_ID=$(inventory_host_id "ailab-attack")
K8S_ID=$(inventory_host_id "ailab-k8s")

CI_USER="labadmin"
CI_PASS="Ailab2026!"

CLOUD_IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
CLOUD_IMG_PATH="/var/lib/vz/template/iso/noble-server-cloudimg-amd64.img"

DEBIAN_IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
DEBIAN_IMG_PATH="/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
ok()  { echo -e "${GREEN}[+]${NC} $1"; }
err() { echo -e "${RED}[!]${NC} $1"; exit 1; }
warn(){ echo -e "${YELLOW}[*]${NC} $1"; }

# ── Preflight Checks ─────────────────────────────────────

if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root on the Proxmox host"
fi

if ! command -v qm >/dev/null 2>&1; then
    err "qm not found — this doesn't appear to be a Proxmox host"
fi

# Verify storage exists
if ! pvesm status | grep -q "$STORAGE"; then
    echo -e "${RED}[!]${NC} Storage '$STORAGE' not found. Available storage:"
    pvesm status
    echo ""
    echo "Edit the STORAGE variable at the top of this script."
    exit 1
fi

# Check for clone VM ID conflicts (templates are handled separately)
for vmid in $DEV_ID $ML_ID $DS_ID $APP_ID $ATTACK_ID $K8S_ID; do
    if qm status $vmid >/dev/null 2>&1; then
        err "VM ID $vmid already exists. Run teardown-lab.sh first or change IDs in this script."
    fi
done

# Detect existing templates so we can skip creation later
TEMPLATES_EXIST=false
if qm status $TEMPLATE_ID >/dev/null 2>&1 && qm status $ATTACK_TEMPLATE_ID >/dev/null 2>&1; then
    TEMPLATES_EXIST=true
fi

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  aipostex Lab — Proxmox Infrastructure Setup${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""
echo "  Storage:      $STORAGE"
echo "  Bridge:       $BRIDGE (${SUBNET}.0/24)"
echo "  Templates:    $TEMPLATE_ID (Ubuntu), $ATTACK_TEMPLATE_ID (Debian)"
echo "  Target VMs:   $DEV_ID (dev), $ML_ID (ml), $DS_ID (ds), $APP_ID (app)"
echo "  Attack VM:    $ATTACK_ID (attack)"
echo "  Cloud-init:   $CI_USER / $CI_PASS"
echo ""
# ASSUME_YES=1 skips the prompt for non-interactive / multi-estate standup.
if [[ "${ASSUME_YES:-0}" != "1" ]]; then
    read -p "Proceed? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 0
fi


# ══════════════════════════════════════════════════════════
# Step 1: Network Bridge
# ══════════════════════════════════════════════════════════

log "Step 1: Creating network bridge $BRIDGE..."

if ip link show $BRIDGE >/dev/null 2>&1; then
    if ip addr show $BRIDGE | grep -q "$GW"; then
        warn "Bridge $BRIDGE already up at $GW, reusing"
    else
        warn "Bridge $BRIDGE exists but IP not set, bringing up..."
        ifup $BRIDGE 2>/dev/null || true
        if ! ip addr show $BRIDGE | grep -q "$GW"; then
            ip addr add ${GW}/24 dev $BRIDGE 2>/dev/null || true
            echo 1 > /proc/sys/net/ipv4/ip_forward
            iptables -t nat -C POSTROUTING -s ${SUBNET}.0/24 -o vmbr0 -j MASQUERADE 2>/dev/null \
                || iptables -t nat -A POSTROUTING -s ${SUBNET}.0/24 -o vmbr0 -j MASQUERADE
        fi
    fi
else
    if grep -q "$BRIDGE" /etc/network/interfaces 2>/dev/null; then
        warn "Bridge $BRIDGE configured in /etc/network/interfaces, bringing up"
        ifup $BRIDGE 2>/dev/null || true
    else
        cat >> /etc/network/interfaces << EOF

# aipostex lab network — isolated
auto $BRIDGE
iface $BRIDGE inet static
    address ${GW}/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    post-up   echo 1 > /proc/sys/net/ipv4/ip_forward
    post-up   iptables -t nat -A POSTROUTING -s ${SUBNET}.0/24 -o vmbr0 -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s ${SUBNET}.0/24 -o vmbr0 -j MASQUERADE
EOF
        ifup $BRIDGE
        ok "Bridge $BRIDGE created at $GW"
    fi
fi

# Verify
ip addr show $BRIDGE | grep -q "$GW" || err "Bridge $BRIDGE not configured correctly"
ok "Bridge $BRIDGE is up at $GW"


# ══════════════════════════════════════════════════════════
# Step 2: Download Cloud Image
# ══════════════════════════════════════════════════════════

log "Step 2: Downloading cloud images..."

if [[ -f "$CLOUD_IMG_PATH" ]]; then
    warn "Ubuntu image already exists at $CLOUD_IMG_PATH, skipping download"
else
    mkdir -p "$(dirname "$CLOUD_IMG_PATH")"
    wget -q --show-progress -O "$CLOUD_IMG_PATH" "$CLOUD_IMG_URL"
    ok "Downloaded Ubuntu 24.04 cloud image"
fi

if [[ -f "$DEBIAN_IMG_PATH" ]]; then
    warn "Debian image already exists at $DEBIAN_IMG_PATH, skipping download"
else
    mkdir -p "$(dirname "$DEBIAN_IMG_PATH")"
    wget -q --show-progress -O "$DEBIAN_IMG_PATH" "$DEBIAN_IMG_URL"
    ok "Downloaded Debian 12 cloud image"
fi


# ══════════════════════════════════════════════════════════
# Step 3: SSH Key
# ══════════════════════════════════════════════════════════

log "Step 3: Checking SSH key..."

SSH_KEY=""
if [[ -f ~/.ssh/id_ed25519.pub ]]; then
    SSH_KEY=~/.ssh/id_ed25519.pub
    ok "SSH key found at $SSH_KEY"
elif [[ -f ~/.ssh/id_rsa.pub ]]; then
    SSH_KEY=~/.ssh/id_rsa.pub
    ok "SSH key found at $SSH_KEY"
else
    warn "No SSH key found, generating one..."
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q
    SSH_KEY=~/.ssh/id_ed25519.pub
    ok "SSH key generated at ~/.ssh/id_ed25519"
fi


# ══════════════════════════════════════════════════════════
# Step 4: Create VM Templates
# ══════════════════════════════════════════════════════════

create_template() {
    local tmpl_id=$1 tmpl_name=$2 img_path=$3

    log "  Creating template $tmpl_name ($tmpl_id)..."

    qm create $tmpl_id \
        --name "$tmpl_name" \
        --memory 4096 \
        --cores 2 \
        --cpu host \
        --net0 virtio,bridge=$BRIDGE

    log "    Importing cloud image disk..."
    qm importdisk $tmpl_id "$img_path" $STORAGE 2>&1 | tail -1

    qm set $tmpl_id --scsihw virtio-scsi-pci --scsi0 ${STORAGE}:vm-${tmpl_id}-disk-0
    qm set $tmpl_id --boot c --bootdisk scsi0
    qm set $tmpl_id --ide2 ${STORAGE}:cloudinit
    qm set $tmpl_id --serial0 socket --vga serial0
    qm resize $tmpl_id scsi0 30G
    qm set $tmpl_id --agent enabled=1

    qm set $tmpl_id --ciuser "$CI_USER"
    qm set $tmpl_id --cipassword "$CI_PASS"
    qm set $tmpl_id --sshkeys "$SSH_KEY"
    qm set $tmpl_id --nameserver 8.8.8.8
    qm set $tmpl_id --ipconfig0 ip=dhcp

    qm template $tmpl_id
    ok "  Template $tmpl_name ($tmpl_id) created"
}

log "Step 4: Creating VM templates..."

if [[ "$TEMPLATES_EXIST" == "true" ]]; then
    warn "Templates $TEMPLATE_ID and $ATTACK_TEMPLATE_ID already exist, skipping creation"
else
    if qm status $TEMPLATE_ID >/dev/null 2>&1; then
        warn "Template $TEMPLATE_ID already exists, skipping"
    else
        create_template $TEMPLATE_ID "ailab-template" "$CLOUD_IMG_PATH"
    fi
    if qm status $ATTACK_TEMPLATE_ID >/dev/null 2>&1; then
        warn "Template $ATTACK_TEMPLATE_ID already exists, skipping"
    else
        create_template $ATTACK_TEMPLATE_ID "ailab-attack-template" "$DEBIAN_IMG_PATH"
    fi
fi


# ══════════════════════════════════════════════════════════
# Step 5: Clone Lab VMs
# ══════════════════════════════════════════════════════════

log "Step 5: Cloning lab VMs..."

clone_vm() {
    local tmpl=$1 vmid=$2 name=$3 ip=$4
    local mem=4096 cores=2
    # RTV workshop headroom: the ml VM hosts the busiest stack (Ray + MLflow + ChromaDB +
    # LiteLLM + the SmolLM backend) and the attack box hosts ~15 concurrent seat shells, so
    # give those two 4c/8GB. Keyed off the stable role name so it holds across GROUP_ID strides.
    case "$name" in
        ailab-ml|ailab-attack) mem=8192; cores=4 ;;
    esac

    log "  Cloning $name (VM $vmid, IP ${ip})..."
    qm clone $tmpl $vmid --name "$name" --full
    # Pin to this estate's bridge: clones inherit the (shared) template's net0 bridge,
    # so without this an estate-K VM would land on the base estate's vmbr100.
    qm set $vmid --net0 virtio,bridge=$BRIDGE
    qm set $vmid --ipconfig0 "ip=${ip}/24,gw=${GW}"
    qm set $vmid --memory $mem --cores $cores
    ok "  $name created"
}

# Only clone the VMs this deploy's profile wants (LAB_PROFILE / LAB_ONLY_ROLES; default = all).
maybe_clone() { # $1=role  $2..=clone_vm args
    local role=$1; shift
    if inventory_role_wanted "$role"; then clone_vm "$@"; else log "  skip ailab-${role} (not in profile: ${LAB_ONLY_ROLES})"; fi
}

maybe_clone dev    $TEMPLATE_ID        $DEV_ID    "ailab-dev"    "$(inventory_host_ip "ailab-dev")"
maybe_clone ml     $TEMPLATE_ID        $ML_ID     "ailab-ml"     "$(inventory_host_ip "ailab-ml")"
maybe_clone ds     $TEMPLATE_ID        $DS_ID     "ailab-ds"     "$(inventory_host_ip "ailab-ds")"
maybe_clone app    $TEMPLATE_ID        $APP_ID    "ailab-app"    "$(inventory_host_ip "ailab-app")"
maybe_clone attack $ATTACK_TEMPLATE_ID $ATTACK_ID "ailab-attack" "$(inventory_host_ip "ailab-attack")"
# ailab-k8s runs Docker + a vuln+secure k3s PAIR (k8s-node/provision.sh) → more headroom.
if inventory_role_wanted k8s; then
    clone_vm $TEMPLATE_ID    $K8S_ID    "ailab-k8s"    "$(inventory_host_ip "ailab-k8s")"
    qm set $K8S_ID --memory 6144 --cores 4
else
    log "  skip ailab-k8s (not in profile: ${LAB_ONLY_ROLES})"
fi


# ══════════════════════════════════════════════════════════
# Step 6: Start VMs
# ══════════════════════════════════════════════════════════

log "Step 6: Starting VMs..."

qm start $DEV_ID
qm start $ML_ID
qm start $DS_ID
qm start $APP_ID
qm start $ATTACK_ID
qm start $K8S_ID

ok "All VMs starting"

# Wait for cloud-init to complete
warn "Waiting for cloud-init to complete (~90 seconds)..."
sleep 90

# Test SSH
ALL_UP=true
for host in ${LAB_ALL_HOSTS}; do
    ip=$(inventory_host_ip "$host")
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "${CI_USER}@${ip}" "echo ok" >/dev/null 2>&1; then
        ok "SSH to ${ip} works"
    else
        warn "SSH to ${ip} not responding yet — may need more time"
        ALL_UP=false
    fi
done

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Proxmox Infrastructure Setup Complete${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""
echo "  Target VMs (Ubuntu 24.04):"
echo "    $DEV_ID  ailab-dev     $(inventory_host_ip "ailab-dev")"
echo "    $ML_ID  ailab-ml      $(inventory_host_ip "ailab-ml")"
echo "    $DS_ID  ailab-ds      $(inventory_host_ip "ailab-ds")"
echo "    $APP_ID  ailab-app     $(inventory_host_ip "ailab-app")"
echo ""
echo "  Attack VM (Debian 12):"
echo "    $ATTACK_ID  ailab-attack  $(inventory_host_ip "ailab-attack")"
echo ""
echo "  Kubernetes node (Docker + vuln :6443 / secure :6444 k3s pair):"
echo "    $K8S_ID  ailab-k8s     $(inventory_host_ip "ailab-k8s")"
echo ""
echo "  SSH access:  ssh ${CI_USER}@$(inventory_host_ip "ailab-attack")"
echo "  Password:    $CI_PASS"
echo ""

if [[ "$ALL_UP" == "true" ]]; then
    echo -e "${GREEN}  All VMs are responding.${NC}"
else
    echo -e "${YELLOW}  Some VMs may still be booting. Wait a minute and test SSH manually.${NC}"
fi

echo ""
echo "  Next steps:"
echo "    1. bash attack-box/setup.sh      # Provision the attack box (Go, Tailscale)"
echo "    2. bash deploy-all.sh            # Deploy target lab environment"
echo "    3. bash verify-lab.sh            # Verify everything works"
echo "    4. Take snapshots:"
echo "       qm snapshot $DEV_ID lab-ready"
echo "       qm snapshot $ML_ID lab-ready"
echo "       qm snapshot $DS_ID lab-ready"
echo "       qm snapshot $APP_ID lab-ready"
echo "       qm snapshot $ATTACK_ID lab-ready"
