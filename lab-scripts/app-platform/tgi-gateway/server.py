#!/usr/bin/env python3
"""Protocol-real TGI gateway used by the guided credential chain.

TGI itself does not bearer-gate /generate. The lab models the common production
shape: a thin inference gateway in front of TGI that leaves discovery endpoints
reachable but requires the HF token harvested from MLflow for generation.

It also mirrors the HuggingFace Hub file-download surface (`/<model>/resolve/
<revision>/<file>`) faithfully — realistic file set, revision resolution, real
Hub response headers (ETag / X-Linked-Etag / X-Repo-Commit / Accept-Ranges), HEAD
support, the 302 LFS redirect for weight files, and a gated-repo 401 — so the
aipostex `huggingface model-download` verb (and a real `huggingface_hub` client)
exercise the same flow they would against the public Hub, without leaving the lab.
"""

from __future__ import annotations

import hashlib
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


PORT = int(os.environ.get("TGI_GATEWAY_PORT", "8180"))
REQUIRED_TOKEN = os.environ.get("TGI_GATEWAY_TOKEN", "hf_FAKE_aBcDeFgHiJkLmNoPqRsTuVwXyZ123")
STAGE = os.environ.get("TGI_GATEWAY_STAGE", "staging")
# When TGI_UPSTREAM_URL is set, /generate proxies to a real OpenAI-compatible
# backend (e.g. LiteLLM -> Ollama) and returns genuine model output; on upstream
# failure it returns an honest 502 (never a fake 200). When unset, /generate is an
# honest auth-gated fixture that proves credential replay only.
UPSTREAM_URL = os.environ.get("TGI_UPSTREAM_URL", "")
UPSTREAM_MODEL = os.environ.get("TGI_UPSTREAM_MODEL", "local-smollm")
UPSTREAM_TIMEOUT = float(os.environ.get("TGI_UPSTREAM_TIMEOUT", "30"))

_start = time.monotonic()
_req_count = 0

# The open lab repo and a second GATED repo that mirrors a private/gated Hub model
# (requires the harvested HF token to resolve files → exercises the client's
# --hub-header path and the real 401 behavior).
MODEL_ID = "acme-tgi-lab"
GATED_MODEL_ID = "acme-tgi-gated"
# A stable resolved commit, echoed back as X-Repo-Commit like the real Hub.
COMMIT_SHA = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678"
# Revisions that resolve: the default branch, the pinned commit, and a release tag.
VALID_REVISIONS = {"main", COMMIT_SHA, "v1.0"}


def _sha(body: bytes) -> str:
    return hashlib.sha256(body).hexdigest()


_WEIGHTS = (
    b"SAFE_TENSORS_LAB_MODEL_CHUNK\n"
    + b"acme-tgi-lab weights are served here for bounded artifact-read verification.\n" * 64
)
_PYTORCH = (
    b"PYTORCH_LAB_CHECKPOINT\n"
    + b"acme-tgi-lab pytorch checkpoint bytes for bounded artifact-read verification.\n" * 48
)

MODEL_FILES = {
    "config.json": json.dumps({
        "architectures": ["LlamaForCausalLM"],
        "model_type": "llama",
        "hidden_size": 128,
        "num_attention_heads": 4,
        "aipostex_lab": "hub-compatible-config",
    }, indent=2).encode(),
    "tokenizer.json": json.dumps({
        "version": "1.0",
        "model": {"type": "BPE"},
        "added_tokens": [{"id": 32000, "content": "<acme_policy>"}],
    }, indent=2).encode(),
    "tokenizer_config.json": json.dumps({
        "model_max_length": 4096,
        "tokenizer_class": "PreTrainedTokenizerFast",
    }, indent=2).encode(),
    "generation_config.json": json.dumps({
        "max_new_tokens": 128,
        "temperature": 0.1,
    }, indent=2).encode(),
    "model.safetensors": _WEIGHTS,
    "pytorch_model.bin": _PYTORCH,
    "model.safetensors.index.json": json.dumps({
        "metadata": {"total_size": len(_WEIGHTS)},
        "weight_map": {"model.embed_tokens.weight": "model.safetensors"},
    }, indent=2).encode(),
    ".gitattributes": (
        b"*.safetensors filter=lfs diff=lfs merge=lfs -text\n"
        b"*.bin filter=lfs diff=lfs merge=lfs -text\n"
    ),
    "README.md": (
        b"---\nlicense: apache-2.0\npipeline_tag: text-generation\n---\n"
        b"# acme-tgi-lab\n\nLab model served by the aipostex TGI gateway "
        b"(Hub-compatible mirror).\n"
    ),
}

# Weight/checkpoint files are LFS-tracked on the real Hub and served via a 302
# redirect to a CDN URL. We mirror that: resolve returns 302 -> /lfs/<oid>.
LFS_FILES = {"model.safetensors", "pytorch_model.bin"}
LFS_STORE = {_sha(MODEL_FILES[_fn]): (MODEL_FILES[_fn], _fn) for _fn in LFS_FILES}


class Handler(BaseHTTPRequestHandler):
    timeout = 10

    def do_GET(self):
        global _req_count
        _req_count += 1
        path = self.path.split("?")[0].rstrip("/") or "/"

        if path == "/health":
            self._json({"status": "ok", "gateway": "tgi", "stage": STAGE})
        elif path == "/info":
            self._json({
                "model_id": MODEL_ID,
                "model_pipeline_tag": "text-generation",
                "sha": "lab-gateway-abc123",
                "version": "1.4.5",
                "max_input_length": 4096,
                "max_total_tokens": 8192,
                "max_batch_total_tokens": 32768,
                "waiting_served_ratio": 0.3,
            })
        elif path == "/v1/models":
            self._json({
                "object": "list",
                "data": [{"id": MODEL_ID, "object": "model", "owned_by": "acme-corp"}],
            })
        elif self._serve_lfs(path):
            return
        elif self._resolve_request(path):
            return
        elif path == "/metrics":
            uptime = time.monotonic() - _start
            body = (
                "# HELP tgi_request_count Total requests\n"
                "# TYPE tgi_request_count counter\n"
                f"tgi_request_count {_req_count}\n"
                "# HELP tgi_queue_size Current queue depth\n"
                "# TYPE tgi_queue_size gauge\n"
                "tgi_queue_size 0\n"
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

    def do_HEAD(self):
        # Real huggingface_hub issues a HEAD to read etag/size/commit before GET.
        global _req_count
        _req_count += 1
        path = self.path.split("?")[0].rstrip("/") or "/"
        if self._serve_lfs(path, head_only=True):
            return
        if self._resolve_request(path, head_only=True):
            return
        if path in ("/health", "/info", "/v1/models", "/metrics"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("X-Aipostex-Gateway", f"tgi-{STAGE}")
            self.end_headers()
            return
        self.send_response(404)
        self.send_header("X-Aipostex-Gateway", f"tgi-{STAGE}")
        self.end_headers()

    def do_POST(self):
        global _req_count
        _req_count += 1
        path = self.path.split("?")[0].rstrip("/") or "/"
        if path != "/generate":
            self._text(404, "Not Found")
            return

        if self.headers.get("Authorization", "") != f"Bearer {REQUIRED_TOKEN}":
            self._json({"error": "authentication required", "stage": STAGE}, status=401)
            return

        prompt, max_tokens = self._read_generate_request()

        if UPSTREAM_URL:
            generated, err = self._proxy_generate(prompt, max_tokens)
            if err is not None:
                # Honest failure — never fake a 200 when real inference is unavailable.
                self._json({"error": "upstream inference unavailable", "detail": err, "stage": STAGE}, status=502)
                return
            self._json({
                "generated_text": generated,
                "gateway": "tgi",
                "stage": STAGE,
                "credential_replay": "accepted",
                "inference": "real",
            })
            return

        # No upstream configured: honest auth-gated fixture (proves credential replay only).
        self._json({
            "generated_text": "[fixture] auth-gated TGI-compatible gateway; set TGI_UPSTREAM_URL for real generation",
            "gateway": "tgi",
            "stage": STAGE,
            "credential_replay": "accepted",
            "inference": "fixture",
        })

    def _read_generate_request(self):
        try:
            length = int(self.headers.get("Content-Length", "0") or "0")
        except ValueError:
            length = 0
        prompt, max_tokens = "", 64
        if length > 0:
            try:
                payload = json.loads(self.rfile.read(length).decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                payload = {}
            if isinstance(payload, dict):
                prompt = str(payload.get("inputs", "") or "")
                params = payload.get("parameters")
                if isinstance(params, dict):
                    try:
                        max_tokens = int(params.get("max_new_tokens", max_tokens))
                    except (TypeError, ValueError):
                        max_tokens = 64
        return prompt, max_tokens

    def _proxy_generate(self, prompt, max_tokens):
        # OpenAI-compatible chat-completions upstream (LiteLLM / Ollama / vLLM speak it).
        req_body = json.dumps({
            "model": UPSTREAM_MODEL,
            "messages": [{"role": "user", "content": prompt or "Summarize the incident-response runbook."}],
            "max_tokens": max_tokens,
        }).encode()
        req = urllib.request.Request(
            UPSTREAM_URL,
            data=req_body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=UPSTREAM_TIMEOUT) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            return None, f"upstream HTTP {exc.code}"
        except Exception as exc:  # surface any upstream failure honestly
            return None, f"upstream error: {exc.__class__.__name__}"
        try:
            content = data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError):
            return None, "upstream returned no completion"
        if not isinstance(content, str) or not content.strip():
            return None, "upstream returned empty completion"
        return content, None

    def _hub_content_type(self, filename):
        if filename.endswith(".json"):
            return "application/json"
        if filename.endswith(".md"):
            return "text/markdown; charset=utf-8"
        if filename.endswith(".safetensors"):
            return "application/octet-stream"
        return "application/octet-stream"

    def _resolve_request(self, path, head_only=False):
        parts = [urllib.parse.unquote(p) for p in path.strip("/").split("/") if p]
        if "resolve" not in parts:
            return False
        idx = parts.index("resolve")
        if idx == 0 or idx + 2 > len(parts):
            return False
        model_id = "/".join(parts[:idx])
        revision = parts[idx + 1]
        filename = "/".join(parts[idx + 2:])

        # Gated repo mirrors a private/gated Hub model: resolving files requires the
        # harvested HF token, else 401 (like the real Hub).
        if model_id == GATED_MODEL_ID:
            if self.headers.get("Authorization", "") != f"Bearer {REQUIRED_TOKEN}":
                self._text(401, "Unauthorized", extra={"WWW-Authenticate": "Bearer realm=\"hf\""})
                return True
        elif model_id != MODEL_ID:
            self._text(404, "Not Found")
            return True

        if revision not in VALID_REVISIONS:
            self._text(404, "Not Found")
            return True

        body = MODEL_FILES.get(filename)
        if body is None:
            self._text(404, "Not Found")
            return True

        # LFS-tracked weights: mirror the Hub's 302 redirect to a CDN-style LFS URL.
        # huggingface_hub and the Go http client follow it (Range carries on same-host).
        if filename in LFS_FILES and not head_only:
            oid = _sha(body)
            self.send_response(302)
            self.send_header("Location", f"/lfs/{oid}")
            self.send_header("X-Repo-Commit", COMMIT_SHA)
            self.send_header("X-Linked-Etag", f'"{oid}"')
            self.send_header("X-Linked-Size", str(len(body)))
            self.send_header("Content-Length", "0")
            self.send_header("X-Aipostex-Gateway", f"tgi-{STAGE}")
            self.end_headers()
            return True

        oid = _sha(body)
        extra = {"ETag": f'"{oid}"', "X-Repo-Commit": COMMIT_SHA}
        if filename in LFS_FILES:
            extra["X-Linked-Etag"] = f'"{oid}"'
            extra["X-Linked-Size"] = str(len(body))
        self._bytes(200, body, content_type=self._hub_content_type(filename),
                    head_only=head_only, extra=extra)
        return True

    def _serve_lfs(self, path, head_only=False):
        parts = [p for p in path.strip("/").split("/") if p]
        if len(parts) != 2 or parts[0] != "lfs":
            return False
        entry = LFS_STORE.get(parts[1])
        if entry is None:
            self._text(404, "Not Found")
            return True
        body, _filename = entry
        oid = parts[1]
        self._bytes(200, body, content_type="application/octet-stream", head_only=head_only,
                    extra={"ETag": f'"{oid}"', "X-Linked-Etag": f'"{oid}"', "X-Linked-Size": str(len(body))})
        return True

    def _json(self, payload, status=200):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Aipostex-Gateway", f"tgi-{STAGE}")
        self.end_headers()
        self.wfile.write(body)

    def _bytes(self, code, body, content_type="application/octet-stream", head_only=False, extra=None):
        status = code
        start = 0
        end = len(body) - 1
        range_header = self.headers.get("Range", "")
        if range_header.startswith("bytes="):
            spec = range_header.removeprefix("bytes=")
            left, _, right = spec.partition("-")
            try:
                start = max(0, int(left)) if left else 0
                end = min(len(body) - 1, int(right)) if right else len(body) - 1
                status = 206
            except ValueError:
                start, end, status = 0, len(body) - 1, code
        chunk = body[start:end + 1] if body else b""
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(chunk)))
        self.send_header("Accept-Ranges", "bytes")
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(body)}")
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.send_header("X-Aipostex-Gateway", f"tgi-{STAGE}")
        self.end_headers()
        if not head_only:
            self.wfile.write(chunk)

    def _text(self, code, body, content_type="text/plain", extra=None):
        encoded = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(encoded)))
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.send_header("X-Aipostex-Gateway", f"tgi-{STAGE}")
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
