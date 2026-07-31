#!/usr/bin/env python3
"""Lightweight W&B GraphQL mock for aipostex lab validation.

This fixture intentionally mirrors the real W&B public API shape used by the
official client: metadata is fetched through POST /graphql, run config and
summaryMetrics are JSON strings, and projects/artifacts are Relay-style
connections. Legacy REST routes are not implemented so tool-shaped clients fail.
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 8444

VIEWER = {
    "id": "user-lab-wandb-admin",
    "name": "lab-wandb-admin",
    "username": "lab-wandb-admin",
    "email": "ml-admin@acme.internal",
    "entity": "acme-ml-team",
    "teams": {"edges": [{"node": {"name": "acme-ml-team"}}, {"node": {"name": "acme-platform"}}]},
    "admin": True,
}

PROJECTS = [
    {
        "id": "proj-churn-001",
        "name": "churn-prediction",
        "entityName": "acme-ml-team",
        "createdAt": "2026-04-01T00:00:00Z",
        "isBenchmark": False,
    },
    {
        "id": "proj-fraud-002",
        "name": "fraud-detection",
        "entityName": "acme-ml-team",
        "createdAt": "2026-04-02T00:00:00Z",
        "isBenchmark": False,
    },
]

RUNS = {
    "churn-prediction": [
        {
            "id": "run-churn-daily-001",
            "name": "churn-daily-retrain",
            "displayName": "churn-daily-retrain",
            "state": "finished",
            "createdAt": "2026-04-10T08:00:00Z",
            "tags": ["production", "daily"],
            "config": {
                "learning_rate": {"value": 0.001, "desc": None},
                "epochs": {"value": 50, "desc": None},
                "batch_size": {"value": 128, "desc": None},
                "WANDB_API_KEY": {"value": "FAKE_wandb_server_key_abcdef123456", "desc": None},
                "OPENAI_API_KEY": {"value": "sk-proj-FAKE-wandb-openai-key-9876543210", "desc": None},
                "DATABASE_URL": {
                    "value": "postgresql://wandb_svc:W4ndbSvcPr0d!@db-prod-01.acme.internal:5432/ml_metrics",
                    "desc": None,
                },
            },
            "summaryMetrics": {
                "accuracy": 0.934,
                "f1_score": 0.912,
                "best_epoch": 42,
            },
        },
        {
            "id": "run-churn-weekly-002",
            "name": "churn-weekly-eval",
            "displayName": "churn-weekly-eval",
            "state": "finished",
            "createdAt": "2026-04-07T12:00:00Z",
            "tags": ["evaluation"],
            "config": {
                "eval_split": {"value": 0.2, "desc": None},
                "HF_TOKEN": {"value": "hf_FAKE_WandbRun_aBcDeFgHiJkLmNoPq", "desc": None},
                "AWS_ACCESS_KEY_ID": {"value": "AKIAFAKEWANDB12345678", "desc": None},
                "AWS_SECRET_ACCESS_KEY": {"value": "FakeWandbSecretKey+abcdefghij1234567890", "desc": None},
            },
            "summaryMetrics": {"auc_roc": 0.961, "precision": 0.923},
        },
    ],
    "fraud-detection": [
        {
            "id": "run-fraud-online-001",
            "name": "fraud-online-scoring",
            "displayName": "fraud-online-scoring",
            "state": "running",
            "createdAt": "2026-04-11T06:30:00Z",
            "tags": ["production", "realtime"],
            "config": {
                "model_type": {"value": "xgboost", "desc": None},
                "threshold": {"value": 0.85, "desc": None},
                "ANTHROPIC_API_KEY": {"value": "sk-ant-FAKE-wandb-anthropic-key-abcdef1234", "desc": None},
                "password": {
                    "value": "fraud-model-service:Fr4udM0d3lS3rv!@scoring-api.acme.internal",
                    "desc": None,
                },
            },
            "summaryMetrics": {"transactions_scored": 142857, "alerts_fired": 23},
        },
    ],
}

ARTIFACTS = {
    "churn-prediction": {
        "model": [
            {
                "id": "art-churn-model-001",
                "name": "churn-ensemble-v3",
                "description": "Production churn ensemble (XGBoost + LightGBM)",
                "type": {"name": "model"},
            },
        ],
        "dataset": [
            {
                "id": "art-churn-data-001",
                "name": "customer-features-2026q1",
                "description": "Q1 2026 customer feature store snapshot",
                "type": {"name": "dataset"},
            },
        ],
    },
    "fraud-detection": {
        "model": [
            {
                "id": "art-fraud-model-001",
                "name": "fraud-xgb-realtime-v2",
                "description": "Real-time fraud scoring XGBoost model",
                "type": {"name": "model"},
            },
        ],
        "dataset": [
            {
                "id": "art-fraud-data-001",
                "name": "transaction-features-latest",
                "description": "Latest transaction feature vectors",
                "type": {"name": "dataset"},
            },
        ],
    },
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0].rstrip("/") or "/"
        if path == "/healthz":
            self._text(200, "wandb-local 0.42.0")
            return
        self._text(404, "Not Found")

    def do_POST(self):
        path = self.path.split("?")[0].rstrip("/") or "/"
        if path != "/graphql":
            self._text(404, "Not Found")
            return

        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            # Real W&B GraphQL returns HTTP 200 with errors in the body (not 400).
            self._json(200, {"errors": [{"message": "invalid JSON", "extensions": {"code": "GRAPHQL_PARSE_FAILED"}}]})
            return

        query = payload.get("query", "")
        variables = payload.get("variables") or {}
        self._json(200, {"data": self._dispatch(query, variables)})

    def _dispatch(self, query, variables):
        if "viewer" in query:
            return {"viewer": VIEWER}

        if "models" in query:
            return {
                "models": {
                    "edges": [{"node": {**p, "__typename": "Project"}} for p in PROJECTS],
                    "pageInfo": {"endCursor": None, "hasNextPage": False},
                }
            }

        if "runs" in query:
            project = variables.get("project", "")
            nodes = []
            for run in RUNS.get(project, []):
                encoded = dict(run)
                encoded["config"] = json.dumps(run["config"])
                encoded["summaryMetrics"] = json.dumps(run["summaryMetrics"])
                encoded["__typename"] = "Run"
                nodes.append(encoded)
            return {
                "project": {
                    "internalId": f"internal-{project}",
                    "runCount": len(nodes),
                    "runs": {
                        "edges": [{"node": n, "cursor": n["id"]} for n in nodes],
                        "pageInfo": {"endCursor": None, "hasNextPage": False},
                    },
                }
            }

        if "artifactCollections" in query:
            project = variables.get("project", "")
            art_type = variables.get("type", "model")
            arts = ARTIFACTS.get(project, {}).get(art_type, [])
            return {
                "project": {
                    "artifactType": {
                        "artifactCollections": {
                            "totalCount": len(arts),
                            "edges": [{"node": {**a, "__typename": "ArtifactCollection"}} for a in arts],
                            "pageInfo": {"endCursor": None, "hasNextPage": False},
                        }
                    }
                }
            }

        return {}

    def _json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
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
