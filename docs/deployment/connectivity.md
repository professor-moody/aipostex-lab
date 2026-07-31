# Attendee Connectivity

How participants get onto the lab, fast and reliably, at a hands-on event. Everything runs on **one
host — the attack box**; the estate sits behind it. Attendees never install the tool or touch the
estate directly: they connect to the attack box, log into a per-seat account, and run `aipostex`
there.

> **The model in one line:** attendees reach the **attack box**; the box is the only thing that
> reaches the estate. Secure the box, and the estate is sealed by architecture.

## Why the attack box is the only entrance

The estate VMs live on an **isolated bridge with no physical uplink** (`vmbr100` / `172.16.50.0/24`).
Nothing outside the hypervisor can route to them — the only host with a foot on both networks is the
attack box. So "getting an attendee onto the lab" means one thing: **getting them an SSH session on
the attack box.** Per-seat Linux accounts (`p01`..`p25`, a shared password) keep each person's work
isolated; the tool and scoring script already live on the box.

This keeps the connectivity problem small and robust: you are not exposing an estate of services to a
room — you are exposing **one SSH port on one bastion**, and everything valuable is sealed behind it.

## Waves — sequential groups, reset between

The room runs as **two waves of up to 25 attendees, ~50 minutes each** — one group at a time,
matched to the **25 seats** (`p01`..`p25`). Running groups sequentially makes isolation *temporal*:
only one wave is ever on the estate, so there are **no per-attendee VPNs, no per-group keys, no
per-range ACLs** to manage — everyone joins the same offline AP and takes a seat.

Between waves, **`reset-wave` rolls the whole estate (and the attack box) back to `lab-ready`** — every
service reseeded, every seat's work cleared — so the next group starts from a pristine lab in about a
minute. The connect block on the slide (SSID / seat password) stays the same wave to wave; only the
people change.

## Primary: a self-contained offline AP (recommended)

The simplest, most robust setup at a venue is an **offline WiFi access point** that only the attack
box bridges to the estate:

- A travel router (an OpenWRT-class box such as a GL.iNet) runs a WiFi AP with **no WAN** — the lab is
  fully offline and self-contained. No internet dependency, nothing for a hostile network to block, no
  VPN to negotiate.
- The attack box is **dual-homed**: one NIC on the estate bridge, one on the AP's LAN with a static
  address (`<box-lan-ip>`, e.g. `192.168.8.99`).
- Attendees **join the AP's WiFi and SSH straight to a seat**: `ssh pNN@<box-lan-ip>`.
  Time-to-connected is one WiFi join + one SSH — under a minute, any OS.

Because the estate is sealed by architecture (its bridge has no physical port), the AP's LAN is **flat
and that's fine** — the only things on it are the attack box and the hypervisor's management page
(protect that with a strong password). Attendees, the box, and management share one subnet; the crown
jewels are unreachable regardless.

> **Station isolation: leave it OFF for this model.** OpenWRT/GL client isolation blocks
> wireless→wired traffic, which would cut attendees off from the (wired-side) attack box. Isolation
> only helps when clients need *nothing* on the LAN but a tunnel — not here, where the box itself is
> the destination.

Reproducible AP config: `scripts/flint-offline-ap.sh` (SSID, WPA2/WPA3-mixed, PMF, WPS off, WAN
unplugged).

### In-lab documentation (offline)

The venue has no internet, so the docs can't live on a public site during the session — they're
served **from the attack box** instead. A built static copy of this site is hosted on the box
(`attack-box/serve-docs.sh` installs it as a systemd service on port 80), so any attendee on the lab
WiFi can open **`http://<box-lan-ip>/`** for the full guide and scenarios — no internet required. The
service is baked into the `lab-ready` snapshot, so it comes back automatically after every
`reset-wave`.

## Alternative: a remotely-hosted lab (VPN to the box)

If the estate runs on a home lab or in the cloud rather than on-site, front the **attack box** with a
VPN and have attendees tunnel to it, then SSH to their seat exactly as above:

- **WireGuard** or **Tailscale** on the attack box both work; scope the tunnel (a subnet-router route
  or `AllowedIPs`) to the estate range so it points only at the lab.
- On hostile networks that block UDP, an overlay with a TCP/443 relay (e.g. Tailscale's DERP) traverses
  where raw WireGuard can't.
- The attack box is a router in this mode, so **persist `ip_forward`** to `/etc/sysctl.d/` — a snapshot
  rollback or reboot loses a runtime `sysctl -w`. Verify: `sysctl net.ipv4.ip_forward` → `1`.

The cloud path documents its own access model in [aws.md](aws.md).

## Wireless AP hardening

Treat event RF as hostile (deauth floods, evil twins, KARMA/MANA, PMKID capture). Even with the estate
sealed behind the box, harden the AP so the transport itself is sound:

- **WPA2/WPA3-mixed (SAE where clients allow).** SAE resists offline handshake cracking and gives
  forward secrecy. WPA3-only is stronger but locks out older clients — mixed mode is the pragmatic
  default for a room of unknown devices.
- **802.11w PMF on** — kills the classic deauth/disassoc flood (required by WPA3; enable it explicitly).
- **WPS off, remote-admin off, default creds changed, current firmware** (patch KRACK/Dragonblood).
  Reduce TX power / use a directional antenna so coverage stays at the tables. Don't rely on a hidden
  SSID or MAC filtering — both are trivially defeated.
- **Rotate the PSK** per session; watch for rogue / evil-twin APs.
- If the RF gets actively attacked, fall back to **wired** — a small managed switch to the tables
  removes the RF surface entirely, and the same "join the box's LAN → SSH to a seat" flow works over
  copper.

## Onboarding

### Operator

1. Bring the AP (travel router) + power; optionally a small managed switch as a wired fallback.
2. Bring up the offline AP (`scripts/flint-offline-ap.sh`); confirm the attack box's LAN-side address
   and that seat accounts `p01`..`p25` exist (`attack-box/provision-seats.sh`).
3. Project the connect block on a slide: **SSID + WiFi password + `ssh pNN@<box-lan-ip>` + seat
   password.** It stays the same every wave.
4. Dry-run from a clean device: join WiFi → `ssh p01@<box-lan-ip>` → `aipostex version` → run a chain
   hop.
5. **Between waves:** run `reset-wave` to roll the estate + attack box back to `lab-ready` (~1 min),
   clearing the previous group's work before the next one takes the seats.

### Participant (from the slide)

1. **Join the lab WiFi** (SSID + password on the slide).
2. **SSH to a seat:** `ssh pNN@<box-lan-ip>` — grab an unused `p01`..`p25`; shared password on the
   slide.
3. Run `aipostex` **on the box** — you install nothing.
4. **Read the docs at `http://<box-lan-ip>/`** — the full guide + all scenarios, served from the lab
   (no internet needed).

## Troubleshooting

- **Can't reach the box after joining WiFi:** confirm station/client isolation is **OFF** on the AP (it
  blocks wireless→wired to the box), and that the box's LAN-side NIC has its static address.
- **SSH refused / wrong password:** seats use a shared password (on the slide); confirm the account
  exists (`p01`..`p25`) and password auth is enabled on the box.
- **RF under active attack (deauths, evil twins):** move the tables to the wired switch; the same
  SSH-to-seat flow works unchanged over copper.
- **Reboots lose routing (remote/VPN mode):** `ip_forward` must be persisted in `/etc/sysctl.d/`, not
  set at runtime.

## Pre-event checklist

- [ ] Offline AP up (SSID + PSK set; PMF on; WPS off; hardened); WAN unplugged if self-contained.
- [ ] Attack box dual-homed; LAN-side static address reachable; estate bridge sealed (no physical
      uplink).
- [ ] Seat accounts `p01`..`p25` present with the shared password; the binary + `~/lab` in each.
- [ ] Connect block (SSID / PSK / `ssh pNN@<box-lan-ip>` / seat pw) on the slide.
- [ ] Clean-device dry run: join WiFi → SSH to a seat → `aipostex version` → run a chain hop.
- [ ] Wired switch on hand as the RF-attack fallback.
- [ ] (Remote/VPN mode only) `ip_forward=1` persisted; tunnel scoped to the estate range.
