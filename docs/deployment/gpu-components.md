---
title: GPU Components (Full-Real Path)
---

# Per-component GPU deploy (full-real path)

The lab is **CPU-only by default** — the live RTV tactic runs on commodity hardware, so the
GPU-bound inference servers (Triton, vLLM, TorchServe, HF TGI/TEI) ship as **protocol-accurate
detection fixtures**: they speak the real product's API shape but return canned responses.
aipostex's [inference-reality probe](#how-the-tool-reacts) honestly scores them as `reachable`
(detection), never `execution-confirmed`.

On a box with an **NVIDIA GPU** you can make any one of these components **real**, individually,
on the same port — without disturbing the rest of the CPU lab. This is the per-component
"full-real" path of the dual-lab model.

## Swap one component to real

Run on the host serving that component (ailab-ml for vllm/triton/torchserve/tei; the backend for
tgi), as root:

```bash
sudo bash lab-scripts/ml-platform/deploy-real-component.sh <vllm|triton|torchserve|tei|tgi> [model]
```

It checks for a GPU (`nvidia-smi`), stops the component's `*-mock` service, and installs/runs the
real product on the same port. Revert with `sudo systemctl restart <component>-mock` (or re-run
`deploy-all.sh --phase 2`).

The script encodes the canonical real-product install for each component (vLLM OpenAI server,
Triton container + model repo, TorchServe + `.mar`, TEI/TGI containers). These recipes require a
GPU and a model and **must be validated on your GPU hardware** — they cannot be exercised on the
CPU lab.

## How the tool reacts

Once a component is real, the tool's inference-reality probe (it sends two distinct inputs and
compares outputs) sees the output **vary with input** and escalates that surface from
`reachable` → `execution-confirmed` — automatically and honestly. Against the CPU fixture the
same probe sees identical canned output and stays at `reachable`. No flags, no hardcoding: the
`landed` value reflects what is actually real.

Confirm with `verify-chain.sh` / `score.py` for that surface, or directly, e.g.:

```bash
aipostex openai-compat --target http://<ml>:8182 validate-inference --model <model>
```

## Rough GPU budget (per component)

| Component | Port | Real product | Indicative VRAM |
|-----------|------|--------------|-----------------|
| vLLM | 8182 | vLLM OpenAI server | small model ~2–8 GB; 7B ~16–24 GB |
| HF TGI | 8180 (via gateway) | text-generation-inference | 7B ~16–24 GB |
| HF TEI | 8181 | text-embeddings-inference | embedding model ~1–4 GB |
| Triton | 8500 | tritonserver + model repo | model-dependent |
| TorchServe | 8081 | torchserve + `.mar` | model-dependent |

For the live tactic keep everything CPU (fixtures). Use this path for demos, recorded segments,
or operators who want to prove the tool's real-inference behavior end-to-end on GPU hardware.
