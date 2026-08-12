#!/bin/bash
# Shared human-editable lab inventory and topology metadata.
# Source this file from Bash orchestration, verification, and wrapper scripts.
# shellcheck disable=SC2034  # Variables are used by scripts that source this file.

LAB_NAME="aipostex Lab"

# ── Multi-estate group offset ────────────────────────────────────────────────
# Group 0 is the base estate (real inventory IDs / 172.16.50 / vmbr100). Estate K is
# provisioned non-colliding and isolated using the SAME stride scheme reset-wave.sh
# already assumes, so deploy and reset agree:
#   VM IDs : <base> + VMID_STRIDE*GROUP_ID  (1000 keeps estate K clear of 106 / 210-250 /
#                                            foundry 310-350 / templates 1101-1102)
#   subnet : 172.16.(50 + SUBNET_STRIDE*GROUP_ID)
#   bridge : vmbr10<GROUP_ID>               (group 0 = vmbr100, the existing base bridge)
# Designed for single-digit GROUP_ID (a handful of estates on one host). GROUP_ID=0
# resolves to exactly the base estate, so existing single-estate behavior is unchanged.
GROUP_ID="${GROUP_ID:-0}"
VMID_STRIDE="${VMID_STRIDE:-1000}"
SUBNET_STRIDE="${SUBNET_STRIDE:-1}"

# Per-estate isolated bridge; honor an explicit LAB_BRIDGE override.
LAB_BRIDGE="${LAB_BRIDGE:-vmbr10${GROUP_ID}}"
# Honor an explicit LAB_SUBNET override (e.g. reset-wave.sh per-estate verify); otherwise
# derive it from GROUP_ID.
LAB_SUBNET="${LAB_SUBNET:-172.16.$((50 + SUBNET_STRIDE * GROUP_ID))}"
LAB_GATEWAY="${LAB_SUBNET}.1"

LAB_TEMPLATE_ID=1101          # templates are the shared clone source — NOT strided per estate
LAB_ATTACK_TEMPLATE_ID=1102

LAB_AI_ENDPOINTS=29
LAB_TARGET_VM_COUNT=4
LAB_TOTAL_VM_COUNT=6
LAB_VERIFY_LAB_EXPECTED_CHECKS=62
LAB_TOTAL_SENSITIVE_FINDINGS=170

LAB_TARGET_HOSTS="ailab-dev ailab-ml ailab-ds ailab-app"
# k8s is a real estate target but is provisioned/verified via a dedicated path (k3s, not
# the generic role service-matcher), so it's in ALL_HOSTS (etc/hosts, snapshots) but not
# the generic TARGET_HOSTS loop.
LAB_K8S_HOST="ailab-k8s"
LAB_ALL_HOSTS="${LAB_TARGET_HOSTS} ${LAB_K8S_HOST} ailab-attack"
LAB_SERVICE_SCAN_PORTS="3000,3333,4000,4001,5000,5432,6274,6333,7860,8000,8080,8081,8082,8090,8100,8101,8102,8180,8181,8182,8265,8444,8500,8501,8888,8889,9000,11434"
# Post-ex ports are opt-in (not in default scan); set LAB_POSTEX_PORTS to scan them
LAB_POSTEX_PORTS="8765,9999"

inventory_host_ip() {
    case "$1" in
        ailab-dev) echo "${LAB_SUBNET}.10" ;;
        ailab-ml) echo "${LAB_SUBNET}.20" ;;
        ailab-ds) echo "${LAB_SUBNET}.30" ;;
        ailab-app) echo "${LAB_SUBNET}.40" ;;
        ailab-k8s) echo "${LAB_SUBNET}.50" ;;
        ailab-attack) echo "${LAB_SUBNET}.99" ;;
        ailab-siem) echo "${LAB_SUBNET}.60" ;;  # persistent detection host (Elastic); NOT in reset-wave
        *) return 1 ;;
    esac
}

inventory_host_id() {
    local base
    case "$1" in
        ailab-dev) base=210 ;;
        ailab-ml) base=220 ;;
        ailab-ds) base=230 ;;
        ailab-app) base=250 ;;
        ailab-k8s) base=260 ;;
        ailab-attack) base=240 ;;
        ailab-siem) base=270 ;;  # persistent detection host (Elastic); NOT in reset-wave
        *) return 1 ;;
    esac
    echo "$((base + VMID_STRIDE * GROUP_ID))"
}

inventory_host_role() {
    case "$1" in
        ailab-dev) echo "developer-workstation" ;;
        ailab-ml) echo "ml-platform" ;;
        ailab-ds) echo "data-science" ;;
        ailab-app) echo "shared-ai-apps" ;;
        ailab-k8s) echo "k8s-cluster" ;;
        ailab-attack) echo "attack-box" ;;
        *) return 1 ;;
    esac
}

inventory_host_role_dir() {
    case "$1" in
        ailab-dev) echo "dev-workstation" ;;
        ailab-ml) echo "ml-platform" ;;
        ailab-ds) echo "data-sci" ;;
        ailab-app) echo "app-platform" ;;
        ailab-k8s) echo "k8s-node" ;;
        ailab-attack) echo "attack-box" ;;
        *) return 1 ;;
    esac
}

inventory_host_expected_services() {
    case "$1" in
        ailab-dev) echo "5" ;;
        ailab-ml) echo "13" ;;
        ailab-ds) echo "6" ;;
        ailab-app) echo "7" ;;
        *) return 1 ;;
    esac
}

inventory_host_service_matcher() {
    case "$1" in
        ailab-dev) echo "(ollama|jupyter|mcp|gradio|inspector)" ;;
        ailab-ml) echo "(chromadb|mlflow|litellm|ray|hf-tei-mock|vllm-mock|bentoml-mock|torchserve-mock|triton-mock|wandb-mock|kubeflow-mock|tfserving-mock)" ;;
        ailab-ds) echo "(ollama|jupyter-ds|weaviate|qdrant|postgresql|mlflow-auth-gateway)" ;;
        ailab-app) echo "(langserve|streamlit|tgi-gateway|a2a-agent|post-ex-oracle)" ;;
        *) return 1 ;;
    esac
}

inventory_target_ips_csv() {
    local first=1 host ip
    for host in ${LAB_TARGET_HOSTS}; do
        ip=$(inventory_host_ip "$host") || return 1
        if [[ $first -eq 1 ]]; then
            printf '%s' "$ip"
            first=0
        else
            printf ',%s' "$ip"
        fi
    done
}

inventory_listener_url() {
    echo "http://$(inventory_host_ip "ailab-attack"):9000"
}

inventory_pox_url() {
    echo "http://$(inventory_host_ip "ailab-app"):8765"
}

inventory_hosts_entries() {
    local host ip
    for host in ${LAB_ALL_HOSTS}; do
        ip=$(inventory_host_ip "$host") || return 1
        printf '%s  %s\n' "$ip" "$host"
    done
}

# ── Tactic profiles / role selection (single-tactic vs full-lab deploys) ──────────────────────
# Deploy only the VMs a tactic needs. LAB_PROFILE expands to a role set; LAB_ONLY_ROLES overrides
# it directly. Default is the full estate, so the unset behaviour is UNCHANGED. Short role names:
# dev ml ds app attack k8s. `attack` (the foothold) is ALWAYS included. See
# docs/deployment/deployment-matrix.md and docs/demo/tactic-chain.md for the tactic->VM mapping.
inventory_profile_roles() {  # $1 = profile name -> space-separated short roles
    case "${1:-full}" in
        full)             echo "dev ml ds app attack k8s" ;;
        credential-chain) echo "dev ml ds app attack" ;;
        a2a)              echo "app attack" ;;
        k8s)              echo "k8s attack" ;;
        *) return 1 ;;
    esac
}
LAB_ONLY_ROLES="${LAB_ONLY_ROLES:-$(inventory_profile_roles "${LAB_PROFILE:-full}")}"
inventory_role_wanted() {  # $1 = short role (dev|ml|ds|app|attack|k8s) -> 0 if this deploy includes it
    [ "$1" = "attack" ] && return 0                     # the foothold is always deployed
    case " ${LAB_ONLY_ROLES} " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}
