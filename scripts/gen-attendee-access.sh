#!/usr/bin/env bash
# gen-attendee-access.sh — pre-generate per-attendee entrance material for the RTV lab.
#
# Emits, per participant, BOTH entrances (see docs/deployment/connectivity.md):
#   1. WireGuard  — a client .conf whose AllowedIPs is ONLY that participant's estate /24,
#                   plus the server-side [Peer] block to add to the relay's wg0.conf.
#   2. Tailscale  — a tagged, ephemeral pre-auth key (minted via the API if creds are set,
#                   otherwise a placeholder) + the tag->route ACL policy.
# ...each rendered to a QR (via qrencode, if installed) and a printable per-seat card.
#
# Fully OFFLINE for WireGuard (wg genkey). Nothing here touches the estate; it only produces
# files. Apply the server side with scripts/provision-relay.sh (see docs/deployment/connectivity.md).
#
# Isolation model:
#   - Estate K lab subnet    : 172.16.(50+K).0/24
#   - WG tunnel network       : 10.100.0.0/16  (relay = 10.100.0.1; group K peer i = 10.100.K.(10+i))
#   - Client .conf AllowedIPs : 172.16.(50+K).0/24  (a peer can only ROUTE to its own estate)
#   - Tailscale ACL           : tag:group-K may reach ONLY 172.16.(50+K).0/24
#   The relay ALSO firewalls tunnel-IP -> estate (defence in depth) — see provision-relay.sh.
#
# Usage:
#   # RTV wave model — ONE shared onboarding block per group (recommended):
#   bash scripts/gen-attendee-access.sh --groups 0 --per-group-only \
#        --attack-box <attack-box-ip> --seats 25 --out ./attendee-access
#   # Legacy — per-participant cards (both entrances):
#   bash scripts/gen-attendee-access.sh --groups "0 1 2" --per-group 5 \
#        --relay-endpoint vpn.example.com:51820 --out ./attendee-access
#
# Options:
#   --groups "K..."       Estate group ids (default "0")
#   --per-group-only      Emit ONE onboarding block per group (RTV wave model); no per-seat cards
#   --attack-box IP       Attack-box Tailscale IP printed in the per-group block (with --per-group-only)
#   --seats N             Seat range p01..pNN shown in the per-group block (default 25)
#   --per-group N         Participants per group in legacy per-participant mode (default 5)
#   --relay-endpoint H:P  Public WireGuard endpoint of the relay (host:port) [required for usable .conf]
#   --relay-pubkey KEY    Relay WG server PUBLIC key (default: generate a fresh server keypair here)
#   --tailnet NAME        Tailnet for API key minting (or set TS_TAILNET)
#   --out DIR             Output directory (default ./attendee-access)
#
# Tailscale key minting (optional): export TS_API_KEY and TS_TAILNET (or --tailnet) to mint real
# ephemeral, reusable, tagged pre-auth keys via the API. Without them, a placeholder is written and
# you mint keys in the admin console (Settings -> Keys: ephemeral + reusable + tag:group-K).
#
# Prereqs: wireguard-tools (wg). Optional: qrencode (QRs), curl+jq (Tailscale API minting).
set -euo pipefail

GROUP_IDS="0"
PER_GROUP=5
RELAY_ENDPOINT=""
RELAY_PUBKEY=""
TAILNET="${TS_TAILNET:-}"
OUT="./attendee-access"
WG_TUNNEL_PREFIX="10.100"        # 10.100.K.(10+i) per participant; relay 10.100.0.1
PER_GROUP_ONLY=0                 # RTV wave model: ONE onboarding block per group, no per-seat cards
ATTACK_BOX=""                    # attack-box Tailscale IP to print in the per-group onboarding block
SEATS=25                         # seat range p01..pNN shown in the per-group block

while [[ $# -gt 0 ]]; do
    case "$1" in
        --groups)         GROUP_IDS="$2"; shift 2 ;;
        --per-group)      PER_GROUP="$2"; shift 2 ;;
        --per-group-only) PER_GROUP_ONLY=1; shift ;;
        --attack-box)     ATTACK_BOX="$2"; shift 2 ;;
        --seats)          SEATS="$2"; shift 2 ;;
        --relay-endpoint) RELAY_ENDPOINT="$2"; shift 2 ;;
        --relay-pubkey)   RELAY_PUBKEY="$2"; shift 2 ;;
        --tailnet)        TAILNET="$2"; shift 2 ;;
        --out)            OUT="$2"; shift 2 ;;
        -h|--help)        sed -n '2,43p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# Accept both space- and comma-separated group ids ("0 1 2" or 0,1,2). NOTE: the variable is
# GROUP_IDS, not GROUPS — GROUPS is a bash special read-only variable (the user's group array).
GROUP_IDS="$(echo "$GROUP_IDS" | tr ',' ' ')"

command -v wg >/dev/null 2>&1 || { echo "[!] wireguard-tools (wg) is required" >&2; exit 1; }
HAVE_QR=0; command -v qrencode >/dev/null 2>&1 && HAVE_QR=1 || echo "[*] qrencode not found — skipping QR PNGs (install qrencode for per-seat QRs)"
[[ -n "$RELAY_ENDPOINT" ]] || echo "[*] no --relay-endpoint — WireGuard .conf Endpoint will be a <RELAY_ENDPOINT> placeholder"

# Estate subnet for group/range K. Proxmox on-prem: 172.16.(50+K); AWS: 10.0.(K+1).
# Flip with ESTATE_SCHEME=aws for the cloud lab (keeps the /24 the tunnel is scoped to).
estate_subnet() {
    case "${ESTATE_SCHEME:-proxmox}" in
        aws) echo "10.0.$(( $1 + 1 ))" ;;    # AWS range K -> 10.0.(K+1).x
        *)   echo "172.16.$(( 50 + $1 ))" ;; # Proxmox estate K -> 172.16.(50+K).x
    esac
}

mkdir -p "$OUT"/{wireguard,tailscale,cards}

# ── Relay WG server key (generate one if the operator didn't supply a pubkey) ────────────────
if [[ -z "$RELAY_PUBKEY" ]]; then
    echo "[*] generating a relay WG server keypair (out/wireguard/relay-server.{key,pub})"
    umask 077
    wg genkey > "$OUT/wireguard/relay-server.key"
    wg pubkey < "$OUT/wireguard/relay-server.key" > "$OUT/wireguard/relay-server.pub"
    RELAY_PUBKEY="$(cat "$OUT/wireguard/relay-server.pub")"
    echo "[+] relay server pubkey: $RELAY_PUBKEY"
    echo "    (install out/wireguard/relay-server.key on the relay via scripts/provision-relay.sh)"
fi

SERVER_PEERS="$OUT/wireguard/relay-peers.conf"   # append these [Peer]s to the relay wg0.conf
: > "$SERVER_PEERS"
echo "# server-side [Peer] blocks — append to the relay's wg0.conf, then 'wg syncconf'" >> "$SERVER_PEERS"

emit_qr() { # $1=text  $2=png-path
    [[ "$HAVE_QR" -eq 1 ]] || return 0
    printf '%s' "$1" | qrencode -o "$2" -s 6 -m 2 2>/dev/null || echo "[!] qrencode failed for $2" >&2
}

# ── Entrance material ────────────────────────────────────────────────────────────────────────
# Default: per-PARTICIPANT material (both entrances, one card each). With --per-group-only we emit
# ONE onboarding block per GROUP — the RTV wave model: a shared per-group Tailscale key + a single
# shared WireGuard failsafe config, distributed on a projected slide, not per-seat cards.
for K in $GROUP_IDS; do
    subnet="$(estate_subnet "$K")"
    ep="${RELAY_ENDPOINT:-<RELAY_ENDPOINT>}"

    if [[ "$PER_GROUP_ONLY" -eq 1 ]]; then
        name="group${K}"
        tun_ip="${WG_TUNNEL_PREFIX}.${K}.10"

        # one shared WireGuard FAILSAFE config for the whole group
        priv="$(wg genkey)"; pub="$(printf '%s' "$priv" | wg pubkey)"; psk="$(wg genpsk)"
        conf="$OUT/wireguard/${name}.conf"
        umask 077
        cat > "$conf" <<EOF
# aipostex RTV — WireGuard FAILSAFE for group ${K} (shared by the whole group; reaches ONLY ${subnet}.0/24)
[Interface]
PrivateKey = ${priv}
Address = ${tun_ip}/32

[Peer]
PublicKey = ${RELAY_PUBKEY}
PresharedKey = ${psk}
Endpoint = ${ep}
AllowedIPs = ${subnet}.0/24
PersistentKeepalive = 25
EOF
        {
            echo ""
            echo "[Peer]  # group ${K} (shared) -> estate ${K} (${subnet}.0/24)"
            echo "PublicKey = ${pub}"
            echo "PresharedKey = ${psk}"
            echo "AllowedIPs = ${tun_ip}/32"
        } >> "$SERVER_PEERS"
        emit_qr "$(cat "$conf")" "$OUT/wireguard/${name}.png"

        # ONE onboarding block for the group (project this / put behind a short-URL)
        box="${ATTACK_BOX:-<ATTACK_BOX_TS_IP>}"
        ts_cmd="sudo tailscale up --auth-key=<TAILSCALE_AUTH_KEY_group${K}> --accept-routes"
        emit_qr "$ts_cmd" "$OUT/tailscale/${name}.png"
        cat > "$OUT/cards/${name}.md" <<EOF
# Group ${K} — connect (project this; the whole wave uses the same key)

## 1. Install Tailscale
- Linux/macOS: \`curl -fsSL https://tailscale.com/install.sh | sh\`
- Windows: https://tailscale.com/download/windows   ·   iOS/Android: app store

## 2. Join the tailnet (same key for everyone)
\`${ts_cmd}\`
(or scan tailscale/${name}.png)

## 3. SSH to your seat on the attack box
\`ssh pNN@${box}\`  — grab an unused seat p01..p$(printf '%02d' "$SEATS"); shared password on the slide.

## Then, on the box
\`./aipostex version\`  →  \`mkdir -p ~/lab-results\`  →  run the guided chain  →
\`python3 ~/lab/scoring/score.py ~/lab-results --strict\`

## Failsafe — WireGuard (only if Tailscale is blocked)
Import wireguard/${name}.conf (desktop) or scan wireguard/${name}.png (mobile). Reaches ONLY estate ${K}.
EOF
        continue
    fi

    for ((i=1; i<=PER_GROUP; i++)); do
        name="group${K}-p${i}"
        tun_ip="${WG_TUNNEL_PREFIX}.${K}.$((10 + i))"

        # WireGuard peer keypair (offline)
        priv="$(wg genkey)"; pub="$(printf '%s' "$priv" | wg pubkey)"
        psk="$(wg genpsk)"

        conf="$OUT/wireguard/${name}.conf"
        umask 077
        cat > "$conf" <<EOF
# aipostex RTV — WireGuard entrance for ${name} (reaches ONLY estate ${K}: ${subnet}.0/24)
[Interface]
PrivateKey = ${priv}
Address = ${tun_ip}/32

[Peer]
PublicKey = ${RELAY_PUBKEY}
PresharedKey = ${psk}
Endpoint = ${ep}
AllowedIPs = ${subnet}.0/24
PersistentKeepalive = 25
EOF

        # server-side peer block (relay restricts this peer to its own tunnel /32)
        {
            echo ""
            echo "[Peer]  # ${name} -> estate ${K} (${subnet}.0/24)"
            echo "PublicKey = ${pub}"
            echo "PresharedKey = ${psk}"
            echo "AllowedIPs = ${tun_ip}/32"
        } >> "$SERVER_PEERS"

        emit_qr "$(cat "$conf")" "$OUT/wireguard/${name}.png"

        # Tailscale command (key filled below if minted)
        ts_cmd="tailscale up --auth-key=<TAILSCALE_AUTH_KEY_group${K}> --accept-routes"
        emit_qr "$ts_cmd" "$OUT/tailscale/${name}.png"

        # printable per-seat card
        # Seat shell account on the attack box is pNN (p01..p25), NOT the peer name.
        seat="$(printf 'p%02d' "$i")"
        if [ "${ESTATE_SCHEME:-proxmox}" = aws ]; then
            cat > "$OUT/cards/${name}.md" <<EOF
# Seat ${seat} — your range: estate ${K} (${subnet}.0/24)

> **The lab is in the cloud, so the WireGuard tunnel is how you get in.** There is no lab WiFi
> to join. Bring the tunnel up first, then SSH over it.

## 1. Turn on the tunnel
- **Mobile:** scan \`wireguard/${name}.png\` with the WireGuard app, toggle it on.
- **Desktop:** import \`wireguard/${name}.conf\` into the WireGuard client, toggle it on.

## 2. Get your shell
\`\`\`
ssh ${seat}@${subnet}.99      # password: aipostex
\`\`\`

## 3. Check you are in
\`\`\`
aipostex discover network --target ${subnet}.0/24
\`\`\`

Your tunnel reaches ONLY estate ${K} (${subnet}.0/24). Stuck? Ask a room volunteer.
EOF
        else
            cat > "$OUT/cards/${name}.md" <<EOF
# Seat ${seat} — your range: estate ${K} (${subnet}.0/24)

> **On-site (the con default):** join the **aipostex-lab** WiFi and \`ssh ${seat}@<attack-box>\`
> (password: aipostex) — no VPN. The methods below are the REMOTE / off-site fallback only.

## Remote access — Tailscale (scan, install, you're in)
1. Install Tailscale: https://tailscale.com/download
2. Run: \`${ts_cmd}\`
   (or scan tailscale/${name}.png)

## Remote fallback — WireGuard
- Mobile: scan wireguard/${name}.png with the WireGuard app.
- Desktop: import wireguard/${name}.conf, toggle on.

You will reach ONLY estate ${K}. Stuck? Ask a room volunteer.
EOF
        fi
    done
done

# ── Tailscale ACL (tag -> route) ─────────────────────────────────────────────────────────────
ACL="$OUT/tailscale/tailscale-acl.json"
{
    echo '{'
    echo '  "tagOwners": {'
    first=1
    for K in $GROUP_IDS; do [[ $first -eq 1 ]] && first=0 || echo ','; printf '    "tag:group-%s": ["autogroup:admin"]' "$K"; done
    echo ''
    echo '  },'
    echo '  "acls": ['
    first=1
    for K in $GROUP_IDS; do
        subnet="$(estate_subnet "$K")"
        [[ $first -eq 1 ]] && first=0 || echo ','
        printf '    {"action": "accept", "src": ["tag:group-%s"], "dst": ["%s.0/24:*"]}' "$K" "$subnet"
    done
    echo ''
    echo '  ]'
    echo '}'
} > "$ACL"

# ── Optional: mint real Tailscale ephemeral tagged pre-auth keys via the API ─────────────────
if [[ -n "${TS_API_KEY:-}" && -n "$TAILNET" ]] && command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    echo "[*] minting Tailscale ephemeral pre-auth keys via the API (tailnet=$TAILNET)"
    for K in $GROUP_IDS; do
        body=$(jq -n --arg tag "tag:group-$K" '{capabilities:{devices:{create:{reusable:true,ephemeral:true,preauthorized:true,tags:[$tag]}}}}')
        key=$(curl -fsSL -u "${TS_API_KEY}:" -H 'Content-Type: application/json' \
              "https://api.tailscale.com/api/v2/tailnet/${TAILNET}/keys" -d "$body" 2>/dev/null | jq -r '.key // empty')
        if [[ -n "$key" ]]; then
            echo "$key" > "$OUT/tailscale/authkey-group${K}.txt"
            # backfill the real key into that group's card(s) + regenerate the Tailscale QR(s)
            for card in "$OUT/cards/group${K}.md" "$OUT"/cards/group${K}-p*.md; do
                [[ -e "$card" ]] || continue
                sed -i.bak "s|<TAILSCALE_AUTH_KEY_group${K}>|${key}|g" "$card" && rm -f "${card}.bak"
            done
            if [[ "$PER_GROUP_ONLY" -eq 1 ]]; then
                emit_qr "sudo tailscale up --auth-key=${key} --accept-routes" "$OUT/tailscale/group${K}.png"
            else
                for ((i=1; i<=PER_GROUP; i++)); do
                    emit_qr "tailscale up --auth-key=${key} --accept-routes" "$OUT/tailscale/group${K}-p${i}.png"
                done
            fi
            echo "[+] group $K key minted"
        else
            echo "[!] group $K key mint failed — leaving placeholder"
        fi
    done
else
    echo "[*] TS_API_KEY/TAILNET not set (or curl/jq missing) — Tailscale keys left as placeholders."
    echo "    Mint in the admin console (ephemeral + reusable + tag:group-K) and replace <TAILSCALE_AUTH_KEY_group*>."
fi

echo ""
echo "[+] done -> $OUT"
if [[ "$PER_GROUP_ONLY" -eq 1 ]]; then
    echo "    cards/      : ONE onboarding block per group (project it / short-URL it) — cards/group<K>.md"
    echo "    tailscale/  : tailscale-acl.json + one authkey-group<K>.txt + one QR per group"
    echo "    wireguard/  : one shared FAILSAFE .conf per group (+ QR) and relay-peers.conf (server side)"
else
    echo "    wireguard/  : per-participant .conf (+ QR) and relay-peers.conf (server side)"
    echo "    tailscale/  : tailscale-acl.json (apply to your tailnet) and per-participant QRs/keys"
    echo "    cards/      : printable per-seat cards (both entrances)"
fi
echo "    NEXT: apply the server side with scripts/provision-relay.sh; see docs/deployment/connectivity.md"
