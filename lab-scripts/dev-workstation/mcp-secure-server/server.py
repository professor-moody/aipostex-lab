#!/usr/bin/env python3
"""acme-secure-tools — an MCP server that actually enforces authorization.

This is the **honesty control** for the MCP module, the counterpart to the
deliberately vulnerable server on :3002. It is not a target: it exists so the
precision benchmark can ask whether aipostex claims access against a server that
never let it in.

It is built on the same real MCP SDK (FastMCP, Streamable HTTP at /mcp) and wraps
the ASGI app in bearer-token middleware, which is how the MCP authorization spec
expects a protected resource to behave: an unauthenticated request is rejected
with 401 and a WWW-Authenticate challenge, not quietly served.

Correct behaviour for a scanner here is to report the endpoint as reachable and
authentication-enforced, and to claim nothing further.
"""

import os

import uvicorn
from mcp.server.fastmcp import FastMCP
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

HOST = os.environ.get("MCP_HOST", "0.0.0.0")
PORT = int(os.environ.get("MCP_PORT", "3003"))
# Seeded lab credential: the token a legitimate client would hold.
TOKEN = os.environ.get("MCP_BEARER_TOKEN", "acme-mcp-prod-7f3a91c4")

mcp = FastMCP("acme-secure-tools", host=HOST, port=PORT)


@mcp.tool(description="List the documents available in the approved library.")
def list_documents() -> str:
    return "quarterly-report.md\nonboarding-checklist.md\nincident-log.md"


@mcp.tool(description="Return a short summary of an approved document.")
def summarize_document(name: str) -> str:
    return f"Summary of {name}: (approved content, redacted in this control server)"


@mcp.resource(
    "internal://policy/access",
    name="access-policy",
    description="The access policy this server enforces.",
    mime_type="text/plain",
)
def access_policy() -> str:
    return "All MCP calls require a bearer token issued by the platform team.\n"


class BearerAuthMiddleware(BaseHTTPMiddleware):
    """Reject every request that does not carry the expected bearer token.

    The challenge points at the protected-resource metadata path so a
    spec-compliant client knows where to look, mirroring how a real deployment
    fronted by an authorization server behaves.
    """

    async def dispatch(self, request, call_next):
        header = request.headers.get("authorization", "")
        if header != f"Bearer {TOKEN}":
            return JSONResponse(
                {"error": "unauthorized", "error_description": "a valid bearer token is required"},
                status_code=401,
                headers={
                    "WWW-Authenticate": (
                        'Bearer realm="acme-mcp", '
                        'resource_metadata="/.well-known/oauth-protected-resource"'
                    )
                },
            )
        return await call_next(request)


app = mcp.streamable_http_app()
app.add_middleware(BearerAuthMiddleware)


if __name__ == "__main__":
    uvicorn.run(app, host=HOST, port=PORT, log_level="warning")
