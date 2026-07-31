#!/bin/bash
# Provision enterprise attack box with operator tools and ent-* SSH aliases.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "${SCRIPT_DIR}/../common.sh"

GO_VERSION="${GO_VERSION:-1.23.6}"
LABADMIN_HOME="$(eval echo ~labadmin)"
SSH_DIR="${LABADMIN_HOME}/.ssh"
SSH_CONFIG="${SSH_DIR}/config"
MANAGED_START="# >>> aipostex-enterprise managed block >>>"
MANAGED_END="# <<< aipostex-enterprise managed block <<<"

echo "[*] Provisioning ent-attack..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl wget git jq make python3 python3-pip python3-venv nmap netcat-openbsd tmux tree unzip dnsutils net-tools iputils-ping openssh-client 2>/dev/null

if ! command -v go >/dev/null 2>&1; then
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' > /etc/profile.d/go.sh
fi

mkdir -p "${SSH_DIR}"
tmp_config=$(mktemp)
if [[ -f "${SSH_CONFIG}" ]]; then
    awk -v start="${MANAGED_START}" -v end="${MANAGED_END}" '
        $0 == start {skip=1; next}
        $0 == end {skip=0; next}
        !skip {print}
    ' "${SSH_CONFIG}" > "${tmp_config}"
else
    : > "${tmp_config}"
fi

{
    echo ""
    echo "${MANAGED_START}"
    for host in ${ENT_TARGET_HOSTS}; do
        echo "Host ${host}"
        echo "    HostName $(enterprise_host_ip "$host")"
        echo "    User labadmin"
        echo "    StrictHostKeyChecking no"
        echo "    UserKnownHostsFile /dev/null"
        echo ""
    done
    echo "${MANAGED_END}"
} >> "${tmp_config}"
mv "${tmp_config}" "${SSH_CONFIG}"
chown -R labadmin:labadmin "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
chmod 600 "${SSH_CONFIG}"

KEY_FILE="${SSH_DIR}/id_ed25519"
if [[ ! -f "${KEY_FILE}" ]]; then
    sudo -u labadmin ssh-keygen -t ed25519 -f "${KEY_FILE}" -N '' -C 'labadmin@ent-attack' >/dev/null
fi

mkdir -p "${LABADMIN_HOME}/lab/enterprise"
enterprise_hosts_entries > "${LABADMIN_HOME}/lab/enterprise/hosts"
chown -R labadmin:labadmin "${LABADMIN_HOME}/lab"

echo "[+] ent-attack provisioning complete"
