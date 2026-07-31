#!/bin/bash
# seed.sh — Seed ailab-ds with models, vector data, and notebooks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEED_VENV="/opt/data-sci-seed/venv"
PIP_PACKAGES=(
    "weaviate-client>=4.9.0,<5.0.0"
    "qdrant-client>=1.12.0,<2.0.0"
    "psycopg2-binary>=2.9.0,<3.0.0"
)

install_seed_deps() {
    "${SEED_VENV}/bin/python3" -m pip install --quiet --upgrade pip setuptools wheel
    "${SEED_VENV}/bin/python3" -m pip install --quiet --upgrade "${PIP_PACKAGES[@]}"
}

verify_seed_deps() {
    "${SEED_VENV}/bin/python3" - <<'PY'
import importlib

for module in ("weaviate", "qdrant_client", "psycopg2"):
    importlib.import_module(module)
PY
}

echo "[*] Seeding ailab-ds..."

echo "[*] Ensuring seeding virtualenv exists..."
if [[ ! -x "${SEED_VENV}/bin/python3" ]]; then
    /usr/bin/python3 -m venv "${SEED_VENV}"
fi

install_seed_deps
if ! verify_seed_deps; then
    echo "[!] Seed dependency import check failed; rebuilding ${SEED_VENV}..."
    rm -rf "${SEED_VENV}"
    /usr/bin/python3 -m venv "${SEED_VENV}"
    install_seed_deps
    verify_seed_deps
fi

echo "[*] Pulling Ollama model..."
ollama pull smollm2:135m

echo "[*] Seeding Weaviate..."
"${SEED_VENV}/bin/python3" "${SCRIPT_DIR}/seed_weaviate.py" localhost 8080

echo "[*] Seeding Qdrant..."
"${SEED_VENV}/bin/python3" "${SCRIPT_DIR}/seed_qdrant.py" localhost 6333

echo "[*] Seeding pgvector..."
# Ensure localhost trust auth is in pg_hba.conf (first-match-wins, so replace in-place).
PG_HBA=$(find /etc/postgresql -name pg_hba.conf 2>/dev/null | head -1)
if [[ -n "${PG_HBA}" ]]; then
    if grep -qE '^host\s+all\s+all\s+127\.0\.0\.1/32\s+scram-sha-256' "${PG_HBA}" || \
       grep -qE '^host\s+all\s+all\s+::1/128\s+scram-sha-256' "${PG_HBA}"; then
        echo "[*] Fixing pg_hba.conf: switching localhost auth from scram to trust..."
        sed -i -E 's/^(host\s+all\s+all\s+127\.0\.0\.1\/32\s+).*/\1trust/' "${PG_HBA}"
        sed -i -E 's/^(host\s+all\s+all\s+::1\/128\s+).*/\1trust/' "${PG_HBA}"
        systemctl reload postgresql
        sleep 1
    fi
fi
"${SEED_VENV}/bin/python3" "${SCRIPT_DIR}/seed_pgvector.py" localhost 5432

echo "[*] Placing notebooks..."
sudo -u dsuser mkdir -p /home/dsuser/notebooks
cp "${SCRIPT_DIR}"/notebooks/*.ipynb /home/dsuser/notebooks/
chown -R dsuser:dsuser /home/dsuser/notebooks

echo "[+] ailab-ds seeding complete"
