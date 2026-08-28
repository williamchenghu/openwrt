# Build & validation spec — slim WR703N Brother DCP-1510 Wi-Fi print gateway

> Wayfinder map: **Wayfinder: slim WR703N Brother DCP-1510 Wi-Fi print gateway** (issue #1, `wayfinder:map`)
> Purpose: the map's destination — a **reproducible build and validation
> specification** that turns the ticket decisions into a buildable firmware.
> This document closes the map; it is not the firmware build itself.
> Status: **implementation-ready spec** (not yet built).

## What this spec is, and what it is not

The map's destination is "the implementation-ready build and validation
specification, not the firmware build itself." This file is that
specification: the exact source edits, the `.config` package set, the build
environment and commands, the expected artifacts, and the pass/fail acceptance
tests. Someone with a Linux x86_64 machine and ~3–6 h of toolchain compile
time can follow it to produce the image. Nothing here is site-specific (ticket
#6): the image is network-agnostic and reusable for any modified WR703N.

**Version pin:** build from the `ath79`/`tiny` mainline-snapshot tree in this
repository, **pinned to commit `c1507be`** (`c1507be27436cf8546e48b3dae1bcc4fcfbaa817`),
the `origin/main` HEAD this spec was written against. Fed toolchain/kmod
version drift is avoided by staying on that commit (mainline `SNAPSHOT`); the
official `openwrt-24.10` line publishes **no ath79 `tiny` kmods**, so a
self-built snapshot is the supported path (ticket #2 re-audit). Verify the
three edit targets below still hold at build time before compiling.

---

## 1. Build environment

- **Host:** Linux x86_64 (OpenWrt's `make`/toolchain tooling does not build on
  macOS; use a Linux VM, container, or WSL2 on this Mac).
- **Dependencies:** install the Debian/Ubuntu prerequisites from
  `docs/agent/…`? No — use the official list, from the OpenWrt docs (also
  available as `apt-get install` in the build guide in
  `README`/`include/prereq.mk`):
  `build-essential clang flex bison g++ gawk gcc-multilib g++-multilib
  gettext git libncurses5-dev libssl-dev python3 python3-venv python3-setuptools
  rsync swig unzip zlib1g-dev file wget curl`.
  - Disk: ≥ 10 GB free. Time: first build ~3–6 h (toolchain), later builds
    incremental.
  - Do not build as root (`make` refuses); use an unprivileged user.
- **Sources:** a fresh checkout at the pinned commit into the project root of
  this repo (the tree already is the OpenWrt source), or `git clone
  https://github.com/williamchenghu/openwrt.git && git checkout c1507be`.
  The edits in §2 apply against that checkout, then the build is run there.

---

## 2. Source edits (captured on a feature branch)

Three coordinated edits enable the full 8 MB on the **703N only**, without
touching the 4 MB `tplink_tl-mr10u` (which shares a DTS aggregate — see
correction note below).

### 2.1 `target/linux/ath79/image/tiny-tp-link.mk`

```
define Device/tplink_tl-wr703n
  $(Device/tplink-8mlzma)        # was $(Device/tplink-4mlzma)
  SOC := ar9331
  DEVICE_MODEL := TL-WR703N
  DEVICE_PACKAGES := kmod-usb-chipidea2
  TPLINK_HWID := 0x07030101
  SUPPORTED_DEVICES += tl-wr703n
endef
```

`tplink-8mlzma` (in `target/linux/ath79/image/common-tp-link.mk`) gives
`TPLINK_FLASHLAYOUT := 8Mlzma`, `IMAGE_SIZE := 8000k` — matching the 8 MB
firmware region (ticket #2).

> **Correction to ticket #2's §3.** Ticket #2 said to edit the partitions in
> the shared aggregate `ar9331_tplink_tl-wr703n_tl-mr10u.dtsi`. That aggregate
> is included by **both** `tplink_tl-wr703n` **and** `tplink_tl-mr10u`, and
> both are built in `ath79/tiny`. Editing the shared file would resize the
> MR10U (a stock 4 MB device) and break its image. The 8 MB layout must live in
> a **per-device** DTS variant instead — see §2.2. (Verify at build time that
> the `.dtsi` is still shared with the MR10U; if the share was refactored
> away, editing the then-private file becomes acceptable.)

### 2.2 Split an 8 MB DTS variant for the 703N (mirrors `tl-wr710n-8m.dtsi`)

The codebase's established convention for a same-board / different-flash-size
variant is a dedicated `-8m.dtsi` (see `ar9331_tplink_tl-wr710n-8m.dtsi`).
Apply the same pattern:

1. **`target/linux/ath79/dts/ar9331_tplink_tl-wr703n-8m.dtsi`** (new file) —
   copy `ar9331_tplink_tl-wr703n_tl-mr10u.dtsi`, keep the `#include
   "ar9331.dtsi"` and all SoC/peripheral wiring, and in the `flash@0`
   `partitions` node change the two entries to the 8 MB layout:
   - `partition@20000` `reg = <0x20000 0x3d0000>` → `reg = <0x20000 0x7d0000>;`
     (`firmware` spans 0x20000..0x7f0000)
   - `art: partition@3f0000` `reg = <0x3f0000 0x10000>` → keep the `art` label,
     change to `partition@7f0000` with `reg = <0x7f0000 0x10000>;`
   Leave u-boot (0x0–0x20000) and the `cal_art_1000` nvmem child untouched.
   `art` stays pinned to the very end of flash (per-unit data, read from
   `cal_art_1000` at ART+0x1000, 0x440 B — ticket #7).

2. **`target/linux/ath79/dts/ar9331_tplink_tl-wr703n.dts`** — change the
   include so this device builds against the 8 MB variant:
   `#include "ar9331_tplink_tl-wr703n_tl-mr10u.dtsi"` →
   `#include "ar9331_tplink_tl-wr703n-8m.dtsi"`.
   (The `&reg_usb_vbus` gpio override and `model`/`compatible` blocks stay as
   they are. The MR10U `.dts` continues to include the shared 4 MB aggregate.)

### 2.3 Commit + PR

Per the repo's ways of working, these edits go on a **feature branch** off
`origin/main` and land via a PR (do not commit to `main`). The diffconfig from
§3.2 attaches to the same branch/PR so the build is fully reproducible from
the merged state.

---

## 3. Configuration (`make menuconfig`) — the package set

Launch menuconfig, set the target, enable the in-scope package set, disable
the out-of-scope services, and **do not** minimize further. Then capture a
reproducible diffconfig.

### 3.1 Menu selections

- **Target System:** `Atheros ATH79`
- **Target Profile:** `Devices with small flash` (subtarget `tiny`)
- **Target Devices:** `TP-Link TL-WR703N` (only; do not feel compelled to
  build others — the MR10U may be left enabled or not, but 703N must be)
- **Target Images:** keep default — **squashfs** rootfs (pair of
  `sysupgrade.bin` + `factory.bin`); no initramfs/fit needed.

Package toggles (add these on top of the profile's defaults):
- `luci`, `luci-theme-bootstrap`, `luci-app-p910nd` — full admin UI + printer
  status page (map scope amendment; SSH stays primary admin).
- `p910nd`, `kmod-usb-printer` — raw TCP 9100 pass-through, the DCP-1510
  print stack (ticket #4). No CUPS, no filters, no Brother server software.
- WiFi client: keep the profile default `kmod-ath9k` + `wpad-basic-mbedtls`
  (built-in AR9331 wmac, station mode).
- `dropbear` (default on) — SSH; modern defaults generate an **ed25519**
  hostkey, fixing the #3 macOS `No matching algo hostkey` failure.
- `kmod-usb-chipidea2` already in the device's `DEVICE_PACKAGES`.

Disable (out of scope, ticket #6):
- `dnsmasq`, `odhcpd` — no local DHCP/DNS; the gateway is a pure client.
- No `luci-app-ddns`, no VPN, no AP/NAT/firewall extras.

**Do not** set `mini`/lean profile to claw back bytes — the post-#5 audit
confirms the full 8 MB build fits with margin and the print stack is only
~20 KB installed (map re-audit).

### 3.2 Capture a reproducible diffconfig

```bash
./scripts/feeds update -a
./scripts/feeds install -a
make defconfig
make menuconfig                 # apply §3.1, then save + exit
./scripts/diffconfig.sh > diffconfig   # commit this diffconfig
```

`diffconfig` (a `CONFIG_*` delta vs. defaults) is the reproducible artifact:
apply it later with `cp diffconfig .config && make defconfig`.

---

## 4. Image size budget

Target: 8 MB SPI-NOR (this unit) with `art` pinned at 0x7f0000–0x800000 and
`firmware` spanning 0x20000–0x7f0000 (**8000 k** usable; `IMAGE_SIZE := 8000k`).

| Component                                   | Installed (typical) |
|---------------------------------------------|---------------------|
| Kernel (ath79/tiny lzma)                    | ~2.0–2.5 MB         |
| Base + SSH + WiFi client + USB host (kmods) | ~2.0–2.5 MB         |
| Print stack: `p910nd` + `kmod-usb-printer`  | ~20 KB (ticket #4)  |
| LuCI + theme + `luci-app-p910nd`            | ~0.5 MB             |
| **Total (est.)**                            | **~5.5–6.5 MB**     |

Leaves ~1.5–2.5 MB headroom. **Pass gate:** the built `*-squashfs-sysupgrade.bin`
must be `≤ 8000 KB` (the `tplink-v1`/`mktplinkfw` builder enforces
`IMAGE_SIZE`; an over-size build fails the image step).

---

## 5. Build command

```bash
make V=s -j$(nproc)   # repeat until warnings-free; ipv4 toolchain built once
ls -la bin/targets/ath79/tiny/
```

Expected artifacts (squashfs):
```
openwrt-ath79-tiny-tplink_tl-wr703n-<rev>-squashfs-sysupgrade.bin
openwrt-ath79-tiny-tplink_tl-wr703n-<rev>-squashfs-factory.bin
openwrt-ath79-tiny-tplink_tl-wr703n-<rev>-squashfs-<…> (any optional variant)
```

`factory.bin` (TP-Link V1 header, `-F 8Mlzma`) is only for flashing from a
stock bootloader/web UI; with **Breed** present it is still the first-flash
image (ticket #7). `sysupgrade.bin` is for routine upgrades over OpenWrt.

---

## 6. Validation / acceptance tests (pass/fail)

Derived from tickets #6 (runtime) and #7 (flashing/recovery).

### 6.1 Verification on the host (before touching the device)
1. **Layout in the image:** confirm the DTB carries the 8 MB table —
   `firmware 0x20000 0x7d0000`, `art 0x7f0000 0x10000` (unpack the DTB from
   the factory/sysupgrade image or `fdtget bin/targets/ath79/tiny/*-dtb`).
2. **Size gate:** both images build and are within 8000 k (§4).
3. **No site config baked in:** image contains no Wi-Fi credentials, no root
   password, no static IP (grep the overlay; it must only ship generic
   defaults + the p910nd uci config below).

### 6.2 First flash (Breed — one time per unit)
1. Power off; hold the **reset** button, power on until Breed's web console
   appears at **192.168.1.1** (Breed also auto-enters web mode on boot
   failure). ← Proven recovery path, ticket #7.
2. Browser → Breed **常规固件** (firmware upload). **Firmware field =**
   `*-factory.bin`. **Leave bootloader + ART fields empty** — Breed and ART
   are preserved (do **not** let Breed write flash/ART). ART stays the unit's
   own per-device copy under `backup/wr703n/`; never baked into the image.
3. Flashing completes → device boots the new image.

### 6.3 First-boot provisioning (ticket #6 flow)
1. With **no wireless config shipped**, connect the wired port to the upstream
   router. The DHCP client on `br-lan` obtains an address → LuCI reachable at
   that address.
2. Set the **root password** (LuCI first-run page) — dropbear now permits
   login (it refuses while root has no password).
3. Add the WiFi client: LuCI **Wireless → Add**, mode **Client**, ESSID +
   password, **LAN** network → `wlan0` joins `br-lan`. Optionally add an SSH
   key under System → Administration → SSH-Keys.
4. Expected on-radio layout after setup: single `br-lan` = eth0 + wlan0
   (station); no AP; SSH on eth0+wlan0; `eth1` disabled from LAN forwarding.

### 6.4 Reachability & services
1. From the upstream LAN: **ping** the device by its static lease; **SSH**
   works on port 22 with the **ed25519** hostkey (no macOS `No matching algo
   hostkey`).
2. **Printer service:** `adbd`? No — `p910nd` listens on **TCP 9100**,
   device `/dev/usb/lp0`, `bidirectional 1`, `mdns 1` (Mac Bonjour discovery
   only, **not** AirPrint). `netstat -ltnp` on the gateway shows `:9100`
   bound. mDNS announces `pdl-datastream` (Mac discovery), not AirPrint.
3. **No local services:** dnsmasq and odhcpd **not** running; one `lan` zone,
   no `wan`, no masquerade.

### 6.5 Print acceptance (the hard requirement, ticket #4)
- **Windows:** add the DCP-1510 via official Brother driver on a **Standard
  TCP/IP Port**, Port 9100, Raw. Test page prints.
- **macOS:** add by IP with the Brother driver or `brlaser` (or via Bonjour
  discovery from p910nd's mDNS). Test page prints.
- **Bidirectional:** a successful status/ink read confirms `bidirectional 1`.

### 6.6 Re-flash regression (routine upgrade)
From running OpenWrt on the device, upgrade with `sysupgrade -i
*-sysupgrade.bin` over SSH/LuCI; device keeps working (ticket #2 path).

---

## 7. Downstream closure

After the PR at §2.3 merges and the build passes §6 on a real unit:
- Post the **"✅ Ticket closed: … (#1)"** overview comment on the map issue
  with the decision summary, the size result, and links.
- Record the merge as the build-spec milestone; a separate follow-up can track
  the actual .bin artifacts + unit acceptance if desired.