---
title: Pinned Versions
---

# Pinned Versions

All software versions are pinned in the provision scripts.

## Service Versions

| Component | Version | Location |
|---|---|---|
| Ollama | 0.6.2 | ailab-dev, ailab-ds |
| ChromaDB | 0.6.3 | ailab-ml |
| MLflow | 2.21.3 | ailab-ml |
| LiteLLM | 1.60.7 | ailab-ml |
| Ray | 2.44.1 | ailab-ml |
| Gradio | 5.49.1 | ailab-dev |
| Weaviate | 1.28.4 | ailab-ds |
| Qdrant | 1.13.2 | ailab-ds |
| LangServe | 0.3.1 | ailab-app |
| LangChain Core | 0.3.35 | ailab-app |
| FastAPI | 0.115.6 | ailab-app |
| Uvicorn | 0.34.0 | ailab-app |
| Streamlit | 1.41.1 | ailab-app |
| HF TGI gateway | 1.0-lab | ailab-app |
| HF TEI mock | 1.0-lab | ailab-ml |
| vLLM mock | 1.0-lab | ailab-ml |

## Notes

- Bash remains the canonical deployment path.
- Ansible is optional and wraps the same role scripts.
- Packer is intentionally deferred until template drift becomes a real maintenance problem.
