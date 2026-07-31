#!/bin/bash
# enterprise-verify.sh - verify the enterprise lab substrate, services, seeds,
# and optional Pro profile policy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-scripts/lib/enterprise-inventory.sh
source "${SCRIPT_DIR}/lib/enterprise-inventory.sh"
# shellcheck source=lab-scripts/lib/enterprise-service-catalog.sh
source "${SCRIPT_DIR}/lib/enterprise-service-catalog.sh"

LAYER="all"
PROFILE="team"
CI_USER="${CI_USER:-labadmin}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

usage() {
    cat <<EOF
Usage: $0 [--layer net|services|seed|policy|all] [--profile team|pro]

Layers:
  net       Ping, SSH, and planned DNS aliases
  services  HTTP health checks from the enterprise service catalog
  seed      Seeded artifact presence checks on enterprise hosts
  policy    Team/pro network policy inspection
  all       Run every verification layer
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --layer)
            LAYER="${2:-}"
            shift 2
            ;;
        --profile)
            PROFILE="${2:-}"
            shift 2
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

case "$LAYER" in
    net|services|seed|policy|all) ;;
    *) echo "Unknown layer: $LAYER" >&2; exit 2 ;;
esac

case "$PROFILE" in
    team|pro) ;;
    *) echo "Unknown profile: $PROFILE" >&2; exit 2 ;;
esac

ok() { echo -e "  ${GREEN}[✓]${NC} $1"; PASS=$((PASS + 1)); }
bad() { echo -e "  ${RED}[✗]${NC} $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${YELLOW}[!]${NC} $1"; WARN=$((WARN + 1)); }

ssh_cmd() {
    local host=$1
    shift
    ssh ${SSH_OPTS} "${CI_USER}@$(enterprise_host_ip "$host")" "$@"
}

check_ping() {
    local host=$1 ip
    ip=$(enterprise_host_ip "$host")
    if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
        ok "Ping $host ($ip)"
    else
        bad "Ping $host ($ip)"
    fi
}

check_ssh() {
    local host=$1 ip
    ip=$(enterprise_host_ip "$host")
    if ssh_cmd "$host" "echo ok" >/dev/null 2>&1; then
        ok "SSH to $host ($ip)"
    else
        bad "SSH to $host ($ip)"
    fi
}

check_hosts_entry() {
    local host=$1 ip aliases
    ip=$(enterprise_host_ip "$host")
    aliases=$(enterprise_host_dns_aliases "$host" || true)
    if [[ -n "$aliases" ]]; then
        ok "DNS aliases planned for $host: $aliases"
    else
        warn "No DNS aliases planned for $host ($ip)"
    fi
}

check_service() {
    local host=$1 port=$2 path=$3 expect=$4 name=$5 header=${6:-}
    local ip result
    ip=$(enterprise_host_ip "$host")
    local curl_args=(curl -sf --max-time 5)
    [[ -n "$header" ]] && curl_args+=(-H "$header")
    result=$("${curl_args[@]}" "http://${ip}:${port}${path}" 2>/dev/null || echo "UNREACHABLE")
    if [[ -z "$expect" && "$result" != "UNREACHABLE" ]]; then
        ok "$name ($host:$port)"
    elif echo "$result" | grep -qi "$expect"; then
        ok "$name ($host:$port)"
    else
        bad "$name ($host:$port) - expected '$expect'"
    fi
}

check_remote_file() {
    local host=$1 path=$2 label=$3
    if ssh_cmd "$host" "test -s '${path}'" >/dev/null 2>&1; then
        ok "$label on $host"
    else
        bad "$label missing on $host ($path)"
    fi
}

check_remote_command() {
    local host=$1 label=$2 command=$3
    if ssh_cmd "$host" "$command" >/dev/null 2>&1; then
        ok "$label on $host"
    else
        bad "$label failed on $host"
    fi
}

run_net_checks() {
    echo ""
    echo -e "${YELLOW}-- Network and SSH --${NC}"
    local host
    for host in ${ENT_HOSTS}; do
        check_ping "$host"
        check_ssh "$host"
        check_hosts_entry "$host"
    done
}

run_service_checks() {
    echo ""
    echo -e "${YELLOW}-- Enterprise Services --${NC}"
    while IFS='|' read -r service_host port path expect name header; do
        [[ -n "$service_host" ]] || continue
        check_service "$service_host" "$port" "$path" "$expect" "$name" "$header"
    done < <(enterprise_service_health_checks)
}

run_seed_checks() {
    echo ""
    echo -e "${YELLOW}-- Seeded Enterprise Artifacts --${NC}"
    check_remote_file ent-dev-01 "/home/devuser/projects/acme-enterprise/README.md" "Research notebook/project seed"
    check_remote_file ent-mlops-01 "/opt/acme-mlops/ci-logs/model-promote-2026-05-20.log" "MLOps CI log seed"
    check_remote_file ent-inference-01 "/opt/acme-inference/config-history/litellm-notes.env" "Inference config-history seed"
    check_remote_file ent-data-01 "/var/lib/minio/data/acme-ml-data/churn/weekly/README.txt" "MinIO data seed"
    check_remote_file ent-app-01 "/home/appuser/projects/rag-support-app/.env" "RAG app config seed"
    check_remote_file ent-observe-01 "/var/log/acme-observe/events.jsonl" "Observability event seed"
    check_remote_command ent-idp-01 "Vault KV seed" "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root-enterprise-FAKE vault kv get kv/inference/litellm"
}

run_policy_checks() {
    echo ""
    echo -e "${YELLOW}-- Network Policy --${NC}"
    if [[ "$PROFILE" == "team" ]]; then
        ok "Team profile uses open routed enterprise zones"
        return
    fi

    if ! command -v iptables >/dev/null 2>&1; then
        warn "iptables is not available on this host; run policy verification on Proxmox"
        return
    fi

    local output=""
    if output=$(bash "${SCRIPT_DIR}/enterprise-policy.sh" verify 2>/dev/null); then
        :
    elif command -v sudo >/dev/null 2>&1 && output=$(sudo -n bash "${SCRIPT_DIR}/enterprise-policy.sh" verify 2>/dev/null); then
        :
    else
        warn "Could not inspect Pro firewall chain without root privileges"
        return
    fi

    if echo "$output" | grep -q "AIPOSTEX_ENT_PRO"; then
        ok "Pro firewall chain is installed"
    else
        bad "Pro firewall chain is missing"
    fi
}

print_summary() {
    echo ""
    echo -e "${CYAN}================================================${NC}"
    echo -e "  Final: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${WARN} warnings${NC}"
    echo -e "${CYAN}================================================${NC}"
    [[ $FAIL -eq 0 ]]
}

main() {
    echo ""
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}  ${ENT_LAB_NAME} Verification (${PROFILE})${NC}"
    echo -e "${CYAN}================================================${NC}"

    case "$LAYER" in
        net) run_net_checks ;;
        services) run_service_checks ;;
        seed) run_seed_checks ;;
        policy) run_policy_checks ;;
        all)
            run_net_checks
            run_service_checks
            run_seed_checks
            run_policy_checks
            ;;
    esac

    print_summary
}

main "$@"
