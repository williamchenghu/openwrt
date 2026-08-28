# Ticket #5 — Determine feasible iPhone AirPrint support

> Wayfinder map: **Wayfinder: slim WR703N Brother DCP-1510 Wi-Fi print gateway**
> Ticket: **Determine feasible iPhone AirPrint support** (issue #5, `wayfinder:research`)
> Status: resolved — see the ticket's resolution comment for the canonical decision record.

## Question the ticket resolved

> Can the selected minimal WR703N image advertise an AirPrint-compatible service
> over mDNS and accept iPhone jobs that the DCP-1510 can print, and what
> package, protocol, and filtering constraints follow?

## Answer (conclusion)

**No. AirPrint is not feasible on this hardware within this effort's scope, and
it is ruled out.** The DCP-1510 is host-based (GDI) with no PDL interpreter of
its own (ticket #4), so an AirPrint-capable gateway would have to do the whole
rasterization chain on the router: accept an IPP job from the iPhone (PDF or
JPEG), rasterize it, convert it to the DCP-1510's GDI PDL, and stream it to
usblp. That chain is CUPS + ghostscript + brlaser + avahi(+dbus) — a stack that
(a) does not exist in the official OpenWrt package repos at all, (b) needs
roughly two orders of magnitude more storage than this 8 MB flash unit has, and
(c) needs more RAM/CPU than the 64 MB / 400 MHz AR9331 can spare. There is no
lighter path: the iPhone speaks only IPP+PDF/JPEG, and the printer accepts only
GDI PDL, so something on the route must rasterize — and that something cannot
be this router.

## What AirPrint actually requires (protocol facts)

Primary-source teardown of the AirPrint protocol (Finnie, 2010, from a live
Wireshark capture of the iOS 4.2 print flow; still the canonical description,
and consistent with Apple's Bonjour Printing Specification):

- **Transport:** IPP over HTTP on TCP 631 (the CUPS scheduler port).
- **Discovery:** mDNS/Bonjour advertisement of `_ipp._tcp` **with the
  `_universal._sub._ipp._tcp` subtype** — plain CUPS announcements without the
  `_universal` subtype are not listed by iOS.
- **TXT records iOS requires:**
  - `pdl=application/pdf,...` — iOS sends **PDF** (and JPEG for photos). If
    `application/pdf` is absent from `pdl`, iOS will not use the printer.
  - `URF=...` — must be **present and non-empty**; without it the printer does
    not appear in the AirPrint list at all.
  - `txtvers`, `qtotal`, `rp`, `ty`, `printer-state`, `printer-type`, etc.
- **Consequence for this project:** the router must *receive and rasterize*
  PDF. There is no "pass-through" mode for AirPrint the way p910nd passes raw
  9100 through; the incoming document is always PDF/JPEG, never the printer's
  native PDL.

## Why the required stack cannot fit (package facts)

### Not in the official repos

Verified against the mips_24kc package indexes of the two releases this map
cares about (23.05.5 and 24.10.0):

- **No `cups`, no `libcups`, no `ghostscript`, no `brlaser`, no `gutenprint`,
  no `foomatic`** — none exist in `packages` or any official feed. (The
  23.05.5 index was searched exhaustively for `cups|ghostscript|brlaser|
  gutenprint|foomatic`; only unrelated matches like `apcupsd` /
  `collectd-mod-apcups` / `nut-driver-apcupsd-ups` came back. The 24.10.0
  index likewise.)
- **Only the discovery half exists:** `avahi-dbus-daemon` (installed 37 113 B),
  `avahi-nodbus-daemon` (21 402 B), `dbus` (105 690 B), `libdbus` (102 171 B).
  mDNS alone is cheap — but mDNS is the *easy* half, and it is useless without
  the IPP server + rasterizer behind it.
- The OpenWrt wiki's CUPS how-to routes people to **third-party feeds**;
  CUPS has not been in-tree or in-feed for this target.

### The only known complete CUPS+ghostscript feed is archived and needs >100 MB

`openwrt-printing-packages` (FranciscoBorges, now **archived**): the only
maintained OpenWrt feed providing CUPS 1.6.3 + ghostscript + gutenprint +
cups-filters + poppler for mips. Its README states the decisive fact:

> "set up your router to use **external storage** for its root file system, as
> these packages **require more than a 100 MB of space**."

That is external storage / extroot — explicitly out of scope for this effort
(the destination is a self-contained 8 MB flash image; ticket #4 already
confirmed the whole p910nd stack fits in ~20 KB precisely because it does no
rendering). Even an aggressively stripped CUPS+ghostscript build would be tens
of MB — orders of magnitude over the ~3 MB of headroom the 8 MB image has
after kernel + base + LuCI + USB + the p910nd stack.

### Runtime constraints (RAM/CPU)

- The WR703N has **64 MB RAM**, ~30 MB typically free after boot, and a
  **400 MHz MIPS** core.
- ghostscript rasterizing a letter page at 600 dpi needs on the order of
  hundreds of MB of working memory and tens of seconds–minutes of CPU on this
  class of core. Page rendering would OOM or time out long before it printed.
  (Community reports of CUPS-on-router AirPrint — e.g. GL.iNet forums — all
  run on 128 MB+ RAM / much faster cores, and still warn that "without
  Ghostscript you are unlikely to get on-router file conversion to work" and
  that the full driver stack "requires more space than a normal router has".)

### p910nd's mDNS is not AirPrint

Ticket #4 noted p910nd can advertise its raw service over Bonjour
(`pdl-datastream tcp 9100`). That helps **Mac** discovery of the raw 9100
socket (Mac's driver does the GDI rendering locally — fine for the hard
requirement). It is **not** AirPrint: iOS never browses for
`pdl-datastream`; it browses `_ipp._tcp` + `_universal` + `URF` and sends PDF.
So enabling p910nd's `mdns 1` costs nothing and can stay optional, but it does
not unlock iPhone printing.

## Ruled out (with reasons)

- **CUPS + ghostscript + brlaser + avahi on the WR703N (the only genuine
  AirPrint path)** — not packaged for this target; needs >100 MB per the only
  known feed; ghostscript alone exceeds the flash budget by an order of
  magnitude and the RAM budget for real page rendering. Ruled out, not
  deferred: nothing about this hardware changes.
- **A hand-rolled mini IPP server + pdftoraster on the router** — the
  rasterizer (ghostscript/poppler-class) is the bulk of the problem, and it
  does not shrink. Still tens of MB and still OOM-prone on 64 MB RAM.
- **extroot / external storage to host CUPS** — out of scope for this effort
  by the map's own scope (self-contained image), and it moves the goalposts
  from "minimal gateway" to "router with USB storage", which the destination
  does not include.

## Downstream effect

- **Map scope:** AirPrint moves to **Out of scope** (confirmed the map owner's
  default expectation recorded on the ticket: "AirPrint is out of scope for
  this effort unless ticket 4 shows meaningful headroom" — ticket #4 showed
  headroom only for the ~20 KB p910nd stack, not for a rasterizer).
- **Acceptance tests (ticket #7):** drop any AirPrint test; the iPhone is not
  a supported client. Mac/Windows raw-9100 tests stand as the only printing
  acceptance path. (If iPhone printing is ever needed, the honest answer is a
  separate always-on CUPS box — Raspberry Pi / NAS — or an AirPrint-capable
  printer; both are outside this map.)
- **Build spec (the map's destination):** no CUPS/ghostscript/brlaser/avahi in
  `DEVICE_PACKAGES`; optional `mdns 1` in `/etc/config/p910nd` may stay for Mac
  Bonjour discovery but must be documented as *not* AirPrint.
- **Final package set is now fully decided:** `kmod-usb-printer` + `p910nd`
  (ticket #4) + LuCI (scope amendment) + WiFi client + SSH — no printing stack
  beyond that.

## Evidence

### Primary sources

- Finnie, "AirPrint and Linux" (2010) — first-party protocol teardown from a
  live iOS print capture: IPP on 631; `_ipp._tcp` + `_universal._sub._ipp._tcp`
  subtype required; `URF` TXT record required non-empty; `pdl` must include
  `application/pdf`; iOS sends PDF. https://www.finnie.org/2010/11/13/airprint-and-linux/
- Apple, Bonjour Printing Specification (devimages.apple.com, `BonjourPrinting.pdf`)
  — the mDNS/TXT-record contract AirPrint builds on.
- OpenWrt release package indexes, mips_24kc, **23.05.5 and 24.10.0**
  (`downloads.openwrt.org/.../packages/mips_24kc/packages/Packages.gz`):
  exhaustively searched — no cups/libcups/ghostscript/brlaser/gutenprint/
  foomatic; avahi (+dbus) present with installed sizes listed above.
- `openwrt-printing-packages` README (github.com/FranciscoBorges/
  openwrt-printing-packages, archived): "these packages require more than a
  100 MB of space" → external storage required.
- GL.iNet forum, "AirPrint cups on GL router" (2021): real-world CUPS-on-router
  AirPrint report — ghostscript needed for on-router conversion; the driver
  stack "requires more space than a normal router has"; CUPS/ghostscript not in
  official repos, must be cross-compiled from unofficial packages.
- Reddit r/openwrt "My experience printing with OpenWRT" / "Enabling AirPrint
  OpenWRT/Missing packages": CUPS+AirPrint on flash-constrained routers fails on
  storage; corroborates the missing-package situation.

### In-repo (from this ticket's dependency, ticket #4)

- DCP-1510 is host-based GDI (no PCL/BR-Script) — from
  `docs/wayfinder/wr703n-print-gateway/ticket-04-printing-stack.md`; hence no
  server-side PDL to reuse and no way to skip rasterization.
- p910nd Bonjour advertisement is `pdl-datastream tcp 9100` (raw), not
  `_ipp._tcp` — same file.

## Files touched / to touch for the build

No source changed in this ticket (planning only). Build-phase effect: nothing
AirPrint-related goes into the image; optionally set `mdns 1` in the
`/etc/config/p910nd` overlay shipped by the build spec (documented as Mac
discovery only, not AirPrint).
