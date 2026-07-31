# RRR honesty matrix

**RRR — "real result, or it didn't happen."** Detection of a protocol-accurate fixture is a real
result and belongs in the benchmark, labeled a *detection surface*. But every exploit payoff,
demo, tactic success, scoring-contract pass, and chain hop must be backed by real software or real
behavior — no canned successful capability anywhere public. A fixture must never emit a
credential-gate or state-change claim.

## Tiers (mapped to aipostex `landed`)

| Tier | Max `landed` | Meaning |
|---|---|---|
| **detection** | `reachable` | protocol/API realistic enough for fingerprinting + vuln-template coverage; no exploit payoff claimed |
| **credential-gate** | `read-confirmed` | wrong/no credential fails; the harvested credential succeeds (a read) |
| **state-change** | `execution-confirmed` | write+readback, callback, oracle event, real task execution, or real generated output |

## The matrix

`scoring/rrr_matrix.json` assigns each surface (by `module` [+ `action`]) a tier and the maximum
honest `landed` it may claim. Ranks mirror `internal/enrichment.LandedRank`.
Surfaces not listed are reported as **uncovered** (a classification gap to fill), not failed.

- **detection** (max `reachable`): the GPU-bound inference fixtures — Triton, TF-Serving,
  TorchServe, BentoML, TEI — and HuggingFace `enum`/`models`/`metrics`.
- **credential-gate** (max `read-confirmed`): MLflow / W&B / Kubeflow / LiteLLM enumeration reads.
- **state-change** (max `execution-confirmed`): the real inference payoffs — `huggingface generate`
  via the gated TGI gateway, `litellm proxy-chain --relay-test` → real Ollama,
  `openai-compat validate-inference` — and Ray RCE.

## Verify

```bash
python3 score.py <aipostex-output> --rrr                   # fails on any landed over-claim
python3 score.py <aipostex-output> --rrr -v                # also lists uncovered (unclassified) surfaces
python3 score.py <aipostex-output> --rrr-require-covered   # implies --rrr; ALSO fails if any surface is uncovered
```

The benchmark gate (`collect-findings.sh`) uses `--rrr-require-covered`, so every `module:action`
the tool emits must be classified in the matrix — a new action with an elevated proof but no surface
entry fails the run until it is added to `rrr_matrix.json`.

A finding whose claimed `metadata.landed` outranks its surface's max is an **over-claim**
and fails the check — e.g. a Triton (detection) finding claiming `execution-confirmed`, or an
MLflow `enum` (credential-gate) finding claiming `execution-confirmed`. This is what keeps a
fixture-backed "success" from masquerading as real compromise.
