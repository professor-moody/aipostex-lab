#!/bin/bash
# Shared service health expectations for lab verification scripts.
# Source inventory.sh before this file.

inventory_service_health_checks() {
    cat <<'EOF'
ailab-dev|11434|/api/version|version|Ollama|
ailab-dev|8888|/api|version|Jupyter|
ailab-dev|3000|/mcp|serverInfo|MCP Server|
ailab-dev|7860|/|Gradio|Gradio|
ailab-dev|6274|/|inspector|MCP Inspector|
ailab-ml|8000|/api/v1/heartbeat|nanosecond|ChromaDB|
ailab-ml|5000|/health|OK|MLflow backend|
ailab-ml|4000|/health/liveliness|alive|LiteLLM|
ailab-ml|4001|/health/liveliness|alive|LiteLLM-Authed|Authorization: Bearer sk-litellm-lab-auth-key-FAKE123
ailab-ml|8265|/api/version|ray_version|Ray|
ailab-ds|5000|/health|OK|MLflow auth gateway|
ailab-app|8180|/health|ok|HF TGI gateway|
ailab-ml|8181|/info|model|HF TEI mock|
ailab-ml|8182|/health|healthy|vLLM mock|
ailab-ml|3333|/healthz|healthy|BentoML mock|
ailab-ml|8081|/models|models|TorchServe mock|
ailab-ml|8500|/v2/health/ready||Triton mock|
ailab-ml|8444|/healthz|wandb|WandB mock|
ailab-ml|9000|/pipeline/|pipeline|Kubeflow mock|
ailab-ml|8501|/v1/models/acme-fraud-scorer|model_version_status|TF Serving mock|
ailab-ds|8080|/v1/meta|version|Weaviate|
ailab-ds|6333|/collections|result|Qdrant|
ailab-ds|8889|/api|version|Jupyter DS|
ailab-ds|11434|/api/version|version|Ollama DS|
ailab-app|8090|/docs|LangServe|LangServe|
ailab-app|8501|/_stcore/health|ok|Streamlit|
ailab-app|8100|/.well-known/agent-card.json|name|A2A Agent (unauth)|
ailab-app|8101|/.well-known/agent-card.json|name|A2A Agent (multiturn)|
ailab-app|8102|/.well-known/agent-card.json|name|A2A Agent (authed)|Authorization: Bearer sk-a2a-lab-agent-token-FAKE456
ailab-attack|9000|/health|healthy|Lab Listener|
EOF
}
