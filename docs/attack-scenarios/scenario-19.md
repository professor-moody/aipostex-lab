# Scenario 19: Embedding Endpoint Recon

> [All scenarios](index.md)

**Difficulty:** Beginner–Intermediate
**Time:** ~15 minutes
**Prerequisites:** [Scenario 01](scenario-01.md) (reachability survey)
**Target:** ailab-ml:8181 (HF Text Embeddings Inference)

## Background

Every RAG pipeline has an **embedding model** turning text into vectors, and it is often the least
guarded component in the stack. A Text Embeddings Inference (TEI) server exposes model metadata and
an embedding API — frequently **unauthenticated** — because it is treated as "internal
infrastructure." For an attacker it is two things at once: a **recon surface** (which embedding
model is in use tells you how to craft inputs that retrieve or collide with target documents) and a
**data surface** (raw vectors returned with no auth).

Knowing the embedding model matters downstream. If you know a RAG store was built with a specific
model, you can embed your own text with the *same* model to reason about what will retrieve — the
groundwork for the ingestion-poisoning and retrieval-hijacking attacks in
[Scenario 15](scenario-15.md).

## Objective

Fingerprint the embedding service and its model, confirm the embedding surface is unauthenticated,
and capture a raw vector.

## Commands

```bash
TEI=http://172.16.50.20:8181

# 1. Fingerprint the service type and model from /info (TEI vs TGI auto-detected).
aipostex huggingface --target $TEI enum

# 2. Confirm the embedding surface takes input with no auth and returns raw vectors (gated —
#    it exercises the endpoint).
aipostex huggingface --target $TEI embed --inputs "acme quarterly financials" --force-exploit

# 3. Operational metadata (request/embed counters) from the metrics endpoint.
aipostex huggingface --target $TEI metrics
```

## Expected Finding

- **Service + model fingerprint** — `enum` reads `/info` and reports the service as TEI with the
  served embedding model's `model_id`, `model_type`, version, and Docker SHA. That model identity
  is the recon prize: it tells you exactly which embedder feeds the RAG store.
- **Unauthenticated embedding surface** — `embed` posts text to `/embed` with no credential and
  gets back a raw float vector. The finding records the vector dimensionality — the fingerprint of
  the embedding space (e.g. 384 = MiniLM-class, 768 = base-BERT/MPNet-class, 1024 = large-class).
- **Metrics** — request and embed counters confirm the endpoint is live and in use.

!!! note "Mock scope"
    This lab's TEI endpoint is an honestly-labeled mock: it mirrors the TEI **API shape**
    (`/info`, `/embed`, `/metrics`) so the recon and unauthenticated-access surface are real, but it
    does not run a GPU embedding model. `aipostex` grades it accordingly — it claims what it can
    prove (reachable / influenced against the embed surface) and does not over-claim real
    embedding-model semantics.

## Takeaways

- **The embedder is recon, not an afterthought.** Model identity + dimensionality + unauthenticated
  access is everything an attacker needs to start reasoning about the RAG store it feeds.
- **Unauthenticated "internal" ML services are the norm, not the exception** — an embedding
  endpoint with no auth is a finding on its own and a stepping stone into the retrieval pipeline.
- See [Reconnaissance](../techniques/reconnaissance.md) and the RAG attacks in
  [Scenario 15](scenario-15.md).
