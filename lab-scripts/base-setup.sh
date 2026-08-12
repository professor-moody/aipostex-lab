#!/bin/bash
# base-setup.sh — Run on EACH lab VM as root
# Usage: sudo bash /home/labadmin/lab/base-setup.sh
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "[!] base-setup.sh must be run as root (use sudo)"
    exit 1
fi

SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" && pwd)"
LAB_INVENTORY_PATH="${LAB_INVENTORY_PATH:-${SCRIPT_DIR}/lib/inventory.sh}"

if [[ ! -f "${LAB_INVENTORY_PATH}" ]]; then
    echo "[!] inventory.sh not found at ${LAB_INVENTORY_PATH}"
    echo "[!] Copy lab-scripts/base-setup.sh and lab-scripts/lib/ to the VM before running base setup."
    exit 1
fi

# shellcheck source=lab-scripts/lib/inventory.sh
source "${LAB_INVENTORY_PATH}"

HOSTNAME=$(hostname)
echo "[*] $HOSTNAME: Starting base setup..."

export DEBIAN_FRONTEND=noninteractive

echo "[*] Updating packages..."
apt-get update -qq

echo "[*] Installing utilities..."
apt-get install -y -qq \
    curl \
    wget \
    jq \
    git \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    unzip \
    qemu-guest-agent \
    net-tools \
    iputils-ping \
    dnsutils \
    2>/dev/null

systemctl start qemu-guest-agent || true
systemctl enable qemu-guest-agent >/dev/null 2>&1 || true

# Enable SSH password authentication (required for lab access)
echo "[*] Enabling SSH password authentication..."
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config
if systemctl list-unit-files --type=service --no-legend ssh.service 2>/dev/null | grep -q '^ssh\.service'; then
    systemctl restart ssh
elif systemctl list-unit-files --type=service --no-legend sshd.service 2>/dev/null | grep -q '^sshd\.service'; then
    systemctl restart sshd
else
    echo "[!] Neither ssh.service nor sshd.service exists; cannot restart SSH"
    exit 1
fi

if declare -F inventory_hosts_entries >/dev/null 2>&1; then
    HOSTS_MARKER="ailab-dev"
    HOSTS_ENTRIES="$(inventory_hosts_entries)"
elif declare -F enterprise_hosts_entries >/dev/null 2>&1; then
    HOSTS_MARKER="ent-dev-01"
    HOSTS_ENTRIES="$(enterprise_hosts_entries)"
else
    echo "[!] Inventory does not define inventory_hosts_entries or enterprise_hosts_entries"
    exit 1
fi

if ! grep -q "${HOSTS_MARKER}" /etc/hosts 2>/dev/null; then
    echo "${HOSTS_ENTRIES}" >> /etc/hosts
fi

if ! grep -q nameserver /etc/resolv.conf 2>/dev/null; then
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
fi

# --- Elastic Beats: endpoint + application telemetry -> the ailab-siem detection stack.
# Skipped on the SIEM host itself, when INSTALL_BEATS=0, or when no ELASTIC_PASSWORD is
# provided. Non-fatal — Beats buffer and retry if the SIEM is not up yet.
if [[ "${INSTALL_BEATS:-1}" == "1" && "${HOSTNAME}" != "ailab-siem" && -x "${SCRIPT_DIR}/siem/install-beats.sh" ]]; then
    if [[ -n "${ELASTIC_PASSWORD:-}" ]]; then
        SIEM_HOST="${SIEM_HOST:-$(inventory_host_ip ailab-siem)}"
        echo "[*] $HOSTNAME: installing Elastic Beats (SIEM ${SIEM_HOST})"
        SIEM_HOST="${SIEM_HOST}" ELASTIC_PASSWORD="${ELASTIC_PASSWORD}" \
            bash "${SCRIPT_DIR}/siem/install-beats.sh" || echo "[!] Beats install failed (non-fatal)"
    else
        echo "[*] $HOSTNAME: skipping Beats (set ELASTIC_PASSWORD to ship telemetry to ailab-siem)"
    fi
fi

echo "[+] $HOSTNAME: Base setup complete"
echo "    Python: $(python3 --version)"
echo "    pip: $(pip3 --version | cut -d' ' -f1-2)"
