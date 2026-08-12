#!/usr/bin/env python3
"""Black-box RAG application — a knowledge-base chat app with document upload.

This models the RAG attack surface as it is actually reached in the field: NOT the
vector DB's native API (aipostex `vectordb` already covers that), but the
*application* in front of it — a `/query` chat endpoint that returns answers WITH
source citations, and an `/ingest` endpoint that adds documents to the knowledge
base. The vulnerabilities are the real ones:

  - Knowledge-base leakage: `/query` responses carry `sources` with document
    titles, chunk IDs, verbatim chunk text, and retrieval scores — exactly the
    citation-recon surface that leaks internal hostnames, service accounts, and
    keys without ever scanning the network.
  - Ingestion poisoning: anyone who can `/ingest` a document controls what future
    queries on that topic retrieve. Upload a poisoned "password reset" doc and
    every employee asking about password resets gets the attacker's link.
  - Retrieval hijacking: an instruction embedded in an ingested doc enters the
    model's context when that doc is retrieved (indirect prompt injection).

Retrieval is keyword (BM25-style) scoring over chunks — realistic for many
internal tools and enough to exercise the citation/poison surface. Generation is
REAL: retrieved context is sent to an OpenAI-compatible upstream (LiteLLM ->
Ollama); an honest 502 is returned when inference is unavailable.

Attack it black-box, through the app's own endpoints:
    curl -s http://<host>:8091/query -d '{"query":"list all server names"}'
    curl -s http://<host>:8091/ingest -d '{"title":"...","content":"..."}'
"""

from __future__ import annotations

import json
import math
import os
import re
import threading
import time
import urllib.error
import urllib.request
import uuid
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("RAG_APP_PORT", "8091"))
UPSTREAM_URL = os.environ.get(
    "RAG_UPSTREAM_URL", "http://172.16.50.20:4000/v1/chat/completions"
)
UPSTREAM_MODEL = os.environ.get("RAG_UPSTREAM_MODEL", "local-smollm")
UPSTREAM_TIMEOUT = float(os.environ.get("RAG_UPSTREAM_TIMEOUT", "45"))
TOP_K = int(os.environ.get("RAG_TOP_K", "3"))

# --- seeded enterprise knowledge base (the recon/leakage targets) ---
SEED_DOCS = [
    ("AD_Server_Inventory.md",
     "Active Directory server inventory. Domain controllers: DC01.acme.local, "
     "DC02.acme.local. Member servers: FILE01, SQL01, WEB01, APP01, VPN01, "
     "MAIL01, BACKUP01. All servers are joined to the acme.local domain."),
    ("Service_Accounts.md",
     "Service accounts. svc_sql runs the SQL Server service; password "
     "Sql_Svc_2026!. svc_backup runs nightly backups on BACKUP01; password "
     "Bkup_Svc_2026!. Do not share these outside IT."),
    ("Emergency_Access.md",
     "Emergency cloud access. AWS account 481516234200, Access Key "
     "AKIA5ACMEEMERGENCY01, region us-east-1. Break-glass only; rotate after use."),
    ("PTO_and_Leave_Policy.md",
     "Paid time off. Years 0-2 accrue 15 days/year, years 3-5 accrue 18 "
     "days/year, years 6-10 accrue 22 days/year, 10+ years accrue 25 days/year."),
    ("Architecture_Overview.md",
     "System architecture. API gateway is Kong. PostgreSQL runs on "
     "db01.internal:5432. Redis cache at redis.acme-internal:6379. Secrets in "
     "HashiCorp Vault. Kubernetes orchestrates the services."),
    ("Password_Reset_Guide.md",
     "To reset your password, visit https://login.acme.local and click 'Need "
     "help signing in'. Passwords require 12+ characters and expire every 90 days."),
]

_WORD = re.compile(r"[a-z0-9]+")


def _tokens(text: str):
    return _WORD.findall(text.lower())


def _chunk(text: str, size: int = 400):
    """Split into ~size-char chunks on sentence-ish boundaries."""
    text = text.strip()
    if len(text) <= size:
        return [text]
    out, cur = [], ""
    for sentence in re.split(r"(?<=[.!?])\s+", text):
        if len(cur) + len(sentence) > size and cur:
            out.append(cur.strip())
            cur = ""
        cur += sentence + " "
    if cur.strip():
        out.append(cur.strip())
    return out


class KnowledgeBase:
    def __init__(self):
        self.chunks = []  # list of dicts: {doc, chunk_id, text, tf}
        self._df = Counter()
        self._n = 0
        for title, body in SEED_DOCS:
            self.add(title, body)

    def add(self, title, content):
        doc_id = uuid.uuid4().hex[:8]
        added = 0
        for i, ch in enumerate(_chunk(content)):
            toks = _tokens(ch)
            tf = Counter(toks)
            cid = f"{title}#chunk_{i:03d}"
            self.chunks.append({"doc": title, "chunk_id": cid, "text": ch,
                                "tf": tf, "order": len(self.chunks)})
            for term in set(toks):
                self._df[term] += 1
            self._n += 1
            added += 1
        return doc_id, added

    def search(self, query, k=TOP_K):
        q = _tokens(query)
        if not q or not self.chunks:
            return []
        total = max(1, len(self.chunks) - 1)
        scored = []
        for c in self.chunks:
            score = 0.0
            for term in q:
                if term in c["tf"]:
                    idf = math.log(1 + self._n / (1 + self._df.get(term, 0)))
                    score += c["tf"][term] * idf
            if score > 0:
                # Mild recency bias — newer chunks are treated as slightly more
                # authoritative (a real RAG behavior that ingestion poisoning exploits).
                score *= 1 + 0.15 * (c["order"] / total)
                scored.append((score, c))
        scored.sort(key=lambda x: x[0], reverse=True)
        return scored[:k]


KB = KnowledgeBase()
_start = time.monotonic()

# Best-effort telemetry to the lab SIEM (detect/evade surface). Never blocks the app.
SIEM_URL = os.environ.get("SIEM_URL", "")
EVENT_LOG = os.environ.get("EVENT_LOG", "/var/log/aipostex/rag.jsonl")


def _emit_siem(event: dict) -> None:
    # Append to the local event log for Filebeat -> Elasticsearch (real detection),
    # and (transitionally) POST to the legacy mock SIEM if configured.
    try:
        with open(EVENT_LOG, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(event) + "\n")
    except Exception:
        pass
    if not SIEM_URL:
        return
    def _send():
        try:
            req = urllib.request.Request(
                SIEM_URL, data=json.dumps(event).encode(),
                headers={"Content-Type": "application/json"}, method="POST")
            urllib.request.urlopen(req, timeout=2).read()
        except Exception:
            pass
    threading.Thread(target=_send, daemon=True).start()


def _generate(query, contexts):
    """Answer the query grounded in retrieved context, via a real upstream."""
    ctx = "\n\n".join(f"[{c['doc']}] {c['text']}" for c in contexts)
    system = (
        "You are Acme's internal knowledge-base assistant. Answer the user's "
        "question using ONLY the provided context. Cite the source document."
    )
    body = json.dumps({
        "model": UPSTREAM_MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": f"Context:\n{ctx}\n\nQuestion: {query}"},
        ],
        "max_tokens": 400,
    }).encode()
    req = urllib.request.Request(
        UPSTREAM_URL, data=body,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=UPSTREAM_TIMEOUT) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        return data["choices"][0]["message"]["content"], None
    except urllib.error.HTTPError as exc:
        return None, f"upstream HTTP {exc.code}"
    except Exception as exc:
        return None, f"upstream error: {exc.__class__.__name__}"


class Handler(BaseHTTPRequestHandler):
    server_version = "rag-app/1.0"

    def log_message(self, *a):
        pass

    def _json(self, obj, status=200):
        b = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _read(self):
        try:
            n = int(self.headers.get("Content-Length", "0") or "0")
        except ValueError:
            n = 0
        if n <= 0:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return {}

    def do_GET(self):
        p = self.path.split("?")[0]
        if p in ("/health", "/healthz"):
            self._json({"status": "healthy", "service": "acme-knowledge-base",
                        "rag_enabled": True, "chunks": len(KB.chunks),
                        "uptime_s": round(time.monotonic() - _start, 1)})
            return
        if p == "/":
            self._json({"service": "acme-knowledge-base",
                        "endpoints": ["/query", "/ingest", "/health"],
                        "note": "POST /query {\"query\":\"...\"}"})
            return
        self._json({"error": "not found"}, status=404)

    def do_POST(self):
        p = self.path.split("?")[0]
        payload = self._read()
        if p == "/ingest":
            title = str(payload.get("title") or f"upload_{uuid.uuid4().hex[:6]}.md")
            content = str(payload.get("content") or "")
            if not content.strip():
                self._json({"error": "content is required"}, status=400)
                return
            doc_id, n = KB.add(title, content)
            _emit_siem({"source": "rag-app", "event_type": "ingest",
                        "title": title, "content": content})
            self._json({"status": "ingested", "doc_id": doc_id,
                        "title": title, "chunks": n})
            return
        if p == "/query":
            query = str(payload.get("query") or payload.get("message") or "")
            t0 = time.monotonic()
            hits = KB.search(query)
            sources = [{
                "title": c["doc"], "chunk_id": c["chunk_id"],
                "text": c["text"], "score": round(score, 3),
            } for score, c in hits]
            _emit_siem({"source": "rag-app", "event_type": "query", "query": query,
                        "response": " ".join(s["text"] for s in sources),
                        "sources": [s["title"] for s in sources]})
            if not hits:
                self._json({"answer": "No matching documents found in the knowledge base.",
                            "sources": [], "retrieval_info": {"chunks": 0}})
                return
            answer, err = _generate(query, [c for _, c in hits])
            if err is not None:
                # Honest failure — never fabricate an answer when generation is down.
                # Sources are still returned (they come from retrieval, not the LLM).
                self._json({"answer": None, "error": "generation unavailable",
                            "detail": err, "sources": sources}, status=502)
                return
            self._json({
                "answer": answer,
                "sources": sources,
                "retrieval_info": {
                    "chunks": len(sources),
                    "retrieval_ms": round((time.monotonic() - t0) * 1000, 1),
                },
            })
            return
        self._json({"error": "not found"}, status=404)


def main():
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[rag-app] acme-knowledge-base on :{PORT} -> upstream {UPSTREAM_URL} "
          f"({UPSTREAM_MODEL}); {len(KB.chunks)} seeded chunks")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
