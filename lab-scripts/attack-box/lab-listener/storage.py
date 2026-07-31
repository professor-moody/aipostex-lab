"""
storage.py — In-memory ring buffer + JSONL persistence for lab-listener.
Thread-safe; used by server.py only.
"""
import json
import threading
import time
from collections import deque
from pathlib import Path

RING_SIZE = 1000
LOG_PATH = Path("/var/log/lab-listener/events.jsonl")


class EventStore:
    def __init__(self, ring_size: int = RING_SIZE, log_path: Path = LOG_PATH):
        self._lock = threading.Lock()
        self._ring: deque = deque(maxlen=ring_size)
        self._counter = 0
        self._log_path = log_path
        self._log_path.parent.mkdir(parents=True, exist_ok=True)

    def append(self, event: dict) -> dict:
        with self._lock:
            self._counter += 1
            event["seq"] = self._counter
            self._ring.append(event)
        try:
            with self._log_path.open("a") as f:
                f.write(json.dumps(event) + "\n")
        except OSError:
            pass
        return event

    def query(
        self,
        probe_id: str | None = None,
        kind: str | None = None,
        since: str | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict]:
        since_ts = None
        if since:
            try:
                since_ts = float(since) if since.replace(".", "", 1).isdigit() else _parse_iso(since)
            except Exception:
                since_ts = None

        with self._lock:
            items = list(self._ring)

        results = []
        for ev in items:
            if probe_id and ev.get("probe_id") != probe_id:
                continue
            if kind and ev.get("kind") != kind:
                continue
            if since_ts and ev.get("ts_epoch", 0) < since_ts:
                continue
            results.append(ev)

        return results[offset: offset + limit]

    def count(self) -> int:
        with self._lock:
            return len(self._ring)

    def total_seen(self) -> int:
        with self._lock:
            return self._counter


def _parse_iso(s: str) -> float:
    """Parse ISO 8601 timestamp to epoch float (stdlib only)."""
    import datetime
    s = s.rstrip("Z")
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
        try:
            dt = datetime.datetime.strptime(s, fmt)
            return dt.replace(tzinfo=datetime.timezone.utc).timestamp()
        except ValueError:
            continue
    raise ValueError(f"Cannot parse timestamp: {s}")


def make_event(
    kind: str,
    remote_addr: str,
    path: str,
    method: str,
    probe_id: str,
    headers: dict,
    query: dict,
    body_preview: bytes,
    body_size: int,
    body_sha256: str,
) -> dict:
    import hashlib
    now = time.time()
    return {
        "kind": kind,
        "ts": _epoch_to_iso(now),
        "ts_epoch": now,
        "remote_addr": remote_addr,
        "path": path,
        "method": method,
        "probe_id": probe_id,
        "headers": headers,
        "query": query,
        "body_size": body_size,
        "body_preview": body_preview[:2048].hex() if body_preview else "",
        "body_sha256": body_sha256,
    }


def _epoch_to_iso(ts: float) -> str:
    import datetime
    return datetime.datetime.fromtimestamp(ts, tz=datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
