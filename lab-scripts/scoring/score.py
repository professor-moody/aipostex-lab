#!/usr/bin/env python3
"""
score.py — Validate aipostex scan output against the lab's planted data manifest.

Usage:
    python3 score.py <output.json> [output2.json ...] [--threshold 80]
    python3 score.py ~/lab-results/                    --strict
    python3 score.py scan.json ollama.json weaviate.json --strict --contracts

Accepts one or more JSON files, or a directory containing JSON files.
When multiple inputs are given, all findings are merged before scoring.

Reads aipostex JSON output and compares it against the planted data manifest.
It supports two validation layers:

Default / Strict coverage:
    - sensitive-data coverage scoring
    - optional host/source attribution and noise false-positive checks

Contract validation (--contracts):
    - workflow metadata presence
    - evidence metadata presence
    - stage / landed presence
    - read-before-gated recommendation ordering
    - seeded service markers for Gradio, MLflow, Ray, and MCP workflows
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from collections import defaultdict


def load_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        print(f"[!] File not found: {path}", file=sys.stderr)
        sys.exit(2)
    except json.JSONDecodeError as exc:
        print(f"[!] Invalid JSON in {path}: {exc}", file=sys.stderr)
        sys.exit(2)


def resolve_input_paths(paths):
    """Expand directories into their *.json files and return a flat list."""
    resolved = []
    for p in paths:
        if os.path.isdir(p):
            dir_files = sorted(glob.glob(os.path.join(p, "*.json")))
            if not dir_files:
                print(f"[!] No .json files found in directory: {p}", file=sys.stderr)
                sys.exit(2)
            resolved.extend(dir_files)
        else:
            resolved.append(p)
    return resolved


def load_and_merge(paths):
    """Load one or more JSON files and merge all findings into one structure."""
    all_findings = []
    for p in paths:
        data = load_json(p)
        all_findings.extend(normalize_output(data))
    return {"findings": all_findings}


def normalize_output(aipostex_output):
    if isinstance(aipostex_output, list):
        return aipostex_output
    if isinstance(aipostex_output, dict):
        if "findings" in aipostex_output:
            return aipostex_output["findings"]
        if "results" in aipostex_output:
            return aipostex_output["results"]
        return [aipostex_output]
    return []


def extract_manifest_values(manifest):
    categories = defaultdict(list)
    for host, host_data in manifest.get("hosts", {}).items():
        findings = host_data.get("findings", {})
        for category, items in findings.items():
            for item in items:
                entry = {
                    "value": item["value"],
                    "host": host,
                    "hostname": host_data.get("hostname", ""),
                    "source": item.get("source", ""),
                    "type": item.get("type", ""),
                    "category": category,
                }
                for key in ("path", "collection", "class", "model", "experiment"):
                    if key in item:
                        entry[key] = item[key]
                categories[category].append(entry)
    return categories


SOURCE_TO_MODULES = {
    "filesystem": ["scan-files", "filesystem", "file-discovery", "jupyter"],
    "chromadb": ["chromadb", "vectordb"],
    "weaviate": ["weaviate", "vectordb"],
    "qdrant": ["qdrant", "vectordb"],
    "ollama_system_prompt": ["ollama"],
    "notebook": ["jupyter", "notebook", "scan-files", "filesystem"],
    "mlflow": ["mlflow", "jupyter"],
    "ray": ["ray"],
    "gradio": ["gradio"],
    "mcp": ["mcp"],
    "openai_compat": ["openai-compat", "openai_compat", "openai-compatible", "litellm", "jupyter"],
    "milvus": ["milvus", "vectordb"],
    "pgvector": ["pgvector", "vectordb"],
    "wandb": ["wandb"],
    "a2a": ["a2a"],
}

SERVICE_ALIASES = {
    "langserve": ["langserve"],
    "streamlit": ["streamlit"],
    "hf-tgi": ["hf-tgi", "tgi", "text-generation-inference"],
    "hf-tei": ["hf-tei", "tei", "text-embeddings-inference"],
    "vllm": ["vllm"],
    "wandb": ["wandb", "weights-and-biases"],
    "bentoml": ["bentoml"],
    "torchserve": ["torchserve"],
    "triton": ["triton"],
    "a2a": ["a2a"],
}

HOST_FIELD_PATHS = [
    "target",
    "host",
    "hostname",
    "ip",
    "target_host",
    "endpoint",
    "url",
    "service_url",
    "metadata.target",
    "metadata.host",
    "metadata.hostname",
    "metadata.ip",
    "metadata.endpoint",
    "metadata.url",
]

SOURCE_FIELD_PATHS = [
    "module",
    "source",
    "provider",
    "service",
    "fingerprint",
    "template",
    "template_id",
    "action",
    "metadata.module",
    "metadata.source",
    "metadata.provider",
    "metadata.service",
    "metadata.fingerprint",
    "metadata.template",
    "metadata.template_id",
    "metadata.action",
]

LEGACY_TEXT_FIELD_PATHS = [
    "target",
    "host",
    "hostname",
    "url",
    "endpoint",
    "title",
    "summary",
    "description",
    "service",
    "module",
    "source",
    "provider",
    "fingerprint",
    "template",
    "template_id",
    "metadata.target",
    "metadata.host",
    "metadata.hostname",
    "metadata.url",
    "metadata.endpoint",
    "metadata.title",
    "metadata.summary",
    "metadata.description",
    "metadata.service",
    "metadata.module",
    "metadata.source",
    "metadata.provider",
    "metadata.fingerprint",
    "metadata.template",
    "metadata.template_id",
]


def flatten_strings(value):
    values = []
    if value is None:
        return values
    if isinstance(value, dict):
        for nested in value.values():
            values.extend(flatten_strings(nested))
        return values
    if isinstance(value, list):
        for nested in value:
            values.extend(flatten_strings(nested))
        return values
    return [str(value)]


def collect_field_values(obj, field_paths):
    values = []
    for path in field_paths:
        value = get_nested_value(obj, path)
        if value is not None:
            values.extend(flatten_strings(value))
    return [value for value in values if value]


def alias_match(values, aliases):
    normalized_aliases = [alias.lower() for alias in aliases if alias]
    for value in values:
        value_lower = value.lower()
        for alias in normalized_aliases:
            if alias == value_lower or alias in value_lower or value_lower in alias:
                return True
    return False


def finding_matches_host(finding, expected_host, expected_hostname=""):
    structured_values = collect_field_values(finding, HOST_FIELD_PATHS)
    host_aliases = [expected_host]
    if expected_hostname:
        host_aliases.append(expected_hostname)
    if structured_values:
        return alias_match(structured_values, host_aliases)
    return alias_match(collect_field_values(finding, LEGACY_TEXT_FIELD_PATHS), host_aliases)


def finding_matches_source(finding, expected_source):
    aliases = SOURCE_TO_MODULES.get(expected_source, [expected_source])
    structured_values = collect_field_values(finding, SOURCE_FIELD_PATHS)
    if structured_values:
        return alias_match(structured_values, aliases)
    return alias_match(collect_field_values(finding, LEGACY_TEXT_FIELD_PATHS), aliases)


def search_in_output_simple(output_text, value):
    """Case-insensitive substring search across the entire JSON dump.

    This is intentionally loose: short manifest values (≥4 chars) may match
    incidentally against unrelated fields in large output.  Use --strict mode
    (search_in_output_strict) for precise, field-aware validation.
    """
    if not value or len(value) < 4:
        return False
    return value.lower() in output_text.lower()


def search_in_output_strict(findings_list, item):
    value = item["value"]
    if not value or len(value) < 4:
        return False

    value_lower = value.lower()
    for finding in findings_list:
        finding_text = json.dumps(finding).lower()
        if value_lower not in finding_text:
            continue
        if not finding_matches_source(finding, item["source"]):
            continue
        source = finding.get("source", "")
        if source in ("file-discovery", "jupyter"):
            return True
        if not finding_matches_host(finding, item["host"], item.get("hostname", "")):
            continue
        return True
    return False


def extract_manifest_service_inventory(manifest):
    return manifest.get("service_inventory", [])


PORT_FIELD_PATHS = [
    "target",
    "endpoint",
    "url",
    "service_url",
    "metadata.target",
    "metadata.endpoint",
    "metadata.url",
    "metadata.port",
]


def finding_matches_port(finding, expected_port):
    if expected_port is None:
        return True
    port_str = str(expected_port)
    port_fields = collect_field_values(finding, PORT_FIELD_PATHS)
    return any(port_str in str(v) for v in port_fields)


def finding_matches_service(finding, service_item):
    aliases = SERVICE_ALIASES.get(service_item["service"], [service_item["service"]])
    structured_values = collect_field_values(
        finding,
        SOURCE_FIELD_PATHS
        + [
            "title",
            "target",
            "metadata.title",
            "metadata.summary",
        ],
    )
    if structured_values and alias_match(structured_values, aliases):
        return (
            finding_matches_host(finding, service_item["ip"], service_item.get("hostname", ""))
            and finding_matches_port(finding, service_item.get("port"))
        )
    return (
        alias_match(collect_field_values(finding, LEGACY_TEXT_FIELD_PATHS), aliases)
        and finding_matches_host(finding, service_item["ip"], service_item.get("hostname", ""))
        and finding_matches_port(finding, service_item.get("port"))
    )


def score_service_inventory(aipostex_output, manifest, strict=False):
    items = extract_manifest_service_inventory(manifest)
    if not items:
        return None

    findings_list = normalize_output(aipostex_output)
    output_text = json.dumps(aipostex_output).lower()
    found = []
    missed = []

    for item in items:
        if strict:
            matched = any(finding_matches_service(finding, item) for finding in findings_list)
        else:
            aliases = SERVICE_ALIASES.get(item["service"], [item["service"]])
            matched = alias_match([output_text], aliases)
        if matched:
            found.append(item)
        else:
            missed.append(item)

    coverage_pct = (len(found) / len(items) * 100) if items else 0
    return {
        "total_expected": len(items),
        "total_found": len(found),
        "total_missed": len(missed),
        "coverage_pct": round(coverage_pct, 1),
        "found_items": found,
        "missed_items": missed,
    }


def _check_noise_file(finding, noise_files_lower):
    """Return the matched noise file path if any path-like field references one."""
    path_fields = ["path", "file", "source", "target"]
    for field in path_fields:
        val = finding.get(field, "") or ""
        if not isinstance(val, str):
            val = str(val)
        val_lower = val.lower()
        for nf in noise_files_lower:
            if nf in val_lower:
                return nf
    metadata = finding.get("metadata", {})
    if isinstance(metadata, dict):
        for field in path_fields:
            val = metadata.get(field, "") or ""
            if not isinstance(val, str):
                val = str(val)
            val_lower = val.lower()
            for nf in noise_files_lower:
                if nf in val_lower:
                    return nf
    return None


def detect_false_positives(findings_list, manifest):
    noise_collections = manifest.get("noise_collections", {})
    false_positives = []

    noise_names = set()
    for collections in noise_collections.values():
        for name in collections:
            noise_names.add(name.lower())

    noise_files_lower = [f.lower() for f in manifest.get("noise_files", [])]

    collection_fields = ["collection", "class", "source_collection", "source_class"]

    for finding in findings_list:
        metadata = finding.get("metadata", {}) or {}
        if isinstance(metadata, dict) and metadata.get("action") == "enum":
            continue

        matched_noise = None
        for field in collection_fields:
            val = finding.get(field, "") or ""
            if not isinstance(val, str):
                val = str(val)
            if val.lower() in noise_names:
                matched_noise = val.lower()
                break
        if not matched_noise:
            if isinstance(metadata, dict):
                for field in collection_fields:
                    val = metadata.get(field, "") or ""
                    if not isinstance(val, str):
                        val = str(val)
                    if val.lower() in noise_names:
                        matched_noise = val.lower()
                        break
        if matched_noise:
            false_positives.append({
                "noise_collection": matched_noise,
                "finding_preview": json.dumps(finding)[:200],
            })
            continue

        matched_file = _check_noise_file(finding, noise_files_lower)
        if matched_file:
            false_positives.append({
                "noise_file": matched_file,
                "finding_preview": json.dumps(finding)[:200],
            })

    return false_positives


def score_output(aipostex_output, manifest, strict=False):
    categories = extract_manifest_values(manifest)
    findings_list = normalize_output(aipostex_output)
    output_text = json.dumps(aipostex_output)

    results = {}
    total_planted = 0
    total_found = 0

    for category, items in sorted(categories.items()):
        found = []
        missed = []

        for item in items:
            matched = search_in_output_strict(findings_list, item) if strict else search_in_output_simple(output_text, item["value"])
            if matched:
                found.append(item)
            else:
                missed.append(item)

        total_planted += len(items)
        total_found += len(found)

        pct = (len(found) / len(items) * 100) if items else 0
        results[category] = {
            "planted": len(items),
            "found": len(found),
            "missed": len(missed),
            "coverage_pct": round(pct, 1),
            "found_items": found,
            "missed_items": missed,
        }

    overall_pct = (total_found / total_planted * 100) if total_planted else 0
    report = {
        "overall": {
            "total_planted": total_planted,
            "total_found": total_found,
            "total_missed": total_planted - total_found,
            "coverage_pct": round(overall_pct, 1),
        },
        "by_category": results,
    }

    service_inventory = score_service_inventory(aipostex_output, manifest, strict=strict)
    if service_inventory is not None:
        report["service_inventory"] = service_inventory

    if strict:
        fps = detect_false_positives(findings_list, manifest)
        report["false_positives"] = {
            "count": len(fps),
            "items": fps,
        }

    return report


def get_nested_value(obj, path):
    current = obj
    for part in path.split("."):
        if isinstance(current, dict) and part in current:
            current = current[part]
        else:
            return None
    return current


def match_finding(finding, matcher):
    if not matcher:
        return True
    for key, expected in matcher.items():
        if key in {"source", "target", "title", "severity"}:
            actual = finding.get(key)
        elif key in {"module", "action", "provider", "service"}:
            actual = finding.get(key) or get_nested_value(finding, f"metadata.{key}")
        else:
            actual = get_nested_value(finding, f"metadata.{key}")
        if isinstance(expected, list):
            if actual not in expected:
                return False
        elif str(actual) != str(expected):
            return False
    return True


def workflow_read_before_gated(finding):
    workflow = get_nested_value(finding, "metadata.workflow")
    if not isinstance(workflow, dict):
        return False
    recommendations = workflow.get("recommendations")
    if not isinstance(recommendations, list) or not recommendations:
        return False
    seen_gated = False
    for recommendation in recommendations:
        gated = bool(recommendation.get("gated"))
        if gated:
            seen_gated = True
            continue
        if seen_gated:
            return False
    return True


def evaluate_contracts(aipostex_output, manifest):
    findings_list = normalize_output(aipostex_output)
    expectations = manifest.get("contract_expectations", [])
    results = []

    for expectation in expectations:
        matched = [finding for finding in findings_list if match_finding(finding, expectation.get("match", {}))]
        if not matched:
            # A contract marked "required" must have a matching finding in the
            # scored dataset; a missing one is a FAILURE, not a silent skip
            # (e.g. a terminal credential-replay proof that never got collected).
            # Optional contracts remain skip-when-absent.
            required = expectation.get("required", False)
            results.append(
                {
                    "name": expectation["name"],
                    "status": "failed" if required else "skipped",
                    "matched_findings": 0,
                    "errors": ["required contract has no matching finding in the dataset"] if required else [],
                }
            )
            continue

        all_errors = []
        require_metadata = expectation.get("require_metadata", [])
        markers = expectation.get("markers", [])
        require_ordering = expectation.get("read_before_gated", False)
        satisfied = False

        for finding in matched:
            finding_errors = []
            finding_blob = json.dumps(finding)
            for key in require_metadata:
                path = key if "." in key else f"metadata.{key}"
                if get_nested_value(finding, path) is None:
                    finding_errors.append(f"missing {path}")
            for marker in markers:
                if marker not in finding_blob:
                    finding_errors.append(f"missing marker {marker}")
            if require_ordering and not workflow_read_before_gated(finding):
                finding_errors.append("workflow recommendations were not ordered read-before-gated")

            if not finding_errors:
                satisfied = True
                all_errors = []
                break
            all_errors.extend(finding_errors)

        status = "passed" if satisfied else "failed"
        results.append(
            {
                "name": expectation["name"],
                "status": status,
                "matched_findings": len(matched),
                "errors": sorted(set(all_errors)),
            }
        )

    summary = {
        "passed": sum(1 for result in results if result["status"] == "passed"),
        "failed": sum(1 for result in results if result["status"] == "failed"),
        "skipped": sum(1 for result in results if result["status"] == "skipped"),
        "results": results,
    }
    return summary


def load_rrr_matrix(manifest_dir):
    path = os.path.join(manifest_dir, "rrr_matrix.json")
    if not os.path.exists(path):
        return None
    return load_json(path)


def _rrr_best_surface(finding, surfaces):
    """Pick the most specific matching surface (module+action beats module-only)."""
    best = None
    best_specificity = -1
    for surface in surfaces:
        matcher = surface.get("match", {})
        if not matcher or not match_finding(finding, matcher):
            continue
        specificity = len(matcher)
        if specificity > best_specificity:
            best = surface
            best_specificity = specificity
    return best


def evaluate_rrr(aipostex_output, matrix):
    """RRR over-claim check: a finding must not claim a landed that outranks
    its surface's max (a detection fixture must never emit a real-compromise claim).
    Surfaces not in the matrix are reported as 'uncovered', not failed."""
    findings_list = normalize_output(aipostex_output)
    ranks = matrix.get("landed_rank", {})
    surfaces = matrix.get("surfaces", [])
    violations = []
    uncovered = {}
    uncovered_elevated = {}
    reachable_rank = ranks.get("reachable", 1)
    checked = 0
    for finding in findings_list:
        proof = get_nested_value(finding, "metadata.landed") or finding.get("landed")
        if not proof:
            continue
        module = finding.get("module") or get_nested_value(finding, "metadata.module")
        if not module:
            # Findings without a module:action are detection results — vulncheck
            # template matches and fingerprints, scored via coverage/service-inventory.
            # They are not tool exploit-surface claims, so they are out of scope for
            # the RRR over-claim check (their landed vocabulary differs too).
            continue
        surface = _rrr_best_surface(finding, surfaces)
        if surface is None:
            action = finding.get("action") or get_nested_value(finding, "metadata.action") or "*"
            key = f"{module}:{action}"
            uncovered[key] = uncovered.get(key, 0) + 1
            # An unclassified surface claiming above 'reachable' is the real risk:
            # a new execution-confirmed surface slipping past the matrix unclassified.
            if ranks.get(proof, 0) > reachable_rank:
                uncovered_elevated[key] = uncovered_elevated.get(key, 0) + 1
            continue
        checked += 1
        max_proof = surface.get("max_landed", "execution-confirmed")
        claimed_rank = ranks.get(proof, 0)
        allowed_rank = ranks.get(max_proof, 99)
        # forbid_landed expresses a NON-CONTIGUOUS allowed set: a READ surface may reach
        # takeover-capable (rank 5) yet must never claim execution-confirmed (rank 4), because the
        # rank ceiling alone (rank <= allowed) would wrongly permit it. Explicit proof-class guard.
        forbidden = surface.get("forbid_landed", [])
        if proof in forbidden:
            violations.append({
                "surface": surface.get("match"),
                "tier": surface.get("tier"),
                "claimed": proof,
                "max_allowed": "{} (forbidden: {})".format(max_proof, ",".join(forbidden)),
                "title": finding.get("title", ""),
            })
        elif claimed_rank > allowed_rank:
            violations.append({
                "surface": surface.get("match"),
                "tier": surface.get("tier"),
                "claimed": proof,
                "max_allowed": max_proof,
                "title": finding.get("title", ""),
            })
    return {
        "checked": checked,
        "violations_count": len(violations),
        "violations": violations,
        "uncovered": uncovered,
        "uncovered_elevated": uncovered_elevated,
        "uncovered_elevated_count": sum(uncovered_elevated.values()),
    }


def print_report(report, verbose=False, strict=False, contracts=False):
    overall = report["overall"]

    print()
    print("=" * 60)
    mode = "Strict" if strict else "Standard"
    if contracts:
        mode += " + Contracts"
    print(f"  aipostex Lab Scoring Report ({mode} Mode)")
    print("=" * 60)
    print()
    print(f"  Overall Coverage: {overall['coverage_pct']}%")
    print(f"  Found: {overall['total_found']} / {overall['total_planted']} planted items")
    print(f"  Missed: {overall['total_missed']}")
    print()
    print("  By Category:")
    print("  " + "-" * 56)

    for category, data in sorted(report["by_category"].items()):
        bar_len = int(data["coverage_pct"] / 5)
        bar = "#" * bar_len + "." * (20 - bar_len)
        print(f"  {category:<22} {bar} {data['coverage_pct']:>5.1f}%  ({data['found']}/{data['planted']})")

    print()

    if "service_inventory" in report:
        service_inventory = report["service_inventory"]
        print("  Service Inventory:")
        print("  " + "-" * 56)
        print(
            f"  Service inventory coverage: {service_inventory['coverage_pct']}%  "
            f"({service_inventory['total_found']}/{service_inventory['total_expected']})"
        )
        if verbose and service_inventory["missed_items"]:
            for item in service_inventory["missed_items"]:
                print(
                    f"    - missed {item['service']} on {item['hostname']}:{item['port']} "
                    f"({item['category']})"
                )
        print()

    if strict and "false_positives" in report:
        fp = report["false_positives"]
        if fp["count"] > 0:
            print(f"  False Positives: {fp['count']} findings from noise collections")
            print("  " + "-" * 56)
            for item in fp["items"][:10]:
                label = item.get('noise_collection') or item.get('noise_file', 'unknown')
                print(f"    [{label}] {item['finding_preview'][:80]}...")
            if fp["count"] > 10:
                print(f"    ... and {fp['count'] - 10} more")
        else:
            print("  False Positives: 0 (no noise collection findings)")
        print()

    if contracts and "contracts" in report:
        contract_report = report["contracts"]
        print("  Contract Checks:")
        print("  " + "-" * 56)
        print(
            f"  Passed: {contract_report['passed']}  "
            f"Failed: {contract_report['failed']}  "
            f"Skipped: {contract_report['skipped']}"
        )
        for item in contract_report["results"]:
            status = item["status"].upper()
            print(f"    [{status:<7}] {item['name']} (matched={item['matched_findings']})")
            if verbose and item["errors"]:
                for error in item["errors"]:
                    print(f"      - {error}")
        print()

    if verbose:
        missed_any = False
        for category, data in sorted(report["by_category"].items()):
            if data["missed_items"]:
                if not missed_any:
                    print("  Missed Items:")
                    print("  " + "-" * 56)
                    missed_any = True
                for item in data["missed_items"]:
                    loc = item.get("path") or item.get("collection") or item.get("class") or item.get("model") or item.get("experiment") or item.get("source")
                    print(f"    [{category}] {item['value'][:50]:<50} ({item['host']} / {loc})")
        if missed_any:
            print()

    print("=" * 60)
    print()


def main():
    parser = argparse.ArgumentParser(description="Score aipostex output against lab manifest")
    parser.add_argument("output_files", nargs="+", help="Path(s) to aipostex JSON output file(s) or a directory containing them")
    parser.add_argument("--manifest", default=None, help="Path to manifest.json (default: same dir as this script)")
    parser.add_argument("--threshold", type=float, default=80.0, help="Minimum coverage %% to pass (default: 80)")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show missed items and contract errors")
    parser.add_argument("--json", action="store_true", help="Output full JSON report (includes answer-key-derived detail; use for CI/after-action)")
    parser.add_argument("--strict", action="store_true", help="Enable structured matching with host/source validation and false-positive detection")
    parser.add_argument("--contracts", action="store_true", help="Validate workflow + stage/landed contract expectations from the manifest")
    parser.add_argument("--rrr", action="store_true", help="Validate the RRR honesty matrix: fail on landed over-claims, and on uncovered surfaces claiming above 'reachable'")
    parser.add_argument("--rrr-require-covered", action="store_true", help="Imply --rrr and additionally fail if ANY surface is unclassified (uncovered) in the RRR matrix")
    args = parser.parse_args()

    manifest_path = args.manifest or os.path.join(os.path.dirname(os.path.abspath(__file__)), "manifest.json")
    manifest = load_json(manifest_path)

    input_paths = resolve_input_paths(args.output_files)
    if not args.json:
        if len(input_paths) > 1:
            print(f"[*] Loading {len(input_paths)} JSON file(s)...", file=sys.stderr)
    output = load_and_merge(input_paths)

    report = score_output(output, manifest, strict=args.strict)
    if args.contracts:
        report["contracts"] = evaluate_contracts(output, manifest)
    run_rrr = args.rrr or args.rrr_require_covered
    if run_rrr:
        rrr_matrix = load_rrr_matrix(os.path.dirname(os.path.abspath(manifest_path)))
        if rrr_matrix is None:
            print("[!] RRR requested but rrr_matrix.json not found next to the manifest", file=sys.stderr)
        else:
            report["rrr"] = evaluate_rrr(output, rrr_matrix)

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print_report(report, verbose=args.verbose, strict=args.strict, contracts=args.contracts)
        if run_rrr and "rrr" in report:
            rrr = report["rrr"]
            print("")
            print("RRR honesty matrix:")
            print(f"  checked: {rrr['checked']}  over-claims: {rrr['violations_count']}  "
                  f"uncovered: {len(rrr['uncovered'])} (elevated: {rrr.get('uncovered_elevated_count', 0)})")
            for v in rrr["violations"]:
                print(f"  [OVER-CLAIM] {v['surface']} claimed {v['claimed']} > max {v['max_allowed']} ({v['tier']}) — {v['title'][:60]}")
            for key, count in sorted(rrr.get("uncovered_elevated", {}).items()):
                print(f"  [UNCOVERED>reachable] {key} ({count}) — classify it in rrr_matrix.json")
            if (args.verbose or args.rrr_require_covered) and rrr["uncovered"]:
                for key, count in sorted(rrr["uncovered"].items()):
                    print(f"  [uncovered] {key} ({count})")

    coverage_ok = report["overall"]["coverage_pct"] >= args.threshold
    contracts_ok = not args.contracts or report["contracts"]["failed"] == 0
    rrr_ok = True
    if run_rrr and "rrr" in report:
        _rrr = report["rrr"]
        rrr_ok = _rrr["violations_count"] == 0 and _rrr.get("uncovered_elevated_count", 0) == 0
        if args.rrr_require_covered and _rrr["uncovered"]:
            rrr_ok = False
    service_inventory_ok = (
        not args.strict
        or "service_inventory" not in report
        or report["service_inventory"]["total_missed"] == 0
    )
    false_positive_ok = (
        not args.strict
        or "false_positives" not in report
        or report["false_positives"]["count"] == 0
    )

    if coverage_ok and contracts_ok and service_inventory_ok and false_positive_ok and rrr_ok:
        if not args.json:
            print(f"  PASS: Coverage {report['overall']['coverage_pct']}% >= {args.threshold}% threshold")
            if args.contracts:
                print("  PASS: Contract checks reported no failures")
            if run_rrr and "rrr" in report:
                print("  PASS: RRR matrix clean (no over-claims, no elevated/uncovered surfaces)")
            if args.strict and "service_inventory" in report:
                print("  PASS: Service inventory coverage reported no strict misses")
            if args.strict and "false_positives" in report:
                print("  PASS: Strict mode reported no false positives")
        return 0

    if not args.json:
        if not coverage_ok:
            print(f"  FAIL: Coverage {report['overall']['coverage_pct']}% < {args.threshold}% threshold")
        if args.contracts and not contracts_ok:
            print(f"  FAIL: Contract checks reported {report['contracts']['failed']} failure(s)")
        if run_rrr and not rrr_ok:
            _rrr = report.get("rrr", {})
            print(
                f"  FAIL: RRR matrix — {_rrr.get('violations_count', 0)} over-claim(s), "
                f"{_rrr.get('uncovered_elevated_count', 0)} uncovered surface(s) claiming above reachable"
                + (f", {len(_rrr.get('uncovered', {}))} uncovered (require-covered)" if args.rrr_require_covered else "")
            )
        if args.strict and not service_inventory_ok:
            print(
                f"  FAIL: Service inventory coverage missed "
                f"{report['service_inventory']['total_missed']} expected service(s)"
            )
        if args.strict and not false_positive_ok:
            print(f"  FAIL: Strict mode reported {report['false_positives']['count']} false positive(s)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
