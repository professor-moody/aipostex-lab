#!/usr/bin/env python3
"""Lightweight TorchServe mock for aipostex lab validation.

Runs three ports on separate threads matching TorchServe's layout:
  :8080  Inference API   (POST /predictions/{model})
  :8081  Management API  (GET /models, GET /models/{name}, POST /models?url=, etc.)
  :8082  Metrics API     (GET /metrics)
"""
import hashlib
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
from urllib.request import urlopen

INFERENCE_PORT = 8080
MANAGEMENT_PORT = 8081
METRICS_PORT = 8082

MODELS = {
    "acme-sentiment": {
        "modelName": "acme-sentiment",
        "modelVersion": "1.0",
        "status": "READY",
        "runtime": "python",
        "handler": "ts.torch_handler.text_classifier.TextClassifier",
        "minWorkers": 1,
        "maxWorkers": 4,
        "batchSize": 8,
        "workers": [
            {"id": "9001", "status": "READY", "gpu": False},
            {"id": "9002", "status": "READY", "gpu": False},
        ],
    },
    "acme-toxicity": {
        "modelName": "acme-toxicity",
        "modelVersion": "2.1",
        "status": "READY",
        "runtime": "python",
        "handler": "ts.torch_handler.text_classifier.TextClassifier",
        "minWorkers": 1,
        "maxWorkers": 2,
        "batchSize": 4,
        "workers": [
            {"id": "9003", "status": "READY", "gpu": False},
        ],
    },
}

MODEL_LOCK = threading.Lock()

# A tiny .mar-shaped artifact (ZIP magic + filler) served at /artifacts/* so a
# registration can point at a real fetchable archive instead of a circular URL.
MAR_FIXTURE = b"PK\x03\x04aipostex-mar-fixture\x00" + b"\x00" * 32

METRICS_BODY = """\
# HELP ts_inference_requests_total Total inference requests
# TYPE ts_inference_requests_total counter
ts_inference_requests_total{model_name="acme-sentiment",model_version="1.0"} 127
ts_inference_requests_total{model_name="acme-toxicity",model_version="2.1"} 43
# HELP ts_queue_latency_microseconds Queue latency
# TYPE ts_queue_latency_microseconds histogram
ts_queue_latency_microseconds_bucket{le="100"} 120
ts_queue_latency_microseconds_sum 5400
ts_queue_latency_microseconds_count 127
# HELP torchserve_workers_total Active workers
# TYPE torchserve_workers_total gauge
torchserve_workers_total{model_name="acme-sentiment"} 2
torchserve_workers_total{model_name="acme-toxicity"} 1
"""


class InferenceHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.rstrip("/") or "/"
        if path == "/ping":
            self._json({"status": "Healthy"})
        elif path.startswith("/artifacts/"):
            # Serve a small real fetchable .mar-shaped artifact so a registration
            # pointing here produces a genuine server-side fetch (not a circular
            # hit against the management /models JSON).
            self._bytes(200, MAR_FIXTURE)
        else:
            self._text(404, "Not Found")

    def do_POST(self):
        path = self.path.rstrip("/")
        if path.startswith("/predictions/"):
            model_name = path.split("/predictions/", 1)[1].split("/")[0]
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length) if length > 0 else b""
            with MODEL_LOCK:
                model = MODELS.get(model_name)
            if model:
                if model.get("registered") and model.get("status") != "READY":
                    # A model whose archive fetch failed never became servable.
                    self._text(503, f"Model not ready: {model_name} (status={model.get('status')})")
                elif model.get("registered"):
                    self._json({
                        "prediction": "registered-handler-executed",
                        "handler_executed": True,
                        "handler": model.get("handler"),
                        "model": model_name,
                        "model_url": model.get("modelURL"),
                        "input_sha256": hashlib.sha256(body).hexdigest(),
                    })
                else:
                    self._json({"prediction": "positive", "confidence": 0.89, "model": model_name})
            else:
                self._text(404, f"Model not found: {model_name}")
        else:
            self._text(404, "Not Found")

    def _bytes(self, code, payload):
        self.send_response(code)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

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


class ManagementHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.rstrip("/") or "/"
        if path == "/models":
            with MODEL_LOCK:
                models = [{"modelName": m["modelName"], "status": m["status"], "runtime": m["runtime"]} for m in MODELS.values()]
            self._json({"models": models})
        elif path.startswith("/models/"):
            model_name = path.split("/models/", 1)[1].split("/")[0]
            with MODEL_LOCK:
                model = MODELS.get(model_name)
            if model:
                self._json([model])
            else:
                self._text(404, f"Model not found: {model_name}")
        else:
            self._text(404, "Not Found")

    def do_POST(self):
        path = self.path.split("?")[0].rstrip("/")
        if path == "/models":
            parsed = urlparse(self.path)
            params = parse_qs(parsed.query)
            model_url = params.get("url", ["unknown"])[0]
            model_name = params.get("model_name", [""])[0].strip() or derive_model_name(model_url)
            initial_workers = parse_int(params.get("initial_workers", ["1"])[0], 1)
            fetch_status = fetch_model_url(model_url)
            # A model only becomes servable if its archive actually fetched (2xx);
            # a failed/unreachable model-url leaves it FAILED, so predictions 503
            # and the tool cannot claim handler execution off a phantom registration.
            fetched_ok = fetch_status.isdigit() and 200 <= int(fetch_status) < 300
            model_status = "READY" if fetched_ok else "FAILED"
            worker_status = "READY" if fetched_ok else "UNLOADED"
            with MODEL_LOCK:
                MODELS[model_name] = {
                    "modelName": model_name,
                    "modelVersion": "1.0",
                    "status": model_status,
                    "runtime": "python",
                    "handler": "aipostex.registered_handler",
                    "minWorkers": initial_workers,
                    "maxWorkers": max(1, initial_workers),
                    "batchSize": 1,
                    "workers": [
                        {"id": f"dynamic-{model_name}-1", "status": worker_status, "gpu": False},
                    ],
                    "registered": True,
                    "modelURL": model_url,
                    "fetchStatus": fetch_status,
                }
            self._json({"status": "Model registered", "modelName": model_name, "url": model_url, "fetch_status": fetch_status, "model_status": model_status})
        else:
            self._text(404, "Not Found")

    def do_PUT(self):
        path = self.path.split("?")[0].rstrip("/")
        if path.startswith("/models/"):
            self._json({"status": "Workers scaled"})
        else:
            self._text(404, "Not Found")

    def do_DELETE(self):
        path = self.path.rstrip("/")
        if path.startswith("/models/"):
            model_name = path.split("/models/", 1)[1]
            with MODEL_LOCK:
                if MODELS.get(model_name, {}).get("registered"):
                    del MODELS[model_name]
            self._json({"status": f"Model {model_name} unregistered"})
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


class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.rstrip("/") in ("/metrics", "/"):
            self._text(200, METRICS_BODY)
        else:
            self._text(404, "Not Found")

    def _text(self, code, body):
        encoded = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, fmt, *args):
        pass


def run_server(port, handler_class):
    HTTPServer(("0.0.0.0", port), handler_class).serve_forever()


def parse_int(value, default):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def derive_model_name(model_url):
    parsed = urlparse(model_url)
    candidate = parsed.path.rsplit("/", 1)[-1].replace(".mar", "").strip()
    candidate = "".join(ch if ch.isalnum() or ch in "-_." else "-" for ch in candidate)
    return candidate or "registered-model"


def fetch_model_url(model_url):
    parsed = urlparse(model_url)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        return "not-fetched"
    try:
        with urlopen(model_url, timeout=2) as resp:  # noqa: S310 - intentional lab SSRF simulation.
            resp.read(64)
            return str(resp.status)
    except Exception as exc:
        return f"fetch-error:{type(exc).__name__}"


if __name__ == "__main__":
    for port, handler in [
        (INFERENCE_PORT, InferenceHandler),
        (METRICS_PORT, MetricsHandler),
    ]:
        t = threading.Thread(target=run_server, args=(port, handler), daemon=True)
        t.start()
    run_server(MANAGEMENT_PORT, ManagementHandler)
