#!/usr/bin/env python3
"""TensorFlow Serving mock server.

Implements the REST API surface that aipostex's tfserving module probes:
  GET  /v1/models                                — model discovery (404 with structured error)
  GET  /v1/models/<name>                         — model version status
  GET  /v1/models/<name>/metadata                — signature & tensor metadata
  POST /v1/models/<name>:predict                 — input-dependent inference
  POST /v1/models/<name>/versions/<v>:predict    — versioned input-dependent inference
  GET  /monitoring/prometheus/metrics             — Prometheus-format metrics

Port 8501 matches the default TF Serving REST port.
"""
import json
import re
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 8501

_start = time.monotonic()
_req_count = 0
_predict_count = 0

# ── Seeded model data ────────────────────────────────────────────────────

MODELS = {
    "acme-fraud-scorer": {
        "model_version_status": [
            {
                "version": "1",
                "state": "AVAILABLE",
                "status": {"error_code": "OK", "error_message": ""},
            },
            {
                "version": "2",
                "state": "AVAILABLE",
                "status": {"error_code": "OK", "error_message": ""},
            },
        ],
        "metadata": {
            "model_spec": {
                "name": "acme-fraud-scorer",
                "signature_name": "",
                "version": {"value": "2"},
            },
            "metadata": {
                "signature_def": {
                    "signature_def": {
                        "serving_default": {
                            "inputs": {
                                "transaction_features": {
                                    "dtype": "DT_FLOAT",
                                    "tensor_shape": {
                                        "dim": [{"size": "-1"}, {"size": "32"}]
                                    },
                                    "name": "serving_default_transaction_features:0",
                                }
                            },
                            "outputs": {
                                "fraud_probability": {
                                    "dtype": "DT_FLOAT",
                                    "tensor_shape": {
                                        "dim": [{"size": "-1"}, {"size": "1"}]
                                    },
                                    "name": "StatefulPartitionedCall:0",
                                }
                            },
                            "method_name": "tensorflow/serving/predict",
                        }
                    }
                }
            },
        },
        "predict_response": {
            "predictions": [[0.87], [0.12], [0.95]],
        },
    },
    "acme-embeddings": {
        "model_version_status": [
            {
                "version": "1",
                "state": "AVAILABLE",
                "status": {"error_code": "OK", "error_message": ""},
            },
        ],
        "metadata": {
            "model_spec": {
                "name": "acme-embeddings",
                "signature_name": "",
                "version": {"value": "1"},
            },
            "metadata": {
                "signature_def": {
                    "signature_def": {
                        "serving_default": {
                            "inputs": {
                                "input_text": {
                                    "dtype": "DT_STRING",
                                    "tensor_shape": {"dim": [{"size": "-1"}]},
                                    "name": "serving_default_input_text:0",
                                }
                            },
                            "outputs": {
                                "embeddings": {
                                    "dtype": "DT_FLOAT",
                                    "tensor_shape": {
                                        "dim": [{"size": "-1"}, {"size": "128"}]
                                    },
                                    "name": "StatefulPartitionedCall:0",
                                }
                            },
                            "method_name": "tensorflow/serving/predict",
                        }
                    }
                }
            },
        },
        "predict_response": {
            "predictions": [[0.1] * 128],
        },
    },
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        global _req_count
        _req_count += 1
        path = self.path.split("?")[0].rstrip("/") or "/"

        # Prometheus metrics
        if path == "/monitoring/prometheus/metrics":
            uptime = time.monotonic() - _start
            body = (
                "# HELP :tensorflow:serving:request_count Total requests\n"
                "# TYPE :tensorflow:serving:request_count counter\n"
                f':tensorflow:serving:request_count{{model_name="acme-fraud-scorer",model_version="2"}} {_predict_count}\n'
                "# HELP :tensorflow:serving:request_latency Request latency\n"
                "# TYPE :tensorflow:serving:request_latency histogram\n"
                f':tensorflow:serving:request_latency_bucket{{le="0.1"}} {_predict_count}\n'
                f':tensorflow:serving:request_latency_bucket{{le="+Inf"}} {_predict_count}\n'
                f":tensorflow:serving:request_latency_sum {uptime:.2f}\n"
                f":tensorflow:serving:request_latency_count {_req_count}\n"
            )
            self._text(200, body, content_type="text/plain; version=0.0.4; charset=utf-8")
            return

        # GET /v1/models (no model name) → 404 with structured error (real TF Serving behavior)
        if path == "/v1/models":
            self._json(404, {"error": "Missing model name in request", "code": 5, "message": "Not found: /v1/models"})
            return

        # GET /v1/models/<name>
        m = re.match(r"^/v1/models/([^/:]+)$", path)
        if m:
            name = m.group(1)
            if name in MODELS:
                self._json(200, {"model_version_status": MODELS[name]["model_version_status"]})
            else:
                self._json(404, {"error": f"Model {name} not found", "code": 5, "message": f"Servable not found for request: Latest({name})"})
            return

        # GET /v1/models/<name>/metadata
        m = re.match(r"^/v1/models/([^/:]+)/metadata$", path)
        if m:
            name = m.group(1)
            if name in MODELS:
                self._json(200, MODELS[name]["metadata"])
            else:
                self._json(404, {"error": f"Model {name} not found"})
            return

        self._text(404, "Not Found")

    def do_POST(self):
        global _req_count, _predict_count
        _req_count += 1
        path = self.path.split("?")[0].rstrip("/")

        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length > 0 else b"{}"

        # POST /v1/models/<name>:predict or /v1/models/<name>/versions/<v>:predict
        m = re.match(r"^/v1/models/([^/:]+)(?:/versions/\d+)?:predict$", path)
        if m:
            name = m.group(1)
            if name in MODELS:
                _predict_count += 1
                self._json(200, prediction_for(name, body))
            else:
                self._json(404, {"error": f"Model {name} not found"})
            return

        self._text(404, "Not Found")

    # ── helpers ──────────────────────────────────────────
    def _json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
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


def prediction_for(name, raw_body):
    try:
        payload = json.loads(raw_body.decode() or "{}")
    except json.JSONDecodeError:
        payload = {}

    if name == "acme-embeddings":
        text = " ".join(_strings(payload)) or raw_body.decode(errors="ignore")
        seed = sum(ord(ch) for ch in text)
        vector = [round(((seed + i * 17) % 1000) / 1000.0, 4) for i in range(128)]
        return {"predictions": [vector], "model": name}

    nums = _numbers(payload)
    if nums:
        total = sum(float(n) for n in nums)
        avg = total / max(len(nums), 1)
        score = 1.0 / (1.0 + pow(2.718281828, -(avg / 2.0 - 2.0)))
    else:
        score = (sum(raw_body) % 100) / 100.0
    score = max(0.01, min(0.99, score))
    return {"predictions": [[round(score, 4)]], "model": name}


def _numbers(value):
    if isinstance(value, bool):
        return []
    if isinstance(value, (int, float)):
        return [value]
    if isinstance(value, list):
        out = []
        for item in value:
            out.extend(_numbers(item))
        return out
    if isinstance(value, dict):
        out = []
        for item in value.values():
            out.extend(_numbers(item))
        return out
    return []


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
