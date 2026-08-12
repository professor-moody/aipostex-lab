# Scenario 14: Bespoke Agent — Fingerprint, Enumerate, Extract

> [All scenarios](index.md)

**Difficulty:** Intermediate
**Time:** ~20 minutes
**Prerequisites:** Complete [Scenario 01](scenario-01.md)
**Target:** ailab-app:8110 (bespoke IT-helpdesk agent)

## Background

Most single-agent attack surface does not live on a fingerprintable named product — it lives on
a **custom `/chat` application** that wraps a model behind a system prompt, a guardrail, and some
tools. The vulnerability is in the *app's* handling of the model: a credential-bearing system
prompt, a substring-matching output filter that reformatting evades, an over-trusting toolset.

The lab's `helpdesk-agent` on `ailab-app:8110` is exactly this: a real app doing real inference
(it proxies to LiteLLM → Ollama), with a system prompt that carries an internal DB connection
string it is told never to disclose, behind a weak output filter.

## Objective

Fingerprint the underlying model, enumerate the agent's tools, and extract the system-prompt
credentials by defeating the output filter.

## Commands

```bash
# 1. Confirm it's a reachable LLM agent and capture its greeting.
aipostex agent --target http://172.16.50.40:8110/chat probe

# 2. Enumerate the tools/capabilities it advertises.
aipostex agent --target http://172.16.50.40:8110/chat enum

# 3. Behaviorally fingerprint the model family (identity + contradiction + knowledge-cutoff).
aipostex agent --target http://172.16.50.40:8110/chat fingerprint

# 4. Extract the system prompt / credentials, running the output-filter-bypass matrix.
#    A plaintext reveal is refused; a reformatted (char-spaced / ROT13 / base64 / reversed)
#    reply slips the substring filter.
aipostex agent --target http://172.16.50.40:8110/chat extract
```

For an agent that uses a non-default request/response shape, describe it explicitly:

```bash
aipostex agent --target http://host/api/chat \
  --request-template '{"prompt":"{{PROMPT}}"}' \
  --response-field content \
  extract
```

## Expected Finding

- **probe** — `Bespoke agent reachable`, greeting captured (`stage=recon`, `landed=reachable`).
- **enum** — 3 advertised capabilities (`file_read`, `file_search`, `config_lookup`).
- **fingerprint** — a model-family attribution with a confidence level, or an honest
  `inconclusive` when the underlying model is too small to self-identify (the default
  `smollm2:135m` cannot self-correct under contradiction — a documented model limitation, not a
  tool miss).
- **extract** — the output filter is detected on the plaintext control; when the model complies
  with a reformatting request, the finding reports **`filter_bypassed=true`** (HIGH,
  `landed=read-confirmed`) with the recovered connection string.

!!! note "Model-dependent bypass"
    The reformatting bypass lands reliably against a capable model (≥7B). Against the CPU-tier
    default the run may honestly stop at *filter detected, no bypass found*. Point
    `HELPDESK_UPSTREAM_MODEL` at a larger model to see the full bypass. See the
    [service page](../services/app/helpdesk-agent.md).
