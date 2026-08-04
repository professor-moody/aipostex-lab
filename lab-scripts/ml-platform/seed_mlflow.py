#!/usr/bin/env python3
"""
seed_mlflow.py — Populate MLflow with deterministic experiment, run, and registry data.

Run after MLflow is running on the ml-platform VM:
    /opt/ailab-ml/venv/bin/python3 seed_mlflow.py [host] [port]

Creates 3 experiments with runs, metrics, parameters, artifact trees, and
registered model versions that pivot back into real run artifacts. The script is
idempotent enough for repeated lab deploys: it reuses seeded runs and model
versions instead of creating unbounded duplicates.
"""

from __future__ import annotations

import json
import os
import random
import struct
import sys
import tempfile
import time
from pathlib import Path

DEFAULT_HOST = "localhost"
DEFAULT_PORT = 5000
TRACKING_URI = ""
SEED_VERSION = "3.0"
CHAIN_HF_TOKEN = "hf_FAKE_aBcDeFgHiJkLmNoPqRsTuVwXyZ123"
# Estate subnet prefix (base = 172.16.50; GROUP_ID estate K = 172.16.5K; AWS range K =
# 10.0.(K+1)) — threaded in as ESTATE_SUBNET by the seed wrapper so a non-base estate's MLflow
# registry chain points at THIS estate's own TGI gateway, not the base subnet.
ESTATE_SUBNET = os.environ.get("ESTATE_SUBNET", "172.16.50")
CHAIN_TGI_GATEWAY = os.environ.get("CHAIN_TGI_GATEWAY", f"http://{ESTATE_SUBNET}.40:8180")


def make_safetensors(n_bytes: int, seed: int, tensor_name: str = "classifier.weight") -> bytes:
    """Return a VALID minimal .safetensors blob so `mlflow bulk-download` steals real
    model bytes, not just the MLmodel card. Layout: 8-byte little-endian header length,
    JSON header, then F32 tensor data. Deterministic per `seed` for idempotent reseeds.
    Kept small (~1 MB) — the tool's --per-file-bytes cap (256 KB) truncates it anyway;
    the point is that a real weights file exists in the model/ artifact subtree."""
    n_floats = max(1, n_bytes // 4)
    header = {
        tensor_name: {"dtype": "F32", "shape": [n_floats], "data_offsets": [0, n_floats * 4]},
        "__metadata__": {"format": "pt", "framework": "transformers"},
    }
    header_bytes = json.dumps(header).encode("utf-8")
    return struct.pack("<Q", len(header_bytes)) + header_bytes + random.Random(seed).randbytes(n_floats * 4)


mlflow = None
MlflowException = Exception
MlflowClient = None
client = None


def require_mlflow():
    global mlflow, MlflowException, MlflowClient
    if mlflow is not None and MlflowClient is not None:
        return

    try:
        import mlflow as mlflow_module
        from mlflow.exceptions import MlflowException as mlflow_exception
        from mlflow.tracking import MlflowClient as mlflow_client
    except ImportError:
        print("[!] mlflow not installed. Run: /opt/ailab-ml/venv/bin/python3 -m pip install mlflow")
        sys.exit(1)

    mlflow = mlflow_module
    MlflowException = mlflow_exception
    MlflowClient = mlflow_client


EXPERIMENTS = [
    {
        "name": "churn-prediction-v2",
        "runs": [
            {
                "seed_key": "churn-xgboost-baseline",
                "run_name": "xgboost-baseline",
                "params": {
                    "model_type": "xgboost",
                    "learning_rate": "0.05",
                    "max_depth": "8",
                    "n_estimators": "500",
                    "training_data": "postgresql://ds_readonly:DsR34d0nly!Pr0d@db-prod-01.acme.internal:5432/acme_prod",
                    "feature_store": "redis://feature-store.acme.internal:6379/2",
                },
                "metrics": {"auc": 0.872, "precision": 0.81, "recall": 0.79, "f1": 0.80, "loss": 0.312},
                "tags": {"engineer": "jane.doe@acme.corp", "dataset_version": "v3.2"},
                "artifacts": {
                    "model/MLmodel": "artifact_path: model\nflavors:\n  python_function:\n    loader_module: mlflow.pyfunc.model\n",
                    "model/config.json": json.dumps(
                        {
                            "model_path": "s3://acme-ml-models/churn-prediction-v2/",
                            "serving_endpoint": "seldon.acme.internal:8080/churn",
                            "monitoring_dashboard": "grafana.acme.internal/d/churn-model",
                        },
                        indent=2,
                    )
                    + "\n",
                    "deployment/serving.json": json.dumps(
                        {
                            "rollout": "baseline",
                            "canary_percentage": 10,
                            "feature_store": "redis://feature-store.acme.internal:6379/2",
                        },
                        indent=2,
                    )
                    + "\n",
                },
            },
            {
                "seed_key": "churn-lightgbm-production",
                "run_name": "lightgbm-production",
                "params": {
                    "model_type": "lightgbm",
                    "learning_rate": "0.03",
                    "num_leaves": "64",
                    "n_estimators": "800",
                    "training_data": "s3://acme-ml-data/churn/train_v3.parquet",
                    "feature_store": "redis://feature-store.acme.internal:6379/2",
                },
                "metrics": {"auc": 0.891, "precision": 0.84, "recall": 0.82, "f1": 0.83, "loss": 0.287},
                "tags": {"engineer": "jane.doe@acme.corp", "dataset_version": "v3.2", "promoted": "true"},
                "artifacts": {
                    "model/MLmodel": "artifact_path: model\nsignature: churn-score\n",
                    "model/config.json": json.dumps(
                        {
                            "model_path": "s3://acme-ml-models/churn-prediction-v2/",
                            "serving_endpoint": "seldon.acme.internal:8080/churn",
                            "monitoring_dashboard": "grafana.acme.internal/d/churn-model",
                            "registry_name": "acme-churn-ensemble",
                        },
                        indent=2,
                    )
                    + "\n",
                    "deployment/runtime.env": "MODEL_VARIANT=production\nFEATURE_TTL=300\n",
                    "prompts/system.txt": "You are the churn scoring model for ACME customer ops.\n",
                },
            },
            {
                "seed_key": "churn-xgboost-legacy",
                "run_name": "xgboost-legacy",
                "params": {
                    "model_type": "xgboost",
                    "learning_rate": "0.01",
                    "max_depth": "12",
                    "n_estimators": "1200",
                    "training_data": "snowflake://ds_team:Sn0wfl4keDs!@acme.snowflakecomputing.com/ANALYTICS/CHURN",
                },
                "metrics": {"auc": 0.865, "precision": 0.79, "recall": 0.83, "f1": 0.81, "loss": 0.328},
                "tags": {"engineer": "alex.rivera@acme.corp", "dataset_version": "v3.1"},
                "artifacts": {
                    "model/MLmodel": "artifact_path: model\nsignature: legacy-score\n",
                    "deployment/serving.json": json.dumps(
                        {
                            "registry_shadow": "acme-churn-ensemble",
                            "migration": "legacy-snowflake",
                        },
                        indent=2,
                    )
                    + "\n",
                },
            },
        ],
    },
    {
        "name": "fraud-detection-bert",
        "runs": [
            {
                "seed_key": "fraud-bert-stage",
                "run_name": "bert-stage",
                "params": {
                    "model_type": "bert-base-uncased",
                    "epochs": "5",
                    "batch_size": "32",
                    "learning_rate": "2e-5",
                    "training_data": "s3://acme-ml-data/fraud/labeled_transactions_v2.parquet",
                    "gpu_instance": "p4d.24xlarge",
                },
                "metrics": {"accuracy": 0.967, "precision": 0.94, "recall": 0.91, "f1": 0.925, "loss": 0.089},
                "tags": {"engineer": "bob.wilson@acme.corp", "gpu_cost_per_run": "$524"},
                "artifacts": {
                    "model/MLmodel": "artifact_path: model\nframework: transformers\nflavors:\n  transformers:\n    task: text-classification\n    model_binary: model.safetensors\n",
                    "model/model.safetensors": make_safetensors(786_432, 0xB0B0),
                    "deployment/deployment_config.json": json.dumps(
                        {
                            "model_registry": "s3://acme-ml-models/fraud-detection-bert/",
                            "serving_endpoint": "seldon.acme.internal:8080/fraud-scoring",
                            "kafka_input": "kafka-prod.acme.internal:9092/raw-transactions",
                            "pagerduty_key": "FAKE_PD_FRAUD_abc123",
                        },
                        indent=2,
                    )
                    + "\n",
                },
            },
            {
                "seed_key": "fraud-distilbert-candidate",
                "run_name": "distilbert-candidate",
                "params": {
                    "model_type": "distilbert-base-uncased",
                    "epochs": "8",
                    "batch_size": "64",
                    "learning_rate": "3e-5",
                    "training_data": "s3://acme-ml-data/fraud/labeled_transactions_v2.parquet",
                    "gpu_instance": "g5.2xlarge",
                },
                "metrics": {"accuracy": 0.958, "precision": 0.92, "recall": 0.89, "f1": 0.905, "loss": 0.112},
                "tags": {"engineer": "bob.wilson@acme.corp", "gpu_cost_per_run": "$87"},
                "artifacts": {
                    "model/MLmodel": "artifact_path: model\nframework: transformers\nvariant: candidate\n",
                    "model/tokenizer.json": "{\"type\":\"WordPiece\",\"vocab_size\":30522}\n",
                    "deployment/runtime.env": "TOKENIZER_CACHE=/opt/models/tokenizers\n",
                },
            },
            {
                "seed_key": "fraud-bert-production",
                "run_name": "bert-production",
                "params": {
                    "model_type": "bert-base-uncased",
                    "epochs": "10",
                    "batch_size": "16",
                    "learning_rate": "1e-5",
                    "training_data": "s3://acme-ml-data/fraud/labeled_transactions_v3.parquet",
                    "gpu_instance": "p4d.24xlarge",
                    "aws_account": "123456789012",
                },
                "metrics": {"accuracy": 0.974, "precision": 0.96, "recall": 0.93, "f1": 0.945, "loss": 0.071},
                "tags": {"engineer": "bob.wilson@acme.corp", "gpu_cost_per_run": "$1,048", "promoted": "true"},
                "artifacts": {
                    "model/MLmodel": "artifact_path: model\nframework: transformers\nvariant: prod\nflavors:\n  transformers:\n    task: text-classification\n    model_binary: model.safetensors\n",
                    "model/model.safetensors": make_safetensors(1_310_720, 0xB0B1),
                    "deployment/deployment_config.json": json.dumps(
                        {
                            "model_registry": "s3://acme-ml-models/fraud-detection-bert/",
                            "serving_endpoint": "seldon.acme.internal:8080/fraud-scoring",
                            "kafka_input": "kafka-prod.acme.internal:9092/raw-transactions",
                            "pagerduty_key": "FAKE_PD_FRAUD_abc123",
                        },
                        indent=2,
                    )
                    + "\n",
                    "prompts/system.txt": "Flag high-confidence payment fraud with concise evidence.\n",
                },
            },
        ],
    },
    {
        "name": "customer-embedding-model",
        "runs": [
            {
                "seed_key": "embed-minilm-stage",
                "run_name": "minilm-stage",
                "params": {
                    "model_type": "sentence-transformers/all-MiniLM-L6-v2",
                    "fine_tune_epochs": "3",
                    "triplet_margin": "0.5",
                    "training_data": "postgresql://ds_readonly:DsR34d0nly!Pr0d@db-prod-01.acme.internal:5432/acme_prod",
                    "embedding_dim": "384",
                    "hf_tgi_token": CHAIN_HF_TOKEN,
                    "tgi_gateway": CHAIN_TGI_GATEWAY,
                },
                "metrics": {"triplet_loss": 0.234, "recall_at_10": 0.78, "mrr": 0.65},
                "tags": {"engineer": "priya.patel@acme.corp", "use_case": "product-recommendations", "chain_role": "hf-token-source"},
                "artifacts": {
                    "model/MLmodel": "artifact_path: model\nframework: sentence-transformers\n",
                    "deployment/deployment_config.json": json.dumps(
                        {
                            "vector_db": "qdrant://172.16.50.30:6333/product-embeddings",
                            "model_artifacts": "s3://acme-ml-models/customer-embeddings/minilm-v2/",
                            "serving_gateway": CHAIN_TGI_GATEWAY,
                        },
                        indent=2,
                    )
                    + "\n",
                },
            },
            {
                "seed_key": "embed-bge-production",
                "run_name": "bge-production",
                "params": {
                    "model_type": "BAAI/bge-large-en-v1.5",
                    "fine_tune_epochs": "5",
                    "contrastive_lr": "1e-5",
                    "training_data": "snowflake://ds_team:Sn0wfl4keDs!@acme.snowflakecomputing.com/ANALYTICS/CUSTOMERS",
                    "embedding_dim": "1024",
                    "qdrant_collection": "product-embeddings",
                    "qdrant_host": "172.16.50.30:6333",
                    "hf_tgi_token": CHAIN_HF_TOKEN,
                    "tgi_gateway": CHAIN_TGI_GATEWAY,
                },
                "metrics": {"triplet_loss": 0.187, "recall_at_10": 0.86, "mrr": 0.74},
                "tags": {"engineer": "priya.patel@acme.corp", "use_case": "product-recommendations", "promoted": "true", "chain_role": "hf-token-source"},
                "artifacts": {
                    "model/MLmodel": "artifact_path: model\nframework: sentence-transformers\nvariant: prod\n",
                    "deployment/deployment_config.json": json.dumps(
                        {
                            "vector_db": "qdrant://172.16.50.30:6333/product-embeddings",
                            "model_artifacts": "s3://acme-ml-models/customer-embeddings/bge-large-v1/",
                            "serving_gateway": CHAIN_TGI_GATEWAY,
                        },
                        indent=2,
                    )
                    + "\n",
                    "model/model_card.md": "# ACME Product Embeddings\n\nDeployed to product recommendations.\n",
                },
            },
        ],
    },
]

REGISTERED_MODELS = [
    {
        "name": "acme-churn-ensemble",
        "description": "Registered churn scoring model used by the customer retention API.",
        "versions": [
            {
                "seed_key": "acme-churn-ensemble-v1",
                "run_seed_key": "churn-xgboost-baseline",
                "artifact_path": "model",
                "stage": "Staging",
            },
            {
                "seed_key": "acme-churn-ensemble-v2",
                "run_seed_key": "churn-lightgbm-production",
                "artifact_path": "model",
                "stage": "Production",
            },
        ],
    },
    {
        "name": "acme-fraud-bert",
        "description": "Registered fraud scoring model promoted by ML Ops.",
        "versions": [
            {
                "seed_key": "acme-fraud-bert-v1",
                "run_seed_key": "fraud-bert-stage",
                "artifact_path": "model",
                "stage": "Staging",
            },
            {
                "seed_key": "acme-fraud-bert-v2",
                "run_seed_key": "fraud-bert-production",
                "artifact_path": "model",
                "stage": "Production",
            },
        ],
    },
]


def wait_for_mlflow() -> None:
    for attempt in range(15):
        try:
            client.search_experiments()
            print("[+] Connected to MLflow")
            return
        except Exception as exc:
            print(f"    Waiting for MLflow... attempt {attempt + 1}/15 ({exc})")
            time.sleep(3)
    print("[!] Failed to connect to MLflow after 15 attempts")
    sys.exit(1)


def purge_tool_artifacts() -> None:
    """Remove aipostex scan artifacts so every reseed is deterministic.

    The aipostex tool writes proof records into MLflow during rehearsals:
      - `mlflow tamper-proof` reuses the FIXED experiment `aipostex-tamper-proof`
        (GetOrCreateExperiment), appending a fresh run each time.
      - verify/e2e runs create TIMESTAMPED `aipostex-proof-<unixtime>` experiments.
    Neither is part of the seeded corpus, but they accumulate across waves and —
    because MLflow's runs/search orders by recency — eventually crowd the seeded
    chain runs (the customer-embedding-model HF token) out of a `runs --limit N`
    window, silently breaking the signature credential chain. A disk-snapshot
    rollback alone can't fix this if the snapshot was baked with pollution, so purge
    here, on every reseed, keyed strictly to the tool's own `aipostex-` namespace.

    Timestamped proof experiments never collide (unique names) → soft-delete wholesale.
    The fixed `aipostex-tamper-proof` MUST survive (deleting it would collide on the
    next tamper-proof GetOrCreate), so only its accumulated runs are cleared.
    """
    removed_exp = 0
    cleared_runs = 0
    for experiment in client.search_experiments():
        name = experiment.name or ""
        if name.startswith("aipostex-proof-"):
            try:
                client.delete_experiment(experiment.experiment_id)
                removed_exp += 1
            except Exception as exc:  # noqa: BLE001 — best-effort hygiene, never fatal
                print(f"    [!] Could not purge experiment {name}: {exc}")
        elif name == "aipostex-tamper-proof":
            try:
                for run in client.search_runs([experiment.experiment_id], max_results=1000):
                    client.delete_run(run.info.run_id)
                    cleared_runs += 1
            except Exception as exc:  # noqa: BLE001
                print(f"    [!] Could not clear runs in {name}: {exc}")
    if removed_exp or cleared_runs:
        print(f"[*] Purged {removed_exp} proof experiment(s), cleared {cleared_runs} tamper run(s)")


def ensure_experiment(name: str) -> str:
    experiment = client.get_experiment_by_name(name)
    if experiment is None:
        experiment_id = client.create_experiment(name)
        experiment = client.get_experiment(experiment_id)
    return experiment.experiment_id


def _write_artifact(root: Path, relative_path: str, content) -> None:
    path = root / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(content, (bytes, bytearray)):
        path.write_bytes(content)          # binary artifacts (e.g. model.safetensors weights)
    else:
        path.write_text(content, encoding="utf-8")


def log_artifact_tree(artifacts) -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        root = Path(tmp_dir)
        for relative_path, content in artifacts.items():
            _write_artifact(root, relative_path, content)
        mlflow.log_artifacts(str(root))


def run_has_artifact(run_id: str, artifact_path: str) -> bool:
    try:
        return any(e.path == artifact_path for e in client.list_artifacts(run_id, os.path.dirname(artifact_path)))
    except Exception:
        return False


def backfill_missing_artifacts(run_id: str, artifacts) -> list:
    """Log artifacts a previously-seeded run is missing (e.g. model weights added to the
    spec after the run was first created). Idempotent — only uploads absent paths."""
    missing = {p: c for p, c in artifacts.items() if not run_has_artifact(run_id, p)}
    if not missing:
        return []
    with tempfile.TemporaryDirectory() as tmp_dir:
        root = Path(tmp_dir)
        for relative_path, content in missing.items():
            _write_artifact(root, relative_path, content)
        client.log_artifacts(run_id, str(root))
    return sorted(missing)


def extract_tags(entity):
    if entity is None:
        return {}
    if hasattr(entity, "data") and getattr(entity.data, "tags", None) is not None:
        return entity.data.tags or {}
    return getattr(entity, "tags", {}) or {}


def run_matches_seed_version(run, seed_key: str, seed_version: str = SEED_VERSION) -> bool:
    tags = extract_tags(run)
    return tags.get("lab_seed_key") == seed_key and tags.get("lab_seed_version") == seed_version


def model_version_matches_seed_version(version, seed_key: str, seed_version: str = SEED_VERSION) -> bool:
    tags = extract_tags(version)
    return tags.get("lab_seed_key") == seed_key and tags.get("lab_seed_version") == seed_version


def find_seeded_run(experiment_id: str, seed_key: str):
    runs = client.search_runs(
        [experiment_id],
        filter_string=(
            f"tags.lab_seed_key = '{seed_key}' "
            f"and tags.lab_seed_version = '{SEED_VERSION}'"
        ),
        max_results=1,
    )
    return runs[0] if runs else None


def ensure_run(experiment_id: str, spec: dict[str, object]) -> str:
    existing = find_seeded_run(experiment_id, spec["seed_key"])
    if existing is not None:
        run_id = existing.info.run_id
        # Backfill: a run seeded before this spec gained new params/tags would
        # otherwise be reused stale (e.g. missing the chain hf_tgi_token). Params
        # are immutable per-key, so only log keys absent from the existing run;
        # tags are mutable, so always refresh them.
        existing_params = existing.data.params
        added = [k for k in spec["params"] if k not in existing_params]
        for k in added:
            client.log_param(run_id, k, spec["params"][k])
        tags = dict(spec["tags"])
        tags["lab_seed_key"] = spec["seed_key"]
        tags["lab_seed_version"] = SEED_VERSION
        for k, v in tags.items():
            client.set_tag(run_id, k, v)
        backfilled = backfill_missing_artifacts(run_id, spec["artifacts"])
        if added or backfilled:
            notes = []
            if added:
                notes.append(f"params: {', '.join(added)}")
            if backfilled:
                notes.append(f"artifacts: {', '.join(backfilled)}")
            print(f"    [~] Updated seeded run {spec['seed_key']} ({run_id}) — {'; '.join(notes)}")
        else:
            print(f"    [=] Reusing seeded run {spec['seed_key']} ({run_id})")
        return run_id

    with mlflow.start_run(experiment_id=experiment_id, run_name=spec["run_name"]) as active_run:
        mlflow.log_params(spec["params"])
        mlflow.log_metrics(spec["metrics"])
        tags = dict(spec["tags"])
        tags["lab_seed_key"] = spec["seed_key"]
        tags["lab_seed_version"] = SEED_VERSION
        mlflow.set_tags(tags)
        log_artifact_tree(spec["artifacts"])
        run_id = active_run.info.run_id
    print(f"    [+] Created seeded run {spec['seed_key']} ({run_id})")
    return run_id


def ensure_registered_model(name: str, description: str) -> None:
    try:
        client.get_registered_model(name)
    except MlflowException:
        client.create_registered_model(name)
    try:
        client.update_registered_model(name=name, description=description)
    except Exception:
        pass


def existing_version_for_seed(model_name: str, seed_key: str):
    try:
        versions = client.search_model_versions(f"name='{model_name}'")
    except MlflowException:
        return None
    for version in versions:
        if model_version_matches_seed_version(version, seed_key):
            return version
    return None


def ensure_model_version(model_name: str, run_id: str, artifact_path: str, stage: str, seed_key: str):
    version = existing_version_for_seed(model_name, seed_key)
    if version is None:
        source = f"runs:/{run_id}/{artifact_path}"
        version = client.create_model_version(name=model_name, source=source, run_id=run_id)
        client.set_model_version_tag(model_name, version.version, "lab_seed_key", seed_key)
        client.set_model_version_tag(model_name, version.version, "lab_seed_version", SEED_VERSION)
        print(f"    [+] Created model version {model_name} v{version.version} from {source}")
    else:
        print(f"    [=] Reusing model version {model_name} v{version.version} ({seed_key})")

    try:
        client.transition_model_version_stage(
            name=model_name,
            version=version.version,
            stage=stage,
            archive_existing_versions=False,
        )
    except Exception:
        pass
    return version


def main(argv=None):
    global client, TRACKING_URI
    require_mlflow()

    args = list(sys.argv[1:] if argv is None else argv)
    host = args[0] if len(args) > 0 else DEFAULT_HOST
    port = int(args[1]) if len(args) > 1 else DEFAULT_PORT
    TRACKING_URI = f"http://{host}:{port}"

    print(f"[*] Connecting to MLflow at {TRACKING_URI}...")
    mlflow.set_tracking_uri(TRACKING_URI)
    client = MlflowClient()

    wait_for_mlflow()
    purge_tool_artifacts()

    run_ids_by_seed_key: dict[str, str] = {}

    for experiment in EXPERIMENTS:
        print(f"[*] Seeding experiment: {experiment['name']}")
        experiment_id = ensure_experiment(experiment["name"])
        for run_spec in experiment["runs"]:
            run_id = ensure_run(experiment_id, run_spec)
            run_ids_by_seed_key[run_spec["seed_key"]] = run_id

    print("[*] Seeding registered models...")
    for model_spec in REGISTERED_MODELS:
        ensure_registered_model(model_spec["name"], model_spec["description"])
        for version_spec in model_spec["versions"]:
            run_id = run_ids_by_seed_key[version_spec["run_seed_key"]]
            ensure_model_version(
                model_name=model_spec["name"],
                run_id=run_id,
                artifact_path=version_spec["artifact_path"],
                stage=version_spec["stage"],
                seed_key=version_spec["seed_key"],
            )

    print()
    print("[+] ═══════════════════════════════════════════════")
    print("[+] MLflow seeding complete!")
    print(f"[+] Tracking URI: {TRACKING_URI}")
    print("[+] ═══════════════════════════════════════════════")
    print()

    experiments = client.search_experiments()
    for experiment in experiments:
        if experiment.name == "Default":
            continue
        runs = client.search_runs([experiment.experiment_id], max_results=100)
        print(f"    Experiment: {experiment.name}")
        print(f"      Runs: {len(runs)}")

    print()
    for model_spec in REGISTERED_MODELS:
        versions = client.search_model_versions(f"name='{model_spec['name']}'")
        print(f"    Registered model: {model_spec['name']}")
        print(f"      Versions: {len(versions)}")

    print()
    print("[+] Sensitive data planted in MLflow:")
    print("    - PostgreSQL connection strings with credentials")
    print("    - Snowflake connection strings with credentials")
    print("    - S3 bucket paths for model artifacts")
    print("    - Registry models with version sources pointing to runs:/ artifacts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
