#!/bin/sh
# flint-offline-ap.sh — configure a GL.iNet Flint 2 (GL-MT6000) as a PURE OFFLINE AP
# for the aipostex RTV lab. No WAN uplink; venue-local WiFi -> SSH is the only entrance.
#
# RUN THIS ON THE FLINT (not the NUC), over SSH:
#     ssh root@192.168.8.1        # default GL.iNet LAN gateway
#     # paste this script, or scp it over and: sh flint-offline-ap.sh
#
# It sets: WPA2/WPA3-mixed (SAE where clients allow) + PMF optional + station isolation
# OFF (attendees must reach the wired attack box) on BOTH bands, LAN = the segment the
# NUC's vmbr0 port + the attack box net1 + attendee WiFi all share, WAN disabled, WPS
# off, TX power down for a tight table footprint. Params match connectivity.md.
#
# NOTE: GL.iNet's GUI has its own config layer. This uci script is the reproducible
# path; the GUI checklist at the bottom is the reliable belt-and-suspenders. After
# running, VERIFY in the GUI (or with the checks at the end) that the SSID/encryption/
# isolation actually took — GL firmware occasionally re-templates wireless from its store.
#
# ── FILL THESE before running ──────────────────────────────────────────────
SSID="aipostex-lab"                  # attendee WiFi name (goes on the projected slide)
PSK="CHANGE-ME-strong-passphrase"    # WPA2/WPA3-mixed passphrase, >=12 chars (on the slide)
LAN_SUBNET="192.168.8"               # Flint LAN /24; gateway becomes ${LAN_SUBNET}.1
TXPOWER="12"                         # dBm; low = tight footprint at the table
BOX_MAC=""                           # OPTIONAL: attack box net1 MAC -> stable slide IP; empty = skip
BOX_IP="192.168.8.99"                # the stable ssh pNN@<this> shown on the slide
# ───────────────────────────────────────────────────────────────────────────

set -e
echo "Current wireless sections (confirm the names below match):"
uci show wireless | grep -E "\.(ssid|encryption|device)=" || true

# --- LAN: this box is the router/DHCP for the lab segment, gateway .1 ---
uci set network.lan.ipaddr="${LAN_SUBNET}.1"
uci set network.lan.netmask="255.255.255.0"

# --- WAN: OFF. No internet uplink at the venue (intentional; see connectivity.md). ---
uci set network.wan.disabled='1'  2>/dev/null || true
uci set network.wan6.disabled='1' 2>/dev/null || true
# (Belt-and-suspenders: also just leave the WAN port unplugged.)

# --- DHCP on the lab segment ---
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='150'
uci set dhcp.lan.leasetime='2h'

# --- Wireless: WPA2/WPA3-mixed + PMF optional + station isolation OFF, BOTH bands ---
# Auto-detect the real radios/ifaces. The MT6000 names them wifi2g/wifi5g (devices
# mt798611/mt798612), NOT the OpenWRT-default radio0/radio1 — hardcoding radio0
# silently no-ops. This enables EVERY radio and points EVERY AP-mode wifi-iface at the
# lab SSID (same SSID on both bands), so disable any guest SSID first if one exists.
for RADIO in $(uci show wireless | sed -n "s/^wireless\.\([^.]*\)=wifi-device$/\1/p"); do
  uci set wireless.${RADIO}.disabled='0'
  uci set wireless.${RADIO}.country='US'
  uci set wireless.${RADIO}.txpower="${TXPOWER}"
done
APIFACES=""
for IFACE in $(uci show wireless | sed -n "s/^wireless\.\([^.]*\)=wifi-iface$/\1/p"); do
  mode=$(uci -q get wireless.${IFACE}.mode || echo ap)
  [ "$mode" = "ap" ] || continue          # skip mesh/sta ifaces
  uci set wireless.${IFACE}.network='lan'
  uci set wireless.${IFACE}.ssid="${SSID}"
  uci set wireless.${IFACE}.encryption='sae-mixed'  # WPA2/WPA3-mixed: SAE where clients allow, no lockout of older laptops
  uci set wireless.${IFACE}.key="${PSK}"
  uci set wireless.${IFACE}.ieee80211w='1'          # PMF OPTIONAL (mandatory '2' drops mixed WPA2 clients)
  uci set wireless.${IFACE}.isolate='0'             # isolation OFF — attendees MUST reach the wired attack box
  uci set wireless.${IFACE}.wps_pushbutton='0'
  APIFACES="${APIFACES} ${IFACE}"
done
[ -n "$APIFACES" ] || echo "!! no AP-mode wifi-iface found — set the SSID in the GL.iNet GUI instead"

# --- Optional: pin the attack box to a stable IP so the slide shows a fixed ssh target ---
if [ -n "$BOX_MAC" ]; then
  uci -q delete dhcp.aipostex_box 2>/dev/null || true
  uci set dhcp.aipostex_box='host'
  uci set dhcp.aipostex_box.mac="${BOX_MAC}"
  uci set dhcp.aipostex_box.ip="${BOX_IP}"
  uci set dhcp.aipostex_box.name='ailab-attack'
fi

uci commit
wifi reload
/etc/init.d/network reload
/etc/init.d/dnsmasq restart

echo
echo "── verify (per AP iface) ──"
for IFACE in $APIFACES; do
  echo "  ${IFACE}: enc=$(uci -q get wireless.${IFACE}.encryption) (want sae-mixed)  pmf=$(uci -q get wireless.${IFACE}.ieee80211w) (want 1)  isolate=$(uci -q get wireless.${IFACE}.isolate) (want 0)  ssid=$(uci -q get wireless.${IFACE}.ssid)"
done
echo "LAN gw     : $(uci get network.lan.ipaddr)"
echo "WAN        : disabled=$(uci -q get network.wan.disabled) (want: 1, or port unplugged)"
echo
echo "Done. Also do in the GL.iNet GUI (belt-and-suspenders, GUI-only bits):"
echo "  - Update firmware to current (patch KRACK/Dragonblood) BEFORE the con"
echo "  - WPS OFF, UPnP OFF, remote-admin/WAN-admin OFF, change default admin password"
echo "  - Confirm 'Client Isolation' is OFF (it blocks wireless->wired to the attack box)"
echo "  - (No Tailscale/WireGuard/repeater — this AP is intentionally offline)"
