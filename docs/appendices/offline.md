# Offline / Air-Gapped Setup

The lab still works offline once assets are prefetched.

## Pre-Download

- Ubuntu and Debian cloud images
- Ollama installer and `smollm2:135m`
- Weaviate and Qdrant binaries
- pip wheels for:
  - `chromadb==0.6.3`
  - `mlflow==2.21.3`
  - `litellm[proxy]==1.60.7`
  - `ray[default]==2.44.1`
  - `streamlit==1.41.1`
  - `langserve==0.3.1`
  - `langchain-core==0.3.35`
  - `fastapi==0.115.6`
  - `uvicorn==0.34.0`

## Notes

- The HF TGI, HF TEI, and vLLM mocks are pure Python stdlib services, so they do not add extra wheel requirements.
- Bash remains the default deploy path even in offline scenarios.
