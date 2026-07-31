#!/bin/bash
# Shared helpers for enterprise role scripts.
set -euo pipefail

ENTERPRISE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${ENTERPRISE_ROOT}/.." && pwd)"

# shellcheck source=lab-scripts/lib/enterprise-inventory.sh
source "${LAB_ROOT}/lib/enterprise-inventory.sh"

enterprise_wait_for_http() {
    local name=$1
    local url=$2
    local expected=${3:-}
    local attempts=${4:-30}

    echo "[*] Waiting for ${name} at ${url}..."
    for _ in $(seq 1 "${attempts}"); do
        local body
        body=$(curl -sf --max-time 5 "${url}" 2>/dev/null || true)
        if [[ -z "${expected}" && -n "${body}" ]]; then
            echo "[+] ${name} is ready"
            return 0
        fi
        if [[ -n "${expected}" ]] && echo "${body}" | grep -qi "${expected}"; then
            echo "[+] ${name} is ready"
            return 0
        fi
        sleep 2
    done

    echo "[!] ${name} did not pass readiness check"
    return 1
}

enterprise_install_python_service() {
    local name=$1
    local user=$2
    local workdir=$3
    local exec_start=$4

    cat > "/etc/systemd/system/${name}.service" <<EOF
[Unit]
Description=${name}
After=network.target

[Service]
User=${user}
WorkingDirectory=${workdir}
ExecStart=${exec_start}
Restart=always
RestartSec=5
Environment="PATH=/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "${name}"
}
