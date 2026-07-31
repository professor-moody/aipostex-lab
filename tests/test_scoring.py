from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCORE_PATH = ROOT / "lab-scripts" / "scoring" / "score.py"
MANIFEST_PATH = ROOT / "lab-scripts" / "scoring" / "manifest.json"


def load_score_module():
    spec = importlib.util.spec_from_file_location("lab_score", SCORE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


score = load_score_module()
MANIFEST = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
SCORING_DOC_PATH = ROOT / "docs" / "scoring" / "scoring.md"

ALL_STRICT_SERVICES = [
    {"service": "langserve", "target": "172.16.50.40:8090"},
    {"service": "streamlit", "target": "172.16.50.40:8501"},
    {"service": "hf-tgi", "target": "172.16.50.40:8180"},
    {"service": "hf-tei", "target": "172.16.50.20:8181"},
    {"service": "vllm", "target": "172.16.50.20:8182"},
    {"service": "bentoml", "target": "172.16.50.20:3333"},
    {"service": "torchserve", "target": "172.16.50.20:8081"},
    {"service": "triton", "target": "172.16.50.20:8500"},
    {"service": "pgvector", "target": "172.16.50.30:5432"},
    {"service": "wandb", "target": "172.16.50.20:8444"},
    {"service": "kubeflow", "target": "172.16.50.20:9000"},
    {"service": "tfserving", "target": "172.16.50.20:8501"},
]


def count_sensitive_findings(manifest):
    total = 0
    for host_data in manifest["hosts"].values():
        for items in host_data.get("findings", {}).values():
            total += len(items)
    return total


def test_manifest_invariants():
    # 170 = 169 baseline + the looted LiteLLM master key planted in Ray runtime_env
    # (turns the gateway chain into a true credential chain; see chain-config.sh / seed_ray.py).
    assert count_sensitive_findings(MANIFEST) == 170
    assert len(MANIFEST["service_inventory"]) == 12


def test_rrr_matrix_flags_over_claims_and_reports_uncovered():
    matrix = score.load_rrr_matrix(str(MANIFEST_PATH.parent))
    assert matrix is not None, "rrr_matrix.json should live next to the manifest"
    output = {
        "findings": [
            # detection fixture over-claiming a real exploit payoff -> violation
            {"title": "Triton", "metadata": {"module": "triton", "action": "models", "landed": "execution-confirmed"}},
            # credential-gate read over-claiming execution -> violation
            {"title": "MLflow enum", "metadata": {"module": "mlflow", "action": "enum", "landed": "execution-confirmed"}},
            # legitimate state-change claim -> allowed
            {"title": "HF generate", "metadata": {"module": "huggingface", "action": "generate", "landed": "execution-confirmed"}},
            # unlisted surface -> uncovered, not failed
            {"title": "Other", "metadata": {"module": "frobnicate", "action": "xyz", "landed": "execution-confirmed"}},
        ]
    }
    result = score.evaluate_rrr(output, matrix)
    assert result["violations_count"] == 2, result
    flagged = {v["surface"].get("module") for v in result["violations"]}
    assert {"triton", "mlflow"} <= flagged, result
    assert "frobnicate:xyz" in result["uncovered"], result


def test_rrr_matrix_passes_correct_tiers():
    matrix = score.load_rrr_matrix(str(MANIFEST_PATH.parent))
    output = {
        "findings": [
            {"metadata": {"module": "triton", "action": "models", "landed": "reachable"}},
            {"metadata": {"module": "mlflow", "action": "enum", "landed": "read-confirmed"}},
            {"metadata": {"module": "huggingface", "action": "generate", "landed": "execution-confirmed"}},
        ]
    }
    result = score.evaluate_rrr(output, matrix)
    assert result["violations_count"] == 0, result


def test_litellm_realinference_contract_requires_credential_gate():
    # The real-inference contract must require a proven credential gate (control-probe),
    # so an open :4000 relay-test (credential_gated false) gets no credit.
    name = "LiteLLM relay-test real-inference contract"
    base = {
        "module": "litellm", "action": "proxy-chain", "provider": "x",
        "coherence_score": 80, "stage": "impact", "landed": "execution-confirmed",
    }

    def status(credential_gated):
        out = {"findings": [{"title": "t", "metadata": {**base, "credential_gated": credential_gated}}]}
        results = score.evaluate_contracts(out, MANIFEST)["results"]
        return next(r["status"] for r in results if r["name"] == name)

    assert status(True) == "passed"
    assert status(False) != "passed"  # open path: no match -> skipped -> no credit


def test_rrr_uncovered_elevated_vs_reachable():
    matrix = score.load_rrr_matrix(str(MANIFEST_PATH.parent))
    elevated = {"findings": [{"metadata": {"module": "frobnicate", "action": "xyz", "landed": "execution-confirmed"}}]}
    r1 = score.evaluate_rrr(elevated, matrix)
    assert r1["violations_count"] == 0  # uncovered, not an over-claim
    assert r1["uncovered_elevated_count"] == 1  # but it claims above reachable -> flagged
    reachable = {"findings": [{"metadata": {"module": "frobnicate", "action": "xyz", "landed": "reachable"}}]}
    r2 = score.evaluate_rrr(reachable, matrix)
    assert r2["uncovered_elevated_count"] == 0  # uncovered-but-reachable is benign
    assert len(r2["uncovered"]) == 1


def test_strict_matching_rejects_incidental_text_only():
    item = {
        "value": "secret-value-1234",
        "host": "172.16.50.20",
        "hostname": "ailab-ml",
        "source": "chromadb",
    }
    findings = [
        {
            "title": "Unstructured note",
            "metadata": {
                "evidence": "chromadb mentioned 172.16.50.20 and secret-value-1234 in a blob",
            },
        }
    ]
    assert not score.search_in_output_strict(findings, item)


def test_strict_matching_accepts_structured_host_and_source():
    item = {
        "value": "secret-value-1234",
        "host": "172.16.50.20",
        "hostname": "ailab-ml",
        "source": "chromadb",
    }
    findings = [
        {
            "target": "172.16.50.20:8000",
            "module": "chromadb",
            "metadata": {
                "summary": "secret-value-1234",
            },
        }
    ]
    assert score.search_in_output_strict(findings, item)


def test_service_inventory_scoring_counts_discovered_services():
    output = {"findings": ALL_STRICT_SERVICES}
    service_report = score.score_service_inventory(output, MANIFEST, strict=True)
    assert service_report["total_expected"] == 12
    assert service_report["total_found"] == 12
    assert service_report["total_missed"] == 0


def test_service_inventory_missing_service_fails_strict_cli(tmp_path):
    output_path = tmp_path / "partial-output.json"
    output_path.write_text(
        json.dumps(
            {
                "findings": [
                    {"service": "langserve", "target": "172.16.50.40:8090"},
                    {"service": "streamlit", "target": "172.16.50.40:8501"},
                ]
            }
        ),
        encoding="utf-8",
    )

    result = subprocess.run(
        [sys.executable, str(SCORE_PATH), str(output_path), "--strict", "--threshold", "0"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    assert "Service inventory" in result.stdout


def test_strict_false_positives_fail_cli(tmp_path):
    noise_collection = next(iter(next(iter(MANIFEST["noise_collections"].values()))))
    output_path = tmp_path / "noise-output.json"
    output_path.write_text(
        json.dumps(
            {
                "findings": [
                    *ALL_STRICT_SERVICES,
                    {"collection": noise_collection, "target": "172.16.50.30:6333"},
                ]
            }
        ),
        encoding="utf-8",
    )

    result = subprocess.run(
        [sys.executable, str(SCORE_PATH), str(output_path), "--strict", "--threshold", "0"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    assert "false positive" in result.stdout.lower()


def test_strict_cli_passes_without_false_positives(tmp_path):
    output_path = tmp_path / "strict-pass.json"
    output_path.write_text(
        json.dumps({"findings": ALL_STRICT_SERVICES}),
        encoding="utf-8",
    )

    result = subprocess.run(
        [sys.executable, str(SCORE_PATH), str(output_path), "--strict", "--threshold", "0"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "no false positives" in result.stdout.lower()


def test_strict_cli_fails_with_only_documented_detection_only_subset(tmp_path):
    output_path = tmp_path / "strict-five-only.json"
    output_path.write_text(
        json.dumps({"findings": ALL_STRICT_SERVICES[:5]}),
        encoding="utf-8",
    )

    result = subprocess.run(
        [sys.executable, str(SCORE_PATH), str(output_path), "--strict", "--threshold", "0"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    assert "service inventory coverage missed 7 expected service(s)" in result.stdout.lower()


def test_strict_report_uses_neutral_service_inventory_wording(tmp_path):
    output_path = tmp_path / "strict-report-wording.json"
    output_path.write_text(
        json.dumps({"findings": ALL_STRICT_SERVICES}),
        encoding="utf-8",
    )

    result = subprocess.run(
        [sys.executable, str(SCORE_PATH), str(output_path), "--strict", "--threshold", "0"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "service inventory coverage" in result.stdout.lower()
    assert "detection-only services" not in result.stdout.lower()


def test_default_scoring_report_is_non_spoiler_and_verbose_reveals_details(tmp_path):
    secret_value = MANIFEST["hosts"]["172.16.50.10"]["findings"]["api_keys"][0]["value"]
    output_path = tmp_path / "empty-output.json"
    output_path.write_text(json.dumps({"findings": []}), encoding="utf-8")

    default_result = subprocess.run(
        [sys.executable, str(SCORE_PATH), str(output_path), "--threshold", "0"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    verbose_result = subprocess.run(
        [sys.executable, str(SCORE_PATH), str(output_path), "--threshold", "0", "--verbose"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert default_result.returncode == 0
    assert secret_value not in default_result.stdout
    assert "Missed Items:" not in default_result.stdout
    assert verbose_result.returncode == 0
    assert secret_value in verbose_result.stdout
    assert "Missed Items:" in verbose_result.stdout


def test_scoring_docs_describe_eight_required_services():
    text = SCORING_DOC_PATH.read_text(encoding="utf-8")

    assert "12 strict-required services" in text
    assert "5 `detection-only` services" in text
    assert "7 additional `exploitable` services" in text


def test_contract_evaluation_reports_passed_failed_and_skipped():
    manifest = {
        "contract_expectations": [
            {
                "name": "passing expectation",
                "match": {"module": "ray", "action": "job-artifacts"},
                "require_metadata": ["workflow", "evidence"],
                "markers": ["/tmp/ray-lab-artifacts/"],
            },
            {
                "name": "failing expectation",
                "match": {"module": "mlflow", "action": "tamper-proof"},
                "require_metadata": ["workflow", "stage"],
                "markers": ["tamper-proof"],
            },
            {
                "name": "skipped expectation",
                "match": {"module": "jupyter", "action": "pip-proof"},
                "require_metadata": ["workflow"],
            },
        ]
    }
    output = {
        "findings": [
            {
                "module": "ray",
                "action": "job-artifacts",
                "metadata": {
                    "workflow": {"recommendations": []},
                    "evidence": {"path": "/tmp/ray-lab-artifacts/example"},
                },
            },
            {
                "module": "mlflow",
                "action": "tamper-proof",
                "metadata": {
                    "workflow": {"recommendations": []},
                },
            },
        ]
    }

    results = score.evaluate_contracts(output, manifest)

    assert results["passed"] == 1
    assert results["failed"] == 1
    assert results["skipped"] == 1
