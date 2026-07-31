#!/bin/bash
# enterprise-deploy.sh — enterprise orchestration wrapper.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-scripts/lib/enterprise-inventory.sh
source "${SCRIPT_DIR}/lib/enterprise-inventory.sh"

PHASE="all"
PROFILE="team"
YES_FLAG=""
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
CI_USER="${CI_USER:-labadmin}"

usage() {
    cat <<EOF
Usage: $0 [--phase infra|base|provision|seed|verify|policy|all] [--profile team|pro] [--yes]

Phases:
  infra      Create enterprise Proxmox VMs and routed bridges
  base       Run base OS setup across enterprise VMs
  provision  Provision enterprise services
  seed       Seed enterprise artifacts
  verify     Verify enterprise network, services, seeds, and policy
  policy     Apply pro firewall policy or report team open-routing mode
  all        Run infra, base, provision, seed, policy, verify
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
        --yes)
            YES_FLAG="--yes"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$PROFILE" in
    team|pro) ;;
    *) echo "Unknown profile: $PROFILE" >&2; exit 2 ;;
esac

ssh_cmd() {
    local host=$1
    shift
    ssh ${SSH_OPTS} "${CI_USER}@$(enterprise_host_ip "$host")" "$@"
}

scp_to_host() {
    local host=$1
    shift
    ssh_cmd "$host" "mkdir -p ~/lab"
    scp ${SSH_OPTS} -r "$@" "${CI_USER}@$(enterprise_host_ip "$host"):~/lab/"
}

wait_for_ssh() {
    local host=$1
    echo "[*] Waiting for SSH on ${host} ($(enterprise_host_ip "$host"))..."
    for _ in $(seq 1 40); do
        if ssh_cmd "$host" "echo ok" >/dev/null 2>&1; then
            echo "[+] SSH ready on ${host}"
            return 0
        fi
        sleep 3
    done
    echo "[!] SSH timeout on ${host}" >&2
    return 1
}

phase_infra() {
    sudo bash "${SCRIPT_DIR}/proxmox-enterprise-setup.sh" --profile "$PROFILE" $YES_FLAG
}

phase_base() {
    local host
    for host in ${ENT_HOSTS}; do
        wait_for_ssh "$host"
        scp_to_host "$host" "${SCRIPT_DIR}/base-setup.sh" "${SCRIPT_DIR}/lib"
        ssh_cmd "$host" "sudo env LAB_INVENTORY_PATH=/home/${CI_USER}/lab/lib/enterprise-inventory.sh bash /home/${CI_USER}/lab/base-setup.sh"
    done
}

copy_full_payload() {
    local host=$1
    ssh_cmd "$host" "mkdir -p ~/lab"
    scp ${SSH_OPTS} -r "${SCRIPT_DIR}/"* "${CI_USER}@$(enterprise_host_ip "$host"):~/lab/"
}

run_role_phase() {
    local host=$1 phase=$2 role_dir script
    role_dir=$(enterprise_host_role_dir "$host")
    script="/home/${CI_USER}/lab/${role_dir}/${phase}.sh"
    copy_full_payload "$host"
    if ssh_cmd "$host" "test -x '${script}'"; then
        ssh_cmd "$host" "sudo bash '${script}'"
    elif ssh_cmd "$host" "test -f '${script}'"; then
        ssh_cmd "$host" "sudo bash '${script}'"
    else
        echo "[*] ${host}: no ${phase}.sh for ${role_dir}, skipping"
    fi
}

distribute_attack_key() {
    local pubkey host
    pubkey=$(ssh_cmd ent-attack "cat ~/.ssh/id_ed25519.pub" 2>/dev/null || true)
    if [[ -z "$pubkey" ]]; then
        echo "[!] Could not read ent-attack SSH public key" >&2
        return 1
    fi
    for host in ${ENT_TARGET_HOSTS}; do
        ssh_cmd "$host" "mkdir -p ~/.ssh && grep -qF '${pubkey}' ~/.ssh/authorized_keys 2>/dev/null || echo '${pubkey}' >> ~/.ssh/authorized_keys"
    done
}

phase_provision() {
    run_role_phase ent-attack provision
    distribute_attack_key

    # Bring identity and observability up before app/platform services that reference them.
    run_role_phase ent-idp-01 provision
    run_role_phase ent-observe-01 provision

    local host
    for host in ent-data-01 ent-inference-01 ent-mlops-01 ent-dev-01 ent-app-01; do
        run_role_phase "$host" provision
    done
}

phase_seed() {
    local host
    for host in ent-idp-01 ent-observe-01 ent-data-01 ent-inference-01 ent-mlops-01 ent-dev-01 ent-app-01 ent-attack; do
        run_role_phase "$host" seed
    done
}

phase_policy() {
    if [[ "$PROFILE" == "pro" ]]; then
        sudo bash "${SCRIPT_DIR}/enterprise-policy.sh" apply
    else
        echo "[*] team profile uses open routed zones; no firewall policy applied"
    fi
}

phase_verify() {
    if [[ "$PROFILE" == "pro" ]]; then
        bash "${SCRIPT_DIR}/enterprise-verify.sh" --layer all --profile pro
    else
        bash "${SCRIPT_DIR}/enterprise-verify.sh" --layer all --profile team
    fi
}

case "$PHASE" in
    infra) phase_infra ;;
    base) phase_base ;;
    provision) phase_provision ;;
    seed) phase_seed ;;
    policy) phase_policy ;;
    verify) phase_verify ;;
    all)
        phase_infra
        phase_base
        phase_provision
        phase_seed
        phase_policy
        phase_verify
        ;;
    *)
        echo "Unknown phase: $PHASE" >&2
        usage >&2
        exit 2
        ;;
esac
