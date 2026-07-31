#!/bin/bash
# seed.sh — Seed ailab-dev with models, files, and notebooks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[*] Seeding ailab-dev..."

echo "[*] Pulling Ollama models..."
bash "${SCRIPT_DIR}/seed-ollama.sh"

echo "[*] Seeding filesystem artifacts..."
bash "${SCRIPT_DIR}/seed-filesystem.sh"

echo "[*] Placing notebooks..."
sudo -u devuser mkdir -p /home/devuser/notebooks
cp "${SCRIPT_DIR}"/notebooks/*.ipynb /home/devuser/notebooks/
chown -R devuser:devuser /home/devuser/notebooks

echo "[+] ailab-dev seeding complete"
