#!/bin/bash
# deploy-real-component.sh — swap a single GPU-bound inference COMPONENT from its CPU
# detection-fixture mock to the REAL product, on the SAME port, on GPU hardware.
#
# This is the per-component "full-real" path of the dual-lab model. The default lab is
# CPU-only (the live RTV tactic), so these services ship as protocol-accurate detection
# fixtures. On a box with an NVIDIA GPU you can make any one of them REAL — and aipostex's
# inference-reality probe will then legitimately escalate that surface from `reachable`
# (canned fixture) to `execution-confirmed` (verified real, input-dependent inference).
#
#   Usage:  sudo bash deploy-real-component.sh <vllm|triton|torchserve|tei|tgi> [model]
#   Revert: sudo systemctl restart <component>-mock   (or re-run deploy-all.sh phase 2)
#
# REQUIRES an NVIDIA GPU + drivers + CUDA. These recipes are the canonical real-product
# installs; validate them on your GPU hardware before relying on them (they cannot be
# exercised on the CPU lab). Run ON ailab-ml (or the GPU host hosting that component).
set -euo pipefail

COMPONENT="${1:-}"
MODEL="${2:-}"
RUN_USER="mluser"

usage() { echo "Usage: sudo bash $0 <vllm|triton|torchserve|tei|tgi> [model]"; exit 2; }
[[ -z "$COMPONENT" ]] && usage

require_gpu() {
    if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi >/dev/null 2>&1; then
        echo "[!] No NVIDIA GPU detected (nvidia-smi). Real $COMPONENT needs a GPU; aborting."
        echo "    The CPU lab keeps the detection fixture; this swap is for GPU hardware only."
        exit 1
    fi
    echo "[+] GPU detected: $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | head -1)"
}

stop_mock() {
    local svc="$1"
    systemctl disable --now "$svc" 2>/dev/null || true
    echo "[*] stopped fixture: $svc"
}

write_unit() { # write_unit <name> <exec> [extra-env]
    local name="$1" exec="$2" extra="${3:-}"
    cat > "/etc/systemd/system/${name}.service" <<EOF
[Unit]
Description=aipostex lab REAL ${name} (GPU)
After=network.target

[Service]
User=${RUN_USER}
${extra}
ExecStart=${exec}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$name"
    systemctl restart "$name"
    echo "[+] started REAL service: ${name}"
}

case "$COMPONENT" in
  vllm)
    # Real vLLM OpenAI-compatible server on :8182 (same port as the mock).
    MODEL="${MODEL:-facebook/opt-125m}"   # small default; pick a model that fits the GPU
    require_gpu
    stop_mock vllm-mock
    sudo -u "$RUN_USER" python3 -m pip install --quiet --upgrade "vllm"
    write_unit vllm \
      "$(command -v python3) -m vllm.entrypoints.openai.api_server --model ${MODEL} --host 0.0.0.0 --port 8182" \
      'Environment="HF_HOME=/home/mluser/.cache/huggingface"'
    echo "    Verify: aipostex openai-compat --target http://localhost:8182 validate-inference --model ${MODEL}"
    ;;

  triton)
    # Real NVIDIA Triton on :8500 (HTTP). Needs a model repository at /opt/triton/models.
    require_gpu
    stop_mock triton-mock
    echo "[!] Triton needs a populated model repository (/opt/triton/models/<model>/{config.pbtxt,1/model.*})."
    echo "    Recommended: run the official container pinned to your CUDA:"
    echo "      docker run --gpus=1 --rm -p8500:8000 -p8501:8001 -p8502:8002 \\"
    echo "        -v /opt/triton/models:/models nvcr.io/nvidia/tritonserver:24.08-py3 \\"
    echo "        tritonserver --model-repository=/models"
    echo "    (Wire that container to a systemd unit on :8500 once the model repo is in place.)"
    echo "    Verify: aipostex triton --target http://localhost:8500 infer --model <name> --payload '{...}' --force-exploit"
    ;;

  torchserve)
    # Real TorchServe inference :8081 (and mgmt :8082). Needs a .mar model archive.
    require_gpu
    stop_mock torchserve-mock
    sudo -u "$RUN_USER" python3 -m pip install --quiet torchserve torch-model-archiver
    echo "[!] TorchServe needs a .mar archive in /opt/torchserve/model-store and a config.properties."
    echo "    torchserve --start --ncs --model-store /opt/torchserve/model-store --models <name>.mar \\"
    echo "      --ts-config /opt/torchserve/config.properties   # inference_address=http://0.0.0.0:8081"
    echo "    (Wrap in a systemd unit on :8081 once the .mar is built with torch-model-archiver.)"
    echo "    Verify: aipostex torchserve --target http://localhost:8081 predict --model <name> --payload '{...}' --force-exploit"
    ;;

  tei)
    # Real HuggingFace Text Embeddings Inference on :8181.
    MODEL="${MODEL:-BAAI/bge-small-en-v1.5}"
    require_gpu
    stop_mock hf-tei-mock
    echo "[!] Use the official TEI container pinned to your GPU arch:"
    echo "      docker run --gpus all --rm -p8181:80 -v /opt/tei/data:/data \\"
    echo "        ghcr.io/huggingface/text-embeddings-inference:1.5 --model-id ${MODEL}"
    echo "    (Wrap in a systemd unit on :8181.)"
    echo "    Verify: aipostex huggingface --target http://localhost:8181 embed ..."
    ;;

  tgi)
    # Real HuggingFace TGI. The lab's :8180 is an auth GATEWAY that proxies to a backend
    # (LiteLLM->Ollama by default). Point it at a real TGI instead of swapping the gateway.
    MODEL="${MODEL:-HuggingFaceH4/zephyr-7b-beta}"
    require_gpu
    echo "[!] Run real TGI on a backend port, then set the gateway's TGI_UPSTREAM_URL to it:"
    echo "      docker run --gpus all --rm -p8185:80 -v /opt/tgi/data:/data \\"
    echo "        ghcr.io/huggingface/text-generation-inference:3.0 --model-id ${MODEL}"
    echo "    Then on ailab-app set TGI_UPSTREAM_URL=http://<ml>:8185 for tgi-gateway and restart it."
    echo "    Verify: aipostex huggingface --target http://<app>:8180 generate ... (gated by the HF token)"
    ;;

  *) usage ;;
esac

echo "[+] Done. aipostex's inference-reality probe should now report this surface as"
echo "    execution-confirmed (output varies with input) instead of reachable (canned fixture)."
