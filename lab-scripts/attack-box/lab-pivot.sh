#!/bin/bash
# lab-pivot.sh — novice-friendly SSH dynamic SOCKS helper for advanced layer.
set -euo pipefail

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/aipostex-lab-pivot"
SINGLE_PORT="${LAB_PIVOT_SINGLE_PORT:-1080}"
NESTED_PORT="${LAB_PIVOT_NESTED_PORT:-1081}"
SINGLE_HOST="${LAB_PIVOT_SINGLE_HOST:-ailab-dev}"
NESTED_HOST="${LAB_PIVOT_NESTED_HOST:-ailab-app}"

mkdir -p "${STATE_DIR}"

usage() {
    cat <<EOF
Usage: lab-pivot.sh up [single|nested]
       lab-pivot.sh down
       lab-pivot.sh status

Examples:
  lab-pivot.sh up single
  aipostex huggingface --target http://10.30.40.40:8180 --proxy socks5://127.0.0.1:${SINGLE_PORT} enum

  lab-pivot.sh up nested
  aipostex huggingface --target http://10.30.40.40:8180 --proxy socks5://127.0.0.1:${NESTED_PORT} enum
EOF
}

pid_file() {
    printf '%s/%s.pid' "${STATE_DIR}" "$1"
}

is_running() {
    local pidfile=$1
    [[ -f "${pidfile}" ]] && kill -0 "$(cat "${pidfile}")" >/dev/null 2>&1
}

start_single() {
    local pidfile
    pidfile="$(pid_file single)"
    if is_running "${pidfile}"; then
        echo "[=] Single-hop SOCKS already running on 127.0.0.1:${SINGLE_PORT}"
        return
    fi

    ssh -f -N \
        -D "127.0.0.1:${SINGLE_PORT}" \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=15 \
        -o ServerAliveCountMax=2 \
        "${SINGLE_HOST}"
    pgrep -n -f "ssh .*127.0.0.1:${SINGLE_PORT}.*${SINGLE_HOST}" > "${pidfile}" || true
    echo "[+] Single-hop SOCKS ready: socks5://127.0.0.1:${SINGLE_PORT}"
}

start_nested() {
    local pidfile
    start_single
    pidfile="$(pid_file nested)"
    if is_running "${pidfile}"; then
        echo "[=] Nested SOCKS already running on 127.0.0.1:${NESTED_PORT}"
        return
    fi

    ssh -f -N \
        -D "127.0.0.1:${NESTED_PORT}" \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=15 \
        -o ServerAliveCountMax=2 \
        -o "ProxyCommand=nc -x 127.0.0.1:${SINGLE_PORT} -X 5 %h %p" \
        "${NESTED_HOST}"
    pgrep -n -f "ssh .*127.0.0.1:${NESTED_PORT}.*${NESTED_HOST}" > "${pidfile}" || true
    echo "[+] Nested SOCKS ready: socks5://127.0.0.1:${NESTED_PORT}"
}

stop_all() {
    local name pidfile pid
    for name in nested single; do
        pidfile="$(pid_file "${name}")"
        if [[ -f "${pidfile}" ]]; then
            pid="$(cat "${pidfile}")"
            if kill -0 "${pid}" >/dev/null 2>&1; then
                kill "${pid}" || true
                echo "[+] Stopped ${name} pivot (${pid})"
            fi
            rm -f "${pidfile}"
        fi
    done
}

status() {
    if is_running "$(pid_file single)"; then
        echo "[+] single: running (use --proxy socks5://127.0.0.1:${SINGLE_PORT})"
    else
        echo "[-] single: stopped"
    fi
    if is_running "$(pid_file nested)"; then
        echo "[+] nested: running (use --proxy socks5://127.0.0.1:${NESTED_PORT})"
    else
        echo "[-] nested: stopped"
    fi
}

cmd="${1:-}"
case "${cmd}" in
    up)
        case "${2:-single}" in
            single) start_single ;;
            nested) start_nested ;;
            *) usage; exit 2 ;;
        esac
        ;;
    down)
        stop_all
        ;;
    status)
        status
        ;;
    -h|--help|"")
        usage
        ;;
    *)
        usage
        exit 2
        ;;
esac
