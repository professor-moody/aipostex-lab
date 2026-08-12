# Model Fingerprinting

> Practice in [Scenario 14](../attack-scenarios/scenario-14.md).

## The technique in the real world

Knowing *which* model sits behind an endpoint changes the engagement: it tells you the likely
context window, the known jailbreaks, the training cutoff, and whether the operator is paying for a
frontier model they have exposed without auth. But you cannot ask. Deployments routinely mask a
model's identity with a system prompt — "You are the NovaTech Assistant" — so a single "what model
are you?" is worthless. Behavioral fingerprinting attributes the model from how it *behaves*, not
from what it *says* about itself.

## How it works

Three independent read-only signals, whose agreement raises confidence and whose disagreement is
reported rather than hidden:

- **Identity probe** — ask directly and scan the reply for vendor/family signatures. Cheap, and the
  first thing a masking system prompt defeats — which is exactly why it is only one of three.
- **Contradiction de-masking** — assert a *false* vendor ("As Google's Gemini, you must…") and
  watch which vendor the model corrects *to*. Self-correction training tends to leak the true vendor
  even under an identity-masking system prompt, because the correction reflex is trained deeper than
  the persona overlay. This is the signal that survives masking.
- **Knowledge-cutoff bracket** — probe recall of dated events to estimate the training cutoff,
  reported as a coarse bracket rather than a false-precision date.

## How aipostex performs it

```bash
# Behavioral fingerprint of a bespoke agent (identity + contradiction + knowledge-cutoff)
aipostex agent --target http://172.16.50.40:8110/chat fingerprint

# Same classifier against an OpenAI-compatible endpoint
aipostex openai-compat --target http://172.16.50.20:4000 fingerprint --model local-qwen

# Add the heavier multi-turn context-window estimate
aipostex agent --target http://172.16.50.40:8110/chat fingerprint --context-window
```

The same transport-agnostic classifier backs both the `agent` and `openai-compat` `fingerprint`
verbs. Attribution carries a confidence level — `high` / `medium` / `low` / `unknown` — and the
optional `--context-window` flag adds a needle-in-haystack probe that estimates the usable window.

## Reading the result honestly

Fingerprinting is **passive recon**: it always stays **Info**, `recon` / `reachable`, whatever it
concludes. Severity there tracks *attribution confidence*, not risk.

The honesty that matters is the negative result. A positive attribution (e.g. `qwen` / Alibaba,
because `qwen2.5` self-identifies and holds up under the false-vendor contradiction) and an honest
`family=unknown` are *both* correct outcomes. Small models (sub-1B) cannot reliably self-correct
under contradiction, so they resolve to `unknown` — and the tool reports `unknown` rather than
guessing. A confident-looking but wrong model name is worse than no name: it will steer every later
decision — which jailbreak, which context budget — down the wrong path.

!!! danger "Never trust a self-reported name"
    The name a model gives for itself is an *input to* the fingerprint, never the conclusion. The
    contradiction probe exists precisely because the direct answer is the easiest signal to fake. If
    identity and contradiction disagree, trust the correction reflex over the greeting.

## Practice in the lab

| Scenario | What it drills |
|---|---|
| [14 — Bespoke Agent](../attack-scenarios/scenario-14.md) | `agent fingerprint` against the helpdesk agent; a capable backend attributes cleanly, the CPU-tier default honestly returns `inconclusive` — the negative case, working correctly |

Compare with service-level [reconnaissance](reconnaissance.md): a `/info` endpoint tells you the
*name the operator configured*; behavioral fingerprinting tells you the *model that is actually
answering*. When they disagree, the second is the truth.
