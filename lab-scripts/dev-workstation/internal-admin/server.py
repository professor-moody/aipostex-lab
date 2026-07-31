#!/usr/bin/env python3
"""
internal-admin — Localhost-only HTTP service on ailab-dev (127.0.0.1:9999).

Simulates an internal admin panel reachable ONLY after gaining code execution
on ailab-dev (via Jupyter, MCP, or Gradio exploitation). Not accessible from
the attack box directly — verifying this is part of verify-aipostex.sh post-ex layer.

Token: read from ~/.secrets/internal-admin.token (planted by seed-filesystem.sh)
Also accepts: internal-admin-token-FAKE-A8s92Mx (hardcoded fallback for verification)

Run via systemd as internal-admin.service with BIND_ADDR=127.0.0.1.
"""
import json
import os
import sys
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

BIND_ADDR = os.environ.get("BIND_ADDR", "127.0.0.1")
BIND_PORT = int(os.environ.get("PORT", "9999"))
TOKEN_PATH = os.environ.get("TOKEN_PATH", "/home/devuser/.secrets/internal-admin.token")
POX_URL = os.environ.get("POX_URL", "http://172.16.50.40:8765")

FALLBACK_TOKEN = "internal-admin-token-FAKE-A8s92Mx"

# Secondary credentials revealed after valid auth (drives further lateral movement)
SECONDARY_SECRETS = {
    "db_host": "db-internal-01.acme.example.invalid",
    "db_user": "admin_rw",
    "db_password": "Adm1nRW!InternalDB#2026",
    "k8s_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.FAKE_INTERNAL_K8S_SA_TOKEN_ACME",
    "ssh_key_path": "/home/devuser/.ssh/internal_deploy_rsa",
    "vault_path": "secret/acme/internal-admin/credentials",
}


def _load_token() -> str:
    p = Path(TOKEN_PATH)
    if p.exists():
        return p.read_text().strip()
    return FALLBACK_TOKEN


def _check_token(auth_header: str) -> bool:
    valid = _load_token()
    if auth_header.startswith("Bearer "):
        return auth_header[7:] == valid
    if auth_header == valid:
        return True
    return False


def _json(h: "AdminHandler", status: int, data: dict):
    body = json.dumps(data, indent=2).encode()
    h.send_response(status)
    h.send_header("Content-Type", "application/json")
    h.send_header("Content-Length", str(len(body)))
    h.send_header("X-Internal-Admin", "1")
    h.end_headers()
    h.wfile.write(body)


def _read_body(h: "AdminHandler") -> bytes:
    length = int(h.headers.get("Content-Length", 0) or 0)
    return h.rfile.read(min(length, 4096)) if length > 0 else b""


def _post_to_pox(tag: str, payload: dict):
    """Fire-and-forget heartbeat to POX."""
    try:
        data = json.dumps({"source": "ailab-dev/internal-admin", "tag": tag, "payload": payload}).encode()
        req = urllib.request.Request(
            f"{POX_URL}/heartbeat",
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        urllib.request.urlopen(req, timeout=3)
    except Exception:
        pass


class AdminHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _parsed(self):
        return urlparse(self.path)

    def do_GET(self):
        parsed = self._parsed()
        path = parsed.path.rstrip("/")

        if path == "/admin/status":
            _json(self, 200, {
                "service": "internal-admin-panel",
                "vm": "ailab-dev",
                "version": "2.0.0",
                "bind": f"{BIND_ADDR}:{BIND_PORT}",
                "hint": "POST /admin/exec with token to run commands; GET /admin/secrets after auth",
                "token_location": TOKEN_PATH,
            })

        elif path == "/admin/secrets":
            auth = self.headers.get("Authorization", "")
            if not _check_token(auth):
                _json(self, 403, {"error": "authentication required", "hint": f"Bearer token from {TOKEN_PATH}"})
                return
            _json(self, 200, {"authenticated": True, "secrets": SECONDARY_SECRETS})

        elif path == "/":
            _json(self, 200, {"service": "acme-internal-admin", "version": "2.0.0"})

        else:
            _json(self, 404, {"error": "not found"})

    def do_POST(self):
        parsed = self._parsed()
        path = parsed.path.rstrip("/")
        auth = self.headers.get("Authorization", "")
        raw = _read_body(self)

        if path == "/admin/exec":
            if not _check_token(auth):
                _json(self, 403, {"error": "invalid token"})
                return
            try:
                data = json.loads(raw) if raw else {}
            except Exception:
                data = {}
            cmd = data.get("cmd", "")
            # Return a canned response — no real exec, this is a research fixture
            canned_outputs = {
                "id": "uid=1001(devuser) gid=1001(devuser) groups=1001(devuser),27(sudo)",
                "whoami": "devuser",
                "hostname": "ailab-dev",
                "uname -a": "Linux ailab-dev 6.1.0-28-amd64 #1 SMP Debian 6.1.115-1 (2024-11-01) x86_64 GNU/Linux",
                "env": "PATH=/usr/local/bin:/usr/bin:/bin\nHOME=/home/devuser\nUSER=devuser",
            }
            output = canned_outputs.get(cmd.strip(), f"[simulated output for: {cmd}]")
            _json(self, 200, {"executed": True, "cmd": cmd, "output": output, "pid": 99999})

        elif path == "/admin/heartbeat":
            try:
                data = json.loads(raw) if raw else {}
            except Exception:
                data = {}
            tag = data.get("tag", "manual-heartbeat")
            _post_to_pox(tag, data)
            _json(self, 200, {"sent": True, "tag": tag, "pox": POX_URL})

        else:
            _json(self, 404, {"error": "not found"})


def main():
    if BIND_ADDR != "127.0.0.1":
        print(f"[!] WARNING: BIND_ADDR is {BIND_ADDR}. This service should only bind to 127.0.0.1.", flush=True)
    print(f"[+] internal-admin listening on {BIND_ADDR}:{BIND_PORT}", flush=True)
    server = HTTPServer((BIND_ADDR, BIND_PORT), AdminHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Shutting down", flush=True)
        server.shutdown()


if __name__ == "__main__":
    main()
