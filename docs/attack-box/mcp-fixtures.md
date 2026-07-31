# MCP Fixtures

The attack box now ships with both **file-based MCP config fixtures** and a **stdio MCP server fixture**.

## Files Installed

Under `~/lab/mcp-configs/`:

- `claude_desktop_config.json`
- `cursor_mcp.json`
- `vscode_settings.json`
- `remote_mcp_chain.json`

Alongside them:

- `~/lab/stdio-mcp-server.py`

## What They Cover

- embedded secrets in local MCP config files
- remote MCP endpoint analysis against the lab MCP server on `ailab-dev`
- stdio transport validation without needing a network listener

## Example Commands

```bash
aipostex mcp analyze --config ~/lab/mcp-configs/claude_desktop_config.json
aipostex mcp analyze --config ~/lab/mcp-configs/remote_mcp_chain.json
aipostex mcp --transport stdio --stdio-command python3 --stdio-args ~/lab/stdio-mcp-server.py enum
```

## Expected Highlights

- `claude_desktop_config.json` exposes a PostgreSQL connection string, GitHub PAT, Slack bot token, and Jira API token
- `cursor_mcp.json` exposes a Brave API key
- `vscode_settings.json` exposes another PostgreSQL credential
- `remote_mcp_chain.json` points to the live MCP surface on `ailab-dev`
- `stdio-mcp-server.py` exposes deterministic tools for `enum` validation on stdio transport

The stdio server intentionally stays minimal. It is a verification fixture, not a production-like MCP implementation.
