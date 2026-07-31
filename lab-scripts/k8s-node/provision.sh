#!/bin/bash
# k8s-node/provision.sh — ailab-k8s estate node: a REAL vuln+secure k3s PAIR on one VM.
#
# The k8s module's honesty story needs a deliberately-weak cluster AND a secured control
# on the SAME estate host: `aipostex k8s ...:6443` reports WEAK (anon enum → secret exfil →
# in-pod RCE), and `...:6444` reports NOT weak (401). Two NATIVE k3s servers can't coexist
# on one host — they collide on flannel VXLAN / kubelet / CNI CIDR — so the pair runs as two
# containers (each k3s gets its own network namespace). This is the exact config that
# `sandbox prove k8s` validates, promoted onto a real estate node so demo Act 6 records
# against 172.16.50.50 instead of the operator's laptop Docker.
#
# Run as root on the ailab-k8s node (LAB_SUBNET.50). Idempotent (deploy-all may re-run it).
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then echo "[!] run as root (sudo)"; exit 1; fi

LAB_SUBNET="${LAB_SUBNET:-172.16.50}"
NODE_IP="${LAB_SUBNET}.50"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="rancher/k3s:v1.31.5-k3s1"

# ── 1. Docker engine ───────────────────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
    echo "[*] installing Docker engine ..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y docker.io
fi
systemctl enable --now docker

# Prefer the compose v2 plugin; fall back to legacy docker-compose, then to plain docker run.
COMPOSE=""
if docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
else
    apt-get install -y docker-compose-v2 >/dev/null 2>&1 || apt-get install -y docker-compose-plugin >/dev/null 2>&1 || true
    docker compose version >/dev/null 2>&1 && COMPOSE="docker compose" || true
fi

# ── 2. Pull the pinned k3s image (explicit, so a pull failure is obvious) ────────
echo "[*] pulling ${IMAGE} ..."
docker pull "$IMAGE"

# ── 3. Bring up the vuln+secure pair ─────────────────────────────────────────────
if [[ -n "$COMPOSE" ]]; then
    echo "[*] starting k8s pair via ${COMPOSE} ..."
    ( cd "$SCRIPT_DIR" && $COMPOSE -f k8s-compose.yml up -d )
else
    echo "[*] compose unavailable — starting k8s pair via docker run ..."
    docker rm -f k8s-vuln k8s-secure >/dev/null 2>&1 || true
    docker run -d --name k8s-vuln --privileged --restart unless-stopped -p 6443:6443 \
        -v "${SCRIPT_DIR}/manifests/vuln:/var/lib/rancher/k3s/server/manifests/seed:ro" \
        "$IMAGE" server --kube-apiserver-arg=anonymous-auth=true \
        --disable=traefik --disable=metrics-server --disable=servicelb --node-name=ml-prod-node
    docker run -d --name k8s-secure --privileged --restart unless-stopped -p 6444:6443 \
        -v "${SCRIPT_DIR}/manifests/secure:/var/lib/rancher/k3s/server/manifests/seed:ro" \
        "$IMAGE" server \
        --disable=traefik --disable=metrics-server --disable=servicelb --node-name=ml-prod-node
fi

# ── 4. Wait for both API servers to RESPOND ─────────────────────────────────────
# The vuln cluster answers /version 200 (anon allowed); the secure cluster answers 401
# (anonymous-auth off → no identity even for /version). Any real HTTP status means the
# API server is up and TLS-serving; the weak-vs-secure semantics are checked in step 6.
for port in 6443 6444; do
    up=0
    for _ in $(seq 1 60); do
        code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 4 "https://${NODE_IP}:${port}/version" || echo 000)
        if [[ "$code" == "200" || "$code" == "401" || "$code" == "403" ]]; then up=1; break; fi
        sleep 3
    done
    if [[ $up -ne 1 ]]; then echo "[!] k3s API on :${port} never responded"; docker ps -a; exit 1; fi
    echo "[+] k3s API responding on ${NODE_IP}:${port}"
done

# ── 5. Wait for the vuln cluster's ml-prod workloads (the anon secret-read target) ─
for _ in $(seq 1 45); do
    if curl -sk --max-time 4 "https://${NODE_IP}:6443/api/v1/namespaces/ml-prod/secrets" | grep -q '"kind"'; then break; fi
    sleep 4
done

# ── 6. Verify: :6443 weak, :6444 secure ─────────────────────────────────────────
echo "[*] verifying vuln (:6443 anonymous secret-read must WORK) ..."
if curl -sk --max-time 6 "https://${NODE_IP}:6443/api/v1/namespaces/ml-prod/secrets" | grep -q '"kind"'; then
    echo "[+] :6443 anonymous secret-read reachable — cluster is deliberately weak (as intended)"
else
    echo "[!] :6443 anonymous secret-read NOT reachable — check anon-auth + anon-rbac binding"; exit 1
fi

echo "[*] verifying secure (:6444 anonymous secret-read must be BLOCKED) ..."
code=$(curl -sk --max-time 6 -o /dev/null -w '%{http_code}' "https://${NODE_IP}:6444/api/v1/namespaces/ml-prod/secrets" || echo 000)
if [[ "$code" == "401" || "$code" == "403" ]]; then
    echo "[+] :6444 anonymous secret-read blocked (${code}) — secure control is honest"
else
    echo "[!] :6444 returned ${code} (expected 401/403) — secure control not enforcing"; exit 1
fi

echo "[+] ailab-k8s: vuln :6443 + secure :6444 ready on ${NODE_IP}"
