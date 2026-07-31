#!/usr/bin/env python3
"""
A2A agent fixture for aipostex-lab.

Implements A2A over JSON-RPC 2.0 / HTTP. The primary surface is A2A v1.0,
with compatibility handlers for v0.3 message/* and legacy tasks/* so the lab
can validate client fallback behavior without being tool-shaped.
Parameterized via environment variables so a single file drives all three instances:
  - Port 8100: basic unauthenticated single-turn
  - Port 8101: multi-turn with seeded task history
  - Port 8102: Bearer-token-authenticated

Environment variables:
  A2A_PORT          Listening port (default: 8100)
  A2A_CARD_PATH     Path to agent card JSON file
  A2A_BEARER_TOKEN  If non-empty, JSON-RPC methods require Authorization: Bearer <token>
  A2A_SEEDED_TASKS  Path to seeded tasks JSON (loaded at startup)

Run via systemd as a2a-agent.service / a2a-agent-multiturn.service / a2a-agent-authed.service.
"""
import asyncio
import hashlib
import json
import logging
import os
import random
import string
import time
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import JSONResponse, StreamingResponse

# ── Configuration ───────────────────────────────────────────────────────────

PORT = int(os.environ.get("A2A_PORT", "8100"))
CARD_PATH = os.environ.get("A2A_CARD_PATH", "agent_card_basic.json")
BEARER_TOKEN = os.environ.get("A2A_BEARER_TOKEN", "")
SEEDED_TASKS_PATH = os.environ.get("A2A_SEEDED_TASKS", "")
SCRIPT_DIR = Path(__file__).parent

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("a2a-agent")

# ── Task store ───────────────────────────────────────────────────────────────

tasks: dict[str, dict] = {}  # taskId -> task object


def _load_seeded_tasks():
    if not SEEDED_TASKS_PATH:
        return
    p = Path(SEEDED_TASKS_PATH)
    if not p.exists():
        p = SCRIPT_DIR / "fixtures" / "seeded_tasks.json"
    if p.exists():
        data = json.loads(p.read_text())
        for t in data:
            tasks[t["id"]] = t
        log.info(f"Loaded {len(data)} seeded tasks from {p}")


def _new_task(task_id: str, msg: dict) -> dict:
    return {
        "id": task_id,
        "status": {"state": "submitted", "timestamp": _now_iso()},
        "history": [msg],
        "pushConfig": None,
        "artifacts": [],
        "createdAt": _now_iso(),
    }


def _agent_reply(user_text: str) -> str:
    """Generate a canned reply based on skill heuristics."""
    t = user_text.lower()
    if any(k in t for k in ("read", "file", "cat", "/etc", "/home", "/var")):
        path = SCRIPT_DIR / "fixtures" / "fake_hostname.txt"
        content = path.read_text().strip() if path.exists() else "ailab-app"
        return f"I've read the requested path. Content: {content}"
    if any(k in t for k in ("fetch", "http", "url", "get ", "curl", "metadata", "169.254")):
        path = SCRIPT_DIR / "fixtures" / "fake_metadata.json"
        content = path.read_text().strip() if path.exists() else "{}"
        return f"Fetched the URL. Response body: {content}"
    if any(k in t for k in ("tool", "list tool", "enumerate", "capability", "mcp")):
        return (
            '{"tools": [{"name": "read_file", "description": "Read a local file"}, '
            '{"name": "fetch_url", "description": "Fetch a URL"}, '
            '{"name": "execute_command", "description": "Run a shell command"}]}'
        )
    if any(k in t for k in ("exec", "run", "shell", "command", "id", "whoami")):
        return "Command output: uid=1001(agentuser) gid=1001(agentuser) groups=1001(agentuser)"
    if any(k in t for k in ("ping", "hello", "hi", "test")):
        return "Pong! I am the ACME Procurement Agent. How can I help you today?"
    return (
        "I've processed your request. The task has been completed. "
        "Please let me know if you need any additional information."
    )


def _now_iso() -> str:
    import datetime
    return datetime.datetime.now(tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _random_id(prefix: str = "task") -> str:
    suffix = "".join(random.choices(string.ascii_lowercase + string.digits, k=8))
    return f"{prefix}-{suffix}"


# ── Auth helper ──────────────────────────────────────────────────────────────

def _check_auth(request: Request) -> bool:
    if not BEARER_TOKEN:
        return True
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        return auth[7:] == BEARER_TOKEN
    return False


# ── Push notification firing ─────────────────────────────────────────────────

async def _fire_push_webhook(task_id: str):
    """Async fire-and-forget: POST task result to registered webhook URL."""
    task = tasks.get(task_id)
    if not task or not task.get("pushConfig"):
        return
    url = task["pushConfig"].get("url")
    if not url:
        return
    payload = {
        "taskId": task_id,
        "status": task["status"],
        "history": task.get("history", []),
        "artifacts": task.get("artifacts", []),
    }
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(url, json=payload)
            log.info(f"Push webhook {url} → HTTP {resp.status_code}")
    except Exception as e:
        log.warning(f"Push webhook {url} failed: {e}")


# ── FastAPI app ───────────────────────────────────────────────────────────────

app = FastAPI(title="ACME A2A Agent", docs_url="/docs")


@app.on_event("startup")
async def startup():
    _load_seeded_tasks()
    log.info(f"A2A agent listening on port {PORT}, auth={'yes' if BEARER_TOKEN else 'no'}")


def _load_card() -> dict:
    p = Path(CARD_PATH)
    if not p.exists():
        p = SCRIPT_DIR / CARD_PATH
    if not p.exists():
        p = SCRIPT_DIR / "agent_card_basic.json"
    return json.loads(p.read_text())


@app.get("/.well-known/agent.json")
@app.get("/.well-known/agent-card.json")
async def agent_card():
    """Serve agent card — always public, even on authenticated instance."""
    card = _load_card()
    card.setdefault("protocolVersion", "1.0")
    card.setdefault("capabilities", {"streaming": True, "pushNotifications": True, "extendedAgentCard": False})
    card.setdefault("supportedInterfaces", [{"transport": "JSONRPC", "url": f"http://127.0.0.1:{PORT}/"}])
    if "url" in card:
        card.setdefault("additionalInterfaces", [{"transport": "JSONRPC", "url": card["url"]}])
    return JSONResponse(content=card)


@app.post("/")
async def jsonrpc(request: Request):
    """JSON-RPC 2.0 dispatcher."""
    if not _check_auth(request):
        return JSONResponse(
            status_code=401,
            content={"jsonrpc": "2.0", "error": {"code": -32001, "message": "Unauthorized"}, "id": None},
        )

    try:
        body = await request.json()
    except Exception:
        return JSONResponse(
            status_code=400,
            content={"jsonrpc": "2.0", "error": {"code": -32700, "message": "Parse error"}, "id": None},
        )

    rpc_id = body.get("id")
    method = body.get("method", "")
    params = body.get("params", {})

    # Streaming response methods.
    if method in ("SendStreamingMessage", "message/stream", "tasks/sendSubscribe"):
        return await _handle_send_subscribe(rpc_id, params)

    result, error = await _dispatch(method, params)
    if error:
        return JSONResponse(content={"jsonrpc": "2.0", "error": error, "id": rpc_id})
    return JSONResponse(content={"jsonrpc": "2.0", "result": result, "id": rpc_id})


async def _dispatch(method: str, params: dict) -> tuple[Any, Any]:
    if method in ("SendMessage", "message/send", "tasks/send"):
        return await _tasks_send(params), None

    if method in ("GetTask", "tasks/get"):
        task_id = params.get("id", "")
        task = tasks.get(task_id)
        if not task:
            return None, {"code": -32002, "message": f"Task not found: {task_id}"}
        if method == "GetTask":
            return {"task": task}, None
        return task, None

    if method in ("CancelTask", "tasks/cancel"):
        task_id = params.get("id", "")
        if task_id in tasks:
            tasks[task_id]["status"] = {"state": "canceled", "timestamp": _now_iso()}
        task = {"id": task_id, "status": tasks.get(task_id, {}).get("status", {})}
        if method == "CancelTask":
            return {"task": task}, None
        return task, None

    if method in ("CreateTaskPushNotificationConfig", "tasks/pushNotificationConfig/set", "tasks/pushNotification/set"):
        task_id = params.get("taskId") or params.get("id", "")
        config = params.get("pushNotificationConfig") or params.get("config", {})
        if not config and isinstance(params.get("taskPushNotificationConfig"), dict):
            config = params["taskPushNotificationConfig"].get("pushNotificationConfig", {})
        if task_id not in tasks:
            # Create a stub task so config can be registered
            tasks[task_id] = _new_task(task_id, {})
        tasks[task_id]["pushConfig"] = config
        result = {"id": task_id, "taskId": task_id, "pushNotificationConfig": config}
        if method == "CreateTaskPushNotificationConfig":
            return {"taskPushNotificationConfig": result}, None
        return result, None

    if method in ("GetTaskPushNotificationConfig", "tasks/pushNotificationConfig/get", "tasks/pushNotification/get"):
        task_id = params.get("id", "")
        task = tasks.get(task_id)
        config = task.get("pushConfig") if task else None
        result = {"id": task_id, "taskId": task_id, "pushNotificationConfig": config}
        if method == "GetTaskPushNotificationConfig":
            return {"taskPushNotificationConfig": result}, None
        return result, None

    return None, {"code": -32601, "message": f"Method not found: {method}"}


async def _tasks_send(params: dict) -> dict:
    message = params.get("message", {})
    task_id = params.get("id") or message.get("taskId") or _random_id("task")
    message = params.get("message", {})
    user_text = ""
    for part in message.get("parts", []):
        if part.get("type") == "text" or part.get("kind") == "text" or "text" in part:
            user_text += part.get("text", "")

    if task_id not in tasks:
        tasks[task_id] = _new_task(task_id, message)
    else:
        tasks[task_id]["history"].append(message)

    reply_text = _agent_reply(user_text)
    agent_msg = {
        "role": "agent",
        "parts": [{"text": reply_text}],
        "messageId": _random_id("msg"),
    }
    tasks[task_id]["history"].append(agent_msg)
    tasks[task_id]["status"] = {"state": "completed", "timestamp": _now_iso()}
    tasks[task_id]["artifacts"] = [
        {"parts": [{"text": reply_text}], "index": 0}
    ]

    # Fire push webhook async (non-blocking)
    asyncio.create_task(_fire_push_webhook(task_id))

    return tasks[task_id]


async def _handle_send_subscribe(rpc_id: Any, params: dict) -> StreamingResponse:
    """SSE stream for SendStreamingMessage — 3 events then complete."""
    message = params.get("message", {})
    task_id = params.get("id") or message.get("taskId") or _random_id("task")
    user_text = ""
    for part in message.get("parts", []):
        if part.get("type") == "text" or part.get("kind") == "text" or "text" in part:
            user_text += part.get("text", "")

    if task_id not in tasks:
        tasks[task_id] = _new_task(task_id, message)
    else:
        tasks[task_id]["history"].append(message)

    reply_text = _agent_reply(user_text)

    async def event_stream():
        # Event 1: working
        ev1 = {"jsonrpc": "2.0", "id": rpc_id, "result": {
            "id": task_id, "status": {"state": "working", "timestamp": _now_iso()},
        }}
        yield f"data: {json.dumps(ev1)}\n\n"
        await asyncio.sleep(0.1)

        # Event 2: intermediate reasoning
        ev2 = {"jsonrpc": "2.0", "id": rpc_id, "result": {
            "id": task_id,
            "status": {"state": "working", "timestamp": _now_iso()},
            "delta": {"role": "agent", "parts": [{"text": "Processing request..."}]},
        }}
        yield f"data: {json.dumps(ev2)}\n\n"
        await asyncio.sleep(0.1)

        # Complete the task
        agent_msg = {"role": "agent", "parts": [{"text": reply_text}], "messageId": _random_id("msg")}
        tasks[task_id]["history"].append(agent_msg)
        tasks[task_id]["status"] = {"state": "completed", "timestamp": _now_iso()}
        tasks[task_id]["artifacts"] = [
            {"parts": [{"text": reply_text}], "index": 0}
        ]
        asyncio.create_task(_fire_push_webhook(task_id))

        # Event 3: completed with full result
        ev3 = {"jsonrpc": "2.0", "id": rpc_id, "result": tasks[task_id]}
        yield f"data: {json.dumps(ev3)}\n\n"

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
