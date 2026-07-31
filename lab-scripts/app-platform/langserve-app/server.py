#!/usr/bin/env python3
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from langchain_core.runnables import RunnableLambda
from langserve import add_routes


def transform(payload):
    if isinstance(payload, dict):
        value = payload.get("input") or payload.get("question") or payload.get("message") or "hello"
    else:
        value = str(payload)
    return {
        "summary": f"ACME assistant processed: {value}",
        "classification": "internal-ai-app",
    }


app = FastAPI(title="LangServe Lab", version="1.0.0", description="Shared AI app box service")
chain = RunnableLambda(transform)
add_routes(app, chain, path="", playground_type="default")


@app.get("/", response_class=HTMLResponse)
def index():
    return """
    <html>
      <head><title>LangServe Lab</title></head>
      <body>
        <h1>LangServe Lab</h1>
        <p>Shared AI app surface for invoke/playground fingerprinting.</p>
        <p>See <a href="/docs">/docs</a> and <a href="/playground/">/playground/</a>.</p>
      </body>
    </html>
    """

