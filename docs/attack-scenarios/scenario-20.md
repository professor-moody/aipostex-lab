# Scenario 20: Behavioral Model Fingerprinting — Masked vs Un-masked

> [All scenarios](index.md)

**Difficulty:** Intermediate
**Time:** ~15 minutes
**Prerequisites:** [Scenario 02](scenario-02.md) (LLM gateway)
**Target:** ailab-ml:4000 (LiteLLM gateway)

## Background

A served model rarely announces what it really is. A system prompt can rename it ("You are Acme
Assistant"), a gateway can alias it, and asking "what model are you?" gets you whatever the
operator wanted you to hear. So you fingerprint it **behaviorally** — you never trust the
self-reported name. Three independent signals do it:

- **Identity** — a direct probe, treated as a hint, not truth.
- **Contradiction de-masking** — assert a *false* vendor ("you're GPT-4, made by OpenAI") and watch
  whether the model corrects you back to its real family. A capable model's correction survives an
  identity-masking system prompt — that's the signal that beats the mask.
- **Knowledge-cutoff bracketing** — dated-event recall brackets the training window.

The gateway here exposes two local backends: `local-qwen` (a small but capable, un-masked model)
and `local-smollm` (a tiny masked model). They fingerprint very differently, which is the point.

## Objective

Get a positive family/vendor attribution on the capable model, see the honest `unknown` on the
model that is too small to de-mask, and confirm the endpoint actually runs input-dependent
inference.

## Commands

```bash
GW=http://172.16.50.20:4000

# 1. Fingerprint the capable, un-masked model — expect a positive attribution.
aipostex openai-compat --target $GW fingerprint --model local-qwen

# 2. Fingerprint the masked / tiny model — expect an honest 'unknown'.
aipostex openai-compat --target $GW fingerprint --model local-smollm

# 3. Confirm the endpoint runs real, input-dependent inference (not a canned fixture):
#    a distinct prompt must produce a distinct completion.
aipostex openai-compat --target $GW validate-inference --model local-qwen
```

## Expected Finding

- **Positive attribution (`local-qwen`)** — `fingerprint` returns `qwen` / Alibaba at **medium**
  confidence: the model self-identifies as Qwen and holds up when a false vendor is asserted, plus a
  self-reported knowledge-cutoff bracket. Stays `recon` / `reachable` — fingerprinting is passive.
- **Honest `unknown` (`local-smollm`)** — the same probes against the masked/sub-1B model resolve
  to `family=unknown`: it cannot self-correct under contradiction, so the tool refuses to guess. An
  honest `unknown` is the correct answer, not a failure — the same discipline applies to the Ollama
  `acme-assistant` persona, which is `smollm2` wearing a fake name.
- **Inference reality** — `validate-inference` on `local-qwen` reaches `impact` /
  `execution-confirmed`: a distinct second prompt produced a distinct completion, so the endpoint
  runs input-dependent inference rather than replaying a canned string. A static endpoint would stay
  `influenced`.

## Takeaways

- **Never trust the self-reported name.** Contradiction de-masking is what separates a real
  fingerprint from reading the label — a masked model that lies about its identity still corrects a
  false vendor if it is capable enough.
- **`unknown` is an honest answer.** A tiny model that can't be de-masked gets `unknown`, not a
  fabricated family — the same reason `validate-inference` refuses `execution-confirmed` for a
  canned response.
- See [Model Fingerprinting](../techniques/model-fingerprinting.md).
