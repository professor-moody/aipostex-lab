#!/bin/bash
# segmentation.sh — OPT-IN network segmentation toggle (default OFF).
#
# The default lab is FLAT: every host is reachable at enumeration (the shadow-AI
# premise), and that flat estate is the validated benchmark premise. This toggle
# is an EXPERIMENTAL "enterprise feel" overlay: it blocks the attack box from the
# exposed MLflow platform backend (ailab-ml:5000) so the ONLY path to MLflow is
# the credential-gated auth gateway (ailab-ds:5000) — i.e. it makes the gated
# credential-chain hop *network*-enforced as well. The credential-gated chain
# (Scenario 08) still works; the direct exposed-backend path (Scenario 06/10)
# becomes refused from the attack box.
#
# It is NOT part of the scored default — leave it disabled for the standard
# benchmark. Hard, multi-zone segmentation lives in the Enterprise lab line
# (lib/enterprise-inventory.sh); this is the lightweight single-rule toggle.
#
#   Run ON ailab-ml as root:   sudo bash segmentation.sh {enable|disable|status}
#   Or from proxmox:           ssh labadmin@172.16.50.20 'sudo bash ~/lab/segmentation.sh enable'
#
# After enabling, verify with:  AIPOSTEX_SEGMENTATION=1 bash verify-chain.sh
set -euo pipefail

ATTACK_IP="${ATTACK_IP:-${LAB_SUBNET:-172.16.50}.99}"    # ailab-attack vantage; set LAB_SUBNET for a non-base estate
BACKEND_PORT="5000"         # MLflow platform backend on ailab-ml (the exposed backend)
COMMENT="aipostex-segmentation"

rule_present() {
    iptables -C INPUT -s "$ATTACK_IP" -p tcp --dport "$BACKEND_PORT" \
        -m comment --comment "$COMMENT" -j DROP 2>/dev/null
}

case "${1:-status}" in
    enable)
        [[ $EUID -eq 0 ]] || { echo "[!] run as root (sudo)"; exit 1; }
        if ! rule_present; then
            iptables -I INPUT -s "$ATTACK_IP" -p tcp --dport "$BACKEND_PORT" \
                -m comment --comment "$COMMENT" -j DROP
        fi
        echo "[+] segmentation ENABLED: ${ATTACK_IP} -> :${BACKEND_PORT} DROP"
        echo "    The gated MLflow gateway path (ailab-ds:5000) is unaffected; only the"
        echo "    direct ailab-ml:5000 backend is now refused from the attack box."
        ;;
    disable)
        [[ $EUID -eq 0 ]] || { echo "[!] run as root (sudo)"; exit 1; }
        while rule_present; do
            iptables -D INPUT -s "$ATTACK_IP" -p tcp --dport "$BACKEND_PORT" \
                -m comment --comment "$COMMENT" -j DROP
        done
        echo "[+] segmentation DISABLED: ailab-ml:5000 directly reachable again (flat lab default)"
        ;;
    status)
        if rule_present; then
            echo "segmentation: ENABLED (attack box blocked from ailab-ml:5000)"
        else
            echo "segmentation: disabled (flat lab default — backend exposed)"
        fi
        ;;
    *)
        echo "usage: $0 {enable|disable|status}"
        exit 2
        ;;
esac
