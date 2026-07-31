#!/bin/bash
# enterprise-policy.sh — render/apply/disable Pro profile cross-zone policy.
#
# Run on the Proxmox host. Team profile does not use this policy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-scripts/lib/enterprise-inventory.sh
source "${SCRIPT_DIR}/lib/enterprise-inventory.sh"

ACTION="${1:-render}"
CHAIN="AIPOSTEX_ENT_PRO"

zone_cidr() { enterprise_zone_cidr "$1"; }
host_ip() { enterprise_host_ip "$1"; }

render_rules() {
    local operator_cidr inference_cidr data_cidr app_cidr developer_cidr mlops_cidr observe_ip idp_ip
    operator_cidr=$(zone_cidr operator)
    inference_cidr=$(zone_cidr inference)
    data_cidr=$(zone_cidr data)
    app_cidr=$(zone_cidr app)
    developer_cidr=$(zone_cidr developer)
    mlops_cidr=$(zone_cidr mlops)
    observe_ip=$(host_ip ent-observe-01)
    idp_ip=$(host_ip ent-idp-01)

    cat <<EOF
iptables -N ${CHAIN} 2>/dev/null || true
iptables -F ${CHAIN}
iptables -C FORWARD -j ${CHAIN} 2>/dev/null || iptables -I FORWARD 1 -j ${CHAIN}
iptables -A ${CHAIN} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A ${CHAIN} -s ${operator_cidr} -d 172.16.60.0/21 -j ACCEPT
iptables -A ${CHAIN} -s 172.16.60.0/21 -d ${idp_ip} -p udp --dport 53 -j ACCEPT
iptables -A ${CHAIN} -s 172.16.60.0/21 -d ${idp_ip} -p tcp -m multiport --dports 53,8080,8200 -j ACCEPT
iptables -A ${CHAIN} -s ${developer_cidr} -d ${inference_cidr} -j ACCEPT
iptables -A ${CHAIN} -s ${mlops_cidr} -d ${inference_cidr} -j ACCEPT
iptables -A ${CHAIN} -s ${app_cidr} -d ${inference_cidr} -j ACCEPT
iptables -A ${CHAIN} -s ${app_cidr} -d ${data_cidr} -j ACCEPT
iptables -A ${CHAIN} -s ${mlops_cidr} -d ${data_cidr} -j ACCEPT
iptables -A ${CHAIN} -s 172.16.60.0/21 -d ${observe_ip} -p tcp -m multiport --dports 3000,9200,9201 -j ACCEPT
iptables -A ${CHAIN} -s 172.16.60.0/21 -o ${ENT_UPSTREAM_BRIDGE} -j ACCEPT
iptables -A ${CHAIN} -s 172.16.60.0/21 -d 172.16.60.0/21 -j DROP
iptables -A ${CHAIN} -j RETURN
EOF
}

disable_rules() {
    iptables -D FORWARD -j "${CHAIN}" 2>/dev/null || true
    iptables -F "${CHAIN}" 2>/dev/null || true
    iptables -X "${CHAIN}" 2>/dev/null || true
}

case "$ACTION" in
    render)
        render_rules
        ;;
    apply)
        [[ $EUID -eq 0 ]] || { echo "apply must run as root on the Proxmox host" >&2; exit 1; }
        disable_rules
        render_rules | bash
        ;;
    disable)
        [[ $EUID -eq 0 ]] || { echo "disable must run as root on the Proxmox host" >&2; exit 1; }
        disable_rules
        ;;
    verify)
        iptables -S "${CHAIN}"
        ;;
    *)
        echo "Usage: $0 {render|apply|disable|verify}" >&2
        exit 2
        ;;
esac
