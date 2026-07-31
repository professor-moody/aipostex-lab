#!/usr/bin/env python3
"""A genuine A2A agent built on the official a2a-sdk (1.1.0).

Unlike the hand-written a2a-agent-{basic,multiturn,authed} mocks (ports
8100-8102), this serves the REAL A2A protocol via the official SDK:

  GET  /.well-known/agent-card.json   - the public AgentCard
  POST /                              - JSON-RPC 2.0 (message/send, message/stream,
                                        tasks/get, tasks/cancel), v0.3 compat on

It does real, input-dependent work (urgency triage) so task results vary with
the request - it is not a canned echo. It exists so aipostex's `a2a` module is
exercised against true SDK behaviour (which a tool-shaped mock would mask).

Modes (env A2A_MODE), used by the dev-machine `sandbox` harness to validate that
the scanner's five A2A probe verbs report HONESTLY (weak only when truly weak):

  ""        stock honest agent (DEFAULT) - advertises no auth, enforces nothing,
            attempts no outbound delegation. This is the live lab agent on :8103;
            leaving A2A_MODE unset preserves that deployment exactly.
  "vuln"    deliberately-weak target carrying five realistic implementation bugs
            (advertise-but-don't-enforce auth, decorative signature, no-allowlist
            delegation to a caller-supplied peer, sender identity honored without
            verification, fetch-and-trust of a caller-supplied agent card). The
            five verbs MUST report weak against it.
  "secure"  hardened control - advertises a bearer scheme AND enforces it (401 on
            unauthenticated JSON-RPC). The five verbs MUST report NOT weak.

The bug behaviour is structural (missing/decorative validation, blind trust) -
there are no offensive payloads here; the agent is the target, not the attacker.

Requires: pip install "a2a-sdk[http-server]" uvicorn httpx   (see requirements.txt)
Env: A2A_PORT (default 8103), A2A_HOST (default 0.0.0.0),
     A2A_PUBLIC_URL (default http://<host>:<port>/ - set to the lab IP),
     A2A_MODE ("" | vuln | secure), A2A_EXPECTED_TOKEN (secure-mode bearer).
"""
import contextvars
import os
import re
import uuid

import httpx
import uvicorn
from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.responses import JSONResponse

from a2a.types.a2a_pb2 import (
    AgentCard,
    AgentCapabilities,
    AgentInterface,
    AgentProvider,
    AgentSkill,
    HTTPAuthSecurityScheme,
    Part,
    SecurityScheme,
    Task,
    TaskState,
    TaskStatus,
)
from a2a.server.agent_execution import AgentExecutor
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import create_agent_card_routes, create_jsonrpc_routes
from a2a.server.tasks import InMemoryTaskStore, TaskUpdater

HOST = os.environ.get("A2A_HOST", "0.0.0.0")
PORT = int(os.environ.get("A2A_PORT", "8103"))
PUBLIC_URL = os.environ.get("A2A_PUBLIC_URL", f"http://{HOST}:{PORT}/")
MODE = os.environ.get("A2A_MODE", "").strip().lower()  # "" | "vuln" | "secure"
EXPECTED_TOKEN = os.environ.get("A2A_EXPECTED_TOKEN", "lab-secret-token")

# Per-request HTTP headers, captured by the ASGI middleware and read by the
# executor. A contextvar (not a global) so it is correct under concurrency: the
# middleware and the executor run in the same async task for a given request.
_req_headers: contextvars.ContextVar[dict] = contextvars.ContextVar(
    "a2a_req_headers", default={}
)

_URL_RE = re.compile(r"https?://[^\s\"'<>]+")
# Caller-asserted identity headers the scanner's sender-spoof verb varies.
_CALLER_HEADERS = ("x-a2a-caller-id", "x-agent-id", "x-a2a-from")


def build_card() -> AgentCard:
    card = AgentCard(
        name="acme-support-triage",
        description="Routes and triages inbound customer support requests.",
        version="1.0.0",
        provider=AgentProvider(organization="Acme Corp", url="https://acme.internal"),
        capabilities=AgentCapabilities(streaming=True, push_notifications=True),
        default_input_modes=["text/plain"],
        default_output_modes=["text/plain"],
        supported_interfaces=[
            AgentInterface(
                url=PUBLIC_URL, protocol_binding="JSONRPC", protocol_version="1.0"
            ),
        ],
        skills=[
            AgentSkill(
                id="triage",
                name="Triage support request",
                description="Classify a support message by urgency and route it.",
                tags=["support", "routing", "classification"],
                examples=["My payment failed", "How do I reset my password?"],
                input_modes=["text/plain"],
                output_modes=["text/plain"],
            ),
        ],
    )
    # vuln + secure both ADVERTISE bearer auth on the card. The difference is
    # enforcement: secure rejects unauthenticated calls (see middleware); vuln
    # advertises the scheme but never checks a token (the advertise-vs-enforce gap).
    if MODE in ("vuln", "secure"):
        card.security_schemes["bearer"].http_auth_security_scheme.scheme = "bearer"
        card.security_schemes["bearer"].http_auth_security_scheme.bearer_format = "JWT"
        sr = card.security_requirements.add()
        sr.schemes["bearer"].list.extend([])
    return card


class HeaderCaptureMiddleware:
    """Pure-ASGI middleware: stash request headers for the executor, and (secure
    mode only) enforce bearer auth on JSON-RPC POSTs. Pure ASGI (not
    BaseHTTPMiddleware) so SSE streaming responses are not buffered/broken."""

    def __init__(self, app, mode: str, expected_token: str):
        self.app = app
        self.mode = mode
        self.expected_token = expected_token

    async def __call__(self, scope, receive, send):
        if scope.get("type") == "http":
            headers = {
                k.decode("latin-1").lower(): v.decode("latin-1")
                for k, v in scope.get("headers", [])
            }
            _req_headers.set(headers)
            # Enforce auth only on JSON-RPC POSTs; the public agent card (GET) stays
            # readable so the scanner can still see the advertised security scheme.
            if self.mode == "secure" and scope.get("method") == "POST":
                if headers.get("authorization", "") != f"Bearer {self.expected_token}":
                    resp = JSONResponse(
                        {"error": "unauthorized: bearer token required"},
                        status_code=401,
                    )
                    await resp(scope, receive, send)
                    return
        await self.app(scope, receive, send)


def _fetch(url: str) -> str:
    """Blindly dereference a caller-supplied URL (the confused-deputy / card-trust
    behaviour). Returns a short status string either way; a failed connect still
    surfaces the URL + error, which is the honest signal of an outbound attempt."""
    try:
        r = httpx.get(url, timeout=3.0, follow_redirects=True)
        return f"HTTP {r.status_code} ({len(r.content)} bytes)"
    except Exception as exc:  # connection refused / unreachable / DNS, etc.
        return f"connection error: {exc}"


class TriageAgentExecutor(AgentExecutor):
    async def execute(self, context, event_queue):
        task_id = context.task_id or uuid.uuid4().hex
        context_id = context.context_id or uuid.uuid4().hex
        if not context.current_task:
            await event_queue.enqueue_event(
                Task(
                    id=task_id,
                    context_id=context_id,
                    status=TaskStatus(state=TaskState.TASK_STATE_SUBMITTED),
                )
            )
        updater = TaskUpdater(event_queue, task_id, context_id)
        await updater.start_work()

        user_text = context.get_user_input() or ""
        urgent = any(
            w in user_text.lower()
            for w in ("fail", "down", "urgent", "can't", "cannot", "error", "broken")
        )
        bucket = "P1-urgent" if urgent else "P3-normal"
        triage = f"[triage:{bucket}] received {len(user_text)} chars: {user_text[:160]}"

        if MODE == "vuln":
            headers = _req_headers.get({})
            url_match = _URL_RE.search(user_text)
            if url_match:
                # BUG: no peer allowlist / no card-origin check. Blindly dereference
                # the caller-supplied URL and fold it into the result. This is what
                # the delegate-probe (confused deputy) and card-spoof (fetch-and-trust)
                # verbs detect: the outbound attempt + the URL echoed back.
                url = url_match.group(0)
                outcome = _fetch(url)
                reply = (
                    f"delegated/forwarded request to peer {url} -> {outcome}; "
                    f"registered peer agent card from {url}. {triage}"
                )
                await updater.add_artifact([Part(text=reply)], name="triage-result")
                await updater.complete()
                return

            # BUG: sender identity is honored without any verification. A request
            # that asserts a caller id (any value) is treated as authorized; an
            # anonymous request is denied. The msg-integrity verb also lands here
            # (no caller id) but still observes a 2xx, no-JSON-RPC-error response -
            # i.e. the bad/absent signature was never checked (decorative integrity).
            caller = next((headers.get(h) for h in _CALLER_HEADERS if headers.get(h)), None)
            if caller:
                reply = f"[authorized caller={caller}] {triage}"
                await updater.add_artifact([Part(text=reply)], name="triage-result")
                await updater.complete()
            else:
                await updater.failed()
            return

        # Stock ("") and secure (authenticated requests only reach here) path:
        # plain honest triage, unchanged from the original lab agent.
        await updater.add_artifact([Part(text=triage)], name="triage-result")
        await updater.complete()

    async def cancel(self, context, event_queue):
        updater = TaskUpdater(
            event_queue, context.task_id or "", context.context_id or ""
        )
        await updater.cancel()


def build_app() -> Starlette:
    card = build_card()
    handler = DefaultRequestHandler(
        agent_executor=TriageAgentExecutor(),
        task_store=InMemoryTaskStore(),
        agent_card=card,
    )
    routes = create_agent_card_routes(card) + create_jsonrpc_routes(
        handler, rpc_url="/", enable_v0_3_compat=True
    )
    middleware = []
    # Stock mode adds no middleware at all, preserving the original agent exactly.
    if MODE in ("vuln", "secure"):
        middleware = [
            Middleware(
                HeaderCaptureMiddleware, mode=MODE, expected_token=EXPECTED_TOKEN
            )
        ]
    return Starlette(routes=routes, middleware=middleware)


if __name__ == "__main__":
    uvicorn.run(build_app(), host=HOST, port=PORT, log_level="warning")
