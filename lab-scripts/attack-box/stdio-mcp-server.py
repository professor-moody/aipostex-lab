#!/usr/bin/env python3
"""
Minimal stdio MCP fixture for attack-box verification.

It accepts newline-delimited JSON-RPC requests on stdin and responds with
deterministic JSON on stdout so `aipostex mcp --transport stdio ... enum`
has a local surface to exercise.
"""

import json
import sys


TOOLS = [
    {
        "name": "read_lab_note",
        "description": "Return a deterministic operator note",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "list_services",
        "description": "Return a fixed list of lab-facing services",
        "inputSchema": {"type": "object", "properties": {}},
    },
]


def respond(message_id, result):
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": message_id, "result": result}) + "\n")
    sys.stdout.flush()


def handle_request(payload):
    method = payload.get("method", "")
    message_id = payload.get("id")

    if method == "initialize":
        respond(
            message_id,
            {
                "protocolVersion": "2024-11-05",
                "serverInfo": {"name": "lab-stdio-mcp", "version": "1.0.0"},
                "capabilities": {"tools": {"listChanged": False}},
            },
        )
        return

    if method == "tools/list":
        respond(message_id, {"tools": TOOLS})
        return

    if method == "tools/call":
        name = (payload.get("params") or {}).get("name", "")
        if name == "read_lab_note":
            respond(message_id, {"content": [{"type": "text", "text": "incident-response runbook"}]})
        elif name == "list_services":
            respond(
                message_id,
                {
                    "content": [
                        {
                            "type": "text",
                            "text": "langserve, streamlit, hf-tgi, hf-tei, vllm",
                        }
                    ]
                },
            )
        else:
            sys.stdout.write(
                json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "id": message_id,
                        "error": {"code": -32601, "message": f"unknown tool: {name}"},
                    }
                )
                + "\n"
            )
            sys.stdout.flush()
        return

    if method == "ping":
        respond(message_id, {})
        return

    sys.stdout.write(
        json.dumps(
            {
                "jsonrpc": "2.0",
                "id": message_id,
                "error": {"code": -32601, "message": f"unknown method: {method}"},
            }
        )
        + "\n"
    )
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        handle_request(payload)


if __name__ == "__main__":
    main()

