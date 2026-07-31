---
title: Mock & Fixture Fidelity
---

# Mock & fixture fidelity

The lab runs **real upstream software wherever CPU allows** and uses honestly-labeled
mocks/fixtures only where the real product needs a GPU or an external SaaS account. This page
records how close each non-real service is to its real product, what is **by design** (the
planted vulnerability), and the remaining polish backlog.

## Three tiers

- **Real software** — Ray, MLflow, Ollama, LiteLLM, Jupyter, ChromaDB, Qdrant, Weaviate,
  PostgreSQL+pgvector, LangServe, Streamlit, Gradio, the MLflow-auth + TGI gateways, and the
  (intentionally vulnerable) MCP server. Genuine, not simulated.
- **Protocol mock** — speaks the real product's API shape with seeded data: W&B (GraphQL),
  Kubeflow (v1beta1 + v2beta1), A2A (JSON-RPC 2.0), TF-Serving.
- **GPU protocol fixture** — protocol-accurate but canned (no GPU driver on the lab yet): Triton,
  TorchServe, BentoML, vLLM, HF TGI/TEI.
  - **Bare detection/enum** of these scores `reachable` — honest, they are just fingerprinted.
  - **The lifecycle exploit verbs** (`torchserve register`, `triton model-load`, `tfserving`/`bentoml
    predict`) DO reach `execution-confirmed`: the fixture runs the real management-API lifecycle
    (unauthenticated registration, SSRF fetch of an attacker-supplied `--model-url`, model → READY),
    and the tool's [inference-reality probe](../deployment/gpu-components.md#how-the-tool-reacts) then
    confirms the invocation is **input-dependent** before grading. **Honesty caveat, stated plainly:**
    on this CPU lab the handler/inference response is a protocol fixture — it is input-dependent
    (the predict path returns an `input_sha256` of the request body, so distinct inputs yield distinct
    responses and the probe legitimately sees variation) but it is **not a real neural network**. The
    *attack* is real-shaped (unauth registration + SSRF is exactly the TorchServe/Triton RCE class); the
    *model output* is simulated. On a real GPU deployment this same flow is genuine model execution.
  - **Upgrade path:** the Proxmox host has an idle **discrete GPU**
    on the `nouveau` driver. As a future GPU-upgrade path, install the CUDA driver + a real
    Triton/TorchServe with a small model (host-side with the VMs proxying, mirroring the TGI gateway,
    or via VFIO passthrough) to make these `execution-confirmed` grades real rather than
    fixture-simulated. Deferred: high-risk on the single host that runs the whole lab, and a lower
    priority than the peripheral own-depth work.

## By design — NOT fidelity gaps

These services are **intentionally unauthenticated** — the misconfiguration *is* the planted
finding (shadow-AI sprawl left open). A fidelity audit will flag "no auth validation" against
the real product, but adding auth here would delete the scenario. Keep them open:

- W&B GraphQL (no Bearer required), Kubeflow API, Ray dashboard, the inference servers, etc.
  The MLflow-auth gateway and TGI gateway are the deliberately *gated* hops in the credential
  chain; everything else models an exposed surface.

## Applied protocol-fidelity fixes (2026-06)

Field-diffed the protocol mocks against the real product APIs and closed safe, non-auth gaps:

- **W&B mock**: GraphQL nodes now carry `__typename` (`Project`/`Run`/`ArtifactCollection`),
  parse errors return HTTP 200 with `errors[].extensions` (real GraphQL semantics, not 400),
  and `Content-Type` is `application/json; charset=utf-8`.
- **Kubeflow mock**: error responses are JSON (`{error,message,code}`) instead of plain text,
  and responses set `X-Content-Type-Options`/`X-Frame-Options`/`Cache-Control` like real KFP.

These are additive and preserve the tool's parsing + the planted unauth findings (verified:
100% coverage, contracts, RRR all still clean).

## Real-product target: A2A agent (a2a-sdk)

The hand-written `a2a-agent-{basic,multiturn,authed}` mocks (8100-8102) are shaped around what
aipostex sends, which can *mask* tool bugs. To validate against true protocol behaviour, an
**additive** real agent built on the official **a2a-sdk** runs on port **8103**
(`a2a-agent-real.service`); see `lab-scripts/app-platform/a2a-real-agent/`. It is opt-in
(`deploy-real-a2a-agent.sh`) and does not touch the scored mocks.

Proving aipostex against it caught three real tool bugs the mock had hidden — the version
fallback ignored `-32602`/`-32009` (only `-32601`); `task-send` claimed success on a JSON-RPC
error; `stream-probe` claimed "eavesdropped" with zero SSE events — all now fixed in aipostex
with tests. This is the A2A half of the deferred real-instance proof.

## Real-product target: MCP server (official MCP SDK)

The MCP target on **ailab-dev:3000** is now a genuine server built on the official **Model
Context Protocol Python SDK** (FastMCP, Streamable HTTP at `/mcp`) — it **replaced** the
former hand-written `acme-mcp` mock outright (no dual-running). Tool argument schemas are
enforced by pydantic, so aipostex is exercised against true SDK behaviour. See
`lab-scripts/dev-workstation/mcp-real-server/`.

Proving aipostex against it caught real tool gaps the lax mock had hidden — the client 404'd on
a real server's base URL (no `/mcp` discovery); the official SDK's strict schema validation
rejected the fixed-shape `cmd-inject` / `path-traversal` / `env-extract` payloads so they never
landed; and the stateful `mcp-cmdi-001` / `mcp-path-001` / `mcp-ssrf-001` scan templates
couldn't complete the handshake over raw HTTP. All fixed in aipostex with tests (endpoint
discovery, schema-aware tool invocation, and an MCP-transport template executor). This is the
MCP half of the deferred real-instance proof.

## Backlog (deferred polish)

Lower-priority realism items, to apply when field-diffing against real instances (the guided
tactic does not depend on them):

- W&B: rate-limit + `X-Request-Id` headers; optional REST fallback endpoints.
- Kubeflow: HTTP 201 + full object (timestamps) on `POST /runs`; single-resource GETs
  (`/runs/{id}`); stateful `page_token` pagination.
- Inference fixtures (Triton/TF-Serving/TorchServe/BentoML/vLLM): error-body JSON wrapping +
  product-specific headers per each KServe/OpenAI/TorchServe spec.
- A2A / MCP: continue tracking the current spec (agent-card schema, JSON-RPC error codes, MCP
  session lifecycle). A2A and MCP now run real product; W&B remains the last deferred
  real-instance proof (self-hosted W&B Server is Docker-gated).
