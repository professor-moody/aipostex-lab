#!/usr/bin/env python3
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


LOG_PATH = Path("/var/log/acme-observe/events.jsonl")
LOG_PATH.parent.mkdir(parents=True, exist_ok=True)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self._json({"status": "ok", "service": "acme-log-receiver"})
        elif self.path == "/events":
            body = LOG_PATH.read_text(encoding="utf-8") if LOG_PATH.exists() else ""
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson")
            self.end_headers()
            self.wfile.write(body.encode())
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path != "/events":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8", errors="replace")
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {"message": raw}
        payload.setdefault("timestamp", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
        with LOG_PATH.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(payload, sort_keys=True) + "\n")
        self._json({"stored": True})

    def _json(self, payload):
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        return


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 9201), Handler).serve_forever()
