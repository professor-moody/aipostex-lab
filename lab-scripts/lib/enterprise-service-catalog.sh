#!/bin/bash
# Planned enterprise service health expectations.
# Source enterprise-inventory.sh before this file.

enterprise_service_health_checks() {
    cat <<'EOF'
ent-dev-01|8888|/api|version|Jupyter Research|
ent-dev-01|11434|/api/version|version|Ollama Research|
ent-dev-01|3000|/mcp|serverInfo|Developer MCP Server|
ent-mlops-01|5000|/health|OK|MLflow|
ent-mlops-01|8265|/api/version|ray_version|Ray|
ent-mlops-01|9000|/pipeline/|pipeline|Kubeflow|
ent-inference-01|4000|/health/liveliness|alive|LiteLLM Gateway|
ent-inference-01|8180|/health|ok|HF TGI Fixture|
ent-inference-01|11434|/api/version|version|Ollama Inference|
ent-data-01|8080|/v1/meta|version|Weaviate|
ent-data-01|6333|/collections|result|Qdrant|
ent-data-01|9001|/minio/health/live||MinIO|
ent-app-01|8090|/docs|LangServe|LangServe|
ent-app-01|8501|/_stcore/health|ok|Streamlit|
ent-observe-01|3000|/api/health|ok|Grafana|
ent-observe-01|9200|/_cluster/health|status|OpenSearch|
ent-observe-01|9201|/health|ok|Log Receiver|
ent-idp-01|8080|/realms/acme|realm|OIDC Fixture|
ent-idp-01|8200|/v1/sys/health|initialized|Vault|
EOF
}
