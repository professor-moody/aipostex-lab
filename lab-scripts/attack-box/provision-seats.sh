#!/bin/bash
# provision-seats.sh — create per-attendee seat accounts (p01..pNN) on the attack box.
#
# Run as root on ailab-attack, AFTER provision.sh and BEFORE the lab-ready snapshot.
# reset-wave rolls the attack box back to lab-ready, so the seats must live IN that snapshot —
# then every wave's rollback restores them with EMPTY homes (no lingering artifacts between
# waves), which is exactly what we want.
#
# Each seat pNN gets:
#   - its own $HOME + ~/lab-results   → per-person scoring, no cross-seat collisions
#   - ~/aipostex  → symlink to the shared binary (/usr/local/bin/aipostex)
#   - ~/lab       → symlink to the shared read-only reference (score.py, fixtures)
# Seats have NO sudo and NO SSH keys to targets — the guided chain is all HTTP to 172.16.50.x
# from the box. They log in over SSH with a shared password (projected on the slide).
#
# Usage:
#   sudo SEATS=25 SEAT_PASSWORD='pick-one' bash provision-seats.sh
set -euo pipefail

SEATS="${SEATS:-25}"
SEAT_PASSWORD="${SEAT_PASSWORD:-aipostex}"      # shared, projected on the slide; override in prod
BIN_SRC="${BIN_SRC:-/home/labadmin/aipostex}"   # operator scp's the binary here first
LAB_REF="${LAB_REF:-/home/labadmin/lab}"        # shared read-only reference (score.py, fixtures)

if [[ $EUID -ne 0 ]]; then echo "[!] This script must be run as root" >&2; exit 1; fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Attack Box — Seat Accounts (p01..p$(printf '%02d' "$SEATS"))"
echo "═══════════════════════════════════════════════════"

# ── Shared binary on PATH (install from labadmin's home if present) ──────────────────────────
if [[ -x "$BIN_SRC" ]]; then
    install -m 0755 "$BIN_SRC" /usr/local/bin/aipostex
    echo "[+] installed /usr/local/bin/aipostex from ${BIN_SRC}"
elif [[ -x /usr/local/bin/aipostex ]]; then
    echo "[*] /usr/local/bin/aipostex already present"
else
    echo "[!] no aipostex binary at ${BIN_SRC} or /usr/local/bin — scp it in before snapshotting"
fi

# ── Make the shared reference reachable by seats, WITHOUT exposing the operator's home ───────
# o+x (traverse only, NOT o+r) on /home/labadmin so seats can follow ~/lab -> /home/labadmin/lab
# but cannot LIST the operator's home (looted creds, answer-key manifest). ~/lab itself is o+rX.
if [[ -d "$LAB_REF" ]]; then
    chmod o-r,o+x /home/labadmin 2>/dev/null || true   # traverse yes, list no (default home is 0755)
    chmod -R o+rX "$LAB_REF" 2>/dev/null || true
fi

# ── Seats ────────────────────────────────────────────────────────────────────────────────────
for ((n=1; n<=SEATS; n++)); do
    seat="$(printf 'p%02d' "$n")"
    home="/home/${seat}"

    if id "$seat" >/dev/null 2>&1; then
        echo "[*] ${seat} exists — refreshing"
    else
        useradd -m -s /bin/bash "$seat"
        echo "[+] created ${seat}"
    fi

    echo "${seat}:${SEAT_PASSWORD}" | chpasswd

    install -d -o "$seat" -g "$seat" -m 0755 "${home}/lab-results"
    ln -sfn /usr/local/bin/aipostex "${home}/aipostex"
    [[ -d "$LAB_REF" ]] && ln -sfn "$LAB_REF" "${home}/lab"
    chown -h "$seat":"$seat" "${home}/aipostex" 2>/dev/null || true
    [[ -e "${home}/lab" ]] && chown -h "$seat":"$seat" "${home}/lab" 2>/dev/null || true
done

# ── Seats log in by password; enable it (labadmin still uses keys) ────────────────────────────
# Isolated, snapshot-restored lab box — global password auth is acceptable and avoids the
# Match-in-drop-in ordering gotcha. Prefer the drop-in; fall back to the main config if the
# Include isn't present.
# MaxAuthTries 30: operator laptops that offer many SSH keys exhaust the default
# limit of 6 BEFORE the seat password is tried, so p01 logins fail. Raising it lets
# the password attempt through. This MUST be written here (not just baked by hand),
# or re-provisioning would silently drop the fix.
# Ubuntu cloud images (AWS) ship /etc/ssh/sshd_config.d/60-cloudimg-settings.conf with
# PasswordAuthentication no. sshd uses the FIRST value per keyword and reads drop-ins in
# lexical order, so ours MUST sort before that file — 00- wins over 60-cloudimg-. (The old
# 60-seats.conf sorted AFTER it and silently lost on AWS; the Proxmox image had no such file.)
SSHD_DROPIN=/etc/ssh/sshd_config.d/00-aipostex-seats.conf
rm -f /etc/ssh/sshd_config.d/60-seats.conf   # retire the old, losing name
if grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d' /etc/ssh/sshd_config 2>/dev/null; then
    printf '# aipostex RTV seat logins use a shared password (sorts before 60-cloudimg-settings)\nPasswordAuthentication yes\nMaxAuthTries 30\n' > "$SSHD_DROPIN"
else
    grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config 2>/dev/null \
        || printf '\n# aipostex-seat-login\nPasswordAuthentication yes\n' >> /etc/ssh/sshd_config
    grep -qE '^MaxAuthTries' /etc/ssh/sshd_config 2>/dev/null \
        || printf 'MaxAuthTries 30\n' >> /etc/ssh/sshd_config
fi
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
echo "[+] password login enabled for seat accounts"

echo ""
echo "[+] ${SEATS} seats ready. Each: ~/aipostex, ~/lab (shared ref), ~/lab-results (own)."
echo "    Log in:  ssh p01@<attack-box>   (shared password on the slide)"
echo "    NOTE: run BEFORE snapshotting lab-ready so a rollback restores clean seats."
echo ""
