"""
ACME Internal Assistant Lab application.

Runs on 0.0.0.0:7860 without authentication and intentionally exposes:
- a bounded text prediction route
- a file-returning route
- a file-upload-capable route
- queue-backed execution

The file outputs are deterministic so aipostex can validate file-chain,
download-file, upload-file, and serve-probe workflows against the lab.
"""

from __future__ import annotations

import json
import re
import shutil
from pathlib import Path

import gradio as gr
import requests


OLLAMA_URL = "http://localhost:11434/api/chat"
DEFAULT_MODEL = "acme-assistant"

BASE_DIR = Path("/tmp/gradio-lab")
EXPORT_DIR = BASE_DIR / "exports"
UPLOAD_DIR = BASE_DIR / "uploads"
SEED_DIR = BASE_DIR / "seed"


def ensure_lab_files() -> None:
    for directory in (EXPORT_DIR, UPLOAD_DIR, SEED_DIR):
        directory.mkdir(parents=True, exist_ok=True)

    seed_files = {
        "operator-note.txt": (
            "aipostex lab seed\n"
            "service=gradio\n"
            "purpose=file-chain validation\n"
        ),
        "service-map.json": json.dumps(
            {
                "predict_endpoint": "predict_text",
                "export_endpoint": "export_bundle",
                "upload_endpoint": "ingest_file",
                "queue_enabled": True,
            },
            indent=2,
        )
        + "\n",
    }
    for name, content in seed_files.items():
        path = SEED_DIR / name
        if not path.exists():
            path.write_text(content, encoding="utf-8")


def safe_slug(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "lab-briefing"


def call_ollama(prompt: str) -> str:
    try:
        resp = requests.post(
            OLLAMA_URL,
            json={
                "model": DEFAULT_MODEL,
                "messages": [{"role": "user", "content": prompt}],
                "stream": False,
            },
            timeout=30,
        )
        resp.raise_for_status()
        return resp.json()["message"]["content"]
    except requests.exceptions.ConnectionError:
        return "Ollama offline; using deterministic lab fallback."
    except Exception as exc:
        return f"Ollama error: {exc}"


def predict_text(prompt: str) -> str:
    cleaned = (prompt or "").strip() or "lab validation prompt"
    model_reply = call_ollama(cleaned)
    return (
        f"ACME internal assistant reply\n"
        f"prompt={cleaned}\n"
        f"model={DEFAULT_MODEL}\n"
        f"seed_file={SEED_DIR / 'operator-note.txt'}\n"
        f"answer={model_reply}"
    )


def export_bundle(topic: str) -> tuple[str, str]:
    cleaned = (topic or "").strip() or "lab briefing"
    slug = safe_slug(cleaned)
    output_path = EXPORT_DIR / f"{slug}-bundle.txt"
    output_path.write_text(
        "\n".join(
            [
                "aipostex gradio export bundle",
                f"topic={cleaned}",
                f"seed_file={SEED_DIR / 'service-map.json'}",
                "classification=internal-demo",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    note = (
        f"Created deterministic bundle for {cleaned}. "
        f"Downloadable path: {output_path}"
    )
    return str(output_path), note


def ingest_file(uploaded_path: str | None) -> tuple[str, str]:
    if not uploaded_path:
        raise gr.Error("No file provided")

    source = Path(uploaded_path)
    destination = UPLOAD_DIR / f"accepted-{source.name}"
    shutil.copyfile(source, destination)

    receipt_path = EXPORT_DIR / f"{destination.stem}-receipt.txt"
    receipt_path.write_text(
        "\n".join(
            [
                "aipostex upload receipt",
                f"uploaded_name={source.name}",
                f"stored_path={destination}",
                f"seed_file={SEED_DIR / 'operator-note.txt'}",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    summary = (
        f"Upload accepted and mirrored to {destination}. "
        f"Receipt file: {receipt_path}"
    )
    return str(receipt_path), summary


ensure_lab_files()

with gr.Blocks(
    title="ACME Internal Assistant Lab",
    analytics_enabled=False,
) as demo:
    gr.Markdown(
        """
        # ACME Internal Assistant Lab
        This intentionally vulnerable internal app exposes callable prediction,
        queue-backed file generation, and file upload flows for operator testing.
        """
    )

    with gr.Tab("Text Assistant"):
        text_prompt = gr.Textbox(
            label="Prompt",
            placeholder="Summarize the customer incident review",
        )
        text_output = gr.Textbox(label="Assistant Response")
        gr.Button("Run Text Prediction").click(
            fn=predict_text,
            inputs=text_prompt,
            outputs=text_output,
            api_name="predict_text",
        )

    with gr.Tab("Bundle Export"):
        export_topic = gr.Textbox(
            label="Bundle Topic",
            value="incident-response runbook",
        )
        export_file = gr.File(label="Generated Bundle")
        export_status = gr.Textbox(label="Export Status")
        gr.Button("Create Export Bundle").click(
            fn=export_bundle,
            inputs=export_topic,
            outputs=[export_file, export_status],
            api_name="export_bundle",
        )

    with gr.Tab("File Intake"):
        upload_input = gr.File(label="Upload Internal Note", type="filepath")
        upload_receipt = gr.File(label="Receipt File")
        upload_status = gr.Textbox(label="Ingest Status")
        gr.Button("Upload and Process").click(
            fn=ingest_file,
            inputs=upload_input,
            outputs=[upload_receipt, upload_status],
            api_name="ingest_file",
        )

demo.queue(default_concurrency_limit=2, max_size=16)

if __name__ == "__main__":
    demo.launch(
        server_name="0.0.0.0",
        server_port=7860,
        share=False,
        show_error=True,
        allowed_paths=[str(BASE_DIR)],
    )
