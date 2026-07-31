#!/usr/bin/env python3
"""Kubeflow Pipelines mock server.

Implements the endpoints that aipostex's kubeflow module probes:
  GET  /pipeline/                                  — dashboard stub (reachability)
  GET  /pipeline/api/v1beta1/pipelines             — list pipelines
  GET  /pipeline/api/v1beta1/runs                  — list runs
  GET  /pipeline/api/v1beta1/experiments           — list experiments
  POST /pipeline/api/v1beta1/runs                  — create run (gated action)
  GET  /notebook/api/namespaces/<ns>/notebooks     — list notebook servers

Seeded data intentionally includes leaked credentials in pipeline parameters
to demonstrate secrets-in-pipeline-config exposure patterns.
"""
import json
import os
import re
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("KUBEFLOW_MOCK_PORT", "9000"))
# API_MODE selects which Kubeflow Pipelines API surface this instance serves:
#   "both" (default) — legacy v1beta1 AND modern v2beta1 (back-compat lab default)
#   "v1"             — only /pipeline/api/v1beta1 (legacy cluster)
#   "v2"             — only /apis/v2beta1 (modern KFP 2.x cluster; v1beta1 paths 404)
API_MODE = os.environ.get("KUBEFLOW_API_MODE", "both").lower()
SERVE_V1 = API_MODE in ("both", "v1")
SERVE_V2 = API_MODE in ("both", "v2")

# ── Seeded data ──────────────────────────────────────────────────────────

PIPELINES = [
    {
        "id": "pipe-001-churn",
        "name": "churn-model-retraining",
        "description": "Weekly retraining pipeline for customer churn prediction model",
        "created_at": "2025-11-15T08:30:00Z",
        "parameters": [
            {"name": "HF_TOKEN", "value": "hf_FAKE_aBcDeFgHiJkLmNoPqRsTuVwXyZ123"},
            {"name": "TRAINING_DATA", "value": "s3://acme-ml-data/churn/weekly/"},
            {"name": "SNOWFLAKE_CONN_STR", "value": "snowflake://ds_team:Sn0wfl4keDs!@acme.snowflakecomputing.com/ANALYTICS/CHURN"},
            {"name": "MODEL_REGISTRY", "value": "http://172.16.50.20:5000"},
        ],
    },
    {
        "id": "pipe-002-fraud",
        "name": "fraud-detection-bert",
        "description": "Fine-tune BERT for transaction fraud classification",
        "created_at": "2025-12-01T14:00:00Z",
        "parameters": [
            {"name": "AWS_ACCESS_KEY_ID", "value": "AKIAFAKEFRAUD12345"},
            {"name": "AWS_SECRET_ACCESS_KEY", "value": "FakeFraudSecret+abcdefghijk12345678"},
            {"name": "TRAINING_EPOCHS", "value": "5"},
            {"name": "BASE_MODEL", "value": "bert-base-uncased"},
        ],
    },
]

RUNS = [
    {
        "id": "run-101",
        "name": "churn-retrain-2026-04-07",
        "status": "Succeeded",
        "pipeline_spec": {"pipeline_id": "pipe-001-churn"},
        "created_at": "2026-04-07T08:30:00Z",
        "finished_at": "2026-04-07T09:15:00Z",
        "resource_references": [
            {"key": {"type": "EXPERIMENT", "id": "exp-default"}},
        ],
    },
    {
        "id": "run-102",
        "name": "churn-retrain-2026-04-14",
        "status": "Running",
        "pipeline_spec": {"pipeline_id": "pipe-001-churn"},
        "created_at": "2026-04-14T08:30:00Z",
        "finished_at": "",
        "resource_references": [
            {"key": {"type": "EXPERIMENT", "id": "exp-default"}},
        ],
    },
    {
        "id": "run-103",
        "name": "fraud-bert-finetune-v3",
        "status": "Succeeded",
        "pipeline_spec": {"pipeline_id": "pipe-002-fraud"},
        "created_at": "2026-03-25T14:00:00Z",
        "finished_at": "2026-03-25T16:45:00Z",
        "resource_references": [
            {"key": {"type": "EXPERIMENT", "id": "exp-prod"}},
        ],
    },
]

EXPERIMENTS = [
    {
        "id": "exp-default",
        "name": "Default",
        "description": "Default experiment",
        "created_at": "2025-10-01T00:00:00Z",
    },
    {
        "id": "exp-prod",
        "name": "Production",
        "description": "Production model experiments",
        "created_at": "2025-10-15T00:00:00Z",
    },
]

NOTEBOOKS = [
    {
        "metadata": {"name": "ds-workbench", "namespace": "kubeflow"},
        "status": {"readyReplicas": 1, "conditions": [{"type": "Running"}]},
        "spec": {"template": {"spec": {"containers": [{"image": "jupyter/scipy-notebook:latest"}]}}},
    },
    {
        "metadata": {"name": "ml-training-nb", "namespace": "kubeflow"},
        "status": {"readyReplicas": 1, "conditions": [{"type": "Running"}]},
        "spec": {"template": {"spec": {"containers": [{"image": "pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime"}]}}},
    },
]

# Track injected runs for the POST endpoint
_injected_runs = []


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0].rstrip("/") or "/"
        params = _parse_qs(self.path)

        # Dashboard stub
        if path == "/pipeline" or path == "/pipeline/":
            body = "<html><head><title>Kubeflow Pipelines</title></head><body><h1>pipeline dashboard</h1></body></html>"
            self._html(body)

        # List pipelines (v1beta1)
        elif SERVE_V1 and path == "/pipeline/api/v1beta1/pipelines":
            page_size = int(params.get("page_size", "50"))
            self._json({
                "pipelines": PIPELINES[:page_size],
                "total_size": len(PIPELINES),
            })

        # List runs (v1beta1)
        elif SERVE_V1 and path == "/pipeline/api/v1beta1/runs":
            page_size = int(params.get("page_size", "50"))
            all_runs = RUNS + _injected_runs
            self._json({
                "runs": all_runs[:page_size],
                "total_size": len(all_runs),
            })

        # List experiments (v1beta1)
        elif SERVE_V1 and path == "/pipeline/api/v1beta1/experiments":
            page_size = int(params.get("page_size", "50"))
            self._json({
                "experiments": EXPERIMENTS[:page_size],
                "total_size": len(EXPERIMENTS),
            })

        # ── KFP 2.x v2beta1 surface (/apis/v2beta1, renamed fields) ──
        elif SERVE_V2 and path == "/apis/v2beta1/pipelines":
            page_size = int(params.get("page_size", "50"))
            self._json({
                "pipelines": [_v2_pipeline(p) for p in PIPELINES[:page_size]],
                "total_size": len(PIPELINES),
            })
        elif SERVE_V2 and path == "/apis/v2beta1/runs":
            page_size = int(params.get("page_size", "50"))
            all_runs = RUNS + _injected_runs
            self._json({
                "runs": [_v2_run(r) for r in all_runs[:page_size]],
                "total_size": len(all_runs),
            })
        elif SERVE_V2 and path == "/apis/v2beta1/experiments":
            page_size = int(params.get("page_size", "50"))
            self._json({
                "experiments": [_v2_experiment(e) for e in EXPERIMENTS[:page_size]],
                "total_size": len(EXPERIMENTS),
            })

        # List notebooks — matches /notebook/api/namespaces/<ns>/notebooks
        elif re.match(r"^/notebook/api/namespaces/[^/]+/notebooks$", path):
            self._json({"items": NOTEBOOKS})

        else:
            self._json_err(404, "Not Found", "resource not found")

    def do_POST(self):
        path = self.path.split("?")[0].rstrip("/")

        if SERVE_V1 and path == "/pipeline/api/v1beta1/runs":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length) if length else b"{}"
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                data = {}
            run_name = data.get("name", "injected-run")
            new_run = {
                "id": f"run-injected-{int(time.time())}",
                "name": run_name,
                "status": "Pending",
                "pipeline_spec": data.get("pipeline_spec", {}),
                "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "finished_at": "",
            }
            _injected_runs.append(new_run)
            self._json({"run": new_run})
        elif SERVE_V2 and path == "/apis/v2beta1/runs":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length) if length else b"{}"
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                data = {}
            new_run = {
                "id": f"run-injected-{int(time.time())}",
                "name": data.get("display_name", data.get("name", "injected-run")),
                "status": "Pending",
                "pipeline_spec": {"pipeline_id": (data.get("pipeline_version_reference") or {}).get("pipeline_id", "")},
                "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "finished_at": "",
            }
            _injected_runs.append(new_run)
            self._json({"run_id": new_run["id"], "display_name": new_run["name"], "state": "PENDING"})
        else:
            self._json_err(404, "Not Found", "resource not found")

    # ── helpers ──────────────────────────────────────────
    def _json(self, payload, code=200):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        # Real KFP sets these defensive headers.
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Cache-Control", "no-cache, private")
        self.end_headers()
        self.wfile.write(body)

    def _json_err(self, code, error, message):
        # Real KFP returns JSON error bodies, not plain text.
        self._json({"error": error, "message": message, "code": code}, code=code)

    def _html(self, body):
        encoded = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _text(self, code, body):
        encoded = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, fmt, *args):
        pass


def _v2_state(status):
    """Map v1beta1 run status to the KFP 2.x run state enum."""
    return {
        "Succeeded": "SUCCEEDED",
        "Running": "RUNNING",
        "Pending": "PENDING",
        "Failed": "FAILED",
    }.get(status, (status or "").upper())


def _v2_pipeline(p):
    """Remap a seeded pipeline to the KFP v2beta1 shape (pipeline_id/display_name).
    Parameters are preserved so the planted secrets-in-config findings still surface."""
    return {
        "pipeline_id": p["id"],
        "display_name": p["name"],
        "description": p.get("description", ""),
        "created_at": p.get("created_at", ""),
        "parameters": p.get("parameters", []),
    }


def _v2_run(r):
    return {
        "run_id": r["id"],
        "display_name": r["name"],
        "state": _v2_state(r.get("status", "")),
        "created_at": r.get("created_at", ""),
        "finished_at": r.get("finished_at", ""),
        "pipeline_version_reference": {
            "pipeline_id": r.get("pipeline_spec", {}).get("pipeline_id", ""),
        },
    }


def _v2_experiment(e):
    return {
        "experiment_id": e["id"],
        "display_name": e["name"],
        "description": e.get("description", ""),
        "created_at": e.get("created_at", ""),
    }


def _parse_qs(url):
    """Minimal query-string parser (no urllib dependency)."""
    if "?" not in url:
        return {}
    qs = url.split("?", 1)[1]
    params = {}
    for pair in qs.split("&"):
        if "=" in pair:
            k, v = pair.split("=", 1)
            params[k] = v
    return params


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
