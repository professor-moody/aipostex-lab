# Reconnaissance

> Practice in [Scenario 01](../attack-scenarios/scenario-01.md) and [Scenario 03](../attack-scenarios/scenario-03.md).

## The technique in the real world

Before anything is exploited, the estate has to be mapped. Enterprise AI infrastructure sprawls:
model servers, vector stores, experiment trackers, LLM gateways, MCP servers, and bespoke `/chat`
apps land on internal networks when a team optimizes for shipping over access control. Recon decides
the rest of the engagement — each reachable service is either a credential source, a code-execution
surface, or a data store, and the fastest paths through an estate chain them together. The recurring
real-world finding is not one broken service; it is how many the team never realized were listening.

## How it works

Recon proceeds from coarse to specific:

- **Discovery** — sweep hosts/ports for AI/ML service signatures, tag each responder by family.
- **Service fingerprinting** — hit a service's own metadata surface (`/info`, `/metrics`,
  `/v1/models`, LiteLLM `/health`) to pull engine versions, model IDs, backend topology, and any
  API base URLs or keys the config leaks.
- **Model fingerprinting** — behaviorally attribute the *model* behind an endpoint, independent of
  what the service page or system prompt claims (see [model fingerprinting](model-fingerprinting.md)).
- **Endpoint / embedding recon** — exercise the live inference or embedding surface to confirm it
  actually serves, and to learn dimensions, limits, and routing.

## How aipostex performs it

```bash
# Network-wide service discovery (tags each host by service family)
aipostex discover network --target 172.16.50.10,172.16.50.20,172.16.50.30,172.16.50.40

# Deeper single-host fingerprint, no exploitation
aipostex discover network --target 172.16.50.20 --discovery-only

# Enumerate an OpenAI-compatible endpoint's models with value scoring
aipostex openai-compat --target http://172.16.50.20:4000 enum

# LiteLLM-specific surface: health topology, readiness, model-info (may carry keys)
aipostex openai-compat --target http://172.16.50.20:4000 litellm-probe

# Confirm an embedding server actually serves (endpoint recon)
aipostex huggingface --target 172.16.50.20:8181 embed --inputs "test sentence" --force-exploit
```

`enum`, `discover network`, `litellm-probe`, and behavioral `fingerprint` are all **read-only**
recon. `litellm-probe` escalates to Critical only if it actually reads back embedded credentials in
`/v1/model/info` — otherwise it reports topology and stops.

## Reading the result honestly

Recon is passive attribution, so it stays at the bottom of both axes: **`recon` / `reachable`**,
Info severity, on every discovery and fingerprint path. That is correct — mapping a service is not
compromising it. Recon only climbs when it *reads confirmed state back*: `litellm-probe` reaching
`read-confirmed` because it pulled a real key out of `/v1/model/info`, or `enum` on a proxy exposing
credentialed model configs. A discovery pass that surfaces a service but reads nothing sensitive is a
`reachable` lead, not a breach — report it as the lead it is.

!!! note "A responder is not a result"
    A service answering a probe proves it is *listening*, nothing more. Resist the urge to grade a
    reachable endpoint as impact; the value is in what the next step reads or changes, and honest
    recon findings are what let you pick that next step deliberately.

## Practice in the lab

| Scenario | What it drills |
|---|---|
| [01 — Reachability Survey](../attack-scenarios/scenario-01.md) | Network-wide discovery and service tagging across every lab host |
| [03 — Inference Server Fingerprinting](../attack-scenarios/scenario-03.md) | `/info` and `/metrics` service fingerprinting plus live embedding recon on HF TGI/TEI |

For model-level (behavioral) fingerprinting, continue to
[Scenario 14](../attack-scenarios/scenario-14.md) and the
[model fingerprinting](model-fingerprinting.md) technique.
