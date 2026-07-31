#!/bin/bash
# seed.sh — Seed ailab-ml with ChromaDB, MLflow, and Ray data.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ML_RUNTIME_VENV="/opt/ailab-ml/venv"
CHROMA_VENV="/opt/chromadb/venv"

# Estate subnet prefix for the cross-service chains the seeds plant (MLflow/LiteLLM/TGI).
# Defaults to the base estate (172.16.50); deploy-all/reset-wave pass the estate's own subnet
# via `sudo env ESTATE_SUBNET=...` so a GROUP_ID/AWS estate's chains stay self-contained.
export ESTATE_SUBNET="${ESTATE_SUBNET:-172.16.50}"

check_service() {
    local svc_name=$1
    local svc_url=$2

    if curl -sf "${svc_url}" >/dev/null 2>&1; then
        echo "[+] ${svc_name} is responding"
        return 0
    fi

    echo "[*] ${svc_name} not responding, restarting..."
    systemctl restart "${svc_name}"
    for _ in $(seq 1 15); do
        sleep 2
        if curl -sf "${svc_url}" >/dev/null 2>&1; then
            echo "[+] ${svc_name} recovered after restart"
            return 0
        fi
    done

    echo "[!] ${svc_name} still not responding"
    journalctl -u "${svc_name}" --no-pager -n 40 || true
    return 1
}

echo "[*] Seeding ailab-ml..."

check_service chromadb "http://localhost:8000/api/v1/heartbeat"
check_service mlflow "http://localhost:5000/"
check_service ray "http://localhost:8265/api/version"

echo "[*] Seeding ChromaDB..."
"${CHROMA_VENV}/bin/python3" "${SCRIPT_DIR}/seed_chromadb.py" localhost 8000

if [[ -f "${SCRIPT_DIR}/seed_mlflow.py" ]]; then
    echo "[*] Seeding MLflow..."
    "${ML_RUNTIME_VENV}/bin/python3" "${SCRIPT_DIR}/seed_mlflow.py" localhost 5000
    chown -R mluser:mluser /opt/mlflow
    find /opt/mlflow/artifacts -type d -exec chmod 755 {} +
fi

if [[ -f "${SCRIPT_DIR}/seed_ray.py" ]]; then
    echo "[*] Seeding Ray..."
    "${ML_RUNTIME_VENV}/bin/python3" "${SCRIPT_DIR}/seed_ray.py" localhost 8265
fi

echo "[+] ailab-ml seeding complete"
