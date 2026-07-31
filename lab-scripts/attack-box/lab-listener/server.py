#!/usr/bin/env python3
"""
lab-listener — Shared callback/validation listener for aipostex-lab.
Runs on ailab-attack (172.16.50.99:9000).

Receives:
  - A2A push notification webhooks  POST /callback/webhook
  - File-exfil payloads              POST /callback/exfil
  - SSRF HTTP callbacks              GET  /callback/ssrf[/<token>]

Query API:
  GET /callbacks?probe_id=&kind=&since=&limit=&offset=
  GET /health
  GET /

Run via systemd as lab-listener.service.
"""
import hashlib
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

from storage import EventStore, make_event

BIND_HOST = os.environ.get("LISTENER_HOST", "0.0.0.0")
BIND_PORT = int(os.environ.get("LISTENER_PORT", "9000"))
MAX_BODY = 64 * 1024  # 64 KB stored; larger bodies are hashed only

store = EventStore()

BANNER = (
    " _       _                      _     _\n"
    "| | __ _| |__        | (_)___| |_ ___ _ __   ___ _ __\n"
    "| |/ _` | '_ \\  ___  | | / __| __/ _ | '_ \\ / _ | '__|\n"
    "| | (_| | |_) ||___| | | \\__ | ||  __| | | |  __| |\n"
    "|_|\\__,_|_.__/       |_|_|___/\\__\\___|_| |_|\\___|_|\n"
    "\n"
    "aipostex-lab callback listener  port {port}\n"
    "Routes:\n"
    "  POST /callback/webhook   A2A push notification sink\n"
    "  POST /callback/exfil     File-exfil sink (stores sha256 + first 64KB)\n"
    "  GET  /callback/ssrf      SSRF HTTP callback\n"
    "  GET  /callback/ssrf/<t>  Token-scoped SSRF beacon\n"
    "  GET  /callbacks          Query captured events\n"
    "  GET  /health             Health check\n"
)


def _remote_addr(handler: "LabHandler") -> str:
    fwd = handler.headers.get("X-Forwarded-For")
    if fwd:
        return fwd.split(",")[0].strip()
    return handler.client_address[0] if handler.client_address else "unknown"


def _probe_id_from(handler: "LabHandler", body: bytes, qs: dict) -> str:
    # 1. query param
    if "probe_id" in qs:
        return qs["probe_id"][0]
    # 2. request header
    hdr = handler.headers.get("X-Probe-Id")
    if hdr:
        return hdr
    # 3. body JSON taskId
    try:
        data = json.loads(body)
        if "taskId" in data:
            return str(data["taskId"])
        if "id" in data:
            return str(data["id"])
    except Exception:
        pass
    return ""


def _read_body(handler: "LabHandler") -> bytes:
    length = int(handler.headers.get("Content-Length", 0) or 0)
    if length <= 0:
        return b""
    return handler.rfile.read(min(length, MAX_BODY))


def _header_dict(handler: "LabHandler") -> dict:
    skip = {"host", "content-length"}
    return {
        k.lower(): v
        for k, v in handler.headers.items()
        if k.lower() not in skip
    }


def _qs_dict(parsed) -> dict:
    return {k: v for k, v in parse_qs(parsed.query).items()}


def _sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def _json_response(handler: "LabHandler", status: int, data: dict):
    body = json.dumps(data, indent=2).encode()
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("X-Lab-Listener", "1")
    handler.end_headers()
    handler.wfile.write(body)


class LabHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        # Suppress per-request logs; events are in storage
        pass

    def _parsed(self):
        return urlparse(self.path)

    def do_GET(self):
        parsed = self._parsed()
        path = parsed.path.rstrip("/")
        qs = _qs_dict(parsed)

        if path == "/health":
            _json_response(self, 200, {
                "status": "healthy",
                "version": "1.0.0",
                "events_in_ring": store.count(),
                "total_seen": store.total_seen(),
            })

        elif path.startswith("/callback/ssrf"):
            # token may be in path: /callback/ssrf/<token>
            token = path[len("/callback/ssrf/"):] if "/" in path[len("/callback/ssrf"):] else ""
            probe_id = qs.get("probe_id", [token or "ssrf"])[0]
            ev = make_event(
                kind="ssrf",
                remote_addr=_remote_addr(self),
                path=parsed.path,
                method="GET",
                probe_id=probe_id,
                headers=_header_dict(self),
                query=qs,
                body_preview=b"",
                body_size=0,
                body_sha256="",
            )
            store.append(ev)
            _json_response(self, 200, {"received": True, "probe_id": probe_id})

        elif path == "/callbacks":
            events = store.query(
                probe_id=qs.get("probe_id", [None])[0],
                kind=qs.get("kind", [None])[0],
                since=qs.get("since", [None])[0],
                limit=int(qs.get("limit", ["100"])[0]),
                offset=int(qs.get("offset", ["0"])[0]),
            )
            _json_response(self, 200, {"count": len(events), "events": events})

        elif path == "/":
            body = BANNER.format(port=BIND_PORT).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("X-Lab-Listener", "1")
            self.end_headers()
            self.wfile.write(body)

        else:
            _json_response(self, 404, {"error": "not found"})

    def do_POST(self):
        parsed = self._parsed()
        path = parsed.path.rstrip("/")
        qs = _qs_dict(parsed)
        body = _read_body(self)
        sha = _sha256(body) if body else ""

        probe_id = _probe_id_from(self, body, qs)

        if path == "/callback/webhook":
            ev = make_event(
                kind="webhook",
                remote_addr=_remote_addr(self),
                path=parsed.path,
                method="POST",
                probe_id=probe_id,
                headers=_header_dict(self),
                query=qs,
                body_preview=body,
                body_size=len(body),
                body_sha256=sha,
            )
            store.append(ev)
            _json_response(self, 200, {"received": True, "probe_id": probe_id, "seq": ev["seq"]})

        elif path == "/callback/exfil":
            tag = qs.get("tag", [probe_id or "untagged"])[0]
            ev = make_event(
                kind="exfil",
                remote_addr=_remote_addr(self),
                path=parsed.path,
                method="POST",
                probe_id=tag,
                headers=_header_dict(self),
                query=qs,
                body_preview=body,
                body_size=len(body),
                body_sha256=sha,
            )
            store.append(ev)
            _json_response(self, 200, {
                "recorded": True,
                "tag": tag,
                "bytes": len(body),
                "sha256": sha,
                "seq": ev["seq"],
            })

        else:
            _json_response(self, 404, {"error": "not found"})


def main():
    print(BANNER.format(port=BIND_PORT), flush=True)
    server = HTTPServer((BIND_HOST, BIND_PORT), LabHandler)
    print(f"[+] Listening on {BIND_HOST}:{BIND_PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Shutting down", flush=True)
        server.shutdown()


if __name__ == "__main__":
    main()
