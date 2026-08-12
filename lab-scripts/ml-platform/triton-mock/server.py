#!/usr/bin/env python3
"""Lightweight NVIDIA Triton Inference Server mock for aipostex lab validation.

Responds to the KServe v2 protocol endpoints that the aipostex Triton client probes:
  GET  /v2                            → server metadata
  GET  /v2/health/ready               → readiness
  GET  /v2/health/live                → liveness
  GET  /v2/models                     → model list
  GET  /v2/models/{name}              → model metadata
  GET  /v2/models/{name}/config       → model config
  POST /v2/models/{name}/infer        → inference
  POST /v2/repository/index           → repository index
  POST /v2/repository/models/{n}/load → model load
  POST /v2/repository/models/{n}/unload → model unload
  GET  /v2/systemsharedmemory/status  → system shared memory
  GET  /v2/cudasharedmemory/status    → CUDA shared memory
"""
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 8500

SERVER_META = {
    "name": "triton-lab-mock",
    "version": "2.42.0",
    "extensions": ["classification", "sequence", "model_repository", "model_repository(unload_dependents)", "schedule_policy", "model_configuration", "system_shared_memory", "cuda_shared_memory", "binary_tensor_data", "statistics", "trace", "logging"],
}

MODELS = {
    "acme-fraud-detector": {
        "name": "acme-fraud-detector",
        "version": "1",
        "state": "READY",
        "platform": "pytorch_libtorch",
        "inputs": [{"name": "input__0", "datatype": "FP32", "shape": [-1, 128]}],
        "outputs": [{"name": "output__0", "datatype": "FP32", "shape": [-1, 2]}],
        "config": {
            "name": "acme-fraud-detector",
            "platform": "pytorch_libtorch",
            "backend": "pytorch",
            "instance_group": [{"name": "acme-fraud-detector_0", "kind": "KIND_CPU", "count": 1}],
            "max_batch_size": 16,
        },
    },
    "acme-embeddings": {
        "name": "acme-embeddings",
        "version": "1",
        "state": "READY",
        "platform": "onnxruntime_onnx",
        "inputs": [{"name": "input_ids", "datatype": "INT64", "shape": [-1, 512]}],
        "outputs": [{"name": "embeddings", "datatype": "FP32", "shape": [-1, 768]}],
        "config": {
            "name": "acme-embeddings",
            "platform": "onnxruntime_onnx",
            "backend": "onnxruntime",
            "instance_group": [{"name": "acme-embeddings_0", "kind": "KIND_CPU", "count": 2}],
            "max_batch_size": 32,
        },
    },
}

LOADED_MODELS = {"acme-fraud-detector", "acme-embeddings"}
MODEL_LOCK = threading.Lock()

MODELS["aipostex-injected"] = {
    "name": "aipostex-injected",
    "version": "1",
    "state": "UNAVAILABLE",
    "platform": "onnxruntime_onnx",
    "inputs": [{"name": "INPUT0", "datatype": "FP32", "shape": [1, 1]}],
    "outputs": [{"name": "OUTPUT0", "datatype": "FP32", "shape": [1, 1]}],
    "config": {
        "name": "aipostex-injected",
        "platform": "onnxruntime_onnx",
        "backend": "onnxruntime",
        "instance_group": [{"name": "aipostex-injected_0", "kind": "KIND_CPU", "count": 1}],
        "max_batch_size": 1,
    },
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.rstrip("/")
        if path == "/v2" or path == "":
            self._json(SERVER_META)
        elif path == "/v2/health/ready":
            self._text(200, "")
        elif path == "/v2/health/live":
            self._text(200, "")
        elif path == "/v2/models":
            with MODEL_LOCK:
                models = [
                    {
                        "name": m["name"],
                        "version": m["version"],
                        "state": "READY",
                        "platform": m["platform"],
                    }
                    for name, m in MODELS.items()
                    if name in LOADED_MODELS
                ]
            self._json({"models": models})
        elif path.startswith("/v2/models/"):
            parts = path.split("/v2/models/", 1)[1].split("/")
            model_name = parts[0]
            with MODEL_LOCK:
                loaded = model_name in LOADED_MODELS
                model = MODELS.get(model_name)
            if model and loaded:
                if len(parts) > 1 and parts[1] == "config":
                    self._json(model["config"])
                else:
                    response = {k: model[k] for k in ("name", "version", "state", "platform", "inputs", "outputs") if k in model}
                    response["state"] = "READY"
                    self._json(response)
            else:
                self._text(404, f"Model not found: {model_name}")
        elif path == "/v2/systemsharedmemory/status":
            self._json([{"name": "lab_shm_region", "key": "/dev/shm/lab_region", "offset": 0, "byte_size": 65536}])
        elif path == "/v2/cudasharedmemory/status":
            self._json([])
        else:
            self._text(404, "Not Found")

    def do_POST(self):
        path = self.path.rstrip("/")
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length > 0 else b""

        if path == "/v2/repository/index":
            with MODEL_LOCK:
                entries = [
                    {
                        "name": m["name"],
                        "version": m["version"],
                        "state": "READY" if name in LOADED_MODELS else "UNAVAILABLE",
                    }
                    for name, m in MODELS.items()
                ]
            self._json(entries)
        elif path.startswith("/v2/repository/models/") and path.endswith("/load"):
            model_name = path.split("/v2/repository/models/", 1)[1].split("/load")[0]
            with MODEL_LOCK:
                if model_name in MODELS:
                    LOADED_MODELS.add(model_name)
                    MODELS[model_name]["state"] = "READY"
                    self._text(200, "")
                else:
                    self._text(404, f"Model not found: {model_name}")
        elif path.startswith("/v2/repository/models/") and path.endswith("/unload"):
            model_name = path.split("/v2/repository/models/", 1)[1].split("/unload")[0]
            with MODEL_LOCK:
                if model_name in MODELS:
                    LOADED_MODELS.discard(model_name)
                    MODELS[model_name]["state"] = "UNAVAILABLE"
                    self._text(200, "")
                else:
                    self._text(404, f"Model not found: {model_name}")
        elif path.startswith("/v2/models/") and path.endswith("/infer"):
            model_name = path.split("/v2/models/", 1)[1].split("/infer")[0]
            with MODEL_LOCK:
                loaded = model_name in LOADED_MODELS
                m = MODELS.get(model_name)
            if m and loaded:
                # Input-dependent output: a real handler's forward pass varies with its
                # input, so the tool's inference reality probe (mutated-input differential)
                # can tell genuine handler execution from a canned fixture. This is a
                # deterministic function of the request bytes, NOT real ML inference.
                seed = sum(body) % 100000
                outputs = []
                for o in m["outputs"]:
                    shape = [1] + [max(1, s) for s in o["shape"][1:]]
                    n = 1
                    for s in shape:
                        n *= s
                    data = [round(((seed + i * 131) % 100000) / 100000.0, 6) for i in range(n)]
                    outputs.append({"name": o["name"], "datatype": o["datatype"], "shape": shape, "data": data})
                self._json({
                    "model_name": model_name,
                    "model_version": m["version"],
                    "outputs": outputs,
                })
            else:
                self._text(404, f"Model not found: {model_name}")
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


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
