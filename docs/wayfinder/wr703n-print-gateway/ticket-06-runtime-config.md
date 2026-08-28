# Ticket #6 — Define client-mode Wi-Fi and SSH-only runtime configuration

> Wayfinder map: **Wayfinder: slim WR703N Brother DCP-1510 Wi-Fi print gateway**
> Ticket: **Define client-mode Wi-Fi and SSH-only runtime configuration** (issue #6, `wayfinder:grilling`)
> Status: resolved — see the ticket's resolution comment for the canonical decision record.

## Question the ticket resolved

> What exact runtime behavior and management defaults should the gateway use when
> joining the existing router: Wi-Fi client mode, DHCP client/static lease, SSH
> access, no local DHCP/NAT/AP, and printer service exposure?

## Audit against prior tickets (#2–#5)

All five original sub-questions are still **valid**; none was invalidated. Three
were sharpened by new facts and one genuinely new question surfaced:

- **Wi-Fi client mode** — unchanged by any prior ticket.
- **DHCP client / static lease** — sharpened by ticket #2: flashing is
  sysupgrade-over-SSH, so post-flash reachability of the device rides entirely
  on its DHCP client against the upstream network.
- **SSH access** — sharpened by ticket #3's live observation: the 19.07.10
  device is rejected by modern macOS SSH (`Exit before auth: No matching algo
  hostkey`) because its dropbear only offers an rsa hostkey. The runtime spec
  must therefore pin modern dropbear defaults (ed25519 hostkey). Also, the
  ticket's "SSH-only" framing is superseded by the map owner's LuCI scope
  amendment: management is SSH (primary) **plus** full LuCI.
- **No local DHCP/NAT/AP** — unchanged; it surfaced the new decision of what
  the single Ethernet port does.
- **Printer service exposure** — fully determined by ticket #4 (p910nd raw TCP
  9100, bidirectional on) and ticket #5 (no AirPrint; p910nd's mDNS is Mac
  discovery only, never AirPrint).
- **New: first-boot provisioning** — a fresh image has no network until the
  Wi-Fi client is configured. The map forbids AP mode and local DHCP, so the
  question of how credentials get in is real. The user chose first-boot-over-
  Ethernet via LuCI (not a build-time overlay) precisely so the image stays
  reusable for any identical router and any network.

## Answer (conclusion)

**The firmware is network-agnostic**: no Wi-Fi credentials, root password, or
other site-specific settings are baked in, so the same image works on any
modified WR703N and in any network. Each unit is provisioned once, on first
boot, over its wired port.

1. **Topology**: one bridge `br-lan` = `eth0` (always present) + `wlan0`
   (Wi-Fi station, added during first-boot setup). No AP, no local
   DHCP/DNS/NAT — the gateway is a pure client of the upstream router.
2. **First boot**: the radio ships with **no wireless configuration** (never
   broadcasts). Plug Ethernet into the upstream network → the DHCP client on
   `br-lan` obtains an address from the upstream router → LuCI is reachable at
   that address. User sets the root password (first-run page), adds the Wi-Fi
   client config (mode Client, ESSID/password, network = lan → `wlan0` joins
   `br-lan`), and may add an SSH public key via LuCI → System →
   Administration → SSH-Keys.
3. **IP addressing**: DHCP client on `br-lan`; a stable address comes from a
   **static lease on the upstream router** (no static IP on the device).
4. **SSH**: dropbear enabled by default, port 22, password auth. Modern
   defaults — **ed25519 hostkey** (verified in-repo: mainline dropbear
   generates `dropbear_ed25519_host_key`), which fixes ticket #3's macOS
   `No matching algo hostkey` failure. Dropbear refuses login while the root
   password is empty, so first access is via LuCI; SSH works once a
   password/key is set there.
5. **Management surface**: SSH (primary) + full LuCI (`luci` +
   `luci-theme-bootstrap`) + `luci-app-p910nd` (printer status page).
6. **Printer service**: p910nd raw TCP 9100 on `/dev/usb/lp0`,
   `bidirectional 1`, `mdns 1` (Mac Bonjour discovery only — **not**
   AirPrint). No avahi/dbus/CUPS (tickets #4, #5).
7. **Firewall & services**: a single `lan` zone over `br-lan`, input ACCEPT
   (OpenWrt lan default → 9100 reachable from the whole upstream LAN), no
   `wan` zone, no masquerade, no forwarding. **dnsmasq and odhcpd disabled**
   (no local DHCP/DNS).

## Evidence

- Tickets #2–#5 resolution comments and findings docs (the map's Decisions so
  far).
- Ticket #3 live observation: `Exit before auth: No matching algo hostkey` —
  19.07 dropbear rsa hostkey vs modern macOS OpenSSH.
- In-repo: `package/network/services/dropbear/Makefile` (L82) generates
  `/etc/dropbear/dropbear_ed25519_host_key`; `files/dropbear.config` defaults
  `PasswordAuth 'on'`, `RootPasswordAuth 'on'`.
- User decisions (grilling rounds 1–2 on this ticket): Q1 all three management
  surfaces; Q2 first-boot-over-Ethernet, no build-time site config; Q3 bridge
  eth0 into the client network; Q4 DHCP client + upstream static lease; Q5 no
  preseeded password, SSH on by default, key settable via LuCI; Q6 single lan
  zone, 9100 open, no masquerade; Q7 `mdns 1` on; Q8 hostname `wr703n-gw`.

## Downstream effect

- Unblocks **Define flashing, recovery, and acceptance tests** (#7): the
  first-boot flow (plug Ethernet → LuCI → set password → configure Wi-Fi
  client → print test) is a required acceptance step; sysupgrade-over-SSH
  (ticket #2) targets a device that first-boots into this flow.
- Build spec (the map's destination): ship generic defaults only — no site
  config in the overlay; ship the p910nd uci config (device `/dev/usb/lp0`,
  `bidirectional 1`, `mdns 1`); leave dropbear at modern defaults; do not
  enable dnsmasq/odhcpd; single `lan` firewall zone.
- Domain vocabulary recorded in `CONTEXT.md` (print gateway, client mode,
  upstream network, `br-lan`, first-boot setup).

## Files touched / to touch for the build

No source changed in this ticket (planning only). Build-phase effect: the
overlay ships the p910nd config and firewall/service defaults listed above;
nothing site-specific goes in the image.
