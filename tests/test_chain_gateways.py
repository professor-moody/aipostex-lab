from __future__ import annotations

import base64
import importlib.util
import json
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class UpstreamMLflowHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path.startswith("/api/2.0/mlflow/experiments/search"):
            self._json({"experiments": [{"experiment_id": "1", "name": "customer-embedding-model"}]})
        elif self.path.startswith("/api/2.0/mlflow/runs/search"):
            self._json(
                {
                    "runs": [
                        {
                            "info": {"run_id": "run-1"},
                            "data": {
                                "params": [
                                    {"key": "hf_tgi_token", "value": "hf_FAKE_aBcDeFgHiJkLmNoPqRsTuVwXyZ123"}
                                ]
                            },
                        }
                    ]
                }
            )
        else:
            self.send_response(404)
            self.end_headers()

    def _json(self, payload):
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


class FakeOpenAIHandler(BaseHTTPRequestHandler):
    """Stand-in for the real OpenAI-compatible backend (LiteLLM -> Ollama)."""

    def do_POST(self):
        if self.path.rstrip("/").endswith("/v1/chat/completions"):
            length = int(self.headers.get("Content-Length", "0") or "0")
            if length:
                self.rfile.read(length)
            self._json({"choices": [{"message": {"role": "assistant", "content": "real model output: contain the breach"}}]})
        else:
            self.send_response(404)
            self.end_headers()

    def _json(self, payload):
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


def serve(handler):
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


def request(url: str, method="GET", headers=None, body=None):
    data = body.encode() if isinstance(body, str) else body
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode()


def test_tgi_gateway_requires_bearer_for_generate():
    module = load_module(
        "tgi_gateway_test",
        ROOT / "lab-scripts" / "app-platform" / "tgi-gateway" / "server.py",
    )
    module.REQUIRED_TOKEN = "hf_test_token"
    server = serve(module.Handler)
    base = f"http://127.0.0.1:{server.server_port}"
    try:
        status, body = request(base + "/info")
        assert status == 200
        assert "acme-tgi-lab" in body

        status, _ = request(
            base + "/generate",
            method="POST",
            headers={"Content-Type": "application/json"},
            body='{"inputs":"hello"}',
        )
        assert status == 401

        status, body = request(
            base + "/generate",
            method="POST",
            headers={"Content-Type": "application/json", "Authorization": "Bearer hf_test_token"},
            body='{"inputs":"hello"}',
        )
        assert status == 200
        assert "credential_replay" in body
    finally:
        server.shutdown()
        server.server_close()


def test_tgi_gateway_proxies_to_real_upstream():
    upstream = serve(FakeOpenAIHandler)
    module = load_module(
        "tgi_gateway_real",
        ROOT / "lab-scripts" / "app-platform" / "tgi-gateway" / "server.py",
    )
    module.REQUIRED_TOKEN = "hf_test_token"
    module.UPSTREAM_URL = f"http://127.0.0.1:{upstream.server_port}/v1/chat/completions"
    module.UPSTREAM_MODEL = "local-smollm"
    gateway = serve(module.Handler)
    base = f"http://127.0.0.1:{gateway.server_port}"
    try:
        status, body = request(
            base + "/generate",
            method="POST",
            headers={"Content-Type": "application/json", "Authorization": "Bearer hf_test_token"},
            body='{"inputs":"how do I respond?","parameters":{"max_new_tokens":16}}',
        )
        assert status == 200
        data = json.loads(body)
        assert data["inference"] == "real"
        assert "real model output" in data["generated_text"]
        assert data["credential_replay"] == "accepted"
    finally:
        gateway.shutdown()
        gateway.server_close()
        upstream.shutdown()
        upstream.server_close()


def test_tgi_gateway_honest_502_when_upstream_down():
    module = load_module(
        "tgi_gateway_502",
        ROOT / "lab-scripts" / "app-platform" / "tgi-gateway" / "server.py",
    )
    module.REQUIRED_TOKEN = "hf_test_token"
    # Closed port -> connection refused -> honest 502, never a fake 200.
    module.UPSTREAM_URL = "http://127.0.0.1:9/v1/chat/completions"
    module.UPSTREAM_TIMEOUT = 2.0
    gateway = serve(module.Handler)
    base = f"http://127.0.0.1:{gateway.server_port}"
    try:
        status, body = request(
            base + "/generate",
            method="POST",
            headers={"Content-Type": "application/json", "Authorization": "Bearer hf_test_token"},
            body='{"inputs":"hello"}',
        )
        assert status == 502
        assert "credential_replay" not in body
    finally:
        gateway.shutdown()
        gateway.server_close()


def test_mlflow_gateway_requires_basic_for_api_paths():
    upstream = serve(UpstreamMLflowHandler)
    module = load_module(
        "mlflow_gateway_test",
        ROOT / "lab-scripts" / "data-sci" / "mlflow-auth-gateway" / "server.py",
    )
    module.UPSTREAM = f"http://127.0.0.1:{upstream.server_port}/"
    module.USERNAME = "ray-pipeline"
    module.PASSWORD = "secret"
    gateway = serve(module.Handler)
    base = f"http://127.0.0.1:{gateway.server_port}"
    encoded = base64.b64encode(b"ray-pipeline:secret").decode()
    try:
        status, body = request(base + "/health")
        assert status == 200
        assert "OK" in body

        status, _ = request(
            base + "/api/2.0/mlflow/experiments/search",
            method="POST",
            headers={"Content-Type": "application/json"},
            body='{"max_results":1}',
        )
        assert status == 401

        status, body = request(
            base + "/api/2.0/mlflow/experiments/search",
            method="POST",
            headers={"Content-Type": "application/json", "Authorization": f"Basic {encoded}"},
            body='{"max_results":1}',
        )
        assert status == 200
        assert "customer-embedding-model" in body
    finally:
        gateway.shutdown()
        gateway.server_close()
        upstream.shutdown()
        upstream.server_close()
