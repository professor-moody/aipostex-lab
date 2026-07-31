#!/bin/bash
# Provision enterprise data host with vector services plus native MinIO.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MINIO_VERSION="${MINIO_VERSION:-RELEASE.2025-04-22T22-12-26Z}"

echo "[*] Provisioning ent-data-01 via data-sci role..."
bash "${LAB_ROOT}/data-sci/provision.sh"

echo "[*] Installing MinIO ${MINIO_VERSION}..."
if ! id minio >/dev/null 2>&1; then
    useradd -r -m -d /var/lib/minio -s /usr/sbin/nologin minio
fi
install -d -o minio -g minio /var/lib/minio/data /etc/minio
curl -fsSL "https://dl.min.io/server/minio/release/linux-amd64/archive/minio.${MINIO_VERSION}" -o /usr/local/bin/minio
chmod 0755 /usr/local/bin/minio

cat > /etc/minio/minio.env <<'EOF'
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin-FAKE-enterprise-secret
MINIO_VOLUMES=/var/lib/minio/data
MINIO_OPTS="--address 0.0.0.0:9001 --console-address 0.0.0.0:9002"
EOF
chown -R minio:minio /etc/minio /var/lib/minio
chmod 0600 /etc/minio/minio.env

cat > /etc/systemd/system/minio.service <<'EOF'
[Unit]
Description=MinIO Object Storage
After=network.target

[Service]
User=minio
Group=minio
EnvironmentFile=/etc/minio/minio.env
ExecStart=/usr/local/bin/minio server $MINIO_OPTS $MINIO_VOLUMES
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now minio
for _ in $(seq 1 30); do
    if curl -sf http://localhost:9001/minio/health/live >/dev/null 2>&1; then
        echo "[+] MinIO is ready on :9001"
        exit 0
    fi
    sleep 2
done
journalctl -u minio --no-pager -n 30 || true
echo "[!] MinIO failed readiness"
exit 1
