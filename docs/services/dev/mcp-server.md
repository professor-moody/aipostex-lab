---
title: Vulnerable MCP Server
---

# Vulnerable MCP Server

## What It Is

An intentionally vulnerable MCP (Model Context Protocol) server built on the **official MCP
Python SDK** (FastMCP, Streamable HTTP transport). It serves the real transport at `/mcp` — the
`initialize` handshake, an `Mcp-Session-Id` per session, and SSE-framed responses — and exposes
dangerous tools whose argument schemas are enforced by pydantic. The vulnerabilities (command
injection, SSRF, path traversal, unauthenticated data access) are intentional and match
real-world CVE patterns.

This is **real product, not a hand-written mock** — see
[Mock & Fixture Fidelity](../../reference/mock-fidelity.md).

---

## Installation

A Python virtualenv with the pinned MCP SDK (no Docker):

```
Source: /home/devuser/projects/internal-tools/mcp-server/server.py
Deps:   /home/devuser/projects/internal-tools/mcp-server/.venv  (mcp==1.28.1, uvicorn)
```

---

## Systemd Unit

**Unit:** `acme-mcp.service`

```ini title="/etc/systemd/system/acme-mcp.service"
[Service]
User=devuser
WorkingDirectory=/home/devuser/projects/internal-tools/mcp-server
Environment="MCP_HOST=0.0.0.0"
Environment="MCP_PORT=3000"
ExecStart=/home/devuser/projects/internal-tools/mcp-server/.venv/bin/python server.py
Restart=always
```

---

## Port & Config

| Parameter | Value |
|---|---|
| Host | `172.16.50.10` |
| Port | `3000` |
| Bind address | `0.0.0.0` |
| Authentication | None |
| Protocol | MCP Streamable HTTP (JSON-RPC 2.0, SSE-framed) |

---

## Endpoints

| Method | Path | Description |
|---|---|---|
| `POST` | `/mcp` | Streamable HTTP transport — `initialize` → `Mcp-Session-Id` → `tools/call` |

The server is session-strict: a bare `tools/list` without an established session is rejected.
Point aipostex at the bare host (`http://172.16.50.10:3000`) and it auto-discovers `/mcp`.

---

## Vulnerability Surface

### Command Injection — `execute_command`

Passes user input directly to `subprocess.run()` with `shell=True`. No sanitization or allowlisting.

**CVE pattern:** CVE-2025-53355

### SSRF — `fetch_url`

Fetches arbitrary URLs without validating against private IP ranges. An attacker can probe internal services, cloud metadata endpoints, or localhost-bound services.

**CVE pattern:** CVE-2025-65513

### Path Traversal — `read_file`

Reads files from disk without sanitizing the path. `../` sequences allow reading arbitrary files accessible to the `devuser` account.

**CVE pattern:** MCP-AUTH-001

### Customer DB Query — `run_query`

Accepts SQL-like input and returns seeded customer PII (names, emails, SSNs). The production
connection string is leaked in the tool description. Demonstrates the risk of unauthenticated
database tools in MCP servers.

### Environment Leak — `get_environment`

Returns secret-looking environment variables (API keys, service tokens) — an explicit
credential-leak surface for `aipostex mcp ... env-extract`.

### Unauthenticated Access

All tools are reachable without any authentication — no API keys, no tokens, no session cookies
beyond the protocol's own `Mcp-Session-Id`.

**CVE pattern:** MCP-AUTH-001

---

## What aipostex Finds

- **Unauthenticated MCP tools** — `tools/list` returns all tools (and their descriptions, which
  leak secrets) without authentication.
- **Command injection** — `execute_command` allows arbitrary OS command execution (`shell=True`).
- **SSRF** — `fetch_url` probes internal services and cloud metadata endpoints.
- **Path traversal** — `read_file` reads files outside the intended working directory.
- **Credential leakage** — `env-extract` reflects seeded secrets via the exec tool's `env` output.
- **`mcp-cmdi-001`** — the network-scan exploit template lands RCE end-to-end via the MCP-transport executor.

---

## Verification

Enumerate tools (aipostex performs the `initialize` → session handshake for you):

```bash
aipostex mcp --target http://172.16.50.10:3000 enum
```

??? example "Expected response"
    A finding set listing `execute_command` (exec, CRIT), `fetch_url` (fetch), `read_file`
    (file, HIGH), `run_query`, and `get_environment`, each with its input schema and a proof
    stage.
