from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
SEED_RAY_PATH = ROOT / "lab-scripts" / "ml-platform" / "seed_ray.py"
SEED_MLFLOW_PATH = ROOT / "lab-scripts" / "ml-platform" / "seed_mlflow.py"


def load_module(module_name: str, path: Path):
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


seed_ray = load_module("seed_ray_module", SEED_RAY_PATH)
seed_mlflow = load_module("seed_mlflow_module", SEED_MLFLOW_PATH)


class FakeRayClient:
    def __init__(self, status_sequences):
        self.status_sequences = {job_id: list(statuses) for job_id, statuses in status_sequences.items()}
        self.last_status = {job_id: statuses[-1] for job_id, statuses in self.status_sequences.items()}

    def get_job_status(self, job_id):
        sequence = self.status_sequences[job_id]
        if sequence:
            self.last_status[job_id] = sequence.pop(0)
        return self.last_status[job_id]


def test_wait_for_jobs_succeeds_when_all_jobs_finish():
    client = FakeRayClient(
        {
            "job-1": ["PENDING", "RUNNING", "SUCCEEDED"],
            "job-2": ["RUNNING", "SUCCEEDED"],
        }
    )
    submitted_jobs = [{"job_id": "job-1"}, {"job_id": "job-2"}]

    ok, statuses = seed_ray.wait_for_jobs(client, submitted_jobs, timeout_seconds=1, poll_interval=0)

    assert ok is True
    assert statuses == {"job-1": "SUCCEEDED", "job-2": "SUCCEEDED"}


def test_wait_for_jobs_fails_on_terminal_failure():
    client = FakeRayClient(
        {
            "job-1": ["RUNNING", "FAILED"],
            "job-2": ["SUCCEEDED"],
        }
    )
    submitted_jobs = [{"job_id": "job-1"}, {"job_id": "job-2"}]

    ok, statuses = seed_ray.wait_for_jobs(client, submitted_jobs, timeout_seconds=1, poll_interval=0)

    assert ok is False
    assert statuses["job-1"] == "FAILED"


def test_write_seed_metadata_records_seed_run_id(tmp_path):
    metadata_path = tmp_path / "seed-run.json"
    submitted_jobs = [
        {
            "name": "runtime-env-validator",
            "job_id": "job-123",
            "metadata": {"seed_run_id": "ray-seed-abc"},
        }
    ]

    seed_ray.write_seed_metadata(
        metadata_path,
        "http://localhost:8265",
        "ray-seed-abc",
        submitted_jobs,
        {"job-123": "SUCCEEDED"},
    )

    payload = json.loads(metadata_path.read_text(encoding="utf-8"))
    assert payload["seed_run_id"] == "ray-seed-abc"
    assert payload["jobs"][0]["status"] == "SUCCEEDED"


def test_mlflow_seed_version_matching_uses_lab_seed_version():
    matching_run = SimpleNamespace(data=SimpleNamespace(tags={"lab_seed_key": "seed-a", "lab_seed_version": "3.0"}))
    stale_run = SimpleNamespace(data=SimpleNamespace(tags={"lab_seed_key": "seed-a", "lab_seed_version": "2.0"}))
    matching_version = SimpleNamespace(tags={"lab_seed_key": "seed-b", "lab_seed_version": "3.0"})
    stale_version = SimpleNamespace(tags={"lab_seed_key": "seed-b", "lab_seed_version": "2.0"})

    assert seed_mlflow.run_matches_seed_version(matching_run, "seed-a") is True
    assert seed_mlflow.run_matches_seed_version(stale_run, "seed-a") is False
    assert seed_mlflow.model_version_matches_seed_version(matching_version, "seed-b") is True
    assert seed_mlflow.model_version_matches_seed_version(stale_version, "seed-b") is False
