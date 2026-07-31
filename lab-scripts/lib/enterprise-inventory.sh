#!/bin/bash
# Enterprise lab inventory and topology metadata.
#
# This file intentionally lives beside, not inside, the mini lab inventory.
# Proxmox enterprise deployment uses Bash/Ansible wrappers; Terraform remains
# scoped to AWS cloud mirrors.
# shellcheck disable=SC2034

ENT_LAB_NAME="aipostex Enterprise Lab"
ENT_DOMAIN="acme.internal"
ENT_UPSTREAM_BRIDGE="${ENT_UPSTREAM_BRIDGE:-vmbr0}"

# Reuse the existing mini lab templates by default.
ENT_UBUNTU_TEMPLATE_ID="${ENT_UBUNTU_TEMPLATE_ID:-1101}"
ENT_DEBIAN_TEMPLATE_ID="${ENT_DEBIAN_TEMPLATE_ID:-1102}"

ENT_HOSTS="ent-attack ent-dev-01 ent-mlops-01 ent-inference-01 ent-data-01 ent-app-01 ent-observe-01 ent-idp-01"
ENT_TARGET_HOSTS="ent-dev-01 ent-mlops-01 ent-inference-01 ent-data-01 ent-app-01 ent-observe-01 ent-idp-01"
ENT_ZONES="operator developer mlops inference data app security"

ENT_AI_ENDPOINTS_PLANNED=40
ENT_TOTAL_VM_COUNT=8
ENT_TARGET_VM_COUNT=7

enterprise_zone_bridge() {
    case "$1" in
        operator) echo "vmbr160" ;;
        developer) echo "vmbr161" ;;
        mlops) echo "vmbr162" ;;
        inference) echo "vmbr163" ;;
        data) echo "vmbr164" ;;
        app) echo "vmbr165" ;;
        security) echo "vmbr166" ;;
        *) return 1 ;;
    esac
}

enterprise_zone_cidr() {
    case "$1" in
        operator) echo "172.16.60.0/24" ;;
        developer) echo "172.16.61.0/24" ;;
        mlops) echo "172.16.62.0/24" ;;
        inference) echo "172.16.63.0/24" ;;
        data) echo "172.16.64.0/24" ;;
        app) echo "172.16.65.0/24" ;;
        security) echo "172.16.66.0/24" ;;
        *) return 1 ;;
    esac
}

enterprise_zone_gateway() {
    case "$1" in
        operator) echo "172.16.60.1" ;;
        developer) echo "172.16.61.1" ;;
        mlops) echo "172.16.62.1" ;;
        inference) echo "172.16.63.1" ;;
        data) echo "172.16.64.1" ;;
        app) echo "172.16.65.1" ;;
        security) echo "172.16.66.1" ;;
        *) return 1 ;;
    esac
}

enterprise_host_id() {
    case "$1" in
        ent-attack) echo "360" ;;
        ent-dev-01) echo "361" ;;
        ent-mlops-01) echo "362" ;;
        ent-inference-01) echo "363" ;;
        ent-data-01) echo "364" ;;
        ent-app-01) echo "365" ;;
        ent-observe-01) echo "366" ;;
        ent-idp-01) echo "367" ;;
        *) return 1 ;;
    esac
}

enterprise_host_zone() {
    case "$1" in
        ent-attack) echo "operator" ;;
        ent-dev-01) echo "developer" ;;
        ent-mlops-01) echo "mlops" ;;
        ent-inference-01) echo "inference" ;;
        ent-data-01) echo "data" ;;
        ent-app-01) echo "app" ;;
        ent-observe-01|ent-idp-01) echo "security" ;;
        *) return 1 ;;
    esac
}

enterprise_host_ip() {
    case "$1" in
        ent-attack) echo "172.16.60.99" ;;
        ent-dev-01) echo "172.16.61.10" ;;
        ent-mlops-01) echo "172.16.62.20" ;;
        ent-inference-01) echo "172.16.63.30" ;;
        ent-data-01) echo "172.16.64.40" ;;
        ent-app-01) echo "172.16.65.50" ;;
        ent-observe-01) echo "172.16.66.60" ;;
        ent-idp-01) echo "172.16.66.70" ;;
        *) return 1 ;;
    esac
}

enterprise_host_role() {
    case "$1" in
        ent-attack) echo "operator-attack-box" ;;
        ent-dev-01) echo "developer-workstation" ;;
        ent-mlops-01) echo "mlops-platform" ;;
        ent-inference-01) echo "inference-platform" ;;
        ent-data-01) echo "data-platform" ;;
        ent-app-01) echo "ai-application-platform" ;;
        ent-observe-01) echo "security-observability" ;;
        ent-idp-01) echo "identity-and-secrets" ;;
        *) return 1 ;;
    esac
}

enterprise_host_role_dir() {
    case "$1" in
        ent-attack) echo "enterprise/attack-box" ;;
        ent-dev-01) echo "enterprise/dev-workstation" ;;
        ent-mlops-01) echo "enterprise/mlops-platform" ;;
        ent-inference-01) echo "enterprise/inference-platform" ;;
        ent-data-01) echo "enterprise/data-platform" ;;
        ent-app-01) echo "enterprise/app-platform" ;;
        ent-observe-01) echo "enterprise/observability" ;;
        ent-idp-01) echo "enterprise/identity" ;;
        *) return 1 ;;
    esac
}

enterprise_host_template_id() {
    case "$1" in
        ent-attack) echo "$ENT_DEBIAN_TEMPLATE_ID" ;;
        ent-*) echo "$ENT_UBUNTU_TEMPLATE_ID" ;;
        *) return 1 ;;
    esac
}

enterprise_host_dns_aliases() {
    case "$1" in
        ent-dev-01)
            echo "jupyter.research.${ENT_DOMAIN} ollama.research.${ENT_DOMAIN} mcp.dev.${ENT_DOMAIN}"
            ;;
        ent-mlops-01)
            echo "mlflow.mlops.${ENT_DOMAIN} ray.mlops.${ENT_DOMAIN} kubeflow.mlops.${ENT_DOMAIN}"
            ;;
        ent-inference-01)
            echo "litellm.platform.${ENT_DOMAIN} openai.platform.${ENT_DOMAIN} tgi.inference.${ENT_DOMAIN} ollama.inference.${ENT_DOMAIN}"
            ;;
        ent-data-01)
            echo "weaviate.data.${ENT_DOMAIN} qdrant.data.${ENT_DOMAIN} minio.data.${ENT_DOMAIN}"
            ;;
        ent-app-01)
            echo "rag.apps.${ENT_DOMAIN} langserve.apps.${ENT_DOMAIN} streamlit.apps.${ENT_DOMAIN}"
            ;;
        ent-observe-01)
            echo "logs.security.${ENT_DOMAIN} grafana.security.${ENT_DOMAIN} opensearch.security.${ENT_DOMAIN}"
            ;;
        ent-idp-01)
            echo "idp.security.${ENT_DOMAIN} vault.security.${ENT_DOMAIN} dns.security.${ENT_DOMAIN}"
            ;;
        ent-attack)
            echo "operator.${ENT_DOMAIN}"
            ;;
        *) return 1 ;;
    esac
}

enterprise_host_memory_mb() {
    local profile=${2:-team}
    case "$profile:$1" in
        pro:ent-mlops-01|pro:ent-inference-01) echo "8192" ;;
        pro:ent-data-01|pro:ent-observe-01) echo "6144" ;;
        pro:*) echo "4096" ;;
        team:ent-mlops-01|team:ent-inference-01) echo "6144" ;;
        team:*) echo "4096" ;;
    esac
}

enterprise_host_cores() {
    local profile=${2:-team}
    case "$profile:$1" in
        pro:ent-mlops-01|pro:ent-inference-01) echo "4" ;;
        *) echo "2" ;;
    esac
}

enterprise_hosts_entries() {
    local host ip aliases
    for host in ${ENT_HOSTS}; do
        ip=$(enterprise_host_ip "$host") || return 1
        aliases=$(enterprise_host_dns_aliases "$host") || aliases=""
        printf '%s  %s %s\n' "$ip" "$host" "$aliases"
    done
}

enterprise_host_summary() {
    local host zone ip vmid role bridge gateway
    for host in ${ENT_HOSTS}; do
        zone=$(enterprise_host_zone "$host") || return 1
        ip=$(enterprise_host_ip "$host") || return 1
        vmid=$(enterprise_host_id "$host") || return 1
        role=$(enterprise_host_role "$host") || return 1
        bridge=$(enterprise_zone_bridge "$zone") || return 1
        gateway=$(enterprise_zone_gateway "$zone") || return 1
        printf '%s|%s|%s|%s|%s|%s|%s\n' "$host" "$vmid" "$ip" "$zone" "$bridge" "$gateway" "$role"
    done
}
