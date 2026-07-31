#!/usr/bin/env python3
"""HuggingFace Text Generation Inference (TGI) mock server.

Implements the endpoints that aipostex's huggingface module probes:
  GET  /health        — liveness
  GET  /info          — server identity (TGI variant: no model_type key)
  GET  /v1/models     — OpenAI-compatible model list (TGI v1.4+)
  GET  /metrics       — Prometheus-format operational metrics
  POST /generate      — text generation
"""
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 8180

# Counters for realistic /metrics values
_start = time.monotonic()
_req_count = 0


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        global _req_count
        _req_count += 1
        path = self.path.split("?")[0].rstrip("/") or "/"

        if path == "/health":
            self._json({"status": "ok"})
        elif path == "/info":
            self._json({
                "model_id": "acme-tgi-lab",
                "model_pipeline_tag": "text-generation",
                "sha": "lab-mock-abc123",
                "version": "1.4.5",
                "max_input_length": 4096,
                "max_total_tokens": 8192,
                "max_batch_total_tokens": 32768,
                "waiting_served_ratio": 0.3,
            })
        elif path == "/v1/models":
            self._json({
                "object": "list",
                "data": [
                    {"id": "acme-tgi-lab", "object": "model", "owned_by": "acme-corp"}
                ],
            })
        elif path == "/metrics":
            uptime = time.monotonic() - _start
            body = (
                "# HELP tgi_request_count Total requests\n"
                "# TYPE tgi_request_count counter\n"
                f"tgi_request_count {_req_count}\n"
                "# HELP tgi_queue_size Current queue depth\n"
                "# TYPE tgi_queue_size gauge\n"
                "tgi_queue_size 0\n"
                "# HELP tgi_batch_current_size Current batch size\n"
                "# TYPE tgi_batch_current_size gauge\n"
                "tgi_batch_current_size 1\n"
                "# HELP tgi_request_duration_seconds Request latency\n"
                "# TYPE tgi_request_duration_seconds histogram\n"
                "tgi_request_duration_seconds_bucket{le=\"0.1\"} 42\n"
                "tgi_request_duration_seconds_bucket{le=\"0.5\"} 57\n"
                "tgi_request_duration_seconds_bucket{le=\"+Inf\"} 60\n"
                f"tgi_request_duration_seconds_sum {uptime:.2f}\n"
                f"tgi_request_duration_seconds_count {_req_count}\n"
            )
            self._text(200, body, content_type="text/plain; version=0.0.4; charset=utf-8")
        else:
            self._text(404, "Not Found")

    def do_POST(self):
        global _req_count
        _req_count += 1
        if self.path.split("?")[0].rstrip("/") == "/generate":
            self._json({"generated_text": "incident-response runbook bundle"})
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

