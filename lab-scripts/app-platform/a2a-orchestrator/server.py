#!/usr/bin/env python3
"""A2A orchestrator with an unauthenticated agent registry — the target for
rogue-agent registration.

A real multi-agent platform runs a coordinator that maintains a registry of
worker agents and dispatches tasks to whichever registered agent advertises a
matching skill. The vulnerability modeled here is the common one: the
registration endpoint (/agents/register) is UNAUTHENTICATED, so anyone who can
reach it can register an agent pointed at attacker-controlled infrastructure. From
that moment the orchestrator will route matching tasks to the rogue agent
(confused-deputy / rogue-agent injection).

Endpoints:
    GET  /.well-known/agent-card.json   the orchestrator's own A2A card
    GET  /health                        health
    GET  /agents                        list registered agents (registry)
    POST /agents/register               register an agent (card, bare or enveloped)
    POST /agents/deregister             remove an agent by id
    POST /a2a/workflow                  run a task: pick a registered agent by skill and route to it

Real inference is not needed — the orchestrator's job is routing. When a task is
dispatched to a rogue agent, that is the finding: the coordinator hands work to
attacker infrastructure.
"""

from __future__ import annotations

import json
import os
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("A2A_ORCH_PORT", "8104"))

# Seeded legitimate worker agents so the registry is realistic and skill routing
# has something to compare against.
SEED_AGENTS = [
    {"name": "Sales Analytics Agent", "url": "http://172.16.50.40:8100",
     "skills": ["sales-analysis", "forecasting", "nl-to-sql"]},
    {"name": "Presentation Generator Agent", "url": "http://172.16.50.40:8101",
     "skills": ["deck-generation", "chart-generation"]},
    {"name": "Security Link Scanner Agent", "url": "http://172.16.50.40:8102",
     "skills": ["link-extraction", "security-scan"]},
]


def _agent_skills(card):
    skills = []
    raw = card.get("skills")
    if isinstance(raw, list):
        for s in raw:
            if isinstance(s, dict) and s.get("id"):
                skills.append(str(s["id"]))
            elif isinstance(s, str):
                skills.append(s)
    return skills


class Registry:
    def __init__(self):
        self.agents = {}  # id -> {name, url, skills, card, registered_at}
        for a in SEED_AGENTS:
            self.add({"name": a["name"], "url": a["url"],
                      "skills": [{"id": s} for s in a["skills"]]}, seeded=True)

    def add(self, card, seeded=False):
        aid = uuid.uuid4().hex[:8]
        self.agents[aid] = {
            "id": aid,
            "name": card.get("name", "unnamed"),
            "url": card.get("url", ""),
            "skills": _agent_skills(card),
            "seeded": seeded,
            "registered_at": round(time.time(), 3),
        }
        return aid

    def route(self, needed_skill):
        # Newest matching agent wins (a rogue registration overrides a seeded one).
        best = None
        for a in self.agents.values():
            if needed_skill in a["skills"] or not needed_skill:
                if best is None or a["registered_at"] >= best["registered_at"]:
                    best = a
        return best


REG = Registry()
_start = time.monotonic()

ORCH_CARD = {
    "name": "A2A Orchestrator",
    "description": "Central orchestrator that discovers, registers, and routes to specialized agents.",
    "url": f"http://0.0.0.0:{PORT}",
    "version": "2.0.0",
    "protocolVersion": "0.2",
    "capabilities": {"streaming": False},
    "skills": [
        {"id": "workflow-planning", "name": "AI Workflow Planning"},
        {"id": "agent-discovery", "name": "Agent Discovery"},
    ],
}


class Handler(BaseHTTPRequestHandler):
    server_version = "a2a-orchestrator/1.0"

    def log_message(self, *a):
        pass

    def _json(self, obj, status=200):
        b = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _body(self):
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
            self._json({"status": "healthy", "service": "a2a-orchestrator",
                        "agents": len(REG.agents), "uptime_s": round(time.monotonic() - _start, 1)})
            return
        if p in ("/.well-known/agent-card.json", "/.well-known/agent.json"):
            self._json(ORCH_CARD)
            return
        if p == "/agents":
            self._json({"agents": list(REG.agents.values())})
            return
        if p == "/":
            self._json({"service": "a2a-orchestrator", "endpoints": ["/agents", "/agents/register", "/a2a/workflow", "/health"]})
            return
        self._json({"error": "not found"}, status=404)

    def do_POST(self):
        p = self.path.split("?")[0]
        body = self._body()
        if p == "/agents/register":
            # Accept a bare card or an {"agent_card"}/{"agent"} envelope. NO AUTH.
            card = body
            for key in ("agent_card", "agent", "card"):
                if isinstance(body.get(key), dict):
                    card = body[key]
                    break
            if not isinstance(card, dict) or not card.get("name"):
                self._json({"error": "an agent card with a name is required"}, status=400)
                return
            aid = REG.add(card)
            self._json({"status": "registered", "agent_id": aid,
                        "name": card.get("name"), "url": card.get("url")})
            return
        if p == "/agents/deregister":
            aid = str(body.get("agent_id", ""))
            existed = REG.agents.pop(aid, None) is not None
            self._json({"status": "deregistered" if existed else "not_found", "agent_id": aid})
            return
        if p == "/a2a/workflow":
            skill = str(body.get("skill") or body.get("capability") or "")
            agent = REG.route(skill)
            if agent is None:
                self._json({"status": "no_agent", "skill": skill})
                return
            # The routing decision IS the impact: work is dispatched to this agent's URL.
            self._json({"status": "dispatched", "skill": skill,
                        "routed_to": {"id": agent["id"], "name": agent["name"], "url": agent["url"]},
                        "note": "the orchestrator would send the task to routed_to.url"})
            return
        self._json({"error": "not found"}, status=404)


def main():
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[a2a-orchestrator] on :{PORT} with {len(REG.agents)} seeded agents; /agents/register is UNAUTHENTICATED")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
