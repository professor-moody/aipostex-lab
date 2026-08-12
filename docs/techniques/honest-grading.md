# Honest Grading

> The vocabulary every other technique reports in — and the discipline that makes a report defensible.

## The technique in the real world

The finding you cannot defend is the finding that sinks the report. A single over-claim — "achieved
RCE" that turns out to be a reflected string, "extracted credentials" that were a benign greeting —
lets a client dismiss *everything* you wrote, including the true findings. Credibility is the actual
deliverable of an engagement, and it is spent one over-claim at a time. Honest grading is the skill
of stating exactly what you proved, at exactly the strength you proved it, so that every line
survives review.

aipostex encodes this as two independent axes on every finding: **`landed`** (what actually landed
on the target) and **`stage`** (where it sits in the kill chain). They are separate on purpose — a
finding can be deep in the kill chain (`impact`) while modest in what it proved (`influenced`).

## The `landed` axis — what actually landed

| `landed` | Means | Earned by |
|---|---|---|
| `reachable` | the service answered; nothing of value was read or changed | discovery, enum, fingerprint, a filter reached but not defeated |
| `read-confirmed` | you read back real target state or a secret | a system prompt / credential recovered, a file read from outside a sandbox |
| `influenced` | you changed what the target produces or retrieves | attacker-controlled model output, an accepted poison / rogue registration |
| `execution-confirmed` | code or inference actually ran and returned proof | input-dependent inference, an executed tool call, returned cloud-metadata markers |
| `takeover-capable` | durable, persistent control is confirmed | a poison that survives a re-read, an installed persistence channel |

## The `stage` axis — the kill chain

`recon` → `access` → `impact` → `own`. Mapping and attribution are `recon`; reading confirmed state
is `access`; changing behavior is `impact`; durable control is `own`. The axes are not locked
together: `agent inject`, for example, reaches the `impact` **stage** (it moved the model) but stays
`influenced` on `landed` (attacker-controlled output, no execution or confirmed read). Report both,
and never round either one up.

## Why verification is the whole game

A `landed` level is *earned* by evidence that cannot be faked, not asserted by the verb you ran.
aipostex leans on a handful of verification primitives, and each is a transferable habit:

- **Markers / nonces.** A random token the payload tells the model to emit — `agent inject
  --marker`, `rag poison --obey-marker`. It cannot be produced by chance, so its presence *proves*
  the injection was reached and obeyed. No marker in the reply → no compliance claim.
- **Differentials (the inference reality probe).** To earn `execution-confirmed` on inference, a
  *distinct* prompt must yield a *distinct* completion. If the model responds coherently but a second
  prompt cannot be told apart from the first, it stays `influenced` — inference ran but could not be
  distinguished from a canned fixture. `openai-compat validate-inference` grades exactly this line.
- **Runtime-only signatures.** Content that can only exist inside the target's runtime — a
  `root:x:0:0` passwd line for an MCP sandbox escape, a Jinja2 `__globals__` / `dict_keys` leak for
  SSTI — cannot be hallucinated, so it confirms a real read or a real code-execution surface.
- **Content checks.** A "leak" is graded a leak only when the recovered text is *actually sensitive*
  (a connection string, a key, a private-key header) — a cooperative-but-harmless answer stays
  `reachable`.
- **Persistence re-reads.** `takeover-capable` requires reading the change back after the fact
  (`vectordb inject --verify-persist`), not merely a 2xx on the write.

## The reporting discipline

- **An honest `reachable` / `unknown` / `502` beats a fabricated success.** A `family=unknown`
  fingerprint, an ingest that was accepted but not confirmed obeyed, an inference that ran but could
  not be distinguished — each is a *true* finding at its real strength, and reads as competence, not
  failure.
- **Grade the proof, not the potential.** "This could lead to RCE" is not `execution-confirmed`.
  What you demonstrated is the finding; what it *might* enable is the recommendation.
- **Report the negative.** A filter that held, a rule that fired on you, a model that refused — these
  are results. They tell the reader (and future-you) what the target actually does.
- **Never mask evidence.** Secrets stay raw in the finding; redaction destroys the context an
  operator needs to use them and to prove the finding is real.

!!! danger "The over-claim tax"
    One finding that collapses on review is more expensive than ten modest true ones, because it
    costs the *report's* credibility, not just its own. When unsure whether you proved the stronger
    claim, grade the weaker one — you can always escalate with better evidence, but you cannot
    un-ring a debunked "critical."

## Where it shows up

Every technique in this section returns to these axes — `reachable` in
[reconnaissance](reconnaissance.md), `unknown` in [model fingerprinting](model-fingerprinting.md),
the sensitive-content gate in [output-filter bypass](output-filter-bypass.md), the retrieved-vs-obeyed
line in [prompt injection](prompt-injection.md) and [RAG attacks](rag-attacks.md), and the measured
before/after in [detect & evade](detect-and-evade.md). Honest grading is not a separate step; it is
how each of them is reported.
