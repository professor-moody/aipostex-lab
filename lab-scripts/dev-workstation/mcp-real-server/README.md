# MCP server (official MCP SDK)

The lab's MCP target on **ailab-dev:3000** — a genuine vulnerable MCP server built
on the official **Model Context Protocol Python SDK** (FastMCP, Streamable HTTP
transport). It serves the real transport at `/mcp` (initialize handshake,
`Mcp-Session-Id`, SSE-framed responses) and exposes dangerous tools whose argument
schemas are **enforced by pydantic**.

This **replaces** the former hand-written `acme-mcp` mock: the lab runs real
product, not a tool-shaped stand-in (see `docs/reference/mock-fidelity.md`).

## Why it exists

A hand-written mock accepts loosely-shaped requests, which masks tool bugs.
Proving aipostex against this real SDK server caught real tool gaps (all fixed in
aipostex with tests):

1. **`/mcp` endpoint discovery** — the client only fell back to `/message`
   (legacy SSE) and 404'd on a real server's base URL; it now auto-discovers
   `/mcp` (the modern Streamable HTTP default).
2. **Schema-aware tool invocation** — the official SDK enforces typed tool
   schemas, so the old fixed-shape payloads were rejected and `cmd-inject` /
   `path-traversal` / `env-extract` never landed. The client now reads each tool's
   `inputSchema` and builds valid arguments, so it genuinely lands RCE / file-read
   / env leakage.
3. **Stateful scan templates** — the `mcp-cmdi-001` / `mcp-path-001` /
   `mcp-ssrf-001` vuln-scan templates couldn't complete the MCP handshake over
   raw HTTP; aipostex now has an MCP-transport executor so they fire in
   `discover network --mode full`.

## Tools exposed

| Tool | Vuln | Notes |
|------|------|-------|
| `read_file(path)` | path traversal / arbitrary read | no path restriction |
| `execute_command(command)` | RCE | `shell=True`; build-admin token in description |
| `fetch_url(url)` | SSRF | no private-IP blocking |
| `run_query(query)` | data exposure | returns seeded customer PII; DSN in description |
| `get_environment()` | credential leak | returns secret-looking env vars |

Plus resources (`file:///etc/hostname`, `db://acme_prod/customers`,
`config://mcp-server/settings`) and prompts (`analyze-customer`,
`generate-report`, `search-docs`).

## Deploy (on ailab-dev, 172.16.50.10)

```bash
sudo bash deploy-real-mcp-server.sh    # venv, installs the SDK, starts acme-mcp.service on :3000
```

(The full provision — `provision.sh` / `deploy-all.sh` — installs the same unit.)

## Prove from the attack box (the tool auto-discovers `/mcp` from the bare host)

```bash
aipostex mcp --target http://172.16.50.10:3000 enum
aipostex mcp --target http://172.16.50.10:3000 poison --mode cmd-inject    --command id         --tool execute_command --force-exploit
aipostex mcp --target http://172.16.50.10:3000 poison --mode path-traversal --path /etc/passwd  --tool read_file       --force-exploit
aipostex mcp --target http://172.16.50.10:3000 env-extract
aipostex discover network --target 172.16.50.10 --ports 3000 --mode full    # mcp-cmdi-001 fires
```

Expected: `enum` flags `execute_command` (exec, CRIT) and `read_file` (file, HIGH);
`cmd-inject` returns real command output; `path-traversal` reads the file;
`env-extract` returns the seeded fake secrets. Against an endpoint that rejects a
call, the actions report `reachable` (not a false success).
