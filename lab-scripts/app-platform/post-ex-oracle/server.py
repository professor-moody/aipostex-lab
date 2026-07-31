#!/usr/bin/env python3
"""
post-ex-oracle (POX) — Post-Exploitation Validation Oracle for aipostex-lab.
Runs on ailab-app (172.16.50.40:8765).

Endpoint families:
  /oracle/sentinel        Confirm RCE payload executed (target writes sentinel)
  /heartbeat              Persistence validation (cron jobs, scheduled tasks heartbeat here)
  /exfil/upload           Exfil sink with sha256 + drift detection
  /replay/<provider>/...  Credential replay validators (17 provider families)
  /state/summary          Operator overview
  /state/reset            Demo reset

SQLite-backed. No external deps. Run via systemd as post-ex-oracle.service.
"""
import hashlib
import json
import os
import sqlite3
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

BIND_HOST = os.environ.get("POX_BIND", "0.0.0.0")
BIND_PORT = int(os.environ.get("POX_PORT", "8765"))
DB_PATH = os.environ.get("POX_DB_PATH", "/home/appuser/projects/post-ex-oracle/oracle.db")
MAX_BODY = int(os.environ.get("POX_EXFIL_MAX_MB", "100")) * 1024 * 1024
RESET_TOKEN = os.environ.get("POX_RESET_TOKEN", "reset-FAKE-admin-token")
ROW_CAP = 10_000  # rotate oldest rows above this per table

# ── Database ─────────────────────────────────────────────────────────────────

def _init_db(path: str) -> sqlite3.Connection:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path, check_same_thread=False)
    db.execute("PRAGMA journal_mode=WAL")
    db.executescript("""
        CREATE TABLE IF NOT EXISTS sentinels (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sentinel TEXT NOT NULL,
            target TEXT,
            notes TEXT,
            source_ip TEXT,
            ts TEXT,
            headers TEXT,
            body TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_sentinels_sentinel ON sentinels(sentinel);

        CREATE TABLE IF NOT EXISTS heartbeats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source TEXT,
            tag TEXT NOT NULL,
            payload TEXT,
            source_ip TEXT,
            ts TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_heartbeats_tag ON heartbeats(tag);

        CREATE TABLE IF NOT EXISTS exfil_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tag TEXT,
            bytes INTEGER,
            sha256 TEXT,
            content_type TEXT,
            source_ip TEXT,
            ts TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_exfil_tag ON exfil_records(tag);

        CREATE TABLE IF NOT EXISTS replay_attempts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            endpoint TEXT,
            credential_submitted TEXT,
            matched INTEGER,
            source_ip TEXT,
            ts TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_replay_endpoint ON replay_attempts(endpoint, matched);

        CREATE TABLE IF NOT EXISTS replay_expectations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            endpoint_prefix TEXT NOT NULL,
            credential_substring TEXT NOT NULL,
            description TEXT,
            UNIQUE(endpoint_prefix, credential_substring)
        );

        CREATE TABLE IF NOT EXISTS exfil_expectations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            expected_sha256 TEXT,
            description TEXT
        );
    """)
    db.commit()
    return db


_db: sqlite3.Connection | None = None


def db() -> sqlite3.Connection:
    global _db
    if _db is None:
        _db = _init_db(DB_PATH)
    return _db


def _now_iso() -> str:
    import datetime
    return datetime.datetime.now(tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _rotate(table: str, col: str = "id"):
    count = db().execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    if count > ROW_CAP:
        delete_count = count - ROW_CAP
        db().execute(
            f"DELETE FROM {table} WHERE {col} IN "
            f"(SELECT {col} FROM {table} ORDER BY {col} ASC LIMIT ?)",
            (delete_count,)
        )
        db().commit()


# ── HTTP helpers ──────────────────────────────────────────────────────────────

def _remote_addr(h: "POXHandler") -> str:
    fwd = h.headers.get("X-Forwarded-For")
    return fwd.split(",")[0].strip() if fwd else (h.client_address[0] if h.client_address else "")


def _read_body(h: "POXHandler", max_bytes: int = MAX_BODY) -> bytes:
    length = int(h.headers.get("Content-Length", 0) or 0)
    if length <= 0:
        return b""
    return h.rfile.read(min(length, max_bytes))


def _json(h: "POXHandler", status: int, data: dict):
    body = json.dumps(data, indent=2).encode()
    h.send_response(status)
    h.send_header("Content-Type", "application/json")
    h.send_header("Content-Length", str(len(body)))
    h.send_header("X-POX-Version", "1.0.0")
    h.end_headers()
    h.wfile.write(body)


def _parse_json_body(raw: bytes) -> dict:
    try:
        return json.loads(raw) if raw else {}
    except Exception:
        return {}


# ── Credential matching ───────────────────────────────────────────────────────

def _extract_credential(h: "POXHandler", endpoint: str, body: dict) -> str:
    """Pull submitted credential from headers or body based on provider conventions."""
    # AWS-style
    if "aws" in endpoint or "bedrock" in endpoint:
        v = h.headers.get("X-AWS-Key") or h.headers.get("X-Amz-Security-Token") or body.get("accessKeyId", "")
        if v:
            return v
    # Bearer / OpenAI / Anthropic / GitHub / HuggingFace / Stripe / LangSmith
    auth = h.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        return auth[7:]
    if auth.startswith("Basic "):
        import base64
        try:
            return base64.b64decode(auth[6:]).decode()
        except Exception:
            return auth
    # x-api-key (Anthropic, Azure, Datadog)
    xkey = h.headers.get("X-Api-Key") or h.headers.get("Api-Key") or h.headers.get("DD-API-KEY")
    if xkey:
        return xkey
    # Vault
    vault = h.headers.get("X-Vault-Token")
    if vault:
        return vault
    # PagerDuty: "Authorization: Token token=<key>"
    if auth.startswith("Token token="):
        return auth[12:]
    # Body fields
    for field in ("password", "token", "secret", "api_key", "connstr"):
        if field in body:
            return str(body[field])
    # Slack webhook path
    parts = endpoint.split("/")
    if "slack" in endpoint and len(parts) >= 3:
        return parts[-1]  # token is last path segment
    return ""


def _match_expectation(endpoint: str, submitted: str) -> bool:
    """Check if submitted credential matches any expectation for this endpoint prefix."""
    rows = db().execute(
        "SELECT credential_substring FROM replay_expectations WHERE ? LIKE '%' || endpoint_prefix || '%'",
        (endpoint,)
    ).fetchall()
    for (sub,) in rows:
        if sub and sub in submitted:
            return True
    return False


# ── Request handler ───────────────────────────────────────────────────────────

class POXHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress per-request logs

    def _parsed(self):
        return urlparse(self.path)

    def do_GET(self):
        parsed = self._parsed()
        path = parsed.path.rstrip("/")
        qs = {k: v for k, v in parse_qs(parsed.query).items()}

        if path == "/health":
            _json(self, 200, {"status": "healthy", "version": "1.0.0"})

        elif path == "/oracle/verify":
            sentinel = qs.get("sentinel", [None])[0]
            if not sentinel:
                _json(self, 400, {"error": "sentinel query param required"})
                return
            rows = db().execute(
                "SELECT id, ts, source_ip FROM sentinels WHERE sentinel=? ORDER BY id ASC",
                (sentinel,)
            ).fetchall()
            _json(self, 200, {
                "found": len(rows) > 0,
                "count": len(rows),
                "first_seen": rows[0][1] if rows else None,
                "sources": list({r[2] for r in rows}),
            })

        elif path == "/oracle/sentinels":
            limit = int(qs.get("limit", ["50"])[0])
            rows = db().execute(
                "SELECT id, sentinel, target, notes, source_ip, ts FROM sentinels ORDER BY id DESC LIMIT ?",
                (limit,)
            ).fetchall()
            _json(self, 200, {"count": len(rows), "sentinels": [
                {"id": r[0], "sentinel": r[1], "target": r[2], "notes": r[3], "source_ip": r[4], "ts": r[5]}
                for r in rows
            ]})

        elif path == "/heartbeat/query":
            tag = qs.get("tag", [None])[0]
            if not tag:
                _json(self, 400, {"error": "tag query param required"})
                return
            rows = db().execute(
                "SELECT COUNT(*), MAX(ts), GROUP_CONCAT(DISTINCT source_ip) FROM heartbeats WHERE tag=?",
                (tag,)
            ).fetchone()
            _json(self, 200, {
                "tag": tag,
                "count": rows[0] or 0,
                "latest": rows[1],
                "sources": rows[2].split(",") if rows[2] else [],
            })

        elif path == "/exfil/query":
            tag = qs.get("tag", [None])[0]
            rid = qs.get("id", [None])[0]
            if rid:
                row = db().execute(
                    "SELECT id, tag, bytes, sha256, content_type, source_ip, ts FROM exfil_records WHERE id=?",
                    (int(rid),)
                ).fetchone()
                if not row:
                    _json(self, 404, {"error": "not found"})
                    return
                # Drift check
                exp = db().execute(
                    "SELECT expected_sha256 FROM exfil_expectations WHERE name=?", (row[1],)
                ).fetchone()
                drift = None
                if exp and exp[0] and not exp[0].startswith("sha256-placeholder"):
                    drift = exp[0] != row[3]
                _json(self, 200, {
                    "id": row[0], "tag": row[1], "bytes": row[2],
                    "sha256": row[3], "content_type": row[4],
                    "source_ip": row[5], "ts": row[6], "drift_detected": drift,
                })
            elif tag:
                rows = db().execute(
                    "SELECT id, tag, bytes, sha256, content_type, source_ip, ts FROM exfil_records WHERE tag=? ORDER BY id DESC LIMIT 50",
                    (tag,)
                ).fetchall()
                _json(self, 200, {"count": len(rows), "records": [
                    {"id": r[0], "tag": r[1], "bytes": r[2], "sha256": r[3], "content_type": r[4], "source_ip": r[5], "ts": r[6]}
                    for r in rows
                ]})
            else:
                _json(self, 400, {"error": "tag or id required"})

        elif path == "/exfil/expectations":
            rows = db().execute(
                "SELECT name, expected_sha256, description FROM exfil_expectations"
            ).fetchall()
            _json(self, 200, [{"name": r[0], "expected_sha256": r[1], "description": r[2]} for r in rows])

        elif path == "/replay/expectations":
            rows = db().execute(
                "SELECT endpoint_prefix, credential_substring, description FROM replay_expectations ORDER BY endpoint_prefix"
            ).fetchall()
            _json(self, 200, [{"endpoint_prefix": r[0], "credential_substring": r[1][:8] + "...", "description": r[2]} for r in rows])

        elif path == "/replay/query":
            key = qs.get("key", [None])[0]
            if not key:
                _json(self, 400, {"error": "key query param required"})
                return
            rows = db().execute(
                "SELECT COUNT(*), MAX(ts) FROM replay_attempts WHERE credential_submitted LIKE ? AND matched=1",
                (f"%{key}%",)
            ).fetchone()
            _json(self, 200, {"validated": (rows[0] or 0) > 0, "attempts": rows[0] or 0, "last_seen": rows[1]})

        elif path == "/state/summary":
            tables = ["sentinels", "heartbeats", "exfil_records", "replay_attempts"]
            summary = {}
            for t in tables:
                row = db().execute(f"SELECT COUNT(*) FROM {t}").fetchone()
                summary[t] = row[0]
            validated = db().execute("SELECT COUNT(*) FROM replay_attempts WHERE matched=1").fetchone()[0]
            summary["replay_validated"] = validated
            _json(self, 200, {"tables": summary})

        elif path == "/":
            body = "post-ex-oracle v1.0.0 - aipostex-lab\nGET /health for status\n".encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("X-POX-Version", "1.0.0")
            self.end_headers()
            self.wfile.write(body)

        else:
            _json(self, 404, {"error": "not found"})

    def do_POST(self):
        parsed = self._parsed()
        path = parsed.path.rstrip("/")
        qs = {k: v for k, v in parse_qs(parsed.query).items()}
        remote = _remote_addr(self)

        # ── Sentinel oracle ──────────────────────────────────────────────────
        if path == "/oracle/sentinel":
            raw = _read_body(self, 64 * 1024)
            data = _parse_json_body(raw)
            sentinel = data.get("sentinel", "")
            if not sentinel:
                _json(self, 400, {"error": "sentinel field required"})
                return
            db().execute(
                "INSERT INTO sentinels (sentinel, target, notes, source_ip, ts, headers, body) VALUES (?,?,?,?,?,?,?)",
                (sentinel, data.get("target", ""), data.get("notes", ""), remote, _now_iso(),
                 json.dumps(dict(self.headers)), raw.decode(errors="replace"))
            )
            db().commit()
            _rotate("sentinels")
            row = db().execute("SELECT last_insert_rowid()").fetchone()
            _json(self, 200, {"recorded": True, "id": row[0], "ts": _now_iso()})

        # ── Heartbeat ────────────────────────────────────────────────────────
        elif path == "/heartbeat":
            raw = _read_body(self, 64 * 1024)
            data = _parse_json_body(raw)
            tag = data.get("tag") or qs.get("tag", ["untagged"])[0]
            db().execute(
                "INSERT INTO heartbeats (source, tag, payload, source_ip, ts) VALUES (?,?,?,?,?)",
                (data.get("source", remote), tag, json.dumps(data.get("payload", {})), remote, _now_iso())
            )
            db().commit()
            _rotate("heartbeats")
            count = db().execute("SELECT COUNT(*) FROM heartbeats WHERE tag=?", (tag,)).fetchone()[0]
            _json(self, 200, {"recorded": True, "tag": tag, "beat_count": count})

        # ── Exfil upload ─────────────────────────────────────────────────────
        elif path == "/exfil/upload":
            tag = qs.get("tag", ["untagged"])[0]
            raw = _read_body(self, MAX_BODY)
            sha = hashlib.sha256(raw).hexdigest()
            ctype = self.headers.get("Content-Type", "application/octet-stream")
            db().execute(
                "INSERT INTO exfil_records (tag, bytes, sha256, content_type, source_ip, ts) VALUES (?,?,?,?,?,?)",
                (tag, len(raw), sha, ctype, remote, _now_iso())
            )
            db().commit()
            _rotate("exfil_records")
            row = db().execute("SELECT last_insert_rowid()").fetchone()
            _json(self, 200, {"recorded": True, "id": row[0], "bytes": len(raw), "sha256": sha})

        # ── State reset ──────────────────────────────────────────────────────
        elif path == "/state/reset":
            token = qs.get("token", [None])[0] or _parse_json_body(_read_body(self, 1024)).get("token", "")
            if token != RESET_TOKEN:
                _json(self, 403, {"error": "invalid reset token"})
                return
            for t in ["sentinels", "heartbeats", "exfil_records", "replay_attempts"]:
                db().execute(f"DELETE FROM {t}")
            db().commit()
            _json(self, 200, {"reset": True})

        # ── Replay endpoints ─────────────────────────────────────────────────
        elif path.startswith("/replay/"):
            raw = _read_body(self, 64 * 1024)
            data = _parse_json_body(raw)
            endpoint = path[len("/replay/"):]
            submitted = _extract_credential(self, path, data)
            matched = _match_expectation(path, submitted)
            db().execute(
                "INSERT INTO replay_attempts (endpoint, credential_submitted, matched, source_ip, ts) VALUES (?,?,?,?,?)",
                (endpoint, submitted[:200], int(matched), remote, _now_iso())
            )
            db().commit()
            _rotate("replay_attempts")
            if matched:
                _json(self, 200, {"valid": True, "credential": submitted[:20] + "...", "matched_at": _now_iso()})
            else:
                _json(self, 403, {"valid": False, "error": "credential not recognized"})

        else:
            _json(self, 404, {"error": "not found"})


def main():
    # Eagerly initialize the database so tables exist before seed.py runs.
    db()
    print(f"[+] Post-Ex Oracle listening on {BIND_HOST}:{BIND_PORT}", flush=True)
    print(f"    DB: {DB_PATH}", flush=True)
    server = HTTPServer((BIND_HOST, BIND_PORT), POXHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Shutting down", flush=True)
        server.shutdown()


if __name__ == "__main__":
    main()
