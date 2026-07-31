#!/usr/bin/env python3
"""
seed_ray.py — Seed the Ray cluster with jobs containing sensitive runtime env data.

Usage:
    /opt/ailab-ml/venv/bin/python3 seed_ray.py [ray_address] [dashboard_port]

Submits lightweight Ray jobs whose runtime_env.env_vars contain planted
secrets and whose logs include deterministic artifact paths and runtime
markers that aipostex can chain through jobs, job-logs, job-artifacts, and
runtime-env workflows.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.request
import uuid
from pathlib import Path

DEFAULT_RAY_ADDRESS = "localhost"
DEFAULT_DASHBOARD_PORT = "8265"
DEFAULT_TIMEOUT_SECONDS = int(os.environ.get("AIPOSTEX_RAY_SEED_TIMEOUT", "120"))
DEFAULT_POLL_INTERVAL_SECONDS = float(os.environ.get("AIPOSTEX_RAY_SEED_POLL_INTERVAL", "2"))
DEFAULT_METADATA_PATH = Path(os.environ.get("AIPOSTEX_RAY_SEED_METADATA_PATH", "/opt/ray/seed-run.json"))
# Estate subnet prefix (Proxmox base = 172.16.50; GROUP_ID estate K = 172.16.5K; AWS range K
# = 10.0.(K+1)). Threaded in as ESTATE_SUBNET by the seed wrappers so a non-base estate's Ray
# job runtime_env chains point at THIS estate's own MLflow/LiteLLM, not the base subnet.
ESTATE_SUBNET = os.environ.get("ESTATE_SUBNET", "172.16.50")
CHAIN_MLFLOW_URL = os.environ.get("CHAIN_MLFLOW_URL", f"http://{ESTATE_SUBNET}.30:5000")
CHAIN_MLFLOW_USERNAME = os.environ.get("CHAIN_MLFLOW_USERNAME", "ray-pipeline")
CHAIN_MLFLOW_PASSWORD = os.environ.get("CHAIN_MLFLOW_PASSWORD", "MlflowRayChain!2026")
CHAIN_LITELLM_URL = os.environ.get("CHAIN_LITELLM_URL", f"http://{ESTATE_SUBNET}.20:4001")
CHAIN_LITELLM_MASTER_KEY = os.environ.get("CHAIN_LITELLM_MASTER_KEY", "sk-litellm-lab-auth-key-FAKE123")
SUCCESS_STATUS = "SUCCEEDED"
FAILURE_STATUSES = {"FAILED", "STOPPED"}


def normalize_status(status) -> str:
    raw = getattr(status, "name", str(status))
    return raw.split(".")[-1].upper()


def build_job_specs(seed_run_id: str):
    return [
        {
            "name": "churn-model-retraining",
            "entrypoint": (
                "python3 -c \"import os, pathlib, platform; "
                "artifact_dir=pathlib.Path('/tmp/ray-lab-artifacts/churn-model-retraining'); "
                "artifact_dir.mkdir(parents=True, exist_ok=True); "
                "artifact_path=artifact_dir/'runtime-note.txt'; "
                "artifact_path.write_text('aipostex ray artifact\\njob=churn-model-retraining\\nmarker=job-artifacts\\n'); "
                "print('Training pipeline started'); "
                "print(f'ARTIFACT_PATH={artifact_path}'); "
                "print(f'PYTHON_VERSION={platform.python_version()}'); "
                "print(f'WORKDIR={os.getcwd()}'); "
                "print('Done')\""
            ),
            "env_vars": {
                "DATABASE_URL": "postgresql://ml_pipeline:MlP1p3l1n3!Pr0d@db-prod-01.acme.internal:5432/ml_features",
                "REDIS_URL": "redis://:R3d1sMlC4ch3!@redis-ml.acme.internal:6379/0",
                "AWS_ACCESS_KEY_ID": "AKIAFAKERAYML12345678",
                "AWS_SECRET_ACCESS_KEY": "FAKE+RayMLSecret/abcdefghijk1234567890",
                "S3_MODEL_BUCKET": "s3://acme-ml-prod/ray-training/",
                "WANDB_API_KEY": "FAKE_wandb_ray_key_abcdef123456",
                "HF_TOKEN": "hf_FAKE_RayTraining_aBcDeFgHiJkLmNoPqRs",
                "MLFLOW_TRACKING_URI": CHAIN_MLFLOW_URL,
                "MLFLOW_TRACKING_USERNAME": CHAIN_MLFLOW_USERNAME,
                "MLFLOW_TRACKING_PASSWORD": CHAIN_MLFLOW_PASSWORD,
                "LITELLM_API_URL": CHAIN_LITELLM_URL,
                "LITELLM_MASTER_KEY": CHAIN_LITELLM_MASTER_KEY,
            },
            "metadata": {
                "name": "churn-model-retraining",
                "team": "ml-platform",
                "seed": "artifact-path",
                "seed_run_id": seed_run_id,
            },
        },
        {
            "name": "runtime-env-validator",
            "entrypoint": (
                "python3 -c \"import os, pathlib; "
                "artifact_dir=pathlib.Path('/tmp/ray-lab-artifacts/runtime-env-validator'); "
                "artifact_dir.mkdir(parents=True, exist_ok=True); "
                "report=artifact_dir/'runtime-env.txt'; "
                "report.write_text('runtime_env=enabled\\nmarker='+os.environ.get('AIPOSTEX_RUNTIME_ENV_MARKER','missing')+'\\n'); "
                "print('Runtime environment validation'); "
                "print('RUNTIME_ENV_MARKER='+os.environ.get('AIPOSTEX_RUNTIME_ENV_MARKER','missing')); "
                "print('PIP_RUNTIME_HINT='+os.environ.get('AIPOSTEX_RUNTIME_PIP_HINT','unset')); "
                "print('ARTIFACT_PATH='+str(report)); "
                "print('Complete')\""
            ),
            "env_vars": {
                "SNOWFLAKE_URI": "snowflake://ray_svc:R4ySvcSn0w!@acme.snowflakecomputing.com/ML/FEATURES",
                "KAFKA_BOOTSTRAP": "kafka-prod.acme.internal:9092",
                "KAFKA_SASL_PASSWORD": "K4fk4Pr0dP4ss!2024",
                "DATADOG_API_KEY": "FAKE_dd_ray_api_key_abcdef1234567890",
                "SENTRY_DSN": "https://FAKE_sentry_ray_key@sentry.acme.internal/42",
                "VAULT_TOKEN": "hvs.FAKE_ray_vault_token_1234567890abcdef",
                "AIPOSTEX_RUNTIME_ENV_MARKER": "enabled-for-lab",
                "AIPOSTEX_RUNTIME_PIP_HINT": "requests-safe-marker",
            },
            "metadata": {
                "name": "runtime-env-validator",
                "team": "data-engineering",
                "seed": "runtime-env",
                "seed_run_id": seed_run_id,
            },
        },
        {
            "name": "model-serving-canary",
            "entrypoint": (
                "python3 -c \"print('Canary deployment health check'); "
                "print('EXECUTION_MARKER=job-logs-confirmed'); "
                "print('Healthy')\""
            ),
            "env_vars": {
                "MODEL_REGISTRY_URL": CHAIN_MLFLOW_URL,
                "SELDON_API_KEY": "seldon_FAKE_api_key_abcdef1234567890",
                "STRIPE_BILLING_KEY": "sk_live_FAKE_ray_billing_key_123456",
                "PD_ROUTING_KEY": "FAKE_PD_RAY_CANARY_abc123",
            },
            "metadata": {
                "name": "model-serving-canary",
                "team": "ml-ops",
                "seed": "execution-marker",
                "seed_run_id": seed_run_id,
            },
        },
    ]


def submit_job(client, entrypoint, env_vars, metadata=None):
    return client.submit_job(
        entrypoint=entrypoint,
        runtime_env={"env_vars": env_vars},
        metadata=metadata or {},
    )


def submit_seed_jobs(client, job_specs):
    submitted_jobs = []
    for spec in job_specs:
        job_id = submit_job(
            client,
            entrypoint=spec["entrypoint"],
            env_vars=spec["env_vars"],
            metadata=spec["metadata"],
        )
        submitted_jobs.append(
            {
                "name": spec["name"],
                "job_id": job_id,
                "metadata": dict(spec["metadata"]),
            }
        )
    return submitted_jobs


def wait_for_jobs(client, submitted_jobs, timeout_seconds=DEFAULT_TIMEOUT_SECONDS, poll_interval=DEFAULT_POLL_INTERVAL_SECONDS):
    deadline = time.time() + timeout_seconds
    final_statuses = {}

    while time.time() <= deadline:
        pending = []
        saw_failure = False

        for job in submitted_jobs:
            status = normalize_status(client.get_job_status(job["job_id"]))
            final_statuses[job["job_id"]] = status
            if status == SUCCESS_STATUS:
                continue
            if status in FAILURE_STATUSES:
                saw_failure = True
            pending.append(job["job_id"])

        if not pending:
            return True, final_statuses
        if saw_failure:
            return False, final_statuses

        time.sleep(poll_interval)

    return False, final_statuses


def write_seed_metadata(path: Path, dashboard_url: str, seed_run_id: str, submitted_jobs, statuses) -> None:
    payload = {
        "dashboard_url": dashboard_url,
        "seed_run_id": seed_run_id,
        "jobs": [
            {
                "name": job["name"],
                "job_id": job["job_id"],
                "status": statuses.get(job["job_id"], "UNKNOWN"),
                "metadata": job["metadata"],
            }
            for job in submitted_jobs
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def load_job_submission_client(ray_dashboard: str):
    try:
        from ray.job_submission import JobSubmissionClient
    except ImportError:
        print("[!] ray not installed. Run: /opt/ailab-ml/venv/bin/python3 -m pip install 'ray[default]==2.44.1'")
        sys.exit(1)
    return JobSubmissionClient(ray_dashboard)


def chain_seed_present(ray_dashboard: str) -> bool:
    """True if a Ray job already carries the guided-chain credential, so seeding can be a
    no-op instead of a duplicate submission. This makes seeding IDEMPOTENT: the boot-time
    self-heal (chain-seed-boot.sh), reset-wave's re-arm, manual reseed, and provisioning can
    each run without stacking duplicate jobs onto an already-seeded Ray. Checks the same
    /api/jobs/ surface verify-chain uses; fails open (returns False) if Ray isn't reachable."""
    try:
        with urllib.request.urlopen(f"{ray_dashboard}/api/jobs/", timeout=8) as resp:
            body = resp.read().decode("utf-8", "replace")
    except Exception:
        return False
    return bool(CHAIN_MLFLOW_PASSWORD) and CHAIN_MLFLOW_PASSWORD in body and "MLFLOW_TRACKING_URI" in body


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    ray_address = args[0] if len(args) > 0 else DEFAULT_RAY_ADDRESS
    dashboard_port = args[1] if len(args) > 1 else DEFAULT_DASHBOARD_PORT
    ray_dashboard = f"http://{ray_address}:{dashboard_port}"
    seed_run_id = f"ray-seed-{uuid.uuid4().hex[:12]}"

    print(f"[+] Connecting to Ray at {ray_dashboard}...")
    client = load_job_submission_client(ray_dashboard)

    # Idempotency guard: if Ray already carries the guided-chain seed, do nothing. Prevents the
    # boot-time self-heal and reset-wave's re-arm from stacking duplicate jobs (6 instead of 3).
    if chain_seed_present(ray_dashboard):
        print("[=] Ray already carries the guided-chain seed — skipping submission (idempotent)")
        return 0

    print("[*] Submitting Ray jobs with planted secrets and bounded proof artifacts...")
    print(f"[*] Seed run id: {seed_run_id}")

    job_specs = build_job_specs(seed_run_id)
    submitted_jobs = submit_seed_jobs(client, job_specs)

    for job in submitted_jobs:
        print(f"  [+] Job submitted: {job['job_id']} ({job['name']})")

    print("[*] Waiting for jobs to complete...")
    jobs_ok, statuses = wait_for_jobs(client, submitted_jobs)

    for job in submitted_jobs:
        print(f"  {job['name']}: {statuses.get(job['job_id'], 'UNKNOWN')}")

    write_seed_metadata(DEFAULT_METADATA_PATH, ray_dashboard, seed_run_id, submitted_jobs, statuses)
    print(f"[*] Wrote seed metadata to {DEFAULT_METADATA_PATH}")

    if not jobs_ok:
        print("[!] Ray seeding did not reach a successful terminal state for all jobs")
        return 1

    print()
    print("[+] ═══════════════════════════════════════════════")
    print("[+] Ray seeding complete!")
    print(f"[+] Dashboard: {ray_dashboard}")
    print(f"[+] Seed metadata: {DEFAULT_METADATA_PATH}")
    print("[+] ═══════════════════════════════════════════════")
    print()
    print("[+] Sensitive data planted in Ray job runtime envs:")
    print("    - AWS keys: AKIAFAKERAYML12345678")
    print("    - DB creds: postgresql://ml_pipeline:MlP1p3l1n3!Pr0d@...")
    print("    - Snowflake: snowflake://ray_svc:R4ySvcSn0w!@...")
    print("    - Kafka SASL password, Vault token, W&B key, HF token")
    print("    - Stripe billing key, PagerDuty routing key, Datadog key")
    print("    - Sentry DSN, Seldon API key")
    print("    - Artifact paths under /tmp/ray-lab-artifacts/ for job-artifacts validation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
