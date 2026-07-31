#!/usr/bin/env python3
"""MLflow registry hook controller for the aipostex lab.

This is intentionally not an MLflow endpoint. It models the common MLOps pattern
where automation watches MLflow registry metadata and reacts to model-version
tags. The controller polls the real MLflow tracking server, finds model-version
tags named ``aipostex.hook.url`` by default, and POSTs one callback per unique
model/version/URL.
"""

from __future__ import annotations

import hashlib
import json
import os
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


TRACKING_URI = os.environ.get("MLFLOW_HOOK_TRACKING_URI", "http://localhost:5000").rstrip("/")
TAG_KEY = os.environ.get("MLFLOW_HOOK_TAG_KEY", "aipostex.hook.url")
POLL_SECONDS = float(os.environ.get("MLFLOW_HOOK_POLL_SECONDS", "2"))
STATE_PATH = Path(os.environ.get("MLFLOW_HOOK_STATE", "/var/lib/aipostex/mlflow-hook-controller/delivered.json"))
MAX_RESULTS = int(os.environ.get("MLFLOW_HOOK_MAX_RESULTS", "100"))
TIMEOUT = float(os.environ.get("MLFLOW_HOOK_TIMEOUT", "5"))


def load_state() -> set[str]:
    try:
        data = json.loads(STATE_PATH.read_text())
        if isinstance(data, list):
            return {str(item) for item in data}
    except FileNotFoundError:
        pass
    except Exception as exc:
        print(f"[!] could not read state {STATE_PATH}: {exc}", flush=True)
    return set()


def save_state(values: set[str]) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(sorted(values), indent=2) + "\n")
    tmp.replace(STATE_PATH)


def request_json(method: str, path: str, payload: dict | None = None) -> dict:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    req = Request(TRACKING_URI + path, data=data, headers=headers, method=method)
    with urlopen(req, timeout=TIMEOUT) as resp:
        raw = resp.read()
    if not raw:
        return {}
    return json.loads(raw.decode())


def list_model_versions() -> list[dict]:
    path = "/api/2.0/mlflow/model-versions/search?" + urlencode({"max_results": MAX_RESULTS})
    data = request_json("GET", path)
    return data.get("model_versions", []) if isinstance(data, dict) else []


def get_model_version(name: str, version: str) -> dict:
    query = urlencode({"name": name, "version": version})
    data = request_json("GET", "/api/2.0/mlflow/model-versions/get?" + query)
    mv = data.get("model_version", {}) if isinstance(data, dict) else {}
    return mv if isinstance(mv, dict) else {}


def tag_value(model_version: dict, key: str) -> str:
    for tag in model_version.get("tags", []) or []:
        if isinstance(tag, dict) and tag.get("key") == key:
            return str(tag.get("value") or "").strip()
    return ""


def delivery_key(model: str, version: str, hook_url: str) -> str:
    raw = f"{model}\0{version}\0{hook_url}".encode()
    return hashlib.sha256(raw).hexdigest()


def deliver(model_version: dict, hook_url: str) -> None:
    payload = {
        "module": "mlflow",
        "action": "hook",
        "event": "model-version-tag",
        "model": model_version.get("name", ""),
        "version": model_version.get("version", ""),
        "stage": model_version.get("current_stage", ""),
        "source": model_version.get("source", ""),
        "run_id": model_version.get("run_id", ""),
        "tag_key": TAG_KEY,
    }
    data = json.dumps(payload).encode()
    req = Request(
        hook_url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "X-Aipostex-MLflow-Hook": "1",
        },
        method="POST",
    )
    with urlopen(req, timeout=TIMEOUT) as resp:
        resp.read()


def poll_once(delivered: set[str]) -> bool:
    changed = False
    for item in list_model_versions():
        model = str(item.get("name") or "").strip()
        version = str(item.get("version") or "").strip()
        if not model or not version:
            continue
        detail = get_model_version(model, version)
        hook_url = tag_value(detail, TAG_KEY)
        if not hook_url.startswith(("http://", "https://")):
            continue
        key = delivery_key(model, version, hook_url)
        if key in delivered:
            continue
        try:
            deliver(detail, hook_url)
            delivered.add(key)
            changed = True
            print(f"[+] delivered MLflow hook model={model} version={version} url={hook_url}", flush=True)
        except (HTTPError, URLError, TimeoutError, OSError) as exc:
            print(f"[!] hook delivery failed model={model} version={version}: {exc}", flush=True)
    return changed


def main() -> None:
    delivered = load_state()
    print(
        f"[+] mlflow-hook-controller watching {TRACKING_URI} tag={TAG_KEY} interval={POLL_SECONDS}s",
        flush=True,
    )
    while True:
        try:
            if poll_once(delivered):
                save_state(delivered)
        except Exception as exc:
            print(f"[!] controller poll failed: {exc}", flush=True)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
