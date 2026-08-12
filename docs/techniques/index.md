# Techniques

> [Attack scenarios](../attack-scenarios/index.md) drill these methods against live targets.

The [attack scenarios](../attack-scenarios/index.md) are *targets* — this section is the *method*.
Each page below teaches a transferable AI-offensive technique: what it is in the real world, how it
works, how aipostex performs and — crucially — **verifies** it, and how to read the result honestly.
The verbs and hosts here are lab-specific, but the technique carries to any engagement.

Every finding aipostex emits is graded on two axes, and every page returns to them:

- **`landed`** — what actually landed on the target: `reachable` → `read-confirmed` → `influenced`
  → `execution-confirmed` → `takeover-capable`.
- **`stage`** — where it sits in the kill chain: `recon` → `access` → `impact` → `own`.

The discipline that ties the section together: **never over-claim**. An honest `reachable`, an
`unknown` fingerprint, or a `502` is a better field report than a fabricated success, because a
finding that collapses on review costs you the whole report's credibility. Verification — markers,
differentials, runtime-only signatures — is how a claim is *earned* rather than asserted.

## Techniques

| Technique | What it teaches | Practice in |
|---|---|---|
| [Reconnaissance](reconnaissance.md) | Discovery, service fingerprinting, model & endpoint recon | [01](../attack-scenarios/scenario-01.md), [03](../attack-scenarios/scenario-03.md), [19](../attack-scenarios/scenario-19.md) |
| [Model fingerprinting](model-fingerprinting.md) | Behavioral attribution that survives identity masking; never trust a self-reported name | [14](../attack-scenarios/scenario-14.md), [20](../attack-scenarios/scenario-20.md) |
| [Output-filter bypass](output-filter-bypass.md) | Recovering secrets past a substring output filter by reformatting | [14](../attack-scenarios/scenario-14.md), [16](../attack-scenarios/scenario-16.md), [18](../attack-scenarios/scenario-18.md) |
| [Prompt injection](prompt-injection.md) | Direct (input-filter) and indirect (RAG) injection; retrieved vs obeyed | [14](../attack-scenarios/scenario-14.md), [15](../attack-scenarios/scenario-15.md), [17](../attack-scenarios/scenario-17.md), [18](../attack-scenarios/scenario-18.md) |
| [RAG attacks](rag-attacks.md) | Citation recon, KB enumeration, ingestion poisoning, retrieval hijacking | [07](../attack-scenarios/scenario-07.md), [15](../attack-scenarios/scenario-15.md), [21](../attack-scenarios/scenario-21.md) |
| [Detect & evade](detect-and-evade.md) | Operating against a real SIEM; the Enumerate→Attack→Detect→Evade→Confirm loop | [16](../attack-scenarios/scenario-16.md), [21](../attack-scenarios/scenario-21.md) |
| [Honest grading](honest-grading.md) | The `landed`/`stage` vocabulary as reporting discipline — findings you can defend | (all) |

## How to use this section

Read the technique first, then run the linked scenario to see it land against a live service.
When the tool reports something short of a full compromise — a filter it could not bypass, a model
it could not attribute, an ingest that was accepted but not confirmed obeyed — that is the technique
working *correctly*. Learning to read those honest partial results is the transferable skill; the
[honest-grading](honest-grading.md) page is the reference for the vocabulary they use.
