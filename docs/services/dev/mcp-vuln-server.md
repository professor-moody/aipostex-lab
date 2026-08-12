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

## Port & Unit

| Parameter | Value |
|---|---|
| Host | `ailab-dev` (`172.16.50.10`) |
| Port | `3002` (Streamable HTTP at `/mcp`) |
| systemd unit | `acme-doc-tools.service` |

## Attacking It

```bash
aipostex mcp --target http://172.16.50.10:3002 enum
aipostex mcp --target http://172.16.50.10:3002 sandbox-escape --force-exploit
aipostex mcp --target http://172.16.50.10:3002 ssti --tool render_report --arg report_data --force-exploit
```

`sandbox-escape` auto-detects `read_document`, sends the prefix-check-bypass payload, and confirms
by reading `/etc/passwd`. `ssti` sends `{{ lipsum.__globals__.keys() }}` to `render_report` and
confirms server-side evaluation from the leaked Python globals.
