#!/usr/bin/env python3
"""HuggingFace Text Embeddings Inference (TEI) mock server.

Implements the endpoints that aipostex's huggingface module probes:
  GET  /info     — server identity (TEI variant: includes model_type key)
  GET  /metrics  — Prometheus-format operational metrics
  POST /embed    — embedding generation (returns 2D array [[f1,f2,...]])
  POST /rerank   — cross-encoder reranking
"""
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 8181

_start = time.monotonic()
_req_count = 0
_embed_count = 0


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        global _req_count
        _req_count += 1
        path = self.path.split("?")[0].rstrip("/") or "/"

        if path == "/info":
            self._json({
                "model_id": "acme-tei-lab",
                "model_type": "embedding",
                "sha": "lab-mock-def456",
                "version": "1.2.3",
                "max_batch_tokens": 16384,
                "dimension": 384,
            })
        elif path == "/metrics":
            uptime = time.monotonic() - _start
            body = (
                "# HELP te_request_count Total requests\n"
                "# TYPE te_request_count counter\n"
                f"te_request_count {_req_count}\n"
                "# HELP te_embed_count Total embeddings computed\n"
                "# TYPE te_embed_count counter\n"
                f"te_embed_count {_embed_count}\n"
                "# HELP te_request_duration_seconds Request latency\n"
                "# TYPE te_request_duration_seconds histogram\n"
                "te_request_duration_seconds_bucket{le=\"0.1\"} 30\n"
                "te_request_duration_seconds_bucket{le=\"0.5\"} 45\n"
                "te_request_duration_seconds_bucket{le=\"+Inf\"} 50\n"
                f"te_request_duration_seconds_sum {uptime:.2f}\n"
                f"te_request_duration_seconds_count {_req_count}\n"
            )
            self._text(200, body, content_type="text/plain; version=0.0.4; charset=utf-8")
        else:
            self._text(404, "Not Found")

    def do_POST(self):
        global _req_count, _embed_count
        _req_count += 1
        path = self.path.split("?")[0].rstrip("/")

        if path == "/embed":
            _embed_count += 1
            # TEI real API returns a 2D array: [[dim1, dim2, ...], ...]
            # One vector per input text.  The client unmarshals as [][]float32.
            self._json([[0.12, 0.42, 0.08, 0.31, -0.15, 0.67, 0.23, -0.09]])
        elif path == "/rerank":
            self._json([
                {"index": 0, "score": 0.95, "text": "passage one"},
                {"index": 1, "score": 0.42, "text": "passage two"},
            ])
        else:
            self._text(404, "Not Found")

    # ── helpers ──────────────────────────────────────────
    def _json(self, payload):
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _text(self, code, body, content_type="text/plain"):
        encoded = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()

