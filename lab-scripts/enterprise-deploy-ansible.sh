#!/bin/bash
# enterprise-deploy-ansible.sh — Optional Ansible orchestration path for Enterprise.
#
# Proxmox infrastructure, snapshots, reset, and Pro firewall policy remain Bash.
# This wrapper generates inventory from enterprise-inventory.sh and runs the
# staged Enterprise Ansible playbook.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PHASE="all"
PROFILE="team"
USER_NAME="labadmin"

usage() {
    cat <<'EOF'
Usage: bash enterprise-deploy-ansible.sh [--phase base|provision|seed|verify|all] [--profile team|pro] [--user labadmin]

Infrastructure-only phases stay in Bash:
  infra     -> bash lab-scripts/enterprise-deploy.sh --phase infra
  policy    -> bash lab-scripts/enterprise-policy.sh apply|disable|verify
  snapshot  -> bash lab-scripts/enterprise-snapshots.sh
  reset     -> bash lab-scripts/enterprise-reset.sh
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase)
            PHASE="${2:-}"
            shift 2
            ;;
        --profile)
            PROFILE="${2:-}"
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

case "$PROFILE" in
    team|pro) ;;
    *)
        echo "[!] Invalid profile: $PROFILE" >&2
        usage >&2
        exit 2
        ;;
esac

case "$PHASE" in
    base|provision|seed|verify|all) ;;
    infra)
        echo "[!] Enterprise infra is Bash-only. Use: bash lab-scripts/enterprise-deploy.sh --phase infra --profile ${PROFILE}" >&2
        exit 2
        ;;
    policy)
        echo "[!] Enterprise policy runs on the Proxmox host. Use: bash lab-scripts/enterprise-policy.sh {render|apply|verify|disable}" >&2
        exit 2
        ;;
    snapshot|snapshots)
        echo "[!] Enterprise snapshots are Bash-only. Use: bash lab-scripts/enterprise-snapshots.sh create enterprise-ready" >&2
        exit 2
        ;;
    reset)
        echo "[!] Enterprise reset is Bash-only. Use: bash lab-scripts/enterprise-reset.sh enterprise-ready" >&2
        exit 2
        ;;
    *)
        echo "[!] Invalid phase: $PHASE" >&2
        usage >&2
        exit 2
        ;;
esac

if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "[!] ansible-playbook not found. Install Ansible or use bash lab-scripts/enterprise-deploy.sh." >&2
    exit 2
fi

TMP_DIR="$(mktemp -d)"
TMP_INVENTORY="${TMP_DIR}/inventory.yml"
trap 'rm -rf "$TMP_DIR"' EXIT

bash "${SCRIPT_DIR}/enterprise-generate-ansible-inventory.sh" --profile "$PROFILE" > "$TMP_INVENTORY"

ANSIBLE_ARGS=(
    ansible-playbook
    -i "$TMP_INVENTORY"
    "${SCRIPT_DIR}/ansible/enterprise.yml"
    -e "enterprise_profile=${PROFILE}"
    -e "ansible_user=${USER_NAME}"
    -e "repo_root=$(cd "${SCRIPT_DIR}/.." && pwd)"
)

if [[ "$PHASE" != "all" ]]; then
    ANSIBLE_ARGS+=(--tags "$PHASE")
fi

"${ANSIBLE_ARGS[@]}"
