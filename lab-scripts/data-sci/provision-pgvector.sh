#!/bin/bash
# provision-pgvector.sh — Install PostgreSQL 16 + pgvector on ailab-ds.
# Called by provision.sh AFTER base packages are ready.
# Result: PostgreSQL listening on 0.0.0.0:5432, pgvector extension loaded,
#         "labdb" database with trust auth for the lab subnet.
set -euo pipefail

PG_VERSION="${PG_VERSION:-16}"

echo "[*] Installing PostgreSQL ${PG_VERSION} + pgvector extension..."

# ── Install PostgreSQL + pgvector from apt ──────────────────
export DEBIAN_FRONTEND=noninteractive

# Add the official PostgreSQL APT repo (pgdg) for latest pgvector packages.
if [ ! -f /etc/apt/sources.list.d/pgdg.list ]; then
    apt-get install -y --no-install-recommends gnupg lsb-release ca-certificates
    echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list
    wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor \
        -o /etc/apt/trusted.gpg.d/pgdg.gpg
    apt-get update -qq
fi

apt-get install -y --no-install-recommends \
    "postgresql-${PG_VERSION}" \
    "postgresql-${PG_VERSION}-pgvector"

echo "[+] PostgreSQL ${PG_VERSION} + pgvector installed"

# ── Configure listen address + auth ─────────────────────────
PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
PG_HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

# Listen on all interfaces (default is localhost only).
sed -i "s/^#\?listen_addresses\s*=.*/listen_addresses = '*'/" "${PG_CONF}"

# Allow trust auth from localhost and the lab subnet for the labdb database.
# This lets the tool and seed scripts connect with default credentials (user=postgres, no password).
# pg_hba is first-match-wins, so we must replace the default scram/md5 lines rather than appending.
sed -i -E 's/^(host\s+all\s+all\s+127\.0\.0\.1\/32\s+).*/\1trust/' "${PG_HBA}"
sed -i -E 's/^(host\s+all\s+all\s+::1\/128\s+).*/\1trust/' "${PG_HBA}"

# Trust the estate subnet (base estate = 172.16.50.0/24).
LAB_CIDR="${LAB_SUBNET:-172.16.50}.0/24"
if ! grep -q "${LAB_CIDR}" "${PG_HBA}"; then
    {
        echo ""
        echo "# Lab subnet — trust auth for aipostex testing"
        printf 'host    all    all    %s    trust\n' "${LAB_CIDR}"
    } >> "${PG_HBA}"
fi

# Restart to pick up changes.
systemctl restart postgresql
systemctl enable postgresql

echo "[*] Waiting for PostgreSQL on :5432..."
for i in $(seq 1 30); do
    if pg_isready -h 127.0.0.1 -p 5432 -q 2>/dev/null; then
        echo "[+] PostgreSQL is ready"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[!] PostgreSQL failed to start. Journal output:"
        journalctl -u postgresql --no-pager -n 30
        exit 1
    fi
    sleep 2
done

# ── Create lab database + enable pgvector extension ─────────
sudo -u postgres psql -c "SELECT 1 FROM pg_database WHERE datname = 'labdb'" | grep -q 1 \
    || sudo -u postgres createdb labdb

sudo -u postgres psql -d labdb -c "CREATE EXTENSION IF NOT EXISTS vector"

echo "[+] PostgreSQL provisioned (port 5432, database=labdb, pgvector extension enabled)"
