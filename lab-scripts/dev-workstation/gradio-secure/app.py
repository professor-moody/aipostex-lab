#!/usr/bin/env python3
"""acme-secure-chat — a Gradio app that actually requires a login.

This is the **honesty control** for the Gradio module, the counterpart to the open
app on :7860. It is not a target: it exists so the precision benchmark can check
that aipostex claims nothing against an app that never let it in.

It uses Gradio's own `auth=` parameter — the framework's real protection — rather
than a proxy in front. Without a session, the API routes answer 401, so a scanner
can see the app is there but cannot call it.
"""

import os

import gradio as gr

PORT = int(os.environ.get("GRADIO_PORT", "7861"))
USER = os.environ.get("GRADIO_USER", "mluser")
PASSWORD = os.environ.get("GRADIO_PASSWORD", "acme-gradio-6c19d3ba")


def summarize(text: str) -> str:
    """Stand-in for the approved internal summarizer."""
    text = (text or "").strip()
    if not text:
        return "Provide text to summarize."
    return f"Summary ({len(text.split())} words in): {text[:120]}"


with gr.Blocks(title="ACME Internal Assistant (authenticated)") as demo:
    gr.Markdown("## ACME Internal Assistant\nAuthorized staff only.")
    box = gr.Textbox(label="Text", lines=4)
    out = gr.Textbox(label="Summary")
    gr.Button("Summarize").click(summarize, inputs=box, outputs=out, api_name="summarize")

demo.queue(default_concurrency_limit=2, max_size=16)

if __name__ == "__main__":
    demo.launch(
        server_name="0.0.0.0",
        server_port=PORT,
        share=False,
        show_error=False,
        auth=(USER, PASSWORD),
        auth_message="ACME internal tooling — sign in with your platform account.",
    )
