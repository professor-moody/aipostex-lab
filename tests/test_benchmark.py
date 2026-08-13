"""Tests for the precision benchmark's classification logic.

The benchmark's value depends entirely on classifying a run correctly, so the pure
functions — what counts as a success claim, and how a pair scores — are tested
directly. The subprocess plumbing is not exercised here; that is what the live run
against the lab does.
"""

import importlib.util
import pathlib

import pytest

SPEC_PATH = pathlib.Path(__file__).resolve().parents[1] / "lab-scripts" / "scoring" / "benchmark.py"
spec = importlib.util.spec_from_file_location("benchmark", SPEC_PATH)
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


def finding(landed, stage="access", title="t"):
    return {"title": title, "severity": "High", "metadata": {"landed": landed, "stage": stage}}


def test_success_claims_counts_only_grades_above_reachable():
    findings = [
        finding("reachable"),
        finding("read-confirmed"),
        finding("influenced"),
        finding("execution-confirmed"),
        finding("takeover-capable"),
    ]
    claims = benchmark.success_claims(findings)
    assert len(claims) == 4
    assert "reachable" not in {c["landed"] for c in claims}


def test_success_claims_ignores_missing_or_unknown_metadata():
    assert benchmark.success_claims([{"title": "no metadata"}]) == []
    assert benchmark.success_claims([{"metadata": {}}]) == []
    assert benchmark.success_claims([{"metadata": {"landed": "unknown"}}]) == []


def test_success_claims_is_case_insensitive():
    assert len(benchmark.success_claims([finding("READ-CONFIRMED")])) == 1


CASE = {
    "id": "x", "module": "m", "verb": ["m", "enum"],
    "vulnerable": {"target": "http://vuln", "label": "open"},
    "hardened": {"target": "http://hard", "label": "authed"},
    "expect_claim_on_vulnerable": True,
}


def result(findings):
    return {"exit_code": 2, "timeout": False, "findings": findings, "stderr": ""}


def test_classify_ideal_run_is_tp_and_tn():
    r = benchmark.classify(CASE, result([finding("read-confirmed")]), result([finding("reachable")]))
    assert (r["tp"], r["fp"], r["fn"], r["tn"]) == (1, 0, 0, 1)


def test_classify_claim_against_hardened_twin_is_a_false_positive():
    r = benchmark.classify(CASE, result([finding("read-confirmed")]), result([finding("read-confirmed")]))
    assert r["fp"] == 1
    assert r["tn"] == 0


def test_classify_missing_claim_on_vulnerable_is_a_false_negative():
    r = benchmark.classify(CASE, result([finding("reachable")]), result([]))
    assert (r["tp"], r["fn"]) == (0, 1)


def test_classify_records_both_sides_for_evidence():
    r = benchmark.classify(CASE, result([finding("influenced", title="got in")]), result([]))
    assert r["vulnerable"]["claims"][0]["title"] == "got in"
    assert r["hardened"]["claims"] == []
    assert r["command"] == "m enum"


def test_aggregate_computes_precision_recall_and_fp_rate():
    results = [
        {"module": "a", "tp": 1, "fp": 0, "fn": 0, "tn": 1},
        {"module": "a", "tp": 1, "fp": 1, "fn": 0, "tn": 0},
        {"module": "b", "tp": 0, "fp": 0, "fn": 1, "tn": 1},
    ]
    agg = benchmark.aggregate(results)
    a = agg["per_module"]["a"]
    assert a["precision"] == pytest.approx(2 / 3)
    assert a["recall"] == 1.0
    assert a["false_positive_rate_on_hardened"] == pytest.approx(0.5)
    b = agg["per_module"]["b"]
    assert b["recall"] == 0.0
    assert b["precision"] is None  # nothing was claimed, so precision is undefined
    o = agg["overall"]
    assert (o["tp"], o["fp"], o["fn"], o["tn"]) == (2, 1, 1, 2)


def test_every_case_declares_a_distinct_id_and_both_sides():
    ids = [c["id"] for c in benchmark.CASES]
    assert len(ids) == len(set(ids)), "case ids must be unique"
    for c in benchmark.CASES:
        assert c["vulnerable"]["target"] != c["hardened"]["target"], c["id"]
        assert c["module"] and c["verb"]


def test_markdown_report_states_the_coverage_limit():
    report = {
        "tool_version": "vtest",
        "results": [benchmark.classify(CASE, result([finding("read-confirmed")]), result([]))],
        "aggregate": benchmark.aggregate([{"module": "m", "tp": 1, "fp": 0, "fn": 0, "tn": 1}]),
    }
    md = benchmark.render_markdown(report)
    assert "Coverage limits" in md
    assert "not extrapolated" in md
    assert "vtest" in md


def test_enumeration_cases_are_not_scored_on_the_exposed_side():
    """An enum verb that stays at `reachable` on an open service is correct, not a miss."""
    case = dict(CASE, expect_claim_on_vulnerable=False)
    r = benchmark.classify(case, result([finding("reachable")]), result([]))
    assert r["kind"] == "enumeration"
    assert (r["tp"], r["fn"]) == (0, 0), "exposed side must not be scored for enumeration verbs"
    assert r["tn"] == 1, "the hardened side is still scored"


def test_enumeration_case_still_catches_a_false_positive():
    case = dict(CASE, expect_claim_on_vulnerable=False)
    r = benchmark.classify(case, result([]), result([finding("read-confirmed")]))
    assert r["fp"] == 1


def test_access_cases_are_labelled_as_such():
    r = benchmark.classify(CASE, result([finding("read-confirmed")]), result([]))
    assert r["kind"] == "access"


def test_corpus_contains_both_kinds():
    kinds = {c["expect_claim_on_vulnerable"] for c in benchmark.CASES}
    assert kinds == {True, False}, "corpus should measure both access and enumeration verbs"
