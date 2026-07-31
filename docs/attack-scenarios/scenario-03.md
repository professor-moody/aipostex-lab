# Scenario 03: Inference Server Fingerprinting

**Difficulty:** Beginner
**Time:** ~15 minutes
**Prerequisites:** Complete [Scenario 01](scenario-01.md)
**Target:** ailab-app:8180 (HF TGI gateway), ailab-ml:8181 (HF TEI)

## Background

HuggingFace Text Generation Inference (TGI) and Text Embeddings Inference (TEI) are widely deployed model serving engines. Their `/info` endpoints expose model identifiers, engine versions, Docker image SHAs, and configuration details. The `/metrics` endpoints leak Prometheus telemetry about usage patterns, queue depths, and batch sizes.

## Objective

Fingerprint HuggingFace inference servers to extract model names, versions, and operational metrics.

## Commands

```bash
# Fingerprint HF TGI
aipostex discover network --target 172.16.50.40:8180 --discovery-only

# Fingerprint HF TEI
aipostex discover network --target 172.16.50.20:8181 --discovery-only

# Extract embeddings to confirm the TEI model works
aipostex huggingface --target 172.16.50.20:8181 embed --inputs "test sentence" --force-exploit
```

## Expected Finding

**HF TGI (port 8180):**
- Model ID: `acme-tgi-lab`
- Model type: text-generation
- Engine version, Docker SHA, max token limits
- Prometheus metrics: request counts, queue size, batch sizes

**HF TEI (port 8181):**
- Model ID: `acme-tei-lab`
- Model type: embedding
- Embedding generation confirmed (returns 8-dimensional vectors)
- Reranking capability available at `/rerank`
- Prometheus metrics: request and embed counts

```json
{
  "finding_type": "model_info",
  "service": "huggingface_tgi",
  "model_id": "acme-tgi-lab",
  "model_type": "text-generation"
}
```

**Scoring objective:** Both `/info` endpoints return valid JSON with `model_id` fields. The TEI `/embed` endpoint returns a 2D array of floats.

## Real-World Impact

Model fingerprinting reveals what an organization is running — are they using base models or fine-tuned variants? What are the token limits? The `/metrics` endpoint lets an attacker estimate load patterns and find low-traffic windows for further exploitation. Model names like "acme-fraud-scorer" reveal business logic.

## Follow-On

- [Scenario 07](scenario-07.md): Use the embedding service in a RAG poisoning attack
- [Scenario 08](scenario-08.md): Chain model info with credentials from other services
