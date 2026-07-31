#!/usr/bin/env python3
"""Lightweight BentoML mock for aipostex lab validation.

Responds to the endpoints that the aipostex BentoML client probes:
  GET  /           → service info
  GET  /healthz    → health check
  GET  /docs.json  → OpenAPI spec with routes
  GET  /metrics    → Prometheus-style metrics
  POST /predict    → input-dependent mock inference
"""
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 3333

SERVICE_INFO = {
    "name": "acme-classifier",
    "version": "1.2.3",
    "bento_version": "1.2.3",
    "service_name": "acme-classifier",
}

OPENAPI_SPEC = {
    "openapi": "3.0.0",
    "info": {"title": "acme-classifier", "version": "1.2.3"},
    "paths": {
        "/predict": {
            "post": {
                "summary": "Run classification inference",
                "description": "Classify input text into categories",
                "requestBody": {
                    "content": {
                        "application/json": {
                            "schema": {"type": "object", "properties": {"text": {"type": "string"}}}
                        }
                    }
                },
            }
        },
        "/classify": {
            "post": {
                "summary": "Classify a batch of text inputs",
                "operationId": "classify",
                "requestBody": {
                    "required": True,
                    "content": {
                        "application/json": {
                            "schema": {
                                "type": "object",
                                "required": ["instances"],
                                "properties": {
                                    "instances": {
                                        "type": "array",
                                        "items": {"type": "string"},
                                    }
                                },
                            }
                        }
                    },
                },
                "responses": {
                    "200": {
                        "description": "Batch classification result",
                        "content": {
                            "application/json": {
                                "schema": {
                                    "type": "object",
                                    "properties": {
                                        "predictions": {
                                            "type": "array",
                                            "items": {"type": "object"},
                                        }
                                    },
                                }
                            }
                        },
                    }
                },
            }
        },
        "/healthz": {"get": {"summary": "Health check"}},
        "/metrics": {"get": {"summary": "Prometheus metrics"}},
    },
}

METRICS_BODY = """\
# HELP bentoml_request_total Total number of requests
# TYPE bentoml_request_total counter
bentoml_request_total{method="POST",endpoint="/predict",status="200"} 42
# HELP bentoml_request_duration_seconds Request duration
# TYPE bentoml_request_duration_seconds histogram
bentoml_request_duration_seconds_bucket{le="0.1"} 38
bentoml_request_duration_seconds_bucket{le="0.5"} 41
bentoml_request_duration_seconds_bucket{le="1.0"} 42
bentoml_request_duration_seconds_sum 3.14
bentoml_request_duration_seconds_count 42
"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.rstrip("/") or "/"
        if path == "/":
            self._json(SERVICE_INFO)
        elif path == "/healthz":
            self._json({"status": "healthy"})
        elif path == "/docs.json":
            self._json(OPENAPI_SPEC)
        elif path == "/metrics":
            self._text(200, METRICS_BODY)
        else:
            self._text(404, "Not Found")

    def do_POST(self):
        path = self.path.rstrip("/") or "/"
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length > 0 else b""
        if path == "/predict":
            self._json(prediction_for(body))
        elif path == "/classify":
            self._json(batch_prediction_for(body))
        else:
            self._text(404, "Not Found")

    def _json(self, payload):
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _text(self, code, body):
        encoded = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, fmt, *args):
        pass


def prediction_for(raw_body):
    payload = _json_body(raw_body)
    text = " ".join(_strings(payload)) or raw_body.decode(errors="ignore")
    seed = sum(ord(ch) for ch in text)
    labels = ["positive", "review", "escalate", "benign"]
    return {
        "label": labels[seed % len(labels)],
        "confidence": round(0.5 + ((seed % 45) / 100.0), 2),
        "model": "acme-classifier",
        "timestamp": time.time(),
    }


def batch_prediction_for(raw_body):
    payload = _json_body(raw_body)
    instances = payload.get("instances") if isinstance(payload, dict) else None
    if not isinstance(instances, list) or not instances:
        instances = _strings(payload) or [raw_body.decode(errors="ignore")]
    return {
        "predictions": [prediction_for(json.dumps({"text": str(item)}).encode()) for item in instances],
        "model": "acme-classifier",
        "timestamp": time.time(),
    }


def _json_body(raw_body):
    try:
        return json.loads(raw_body.decode() or "{}")
    except json.JSONDecodeError:
        return {}


def _strings(value):
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        out = []
        for item in value:
            out.extend(_strings(item))
        return out
    if isinstance(value, dict):
        out = []
        for item in value.values():
            out.extend(_strings(item))
        return out
    return []


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
