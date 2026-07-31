---
title: MCP Inspector Mock
---

# MCP Inspector Mock

## What It Is

A lightweight Python HTTP server that mimics the probe surface of MCP Inspector — the official debugging tool for MCP servers. It responds to the specific paths that aipostex uses to fingerprint MCP Inspector instances, making it appear as though a developer left Inspector running and connected to the vulnerable MCP server on port 3000.

---

## Installation

No pip dependencies. A single Python script using only `http.server` from the standard library.

**Source:** `/home/devuser/projects/internal-tools/mcp-inspector-mock/server.py`

---

## Systemd Unit

**Unit:** `mcp-inspector.service`

```ini title="/etc/systemd/system/mcp-inspector.service"
[Service]
User=devuser
WorkingDirectory=/home/devuser/projects/internal-tools/mcp-inspector-mock
ExecStart=/usr/bin/python3 server.py
Restart=always
```

---

## Port & Config

| Parameter | Value |
|---|---|
| Host | `172.16.50.10` |
| Port | `6274` |
| Bind address | `0.0.0.0` |
| Authentication | None |

---

## Probe Paths

The mock responds to four paths that aipostex uses to fingerprint MCP Inspector:

| Method | Path | Response |
|---|---|---|
| `GET` | `/` | HTML containing `"mcp inspector"` in the body |
| `GET` | `/api/servers` | JSON array with `transportType` and `serverUrl` pointing to `:3000` |
| `GET` | `/api/tools` | JSON array with `toolName` and `serverName` entries |
| `GET` | `/api/version` | JSON with the inspector version string |

The `/api/servers` response references the existing vulnerable MCP server at port 3000, linking the two services in aipostex's discovery output.

---

## What aipostex Finds

- **MCP Inspector fingerprint** — The probe paths match the expected MCP Inspector signature, triggering fingerprint-based detection.
- **Vulnerability template `mcp-auth-003`** — Exposed inspector interface with no authentication.
- **Vulnerability template `mcp-auth-005`** — Inspector connected to an unauthenticated MCP server, amplifying the risk surface.

---

## Verification

Confirm the mock is running and responding to version probes:

```bash
curl http://localhost:6274/api/version
```

??? example "Expected response"
    ```json
    {"version": "0.5.0", "name": "mcp-inspector"}
    ```

Check the connected servers list:

```bash
curl http://localhost:6274/api/servers
```

??? example "Expected response"
    JSON array listing the MCP server at `http://localhost:3000` with `transportType: "sse"`.
