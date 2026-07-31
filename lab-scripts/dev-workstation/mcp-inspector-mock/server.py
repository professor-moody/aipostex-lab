#!/usr/bin/env python3
"""
MCP Inspector mock — lightweight HTTP server that responds to the probe
paths aipostex uses to fingerprint MCP Inspector / MCPJam Inspector.

Probed paths:
  GET /              — HTML containing "mcp inspector"
  GET /api/servers   — JSON with transportType, serverUrl fields
  GET /api/tools     — JSON with toolName, serverName fields
  GET /api/version   — JSON with inspector version info

Runs on port 6274 (the conventional MCP Inspector port).
"""

import json
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = 6274
MCP_SERVER_URL = "http://172.16.50.10:3000"

SERVERS_RESPONSE = json.dumps([
    {
        "name": "acme-internal-mcp",
        "serverUrl": f"{MCP_SERVER_URL}/sse",
        "transportType": "sse",
        "status": "connected",
        "tools": ["execute_command", "fetch_url", "read_file", "run_query"],
    }
])

TOOLS_RESPONSE = json.dumps({
    "tools": [
        {"toolName": "execute_command", "serverName": "acme-internal-mcp", "description": "Execute a shell command"},
        {"toolName": "fetch_url", "serverName": "acme-internal-mcp", "description": "Fetch a URL"},
        {"toolName": "read_file", "serverName": "acme-internal-mcp", "description": "Read a file from disk"},
        {"toolName": "run_query", "serverName": "acme-internal-mcp", "description": "Run a database query"},
    ]
})

VERSION_RESPONSE = json.dumps({
    "name": "mcp inspector",
    "version": "0.6.0",
    "serverCount": 1,
})

INDEX_HTML = """<!DOCTYPE html>
<html><head><title>MCP Inspector</title></head>
<body><h1>MCP Inspector</h1><p>Connected to 1 server(s).</p></body></html>
"""


class InspectorHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.rstrip("/") or "/"
        if path == "/":
            self._respond(200, "text/html", INDEX_HTML)
        elif path == "/api/servers":
            self._respond(200, "application/json", SERVERS_RESPONSE)
        elif path == "/api/tools":
            self._respond(200, "application/json", TOOLS_RESPONSE)
        elif path == "/api/version":
            self._respond(200, "application/json", VERSION_RESPONSE)
        else:
            self._respond(404, "text/plain", "Not Found")

    def _respond(self, code, content_type, body):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body.encode())

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), InspectorHandler)
    print(f"MCP Inspector mock listening on 0.0.0.0:{PORT}")
    server.serve_forever()
