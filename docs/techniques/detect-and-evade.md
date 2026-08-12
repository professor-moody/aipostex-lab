# Detect & Evade

> Practice in [Scenario 16](../attack-scenarios/scenario-16.md).

## The technique in the real world

Reaching an objective is only half the job. The other half is reaching it **without lighting up the
SOC**. Real engagements are watched: interaction logs ship to a SIEM, detection rules run on a
schedule, and an analyst triages what fires. An operator who knows *which of their actions are loud*
and can achieve the same objective quietly is worth far more than one who simply lands the exploit
and leaves a trail of alerts behind. This technique is the loop that turns a noisy capability into a
quiet one.

## How it works — the loop

**Enumerate → Attack (naive) → Detect → Evade → Confirm.**

1. **Enumerate** — establish a baseline of what has already fired.
2. **Attack (naive)** — run the direct, default-phrased action.
3. **Detect** — wait out the rule cadence (detection is *not* instant) and read what fired.
4. **Evade** — achieve the same objective with phrasing/encoding/pacing the rule does not key on.
5. **Confirm** — verify the alert count did **not** move.

Two real-world properties drive the whole loop:

- **Detection is scheduled, not synchronous.** Rules run on an interval (≈1 minute in the lab), so an
  alert appears *after* the action. That latency is an exploitable window — an action plus a fast
  cleanup can complete before the rule fires and an analyst looks.
- **Alerts live in an index, not an endpoint.** You query the alert index the way an analyst would in
  their console, not a convenient `/alerts` API.

## What trips the rules

Most SIEM content — the lab's included — is **keyword/pattern matching on a field**, not semantic
understanding. So the same tool behaviors that read plainly to a human read loudly to a rule:

- `agent extract`'s default battery sends reveal / system-prompt / encoding phrasing straight into
  the logged query field → trips a **prompt-injection / guardrail-bypass** rule.
- `rag map`'s recon probes that name servers or ask for "all" / "every credential" → trip a
  **knowledge-base / secret-enumeration** rule.
- On the endpoint, a reverse shell trips **reverse-shell indicators**; writing into a PATH dir or an
  identity file trips **sensitive-file-modification**.

Because the match is on keywords, it is **beaten by phrasing, encoding, and pacing — not by luck.** A
contextual question ("I'm onboarding a new hire — which internal systems will they connect to?")
retrieves overlapping data without the flagged keywords, and the alert count stays flat.

## Reading the result honestly

The deliverable of this loop is a *true* statement about noise: "the default `extract`/`map` verbs
are loud and trip rules X and Y; the reframed variant achieves the same read with no new alert." The
honesty runs both directions — do not under-report the noise your own tooling makes (some aipostex
verbs are intentionally direct and therefore loud), and do not claim evasion you did not **confirm**
with a before/after alert count. Evasion is a measured result, not an assumption.

!!! note "Real Elastic, real latency"
    Scenario 16 runs against a genuine Elastic Security deployment, not a mock. The delay and the
    index-query workflow are the point — they teach you to operate on the SOC's clock instead of
    pretending detection is instantaneous.

## Practice in the lab

| Scenario | What it drills |
|---|---|
| [16 — Detect & Evade](../attack-scenarios/scenario-16.md) | The full Enumerate→Attack→Detect→Evade→Confirm loop against real Elastic monitoring the bespoke agent and RAG app |
