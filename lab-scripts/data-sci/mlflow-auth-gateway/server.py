#!/usr/bin/env python3
"""Small MLflow auth gateway for the guided credential chain.

The real MLflow server remains on the ML platform host. This gateway is the
attendee-facing DataSci-owned surface: discovery endpoints stay reachable, but
MLflow API calls require the Basic credential leaked from Ray runtime env.
"""

from __future__ import annotations

import base64
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen


PORT = int(os.environ.get("MLFLOW_GATEWAY_PORT", "5000"))
UPSTREAM = os.environ.get("MLFLOW_UPSTREAM", "http://172.16.50.20:5000").rstrip("/") + "/"
USERNAME = os.environ.get("MLFLOW_GATEWAY_USER", "ray-pipeline")
PASSWORD = os.environ.get("MLFLOW_GATEWAY_PASSWORD", "MlflowRayChain!2026")
MAX_BODY = int(os.environ.get("MLFLOW_GATEWAY_MAX_BODY", "1048576"))

PROTECTED_PREFIXES = (
    "/api/2.0/mlflow/",
    "/ajax-api/2.0/mlflow/",
)


def expected_auth() -> str:
    raw = f"{USERNAME}:{PASSWORD}".encode()
    return "Basic " + base64.b64encode(raw).decode()


def is_protected(path: str) -> bool:
    return any(path.startswith(prefix) for prefix in PROTECTED_PREFIXES)


class Handler(BaseHTTPRequestHandler):
    timeout = 10

    def do_GET(self):
        self._handle()

    def do_POST(self):
        self._handle()

    def _handle(self):
        split = urlsplit(self.path)
        path = split.path or "/"

        if path == "/health":
            self._text(200, "OK\n")
            return

        if is_protected(path) and self.headers.get("Authorization", "") != expected_auth():
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="aipostex-mlflow"')
            self.send_header("Content-Type", "application/json")
            body = b'{"error":"authentication required"}\n'
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        body = b""
        if self.command in ("POST", "PUT", "PATCH"):
            length = min(int(self.headers.get("Content-Length", "0") or "0"), MAX_BODY)
            body = self.rfile.read(length) if length > 0 else b""

        upstream_path = path.lstrip("/")
        if split.query:
            upstream_path += "?" + split.query
        upstream_url = urljoin(UPSTREAM, upstream_path)

        headers = {}
        for key, value in self.headers.items():
            if key.lower() in {"host", "connection", "content-length", "authorization"}:
                continue
            headers[key] = value

        req = Request(upstream_url, data=body if body else None, headers=headers, method=self.command)
        try:
            with urlopen(req, timeout=10) as resp:
                data = resp.read()
                self.send_response(resp.status)
                self._copy_headers(resp.headers.items(), len(data))
                self.end_headers()
                self.wfile.write(data)
        except HTTPError as exc:
            data = exc.read()
            self.send_response(exc.code)
            self._copy_headers(exc.headers.items(), len(data))
            self.end_headers()
            self.wfile.write(data)
        except URLError:
            self._text(502, "MLflow upstream unavailable\n")

    def _copy_headers(self, items, content_length: int):
        seen_content_length = False
        for key, value in items:
            if key.lower() in {"connection", "transfer-encoding"}:
                continue
            if key.lower() == "content-length":
                seen_content_length = True
                value = str(content_length)
            self.send_header(key, value)
        if not seen_content_length:
            self.send_header("Content-Length", str(content_length))
        self.send_header("X-Aipostex-Gateway", "mlflow-basic-auth")

    def _text(self, code: int, body: str):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Aipostex-Gateway", "mlflow-basic-auth")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
