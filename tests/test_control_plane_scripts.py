from __future__ import annotations

import json
import shlex
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEPLOY_SCRIPT = ROOT / "lab-scripts" / "deploy-all.sh"
VERIFY_LAB_SCRIPT = ROOT / "lab-scripts" / "verify-lab.sh"
VERIFY_AIPOSTEX_SCRIPT = ROOT / "lab-scripts" / "attack-box" / "verify-aipostex.sh"
SNAPSHOT_SCRIPT = ROOT / "lab-scripts" / "lab-snapshots.sh"


def run_bash(command: str):
    return subprocess.run(
        ["bash", "-lc", command],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def test_deploy_parse_args_accepts_phase_after_skip_base():
    result = run_bash(
        f"source {shlex.quote(str(DEPLOY_SCRIPT))} && "
        "parse_args --skip-base --phase 2 && "
        'printf "%s|%s" "$PHASE" "$SKIP_BASE"'
    )

    assert result.returncode == 0
    assert result.stdout == "2|true"


def test_deploy_parse_args_rejects_unknown_argument():
    result = run_bash(
        f"source {shlex.quote(str(DEPLOY_SCRIPT))}; "
        "parse_args foo"
    )

    assert result.returncode == 2
    assert "Unknown argument: foo" in result.stderr


def test_verify_lab_failures_return_nonzero():
    result = run_bash(
        f"source {shlex.quote(str(VERIFY_LAB_SCRIPT))}; "
        "PASS=0; FAIL=1; WARN=0; "
        "print_final_status_and_exit"
    )

    assert result.returncode == 1
    assert "Some services are down" in result.stdout


def test_snapshot_decline_is_nonzero(tmp_path):
    # lab-snapshots.sh runs a `qm listsnapshot` pre-flight before prompting; stub a
    # fake qm so the snapshot reads as present and we reach the interactive decline path.
    qm = tmp_path / "qm"
    qm.write_text('#!/bin/bash\n[ "$1" = "listsnapshot" ] && echo "demo-snapshot"\nexit 0\n')
    qm.chmod(0o755)

    result = run_bash(
        f"export PATH={shlex.quote(str(tmp_path))}:$PATH; "
        f"printf 'n\\n' | bash {shlex.quote(str(SNAPSHOT_SCRIPT))} restore demo-snapshot"
    )

    assert result.returncode == 3
    assert "Aborted by user" in result.stdout


def test_verify_aipostex_splits_read_only_and_active_preparation():
    text = VERIFY_AIPOSTEX_SCRIPT.read_text(encoding="utf-8")

    assert 'run_operator_layer() {\n    section "operator"\n    prepare_read_only_artifacts' in text
    assert 'run_contract_layer() {\n    section "contract"\n    prepare_read_only_artifacts' in text
    assert (
        'run_active_layer() {\n    section "active"\n    prepare_read_only_artifacts\n    prepare_active_artifacts'
        in text
    )

    readonly_block = text.split("prepare_read_only_artifacts() {", 1)[1].split("prepare_active_artifacts() {", 1)[0]
    active_block = text.split("prepare_active_artifacts() {", 1)[1].split("run_operator_layer() {", 1)[0]

    assert "--force-exploit" not in readonly_block
    assert "--force-exploit" in active_block
    assert '--yes restore "$snapshot_name"' in text
    assert '--yes delete "$snapshot_name"' in text


def test_verify_aipostex_prefers_current_seeded_ray_job(tmp_path):
    jobs_path = tmp_path / "ray-jobs.json"
    jobs_path.write_text(
        json.dumps(
            {
                "findings": [
                    {
                        "metadata": {
                            "name": "runtime-env-validator",
                            "job_id": "old-job",
                            "seed_run_id": "old-seed",
                        }
                    },
                    {
                        "metadata": {
                            "name": "runtime-env-validator",
                            "job_id": "current-job",
                            "seed_run_id": "current-seed",
                        }
                    },
                ]
            }
        ),
        encoding="utf-8",
    )

    result = run_bash(
        f"source {shlex.quote(str(VERIFY_AIPOSTEX_SCRIPT))}; "
        "RAY_SEED_RUN_ID=current-seed; "
        f"printf '%s' \"$(select_seeded_ray_job_id {shlex.quote(str(jobs_path))})\""
    )

    assert result.returncode == 0
    assert result.stdout == "current-job"
