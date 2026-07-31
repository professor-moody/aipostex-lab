#!/bin/bash
# deploy-ansible.sh — Optional Ansible orchestration path for the lab.
# Bash remains the canonical deployment path; this wraps the same scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-scripts/lib/inventory.sh
source "${SCRIPT_DIR}/lib/inventory.sh"

PHASE="all"
USER_NAME="labadmin"

usage() {
    cat <<'EOF'
Usage: bash deploy-ansible.sh [--phase attack|base|provision|seed|verify|all] [--user labadmin]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase)
            PHASE="${2:-}"
            shift 2
            ;;
        --user)
            USER_NAME="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[!] Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$PHASE" in
    attack|base|provision|seed|verify|all) ;;
    *)
        echo "[!] Invalid phase: $PHASE" >&2
        usage >&2
        exit 2
        ;;
esac

if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "[!] ansible-playbook not found. Install Ansible or use bash deploy-all.sh." >&2
    exit 2
fi

TMP_INVENTORY="$(mktemp)"
trap 'rm -f "$TMP_INVENTORY"' EXIT

{
    echo "[target_vms]"
    for host in ${LAB_TARGET_HOSTS}; do
        seed_enabled="false"
        case "$host" in
            ailab-dev|ailab-ml|ailab-ds) seed_enabled="true" ;;
        esac
        printf '%s ansible_host=%s lab_role_dir=%s lab_seed_enabled=%s\n' \
            "$host" \
            "$(inventory_host_ip "$host")" \
            "$(inventory_host_role_dir "$host")" \
            "$seed_enabled"
    done
    echo
    echo "[attack_box]"
    printf 'ailab-attack ansible_host=%s lab_role_dir=%s\n' \
        "$(inventory_host_ip "ailab-attack")" \
        "$(inventory_host_role_dir "ailab-attack")"
    echo
    echo "[all:vars]"
    printf 'ansible_user=%s\n' "$USER_NAME"
    echo 'ansible_python_interpreter=/usr/bin/python3'
} > "$TMP_INVENTORY"

ansible-playbook \
    -i "$TMP_INVENTORY" \
    "${SCRIPT_DIR}/ansible/site.yml" \
    -e "lab_phase=${PHASE}" \
    -e "repo_root=$(cd "${SCRIPT_DIR}/.." && pwd)"

