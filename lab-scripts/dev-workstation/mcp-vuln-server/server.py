#!/usr/bin/env python3
"""Deliberately vulnerable MCP server — the targets for `mcp sandbox-escape` and
`mcp ssti`.

Built on the official Model Context Protocol Python SDK (FastMCP, Streamable HTTP
transport at /mcp), the same real stack as the primary acme-mcp server — this is a
real MCP product surface, not a tool-shaped stand-in. It exposes two tools with
real, classic flaws:

  - read_document(path): advertises a /data/documents sandbox but checks the path
    prefix BEFORE normalizing it, so a traversal payload
    (/data/documents/../../../../etc/passwd) passes the check and then resolves
    outside the sandbox. This is the flaw class assigned CVE-2025-53109 /
    CVE-2025-53110 in Anthropic's MCP filesystem package.

  - render_report(report_data): renders caller-supplied text through an
    UNSANDBOXED Jinja2 template, so template expressions are evaluated
    server-side (SSTI) — {{ lipsum.__globals__ ... }} reaches the Python runtime.

Reach it from the attack box:
    aipostex mcp --target http://172.16.50.10:3002 enum
    aipostex mcp --target http://172.16.50.10:3002 sandbox-escape --force-exploit
    aipostex mcp --target http://172.16.50.10:3002 ssti --tool render_report --arg report_data --force-exploit
"""

import os

import jinja2
from mcp.server.fastmcp import FastMCP

HOST = os.environ.get("MCP_HOST", "0.0.0.0")
PORT = int(os.environ.get("MCP_PORT", "3002"))
ALLOWED_PREFIX = os.environ.get("MCP_DOC_DIR", "/data/documents")

mcp = FastMCP("acme-doc-tools", host=HOST, port=PORT)


@mcp.tool(
    description="Read a document from the document library. Access is restricted to the "
    "/data/documents directory."
)
def read_document(path: str) -> str:
    # VULNERABLE: the prefix check runs BEFORE normalization. A path that starts
    # with the allowed prefix but contains ../ passes the check, then normpath
    # resolves it outside the sandbox (CVE-2025-53109 / CVE-2025-53110 class).
    if not path.startswith(ALLOWED_PREFIX):
        return f"Error: access denied — reads are restricted to {ALLOWED_PREFIX}"
    resolved = os.path.normpath(path)
    try:
        with open(resolved, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except FileNotFoundError:
        return f"Error: {resolved}: not found"
    except Exception as exc:  # noqa: BLE001 - surface the failure class to the caller
        return f"Error reading {resolved}: {exc.__class__.__name__}"


@mcp.tool(
    description="Render a formatted report from report_data using the report template engine."
)
def render_report(report_data: str) -> str:
    # VULNERABLE: caller-supplied data is rendered by an UNSANDBOXED Jinja2 template,
    # so template expressions execute server-side (SSTI). A SandboxedEnvironment
    # would close this; the default Environment does not.
    try:
        return "Report:\n" + jinja2.Template(report_data).render()
    except Exception as exc:  # noqa: BLE001
        return f"Render error: {exc.__class__.__name__}: {exc}"


@mcp.tool(description="List the documents available in the /data/documents library.")
def list_documents() -> str:
    try:
        return "\n".join(sorted(os.listdir(ALLOWED_PREFIX)))
    except Exception as exc:  # noqa: BLE001
        return f"Error: {exc.__class__.__name__}"


def _seed():
    # A legitimate in-sandbox document so the tool works for benign use.
    try:
        os.makedirs(ALLOWED_PREFIX, exist_ok=True)
        readme = os.path.join(ALLOWED_PREFIX, "README.txt")
        if not os.path.exists(readme):
            with open(readme, "w", encoding="utf-8") as fh:
                fh.write("Acme document library. Internal use only.\n")
    except Exception:  # noqa: BLE001 - seeding is best-effort
        pass


if __name__ == "__main__":
    _seed()
    mcp.run(transport="streamable-http")
