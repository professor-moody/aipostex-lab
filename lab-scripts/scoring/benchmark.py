#!/usr/bin/env python3
"""
benchmark.py — measure aipostex precision against paired vulnerable / hardened targets.

score.py answers "did the tool find the planted data?" (coverage / recall). It cannot
answer "does the tool claim success when there is nothing to find?", because a
coverage manifest has no negative side. This benchmark supplies that half.

The lab runs several services as *pairs*: an exposed instance and a hardened twin
that enforces authentication. The same verb is run against both. On the exposed
instance a success claim is correct; on the hardened twin the same claim is a false
positive, because the tool did not get in.

Unit of measurement — a SUCCESS CLAIM
    A finding whose `landed` grade is above `reachable` asserts the tool achieved
    something: read-confirmed, influenced, execution-confirmed, or takeover-capable.
    Findings graded recon/reachable are observations ("the port answered"), not
    claims, and are never counted either way.

Classification
    vulnerable target,  claim present  -> TP  (real weakness, correctly claimed)
    vulnerable target,  no claim       -> FN  (real weakness, missed)
    hardened twin,      claim present  -> FP  (claimed access it never got)
    hardened twin,      no claim       -> TN  (correct restraint)

Reported metrics are per case and per module: precision TP/(TP+FP), recall
TP/(TP+FN), and the false-positive rate over hardened controls.

Coverage is deliberately narrow and is reported as such: only modules with a
hardened twin can be measured this way. The numbers describe those modules and are
never extrapolated to the rest of the tool.

Usage:
    python3 benchmark.py --binary ~/aipostex --output-dir ~/bench-out
    python3 benchmark.py --binary ~/aipostex --output-dir ~/bench-out --markdown report.md
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

# Grades that assert the tool achieved something. Anything at or below "reachable"
# is an observation about the target, not a claim about access.
CLAIM_GRADES = {
    "read-confirmed",
    "influenced",
    "execution-confirmed",
    "takeover-capable",
}

# The frozen benchmark corpus. Each case runs one verb against an exposed instance
# and its hardened twin.
#
# `expect_claim_on_vulnerable` distinguishes the two kinds of verb, and the
# distinction is load-bearing:
#
#   True  — an ACCESS verb. Succeeding means reading or changing something, so on
#           the exposed side it must produce a success claim; silence there is a
#           real false negative.
#   False — an ENUMERATION verb. Listing what an open service exposes is correctly
#           graded `reachable` (an observation, not a claim of access), so the
#           exposed side is not scored. The hardened side still is: an enumeration
#           verb that claims access against an authenticated service is a false
#           positive like any other.
#
# Which verbs fall in which class was determined by running them, not assumed.
CASES = [
    # ── access verbs: scored on both sides ──
    {
        "id": "k8s-rbac-probe",
        "module": "k8s",
        "verb": ["k8s", "rbac-probe", "--insecure"],
        "vulnerable": {"target": "https://172.16.50.50:6443", "label": "anon-open k3s"},
        "hardened": {"target": "https://172.16.50.50:6444", "label": "401-enforced k3s"},
        "expect_claim_on_vulnerable": True,
    },
    {
        "id": "k8s-secret-read",
        "module": "k8s",
        "verb": ["k8s", "secret-read", "--all-namespaces", "--insecure", "--force-exploit"],
        "vulnerable": {"target": "https://172.16.50.50:6443", "label": "anon-open k3s"},
        "hardened": {"target": "https://172.16.50.50:6444", "label": "401-enforced k3s"},
        "expect_claim_on_vulnerable": True,
    },
    {
        "id": "litellm-config-extract",
        "module": "litellm",
        "verb": ["litellm", "config-extract"],
        "vulnerable": {"target": "http://172.16.50.20:4000", "label": "open proxy"},
        "hardened": {"target": "http://172.16.50.20:4001", "label": "key-enforced proxy"},
        "expect_claim_on_vulnerable": True,
    },
    {
        "id": "mlflow-runs",
        "module": "mlflow",
        "verb": ["mlflow", "runs"],
        "vulnerable": {"target": "http://172.16.50.20:5000", "label": "open tracking server"},
        "hardened": {"target": "http://172.16.50.30:5000", "label": "Basic-auth gateway"},
        "expect_claim_on_vulnerable": True,
    },
    {
        "id": "a2a-task-send",
        "module": "a2a",
        "verb": ["a2a", "task-send", "--message", "benchmark probe", "--force-exploit"],
        "vulnerable": {"target": "http://172.16.50.40:8100", "label": "unauthenticated agent"},
        "hardened": {"target": "http://172.16.50.40:8102", "label": "auth-enforcing agent"},
        "expect_claim_on_vulnerable": True,
    },
    # ── enumeration verbs: hardened side scored; exposed side must stay at
    #    `reachable`, which is the honest grade for "the service answered" ──
    {
        "id": "k8s-enum",
        "module": "k8s",
        "verb": ["k8s", "enum", "--insecure"],
        "vulnerable": {"target": "https://172.16.50.50:6443", "label": "anon-open k3s"},
        "hardened": {"target": "https://172.16.50.50:6444", "label": "401-enforced k3s"},
        "expect_claim_on_vulnerable": False,
    },
    {
        "id": "litellm-enum",
        "module": "litellm",
        "verb": ["litellm", "enum"],
        "vulnerable": {"target": "http://172.16.50.20:4000", "label": "open proxy"},
        "hardened": {"target": "http://172.16.50.20:4001", "label": "key-enforced proxy"},
        "expect_claim_on_vulnerable": False,
    },
    {
        "id": "mlflow-experiments",
        "module": "mlflow",
        "verb": ["mlflow", "experiments"],
        "vulnerable": {"target": "http://172.16.50.20:5000", "label": "open tracking server"},
        "hardened": {"target": "http://172.16.50.30:5000", "label": "Basic-auth gateway"},
        "expect_claim_on_vulnerable": False,
    },
]


def run_case(binary: str, verb: list[str], target: str, out_path: str, timeout: int) -> dict:
    """Run one verb against one target, returning the parsed findings and exit code.

    A non-zero exit is not an error here: aipostex exits 2 when it has findings and
    3/4 on partial failure, and a hardened target legitimately produces an error
    path. What matters is what it claimed, so the output is parsed either way.
    """
    cmd = [binary, *verb, "--target", target, "--format", "json", "-o", out_path]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        code = proc.returncode
        stderr = proc.stderr[-2000:]
    except subprocess.TimeoutExpired:
        return {"exit_code": None, "timeout": True, "findings": [], "stderr": "timeout"}

    findings = []
    if os.path.exists(out_path):
        try:
            with open(out_path, encoding="utf-8") as fh:
                data = json.load(fh)
            findings = data.get("findings", []) if isinstance(data, dict) else data
        except (json.JSONDecodeError, OSError) as exc:
            stderr = f"{stderr}\n[benchmark] could not parse {out_path}: {exc}"
    return {"exit_code": code, "timeout": False, "findings": findings, "stderr": stderr}


def success_claims(findings: list) -> list:
    """Return the findings that assert the tool achieved something."""
    claims = []
    for f in findings:
        meta = f.get("metadata") or {}
        landed = str(meta.get("landed", "")).lower()
        if landed in CLAIM_GRADES:
            claims.append(
                {
                    "title": f.get("title", ""),
                    "landed": landed,
                    "stage": str(meta.get("stage", "")),
                    "severity": f.get("severity", ""),
                }
            )
    return claims


def classify(case: dict, vuln_result: dict, hard_result: dict) -> dict:
    """Score one case into TP/FN (exposed side) and FP/TN (hardened side)."""
    vuln_claims = success_claims(vuln_result["findings"])
    hard_claims = success_claims(hard_result["findings"])

    tp = fn = fp = tn = 0
    if case["expect_claim_on_vulnerable"]:
        if vuln_claims:
            tp = 1
        else:
            fn = 1
    if hard_claims:
        fp = 1
    else:
        tn = 1

    return {
        "id": case["id"],
        "module": case["module"],
        "kind": "access" if case["expect_claim_on_vulnerable"] else "enumeration",
        "command": " ".join(case["verb"]),
        "vulnerable": {
            "target": case["vulnerable"]["target"],
            "label": case["vulnerable"]["label"],
            "exit_code": vuln_result["exit_code"],
            "finding_count": len(vuln_result["findings"]),
            "claims": vuln_claims,
        },
        "hardened": {
            "target": case["hardened"]["target"],
            "label": case["hardened"]["label"],
            "exit_code": hard_result["exit_code"],
            "finding_count": len(hard_result["findings"]),
            "claims": hard_claims,
        },
        "tp": tp,
        "fn": fn,
        "fp": fp,
        "tn": tn,
    }


def aggregate(results: list) -> dict:
    """Roll case results up to per-module and overall metrics."""

    def metrics(tp: int, fp: int, fn: int, tn: int) -> dict:
        precision = tp / (tp + fp) if (tp + fp) else None
        recall = tp / (tp + fn) if (tp + fn) else None
        fp_rate = fp / (fp + tn) if (fp + tn) else None
        return {
            "tp": tp, "fp": fp, "fn": fn, "tn": tn,
            "precision": precision,
            "recall": recall,
            "false_positive_rate_on_hardened": fp_rate,
        }

    per_module: dict[str, dict] = {}
    for r in results:
        acc = per_module.setdefault(r["module"], {"tp": 0, "fp": 0, "fn": 0, "tn": 0})
        for k in ("tp", "fp", "fn", "tn"):
            acc[k] += r[k]
    per_module = {m: metrics(**v) for m, v in sorted(per_module.items())}

    totals = {"tp": 0, "fp": 0, "fn": 0, "tn": 0}
    for r in results:
        for k in totals:
            totals[k] += r[k]
    return {"per_module": per_module, "overall": metrics(**totals)}


def fmt(value) -> str:
    return "n/a" if value is None else f"{value * 100:.1f}%"


def render_markdown(report: dict) -> str:
    agg = report["aggregate"]
    lines = [
        "# aipostex precision benchmark",
        "",
        f"- tool version: `{report['tool_version']}`",
        f"- cases: {len(report['results'])} across {len(agg['per_module'])} module(s)",
        "",
        "Measured by running one verb against an exposed service and its hardened twin.",
        "A *success claim* is any finding graded above `reachable`. On the hardened twin",
        "such a claim is a false positive: authentication was enforced, so the tool did",
        "not get in.",
        "",
        "## Overall",
        "",
        "| TP | FP | FN | TN | Precision | Recall | FP rate on hardened |",
        "|---|---|---|---|---|---|---|",
    ]
    o = agg["overall"]
    lines.append(
        f"| {o['tp']} | {o['fp']} | {o['fn']} | {o['tn']} | {fmt(o['precision'])} | "
        f"{fmt(o['recall'])} | {fmt(o['false_positive_rate_on_hardened'])} |"
    )
    lines += ["", "## Per module", "", "| Module | TP | FP | FN | TN | Precision | Recall |", "|---|---|---|---|---|---|---|"]
    for mod, m in agg["per_module"].items():
        lines.append(
            f"| {mod} | {m['tp']} | {m['fp']} | {m['fn']} | {m['tn']} | "
            f"{fmt(m['precision'])} | {fmt(m['recall'])} |"
        )
    lines += [
        "",
        "## Cases",
        "",
        "`access` verbs are scored on both sides. `enumeration` verbs are scored only on",
        "the hardened side: listing what an open service exposes is correctly graded",
        "`reachable`, so the exposed side has no claim to make and a silence there is not",
        "a miss.",
        "",
        "| Case | Kind | Exposed target | Claimed? | Hardened twin | Claimed? | Verdict |",
        "|---|---|---|---|---|---|---|",
    ]
    for r in report["results"]:
        v_claimed = "yes" if r["vulnerable"]["claims"] else "no"
        if r["kind"] == "enumeration":
            v_claimed += " (not scored)"
        h_claimed = "yes" if r["hardened"]["claims"] else "no"
        verdict = []
        if r["tp"]:
            verdict.append("TP")
        if r["fn"]:
            verdict.append("FN")
        if r["fp"]:
            verdict.append("FP")
        if r["tn"]:
            verdict.append("TN")
        lines.append(
            f"| `{r['command']}` | {r['kind']} | {r['vulnerable']['label']} | {v_claimed} | "
            f"{r['hardened']['label']} | {h_claimed} | {' + '.join(verdict)} |"
        )
    lines += [
        "",
        "## Coverage limits",
        "",
        "Only modules with a hardened twin in the lab can be measured this way, so these",
        "numbers describe those modules and are not extrapolated to the rest of the tool.",
        "Recall is measured against the paired access cases only — `score.py` remains the",
        "broader coverage measure against the planted-data manifest.",
        "",
        "A case is one verb against one pair, so the counts are counts of *verbs that",
        "behaved correctly*, not of individual findings. A verb that emits twenty correct",
        "claims counts once, exactly like one that emits a single claim.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description="Measure aipostex precision on paired targets")
    ap.add_argument("--binary", default=os.path.expanduser("~/aipostex"), help="path to the aipostex binary")
    ap.add_argument("--output-dir", default="/tmp/aipostex-benchmark", help="where raw run artifacts are written")
    ap.add_argument("--json", dest="json_out", default=None, help="write the full JSON report here")
    ap.add_argument("--markdown", dest="md_out", default=None, help="write a markdown report here")
    ap.add_argument("--timeout", type=int, default=120, help="per-invocation timeout in seconds")
    ap.add_argument("--case", action="append", help="only run these case ids (repeatable)")
    args = ap.parse_args()

    if not os.path.exists(args.binary):
        print(f"error: aipostex binary not found at {args.binary}", file=sys.stderr)
        return 1
    os.makedirs(args.output_dir, exist_ok=True)

    version = "unknown"
    try:
        version = subprocess.run(
            [args.binary, "version"], capture_output=True, text=True, timeout=30
        ).stdout.strip()
    except (subprocess.SubprocessError, OSError):
        pass

    cases = CASES if not args.case else [c for c in CASES if c["id"] in set(args.case)]
    if not cases:
        print("error: no cases selected", file=sys.stderr)
        return 1

    results = []
    for case in cases:
        print(f"[*] {case['id']}: {' '.join(case['verb'])}")
        vuln = run_case(
            args.binary, case["verb"], case["vulnerable"]["target"],
            os.path.join(args.output_dir, f"{case['id']}-vulnerable.json"), args.timeout,
        )
        hard = run_case(
            args.binary, case["verb"], case["hardened"]["target"],
            os.path.join(args.output_dir, f"{case['id']}-hardened.json"), args.timeout,
        )
        r = classify(case, vuln, hard)
        results.append(r)
        print(
            f"    exposed: {len(r['vulnerable']['claims'])} claim(s) | "
            f"hardened: {len(r['hardened']['claims'])} claim(s) -> "
            f"TP={r['tp']} FP={r['fp']} FN={r['fn']} TN={r['tn']}"
        )

    report = {"tool_version": version, "results": results, "aggregate": aggregate(results)}

    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
        print(f"[+] JSON report: {args.json_out}")
    md = render_markdown(report)
    if args.md_out:
        with open(args.md_out, "w", encoding="utf-8") as fh:
            fh.write(md)
        print(f"[+] Markdown report: {args.md_out}")

    o = report["aggregate"]["overall"]
    print("")
    print(f"    TP={o['tp']} FP={o['fp']} FN={o['fn']} TN={o['tn']}")
    print(f"    precision={fmt(o['precision'])} recall={fmt(o['recall'])} "
          f"fp-rate-on-hardened={fmt(o['false_positive_rate_on_hardened'])}")
    # A false positive is the failure this benchmark exists to catch.
    return 1 if o["fp"] else 0


if __name__ == "__main__":
    sys.exit(main())
