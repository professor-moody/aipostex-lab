#!/bin/bash
# serve-docs.sh — host the built lab docs on the attack box for OFFLINE attendees.
#
# The venue is offline, so attendees can't reach the public docs site. This serves a
# built static copy from the box on port 80, so anyone on the lab WiFi can browse
# http://<box-lan-ip>/ for the full guide + scenarios. It installs a systemd service so
# it survives a reboot; bake it into the lab-ready snapshot so it also survives reset-wave.
#
# Build the site on a machine that HAS mkdocs (the box does not). From the aipostex-lab repo,
# with the real attendee cards as the landing pages and Google Fonts disabled for offline use.
# IMPORTANT: overlay BOTH cards — start.md AND table-card.md ship as the "See you at DEF CON"
# hold-back splash on the PUBLIC site, so offline attendees must get the real guides instead:
#     cp <operator>/cards/start.md      docs/start.md       # real guide, not the con splash
#     cp <operator>/cards/table-card.md docs/table-card.md  # real table card, not the splash
#     mkdocs build -d /tmp/site                             # add `theme.font: false` for offline
#     tar czf labdocs.tgz -C /tmp/site . && scp labdocs.tgz labadmin@<box>:/tmp/
# Then on the box:
#     sudo bash serve-docs.sh /tmp/labdocs.tgz
#     # ...then re-snapshot lab-ready so reset-wave restores it.
set -euo pipefail

SRC="${1:-/tmp/labdocs.tgz}"     # a .tgz of the built site, or a directory
DEST="${DEST:-/opt/lab-docs}"
PORT="${PORT:-80}"

[[ $EUID -eq 0 ]] || { echo "[!] run as root (sudo bash serve-docs.sh <site.tgz|dir>)"; exit 1; }
[[ -e "$SRC" ]]   || { echo "[!] source not found: $SRC"; exit 1; }
id www-data >/dev/null 2>&1 && DOCUSER=www-data || DOCUSER=nobody

echo "[*] Installing docs to $DEST (serving as $DOCUSER on :$PORT)"
rm -rf "$DEST"; mkdir -p "$DEST"
if [[ -d "$SRC" ]]; then cp -r "$SRC"/. "$DEST"/; else tar xzf "$SRC" -C "$DEST"; fi
chmod -R a+rX "$DEST"

cat > /etc/systemd/system/lab-docs.service <<UNIT
[Unit]
Description=aipostex lab attendee docs (offline static site)
After=network.target
[Service]
Type=simple
User=${DOCUSER}
AmbientCapabilities=CAP_NET_BIND_SERVICE
WorkingDirectory=${DEST}
ExecStart=/usr/bin/python3 -m http.server ${PORT} --bind 0.0.0.0 --directory ${DEST}
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now lab-docs
sleep 1
if systemctl is-active --quiet lab-docs; then
    echo "[+] lab-docs serving on :${PORT} — attendees browse http://<box-lan-ip>/"
    echo "[*] Now re-snapshot lab-ready so the service survives reset-wave."
else
    echo "[!] lab-docs failed to start:"; systemctl status lab-docs --no-pager | tail -n 15; exit 1
fi
