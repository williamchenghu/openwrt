# Ticket #4 — Choose the smallest viable printing stack for DCP-1510

> Wayfinder map: **Wayfinder: slim WR703N Brother DCP-1510 Wi-Fi print gateway**
> Ticket: **Choose the smallest viable printing stack for DCP-1510** (issue #4, `wayfinder:research`)
> Status: resolved — see the ticket's resolution comment for the canonical decision record.

## Question the ticket resolved

> Which combination of USB printer support, print queue/server protocol, and
> Brother-specific filtering can print reliably to a DCP-1510 within the tight
> 8 MB flash budget, with Mac/Windows printing as the hard requirement?
> Prioritize the smallest stack (e.g. USB printer gadget + p910nd-style RAW
> port) that Mac/Windows can drive with the official Brother driver, and
> determine what storage (flash vs. opkg) the printer binaries/PDD require.

## Answer (conclusion)

1. **The stack is `kmod-usb-printer` (usblp) + `p910nd` (raw TCP 9100), with
   bidirectional mode on. Nothing else** — no CUPS, no server-side filters, no
   Brother server software, no spooling daemon, no USB-over-IP. The WR703N is
   the USB **host** (the printer is the device), so no USB gadget mode is
   involved; the kernel side is plain usblp host support, which ticket #3
   already proved claims the DCP-1510 cleanly.

2. **Why pass-through is the only right answer: the DCP-1510 is a host-based
   (GDI) printer.** Brother's spec page lists no PCL/BR-Script emulation and no
   network interface — only Hi-Speed USB 2.0. brlaser's README confirms the
   DCP-1510 series belongs to the Brother lasers that *don't* support a
   standard printer language (that is exactly why the open-source brlaser
   driver exists). The printer's page description language is generated
   entirely by the client driver; there is nothing for a server-side stack to
   interpret, convert, or filter.

3. **Consequence: the router is a transparent pipe** (`/dev/usb/lp0` ⇄ TCP 9100).
   Each client's driver emits the GDI PDL and the router streams it through
   untouched. This makes the stack driver-agnostic: any client with a working
   DCP-1510 driver can print, official Brother driver or not.

4. **Package facts (primary sources):**

   | component | source | ipk | installed |
   |---|---|---|---|
   | `kmod-usb-printer` (usblp.ko) | main tree, `package/kernel/linux/modules/usb.mk` (`KernelPackage/usb-printer`); published 23.05.5 `mips_24kc` | 8 286 B | 7 500 B |
   | `p910nd` 0.97 | packages feed, `net/p910nd`; published 23.05.5 `mips_24kc` | 11 834 B | 10 998 B |

   - `p910nd` feed facts: `USERID p910nd=393:lp=7`; procd init `START=99` with
     respawn; `/etc/config/p910nd` defaults `device /dev/usb/lp0`, `port 0`
     (→ TCP 9100), `bidirectional 1`, `enabled 0`; hotplug script
     `/etc/hotplug.d/usbmisc/20-p910nd` restarts the daemon on plug/unplug and
     can anchor config by USB VID/PID; optional mDNS (`mdns 1`) advertises the
     raw service via Bonjour (`pdl-datastream tcp 9100`) for Mac discovery.
   - The feed Makefile declares **no `DEPENDS`** — `kmod-usb-printer` and
     `p910nd` must both be selected explicitly in the image config
     (`DEVICE_PACKAGES`).
   - `CONFIG_USB_PRINTER` defaults to unset in `target/linux/generic/config-*`
     (`# CONFIG_USB_PRINTER is not set`); OpenWrt's KCONFIG overlay enables it
     (`=m`) automatically when the `kmod-usb-printer` package is selected — no
     manual kernel-config edit needed.

5. **Storage answer: everything router-side lives in flash.** Total footprint
   ≈ 20 KB installed; negligible against the ~8 MB budget. No opkg-at-runtime,
   no external storage, no spooling (p910nd is non-spooling — it streams, so no
   tmpfs pressure either). **No PPD/PDD on the router**: the router never
   renders, so it never needs a printer description. The "printer binaries/PDD"
   are the client drivers (Windows driver ~tens of MB, Brother Mac driver
   package ~100+ MB), which are installed on the Mac/Windows machines, not on
   the router.

6. **Client configuration (the hard requirement):**
   - **Windows:** install the official Brother DCP-1510 printer driver, then add
     the printer on a **Standard TCP/IP Port — Raw protocol, port 9100** pointing
     at the WR703N. This is the canonical p910nd client flow. p910nd's
     bidirectional mode forwards the printer's replies, so driver status
     polling works.
   - **macOS:** Brother publishes an official macOS driver for the DCP-1510
     (the model is listed on Brother's macOS Catalina-compatible page; the
     driver is CUPS-based). Add the printer by IP (socket 9100 / LPD / IPP) or
     pick up p910nd's Bonjour advertisement. **brlaser**
     (`printer-driver-brlaser`, Homebrew on Mac) is a maintained open-source
     fallback with the DCP-1510 series explicitly listed as working.
   - **No firmware-blob upload needed.** The "download a firmware to the
     printer at plug-in" dance is an HP-style quirk (e.g. HP LaserJet 1020);
     the DCP-1510 is a standard printer-class device (ticket #3: proto-2
     bidirectional, usblp claims it cleanly). The feed's new hotplug script
     *supports* a `send_driver` blob as a contingency, but it is not required
     here.

7. **Ruled out (with reasons):**
   - **CUPS on the router** — adds ~1–2 MB+ of dependencies and buys nothing:
     there is no PDL to interpret server-side (GDI PDL is emitted by client
     drivers). CUPS is only justified if the router must *accept and rasterize*
     jobs itself — that is AirPrint, which is ticket #5's question, not this
     one's.
   - **USB/IP (usbip)** — would expose the device over TCP, but macOS/Windows
     usbip clients are poor or unsupported; fails the Mac/Windows hard
     requirement.
   - **LPRng / lpd** — spooling daemon, larger, no benefit over p910nd for raw
     pass-through.
   - **`luci-app-p910nd`** — a LuCI web UI for p910nd. **Scope note:** this
     finding originally ruled it out because the map then excluded LuCI. The
     map owner's later scope amendment (Aug 2026) brings the **full LuCI admin
     UI in scope** (`luci` + `luci-theme-bootstrap`, ~0.5 MB installed) with
     `luci-app-p910nd` **optional** — the 8 mlzma layout's relaxed headroom
     makes room for it. So it is no longer ruled out: include it in the build
     if the UI is wanted; it is a small config wrapper over p910nd, not part of
     the print-data path (which remains kmod-usb-printer + p910nd).

## Evidence

### In-repo (primary)

- `package/kernel/linux/modules/usb.mk` (L650–661): `KernelPackage/usb-printer` —
  `KCONFIG:=CONFIG_USB_PRINTER`, `FILES:=…/usb/class/usblp.ko`,
  `AUTOLOAD:=AutoProbe(usblp)`, `AddDepends/usb`.
- `target/linux/generic/config-6.12` (L7256) and `config-6.18` (L7640):
  `# CONFIG_USB_PRINTER is not set` — default-off, auto-enabled (`=m`) when the
  kmod is selected (KCONFIG overlay mechanism).
- `feeds.conf.default`: packages feed is `git.openwrt.org/feed/packages.git` —
  p910nd lives in the feed, not the main tree.
- Ticket #2 findings (`docs/wayfinder/wr703n-print-gateway/ticket-02-firmware-image-format.md`):
  `tplink_tl-wr703n` already ships `DEVICE_PACKAGES := kmod-usb-chipidea2`
  (USB controller), and ~8 MB will be available under the 8mlzma layout.

### Packages feed / published packages (primary)

- `net/p910nd/Makefile` (openwrt/packages master): v0.97, GPL-2.0-only, installs
  `/usr/sbin/p910nd` + `/etc/config/p910nd` + init.d + `hotplug.d/usbmisc/20-p910nd`;
  **no `DEPENDS`**.
- `net/p910nd/files/p910nd.config`: `device /dev/usb/lp0`, `port 0` (actual TCP
  port = 9100 + offset, valid 0–2), `bidirectional 1`, `enabled 0`, `runas_root 0`,
  mDNS options (`mdns`, `mdns_ty`, `mdns_note`, …).
- `net/p910nd/files/p910nd.init`: procd, `START=99`, respawn, `-b` (bidirectional),
  `-f` (device), runs as user `p910nd`/group `lp`; `procd_add_mdns` advertises
  `pdl-datastream tcp 9100` when `mdns 1` (Bonjour Printing Specification).
- `net/p910nd/files/p910nd.hotplug` (2024): restarts p910nd on USB printer
  plug/unplug, anchors config by USB VID/PID, optional `send_driver` blob for
  printers that need firmware download (not needed for the DCP-1510).
- downloads.openwrt.org 23.05.5 indexes (`mips_24kc`): `kmod-usb-printer`
  `5.15.167-1` ipk 8 286 B / installed 7 500 B; `p910nd` `0.97-14` ipk
  11 834 B / installed 10 998 B.
- **Caveat for the build ticket:** the 24.10.0 ath79 `tiny`/`generic` package
  indexes on the release mirror currently publish **no kmods at all** (89 base
  packages vs 1 001 packages in 23.05.5). 23.05.x is verified complete; the
  build spec should lock the release version and re-verify 24.10 package
  availability at build time.

### Printer behavior (primary)

- Brother spec page for DCP-1510 (support.brother.com): Laser, Hi-Speed USB 2.0
  only, **no Ethernet/Wi-Fi, no PCL/BR-Script emulation listed** → host-based
  (GDI) printer; USB-only explains why the print gateway exists at all.
- brlaser README (github.com/pdewacht/brlaser): "Although most Brother printers
  support a standard printer language such as PCL or PostScript, not all do…"
  with "Brother DCP-1510 series" in the reported-working list — corroborates
  host-based GDI.
- Brother "macOS Catalina compatible models" page: DCP-1510 listed with an
  official downloadable driver (the Brother Printer Driver package includes the
  CUPS Printer Driver used by GDI models).
- Ticket #3 (live device): DCP-1510 enumerates as a proto-2 bidirectional
  Brother printer-class device (vid 0x04F9/pid 0x02D0); usblp claims it cleanly
  — an exact match for p910nd's bidirectional pass-through.

### Community (corroborating)

- OpenWrt wiki, "p910nd Printer Server": install `kmod-usb-printer` + `p910nd`;
  Windows client = add local printer → create **Standard TCP/IP Port** → Raw
  protocol, port 9100.
- Chau Chee Yang (2011), "Make host based USB printer work with OpenWrt's
  P910nd print server": host-based printers print fine over p910nd via raw 9100;
  HP-style printers additionally need a firmware upload via USB hotplug — the
  DCP-1510 does not need this (standard printer class, confirmed by ticket #3).

## Downstream effect

- **AirPrint (ticket #5), now unblocked:** the print transport will be raw 9100.
  AirPrint requires the *router* to accept IPP, advertise via Bonjour, and
  rasterize PDF/JPEG into the GDI PDL — i.e. CUPS + rasterizer (ghostscript +
  brlaser) on the router. Whether that fits in 8 MB is exactly ticket #5's
  question; this ticket establishes that p910nd alone cannot serve AirPrint.
- **Acceptance tests (ticket #7) should include:** usblp enumerates the
  DCP-1510 as `/dev/usb/lp0`; p910nd listens on TCP 9100; Windows test page via
  Standard TCP/IP Port (Raw/9100) with the official driver; macOS test page via
  IP (socket 9100 / Bonjour) with the Brother or brlaser driver; printer
  unplug/replug resilience (hotplug restart); image boots with the stack
  enabled (`/etc/config/p910nd` `enabled 1`).
- **Build spec (the map's destination):** add `kmod-usb-printer` and `p910nd`
  to `DEVICE_PACKAGES` for `tplink_tl-wr703n`; ship `/etc/config/p910nd` with
  `enabled 1`, `bidirectional 1`, `device /dev/usb/lp0` (mDNS optional, default
  off). Budget ≈ 20 KB installed. **Add the LuCI admin UI per the scope
  amendment:** `luci` + `luci-theme-bootstrap` (~0.5 MB installed) and
  optionally `luci-app-p910nd`; the 8 mlzma layout's headroom covers this.

## Files touched / to touch for the build

No source changed in this ticket (planning only; the destination is the
implementation-ready spec, not the firmware build). Build-phase edits:
`target/linux/ath79/image/tiny-tp-link.mk` (`DEVICE_PACKAGES`), plus a config
overlay (`/etc/config/p910nd`) — exact mechanism to be specified by the build
ticket.

## Re-audit (post-#5, AirPrint dropped) — stack confirmed, no need to go lean

Re-audited after **Determine feasible iPhone AirPrint support** (issue #5)
resolved via PR #10 confirming **AirPrint is ruled out** (needs on-router
rasterization − CUPS + ghostscript + brlaser + avahi/dbus − none packaged for
`mips_24kc`, >100 MB external storage, exceeds 64 MB RAM/8 MB flash).

**The stack decision above is unchanged and was never dependent on the AirPrint
question.** It rests on the DCP-1510 being host-based (GDI): the client driver
emits the whole PDL, so the router is a dumb pipe (usblp + p910nd raw 9100,
bidirectional). Dropping AirPrint removes the *only* reason this map ever
favored keeping the router-side footprint minimal (headroom for a future
rasterizer) — that reason is gone.

**Feasibility of a full (non-lean) build: yes, fits in 8 MB with margin.**
The 8 mlzma layout (ticket #2) exposes a ~8000 KB firmware region
(0x20000–0x7f0000). The full in-scope set − kernel + base + SSH + WiFi client
(wpad-basic-mbedtls) + kmod-usb-chipidea2 (USB host) + kmod-usb-printer +
p910nd (~20 KB) + LuCI (`luci` + `luci-theme-bootstrap`, ~0.5 MB) + optional
`luci-app-p910nd` − lands around **~5.5–6.5 MB installed**, leaving **~1.5–2.5 MB
headroom**. Squashfs compresses the readable rootfs further, so the on-chip
number is typically smaller. **Build spec: do not minimize the package set.
Ship the full in-scope feature set (LuCI admin UI + USB print + WiFi client +
SSH, nothing more per ticket #5's final set).**

Build-time caveats carried forward: this repo is current mainline snapshot (not
23.05/24.10), so lock the release version and re-verify kmod availability
(24.10.0 ath79 indexes publish no kmods); the WR703N is only defined in the
`ath79/tiny` subtarget (can't move to `generic`); re-confirm ticket #2's two
resized-layout edits so the 8000k headroom is real, not the stock 3904k.
