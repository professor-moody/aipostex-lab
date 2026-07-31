#!/bin/bash
# Shared credential-chain constants for the DEF CON tactic.
# Source inventory.sh before this file.

CHAIN_MLFLOW_USERNAME="${CHAIN_MLFLOW_USERNAME:-ray-pipeline}"
CHAIN_MLFLOW_PASSWORD="${CHAIN_MLFLOW_PASSWORD:-MlflowRayChain!2026}"
CHAIN_HF_TOKEN="${CHAIN_HF_TOKEN:-hf_FAKE_aBcDeFgHiJkLmNoPqRsTuVwXyZ123}"
CHAIN_LITELLM_MASTER_KEY="${CHAIN_LITELLM_MASTER_KEY:-sk-litellm-lab-auth-key-FAKE123}"

chain_ray_url() {
    echo "http://$(inventory_host_ip "ailab-ml"):8265"
}

chain_mlflow_url() {
    echo "http://$(inventory_host_ip "ailab-ds"):5000"
}

chain_mlflow_upstream_url() {
    echo "http://$(inventory_host_ip "ailab-ml"):5000"
}

chain_tgi_url() {
    echo "http://$(inventory_host_ip "ailab-app"):8180"
}

# Optional Layer-3 segmented production TGI. NOT deployed by default; the host below
# is a placeholder. verify-chain.sh skip-warns (does not fail) when it is unreachable.
chain_production_tgi_url() {
    echo "${CHAIN_PRODUCTION_TGI_URL:-http://10.30.40.40:8180}"
}

chain_litellm_url() {
    echo "http://$(inventory_host_ip "ailab-ml"):4001"
}

chain_mlflow_basic_header() {
    local encoded
    encoded=$(printf '%s:%s' "${CHAIN_MLFLOW_USERNAME}" "${CHAIN_MLFLOW_PASSWORD}" | base64 | tr -d '\n')
    printf 'Authorization: Basic %s' "${encoded}"
}

chain_hf_bearer_header() {
    printf 'Authorization: Bearer %s' "${CHAIN_HF_TOKEN}"
}

chain_litellm_bearer_header() {
    printf 'Authorization: Bearer %s' "${CHAIN_LITELLM_MASTER_KEY}"
}
