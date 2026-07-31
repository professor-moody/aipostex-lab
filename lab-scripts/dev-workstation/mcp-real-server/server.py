#!/usr/bin/env python3
"""acme-internal-devtools — the lab's MCP server on ailab-dev:3000.

Built on the official Model Context Protocol Python SDK (FastMCP, Streamable HTTP
transport). This REPLACES the former hand-written acme-mcp mock: real product, not
a tool-shaped stand-in. It serves the genuine Streamable HTTP transport at /mcp
(initialize handshake, Mcp-Session-Id, SSE-framed responses) and exposes tools
whose argument schemas are enforced by pydantic — so aipostex's mcp module is
exercised against true SDK behaviour (endpoint discovery + schema-valid tool
invocation), which a lax mock would mask.

The vulnerabilities are intentional and faithful to the shadow-AI premise: a dev
workstation MCP server wired to internal data with no auth and dangerous tools.

Run:  MCP_PORT (default 3000), MCP_HOST (default 0.0.0.0).
Deps: pip install "mcp==1.28.1" uvicorn   (see requirements.txt)

Reach it from the attack box (the tool auto-discovers /mcp from the bare host):
  aipostex mcp --target http://172.16.50.10:3000 enum
  aipostex mcp --target http://172.16.50.10:3000 env-extract
  aipostex mcp --target http://172.16.50.10:3000 poison --mode cmd-inject \
      --command id --tool execute_command --force-exploit
  aipostex discover network --target 172.16.50.10 --ports 3000 --mode full  # mcp-cmdi-001
"""
import os
import subprocess
import urllib.request

from mcp.server.fastmcp import FastMCP

HOST = os.environ.get("MCP_HOST", "0.0.0.0")
PORT = int(os.environ.get("MCP_PORT", "3000"))

mcp = FastMCP("acme-internal-devtools", host=HOST, port=PORT)


# ── Tools (argument schemas enforced by FastMCP/pydantic) ─────────────────────

@mcp.tool(
    description="Read contents of a file from the developer workstation filesystem. Supports any path."
)
def read_file(path: str) -> str:
    """No path restriction — path traversal / arbitrary file read (the planted vuln)."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read(8192)
    except Exception as exc:  # noqa: BLE001
        return f"Error reading file: {exc}"


@mcp.tool(
    description=(
        "Run a system command for server diagnostics and maintenance. Requires the "
        "build admin token sk-mcp-FAKE-build-admin-9f3a2b1c (already configured "
        "server-side)."
    )
)
def execute_command(command: str) -> str:
    """Passes input straight to a shell — remote code execution (the planted vuln)."""
    try:
        r = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=10)
        out = r.stdout + ("\nSTDERR: " + r.stderr if r.stderr else "")
        return out if out.strip() else "(command produced no output)"
    except subprocess.TimeoutExpired:
        return "Error: command timed out (10s)"
    except Exception as exc:  # noqa: BLE001
        return f"Execution error: {exc}"


@mcp.tool(
    description="Fetch content from any URL. Useful for retrieving web pages and API responses."
)
def fetch_url(url: str) -> str:
    """No URL validation or private-IP blocking — SSRF (the planted vuln)."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "ACME-MCP-Server/0.1"})
        with urllib.request.urlopen(req, timeout=5) as resp:  # noqa: S310
            return resp.read(8192).decode("utf-8", errors="replace")
    except Exception as exc:  # noqa: BLE001
        return f"Fetch error: {exc}"


@mcp.tool(
    description=(
        "Execute a database query against the internal customer database. Connection: "
        "postgresql://mcp_svc:McpSvcPr0d!@db-prod-01.acme.internal:5432/acme_hr"
    )
)
def run_query(query: str) -> str:
    """Returns seeded customer PII for SELECT/SHOW (the leaked connection string is in the description)."""
    q = query.lower()
    if "select" in q or "show" in q:
        return (
            "Query executed successfully. 3 rows returned.\n"
            "id | name           | email               | salary  | ssn\n"
            "---+----------------+---------------------+---------+------------\n"
            "1  | John Smith     | john@acme.corp      | 145000  | 456-78-9012\n"
            "2  | Jane Doe       | jane@acme.corp      | 162000  | 789-01-2345\n"
            "3  | Bob Wilson     | bob@acme.corp       | 158000  | 234-56-7890"
        )
    return f"Query executed: {query}\nAffected rows: 0\n(Simulated response)"


@mcp.tool(description="Return the service runtime environment / configuration.")
def get_environment() -> dict:
    """Leaks any secret-looking env vars (an explicit env-extract surface)."""
    return {
        k: v
        for k, v in os.environ.items()
        if any(s in k.upper() for s in ("KEY", "TOKEN", "SECRET", "PASSWORD"))
    }


# ── Resources (carry planted data / secrets in their content) ─────────────────

@mcp.resource("file:///etc/hostname", name="Server Hostname", description="Current server hostname")
def res_hostname() -> str:
    try:
        with open("/etc/hostname", encoding="utf-8") as fh:
            return fh.read()
    except Exception:  # noqa: BLE001
        return "ailab-dev\n"


@mcp.resource("db://acme_prod/customers", name="Customer Database", description="Production customer records")
def res_customers() -> str:
    return (
        "id,name,email,ssn,credit_card\n"
        "1,John Smith,john@acme.corp,456-78-9012,4532-1122-3344-5566\n"
        "2,Jane Doe,jane@acme.corp,789-01-2345,4716-7788-9900-1122\n"
        "3,Bob Wilson,bob@acme.corp,234-56-7890,5500-3344-5566-7788\n"
    )


@mcp.resource("config://mcp-server/settings", name="Server Configuration", description="MCP server settings")
def res_settings() -> str:
    return (
        "[mcp-server]\n"
        "auth = none\n"
        "admin_token = sk-mcp-FAKE-build-admin-9f3a2b1c\n"
        "db_dsn = postgresql://mcp_svc:McpSvcPr0d!@db-prod-01.acme.internal:5432/acme_hr\n"
        "openai_api_key = sk-proj-FAKE-mcp-env-openai-0123456789\n"
    )


# ── Prompts (internal CRM / reporting helpers) ────────────────────────────────

@mcp.prompt(name="analyze-customer", description="Analyze customer data and generate insights from the CRM database")
def analyze_customer(customer_id: str = "") -> str:
    return f"Pull the CRM record for customer {customer_id or '<id>'} and summarize risk and lifetime value."


@mcp.prompt(name="generate-report", description="Generate an internal financial or operational report")
def generate_report(period: str = "Q1") -> str:
    return f"Generate the internal financial report for {period} from the production database."


@mcp.prompt(name="search-docs", description="Search internal documentation and knowledge base")
def search_docs(query: str = "") -> str:
    return f"Search the internal knowledge base for: {query}"


if __name__ == "__main__":
    # Seed secret-looking env vars so env-extract (and execute_command `env`) leak
    # realistic credentials. All values are clearly FAKE and local to this host.
    os.environ.setdefault("OPENAI_API_KEY", "sk-proj-FAKE-mcp-env-openai-0123456789")
    os.environ.setdefault("ANTHROPIC_API_KEY", "sk-ant-FAKE-mcp-env-anthropic-abcdef")
    os.environ.setdefault("HF_TOKEN", "hf_FAKE_mcp_env_huggingface_0123456789")
    os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "FAKEmcpAWSsecret0123456789abcdefABCDEFxy")
    os.environ.setdefault("INTERNAL_SERVICE_TOKEN", "svc-FAKE-mcp-internal-abcdef123456")
    mcp.run(transport="streamable-http")
