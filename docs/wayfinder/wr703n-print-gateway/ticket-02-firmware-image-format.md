# Ticket #2 — Identify the WR703N target profile and safe firmware image format

> Wayfinder map: **Wayfinder: slim WR703N Brother DCP-1510 Wi-Fi print gateway**
> Ticket: **Identify the WR703N target profile and safe firmware image format** (issue #2, `wayfinder:research`)
> Status: resolved — see the ticket's resolution comment for the canonical decision record.

## Question the ticket resolved

> Which exact OpenWrt target/subtarget/device profile corresponds to the modified
> TP-Link WR703N (ath79/ar9331, `tplink_tl-wr703n`), and which image format,
> flash-layout strategy, and size constraints are safe for its U-Boot flashing
> path and the user's 8 MB SPI-NOR chip? Note the default 4 MB layout
> (`tplink-4mlzma`). Determine whether the 8 MB chip can be flashed with the
> stock 4 MB layout image, or whether a custom mtd partition table must be
> defined to use the extra 4 MB (and whether U-Boot/environment size limits
> permit it).

## Answer (conclusion)

1. **Exact profile: `ath79` / `tiny` subtarget / device `tplink_tl-wr703n`**,
   producing images named:

       openwrt-ath79-tiny-tplink_tl-wr703n-<…>-squashfs-sysupgrade.bin
       openwrt-ath79-tiny-tplink_tl-wr703n-<…>-squashfs-factory.bin

2. **The stock 4 MB image is NOT the right answer.** A stock-`tplink-4mlzma`
   build *will boot* on the 8 MB chip (kernel+rootfs fit inside 4 MB), but its
   device-tree `fixed-partitions` table only exposes ~3.9 MB → the extra ~4 MB
   is wasted. Since OpenWrt ≥ 18.06 drops the WR703N from default image builds
   (`DEFAULT := n`, because stock 4 MB is too small), a custom build is required
   regardless. **The correct strategy is a custom 8 MB mtd layout.**

3. **How to enable the full 8 MB (two coordinated edits):**

   - **`target/linux/ath79/image/tiny-tp-link.mk`** — in
     `define Device/tplink_tl-wr703n` change
     `$(Device/tplink-4mlzma)` → `$(Device/tplink-8mlzma)`.
   - **`target/linux/ath79/dts/ar9331_tplink_tl-wr703n_tl-mr10u.dtsi`** — change
     the firmware/art partitions from the 4 MB offsets to 8 MB offsets:
       - `partition@20000 { reg = <0x20000 0x3d0000>; }` → `reg = <0x20000 0x7d0000>;`
         (`firmware` now spans 0x20000..0x7f0000)
       - `art: partition@3f0000 { reg = <0x3f0000 0x10000>; }` →
         `art: partition@7f0000 { reg = <0x7f0000 0x10000>; }`

   `tplink-8mlzma` exists in `target/linux/ath79/image/common-tp-link.mk`:
   `TPLINK_FLASHLAYOUT := 8Mlzma`, `IMAGE_SIZE := 8000k` — matches the 8 MB
   firmware region (0x7d0000 = 8 192 000 B = 8000 k).

4. **Flashing path (safety):** because OpenWrt is already running on the device
   (19.07.10), onward upgrades use **OpenWrt sysupgrade over SSH**, not the
   TP-Link factory GUI:

       scp bin/targets/ath79/tiny/openwrt-*-sysupgrade.bin root@<ip>:/tmp/
       ssh root@<ip>  # or via LuCI
       sysupgrade -i /tmp/openwrt-*-sysupgrade.bin

   The `factory.bin` (TP-Link V1 header, `-F 8Mlzma`) matters for re-flashing
   from the *stock* bootloader/web UI; it is not needed once OpenWrt is present.

5. **U-Boot / size constraints:** no blocker found. The `tplink-v1` image
   builder (`mktplinkfw`) writes the `TPLINK_FLASHLAYOUT` into the header and
   enforces `IMAGE_SIZE` (8000 k for 8Mlzma). The OKLI/lzma loader offsets are
   unchanged; only the partition table and image size change. `art`
   (Wi-Fi calibration) must remain at the **very end** of flash.

## Evidence

### In-repo (primary)

- `target/linux/ath79/image/Makefile` (L114, L121–124): subtarget's device
  `.mk` is included per-subtarget; `tiny` includes `tiny-tp-link.mk`.
- `target/linux/ath79/tiny/target.mk`: `BOARDNAME:=Devices with small flash`,
  features `low_mem small_flash`.
- `target/linux/ath79/image/tiny-tp-link.mk` L301–309: `Device/tplink_tl-wr703n`
  uses `$(Device/tplink-4mlzma)`, `DEVICE_PACKAGES := kmod-usb-chipidea2`,
  `TPLINK_HWID := 0x07030101`.
- `target/linux/ath79/image/common-tp-link.mk`: `tplink-4mlzma`
  (`4Mlzma`, 3904 k) and `tplink-8mlzma` (`8Mlzma`, 8000 k) both inherit
  `tplink-v1`; `DEFAULT := n` on the 4 M variants.
- `target/linux/ath79/dts/ar9331_tplink_tl-wr703n_tl-mr10u.dtsi`: 4 MB
  `fixed-partitions` (firmware 0x20000–0x3f0000, art 0x3f0000–0x400000).
- `include/image-commands.mk` `Build/tplink-v1-image`: passes `-F
  $(TPLINK_FLASHLAYOUT)`, `-j -X 0x40000`, `-s` for sysupgrade via
  `mktplinkfw`.

### Live device (from the ticket #3 boot log)

- `s25fl064k (8192 Kbytes)` — the 8 MB SPI-NOR chip is detected.
- The previously-flashed 19.07 boot populated an **8 MB-aware table**:
  `firmware` 0x20000–0x7f0000, `art` 0x7f0000–0x800000 — i.e. an 8 MB layout
  already booted successfully on this unit, proving the path is safe.

### External (community)

- [HackingGate: "Build OpenWrt for TL-WR703N with 16M flash"](https://hackinggate.com/blog/build-openwrt-22-03-for-tl-wr703n-with-16m-flash/)
  documents the identical recipe for resized-flash WR703N on ath79: switch the
  device to the `16mlzma` (here `8mlzma`) base *and* resize the DTS firmware/art
  partitions; then flash via `sysupgrade -i`. Validates the 8 MB plan above with
  proven, buildable steps.
- Resized-flash WR703N (8 MB/64 M) is a well-known community mod (e.g. the
  MR3420 forum thread; `right.com.cn` thread-183094).

## Downstream effect

- Confirms for **Choose the smallest viable printing stack** (#4) that ~8 MB is
  available if this layout is adopted; a 4 MB-only build would impose a much
  harder size budget.
- Flashing/recovery (**Define flashing, recovery, and acceptance tests**, #7)
  must use the sysupgrade-over-SSH path and treat `factory.bin` as a fallback.

## Files touched / to touch for the build

The build edits themselves belong to the build phase (the destination boundary is
"implementation-ready spec", not the firmware build), so no source is changed in
this ticket. Ready-to-apply diff sketch above in §3.