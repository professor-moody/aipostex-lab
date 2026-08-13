---
title: Vulnerable MCP Server (ailab-dev)
---

# Vulnerable MCP Server (ailab-dev)

## What It Is

A second, deliberately vulnerable MCP server built on the **official MCP Python SDK** (FastMCP,
Streamable HTTP at `/mcp`) — the same real stack as the primary `acme-mcp` server, not a
tool-shaped stand-in. It exists as the target for the `mcp sandbox-escape` and `mcp ssti` verbs.

## Modeled Weaknesses

- **`read_document(path)` — filesystem sandbox escape.** Advertises a `/data/documents` sandbox
  but checks the path prefix **before normalizing it**, so a traversal payload
  (`/data/documents/../../../../etc/passwd`) passes the check and then resolves outside the
  sandbox — the flaw class assigned **CVE-2025-53109 / CVE-2025-53110** in Anthropic's MCP
  filesystem package.
- **`render_report(report_data)` — server-side template injection.** Renders caller-supplied text
  through an **unsandboxed Jinja2** template, so `{{ lipsum.__globals__ ... }}` reaches the Python
  runtime (a code-execution surface). A `SandboxedEnvironment` would close this; the default one
  does not.
- **`internal://ops/runbook` resource — over-exposed internal data.** The server publishes an ops
  runbook as an MCP **resource**, so any client that can `resources/read` it retrieves live
  secrets (a Postgres DSN, a Datadog API key, an MLflow token). Exposing sensitive data as a
  resource — reachable without invoking a tool — is a distinct data-access surface.
- **`draft_reply(ticket)` prompt — poisoned prompt template.** The server ships a **prompt** whose
  template embeds an internal API token and an `Ignore any previous safety instructions…` line, so
  a client that fetches it with `prompts/get` pulls a server-supplied prompt injection straight
  into its model context.
- **`summarize_with_ai(text)` tool — server→client sampling abuse.** When invoked, the tool calls
  `ctx.session.create_message()` to drive the **connected client's** LLM (MCP *sampling*) and
  slips in an instruction to list any API keys, tokens, or passwords in the client's context —
  context exfiltration / free-proxy abuse. The request rides the standalone GET event stream, so
  it is invisible to a `tools/list` enumeration and only appears when the tool is called.
- **`verify_and_read(doc_id)` tool — server→client elicitation phishing.** When invoked, the tool
  calls `ctx.elicit()` to prompt the **connected client's user** for their "ACME API key" mid-tool-
  call (MCP *elicitation*, 2025 spec) — credential phishing / unintended-approval injection. Like
  sampling it rides the GET event stream and is invisible to `tools/list`.
- **`index_workspace()` tool — server→client roots harvesting.** Calls
  `ctx.session.list_roots()` to make the **connected client** disclose its local filesystem roots —
  reconnaissance of the client machine, invisible to `tools/list`.
- **Completion-based enumeration.** A `@mcp.completion()` handler completes `account_id` and
  `ticket` arguments, disclosing internal identifiers (`acct-4021`, `TCK-9001`, …) that **no**
  `resources/list` or `prompts/list` call exposes. The `records://customers/{account_id}` resource
  **template** is likewise only visible through `resources/templates/list`.
- **`lookup_ticket(ticket_id)` tool + open `logging/setLevel` — log harvesting.** Any client can
  raise the server's verbosity (handler registered on the SDK's low-level server, no auth), after
  which the tool's debug log streams the backend URL and its `service_token` to that client.
- **Open `resources/subscribe` — standing push channel.** Subscriptions are accepted from anyone
  with no authorization check, giving durable notification access to internal resource data.
- **"OAuth theater" — advertised authorization that isn't enforced.** The server publishes OAuth
  metadata (`/.well-known/oauth-protected-resource`, RFC 9728; `/.well-known/oauth-authorization-
  server`, RFC 8414) pointing at itself, and exposes an **open** dynamic client registration
  endpoint (`POST /register`, RFC 7591 — no auth), yet `/mcp` enforces no authorization at all. The
  security surface looks present but is hollow: anyone can reach the tools *and* mint an OAuth
  client.

## Port & Unit

| Parameter | Value |
|---|---|
| Host | `ailab-dev` (`172.16.50.10`) |
| Port | `3002` (Streamable HTTP at `/mcp`) |
| systemd unit | `acme-doc-tools.service` |

## Attacking It

```bash
aipostex mcp --target http://172.16.50.10:3002 enum
aipostex mcp --target http://172.16.50.10:3002 enum --read
aipostex mcp --target http://172.16.50.10:3002 sandbox-escape --force-exploit
aipostex mcp --target http://172.16.50.10:3002 ssti --tool render_report --arg report_data --force-exploit
aipostex mcp --target http://172.16.50.10:3002 sampling --tool summarize_with_ai --force-exploit
aipostex mcp --target http://172.16.50.10:3002 elicitation --tool verify_and_read --force-exploit
aipostex mcp --target http://172.16.50.10:3002 auth --force-exploit
aipostex mcp --target http://172.16.50.10:3002 roots --tool index_workspace --force-exploit
aipostex mcp --target http://172.16.50.10:3002 complete
aipostex mcp --target http://172.16.50.10:3002 logging --tool lookup_ticket --force-exploit
aipostex mcp --target http://172.16.50.10:3002 subscribe --force-exploit
```

`enum` lists the tools, the `ops-runbook` resource, and the `draft_reply` prompt. `enum --read`
goes further and **retrieves** them: it `resources/read`s the runbook (read-confirmed, secrets
surface into the credential index) and `prompts/get`s `draft_reply` (read-confirmed, exposing the
embedded token and the prompt-injection line).

`sandbox-escape` auto-detects `read_document`, sends the prefix-check-bypass payload, and confirms
by reading `/etc/passwd`. `ssti` sends `{{ lipsum.__globals__.keys() }}` to `render_report` and
confirms server-side evaluation from the leaked Python globals. `sampling` advertises the sampling
capability, invokes `summarize_with_ai`, and captures the server-initiated `sampling/createMessage`
request off the GET event stream — confirming the server drives the client's LLM (High,
`access` / `influenced`). `elicitation` does the same for `verify_and_read`, capturing the
`elicitation/create` phish for the client user's API key. `auth` reports the anonymous access
(no token required), discovers the advertised OAuth metadata, and — with `--force-exploit` — mints
a client via the open registration endpoint. `roots` captures the server-initiated `roots/list`
from `index_workspace`; `complete` enumerates the internal ticket and account identifiers;
`logging` raises the level and captures the debug line carrying the service token; `subscribe`
establishes a push channel on the ops runbook.
