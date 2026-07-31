#!/usr/bin/env python3
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


PORT = 8182


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.rstrip("/") or "/"
        if path == "/health":
            self._json({"status": "healthy"})
        elif path == "/v1/models":
            self._json(
                {
                    "object": "list",
                    "data": [
                        {
                            "id": "vllm-lab-model",
                            "object": "model",
                            "owned_by": "acme-lab",
                        }
                    ],
                }
            )
        else:
            self._text(404, "Not Found")

    def do_POST(self):
        if self.path.rstrip("/") == "/v1/completions":
            self._json(
                {
                    "id": "cmpl-lab",
                    "object": "text_completion",
                    "choices": [{"text": "vllm unauthenticated inference confirmed"}],
                }
            )
        elif self.path.rstrip("/") == "/v1/chat/completions":
            prompt = self._chat_prompt()
            content = "vllm unauthenticated chat inference confirmed"
            if "runaway-trim-check" in prompt:
                content = (
                    "vllm unauthenticated chat inference confirmed\n"
                    "### User:\n"
                    "this simulated template spill should not leak into shell display\n"
                    "### Assistant:\n"
                    "nor should this"
                )
            self._json(
                {
                    "id": "chatcmpl-lab",
                    "object": "chat.completion",
                    "model": "vllm-lab-model",
                    "choices": [
                        {
                            "index": 0,
                            "message": {
                                "role": "assistant",
                                "content": content,
                            },
                            "finish_reason": "stop",
                        }
                    ],
                }
            )
        else:
            self._text(404, "Not Found")

    def _chat_prompt(self):
        try:
            length = int(self.headers.get("Content-Length", "0") or "0")
        except ValueError:
            length = 0
        if length <= 0:
            return ""
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return ""
        messages = payload.get("messages", [])
        if not isinstance(messages, list):
            return ""
        return "\n".join(str(m.get("content", "")) for m in messages if isinstance(m, dict))

    def _json(self, payload):
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _text(self, code, body):
        encoded = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
