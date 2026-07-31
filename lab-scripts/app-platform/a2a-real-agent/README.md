# Real A2A agent (official a2a-sdk)

A genuine A2A agent built on the official **a2a-sdk** (Google's Agent-to-Agent
SDK), as opposed to the hand-written `a2a-agent-{basic,multiturn,authed}` mocks
on ports 8100-8102. It serves the real protocol — agent card at
`/.well-known/agent-card.json` and JSON-RPC 2.0 (`message/send`, `message/stream`,
`tasks/get`, `tasks/cancel`) at `/`, with v0.3 backward-compatibility on — and
does real, input-dependent work (urgency triage), so responses vary with input.

It is **additive**: it runs on **port 8103** as `a2a-agent-real.service` and does
not touch the scored mocks (8100-8102) or the benchmark.

## Why it exists

A mock that is shaped around what the *tool* sends will accept the tool's
requests and hide tool bugs. Proving aipostex against this real SDK agent caught
three real bugs the hand-written mock masked:

1. The client only fell back on JSON-RPC `-32601` (method not found), but the
   real SDK rejects the v1.0 `SendMessage` role enum with **`-32602`** (and
   `-32009` for version) — so the client stalled on the first attempt instead of
   falling back to `message/send`.
2. `task-send` reported a successful "unauthenticated task submission" even when
   the agent returned a JSON-RPC error.
3. `stream-probe` claimed "eavesdropped"/exploited with **zero** SSE events.

All three are fixed in aipostex (`shouldTryNextVersion` / honest reachable-vs-
success labels) with tests. See `docs/reference/mock-fidelity.md`.

## Deploy (on ailab-app, 172.16.50.40)

```bash
sudo bash deploy-real-a2a-agent.sh         # creates a venv, installs the SDK, starts :8103
```

Revert (mocks are unaffected):

```bash
sudo systemctl disable --now a2a-agent-real.service
```

## Prove from the attack box

```bash
aipostex a2a --target http://172.16.50.40:8103 enum            # reads the real card
aipostex a2a --target http://172.16.50.40:8103 skills
aipostex a2a --target http://172.16.50.40:8103 task-send   --message 'urgent: db is down' --force-exploit
aipostex a2a --target http://172.16.50.40:8103 stream-probe --message 'list tools'        --force-exploit
```

Expected against the real agent: `enum`/`skills` → reachable; `task-send` →
execution-confirmed (real task + triage artifact); `stream-probe` → exploited
with a non-zero SSE event count. Against an endpoint that rejects the request,
the same actions report `reachable` (not a false success).
