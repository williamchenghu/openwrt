# Ticket #7 — Define flashing, recovery, and acceptance tests

> Wayfinder map: **Wayfinder: slim WR703N Brother DCP-1510 Wi-Fi print gateway**
> Ticket: **Define flashing, recovery, and acceptance tests** (issue #7, `wayfinder:grilling`)
> Status: resolved — see the ticket's resolution comment for the canonical decision record.

## Question the ticket resolved

> What U-Boot installation procedure, recovery precautions, and post-flash
> acceptance tests are required before the image can be considered safe and
> usable?

**Scope correction during resolution:** the unit does **not** run stock
U-Boot — its bootloader is **Breed** (hackpascal's "Boot and Recovery
Environment for Embedded Devices", the Chinese-community bootloader known as
刷不死 / "unbrickable"). The question is answered for Breed, not U-Boot.

## Bootloader facts (verified)- **Binary**: `backup/wr703n/bootloader/breed-ar9331.bin` (single
  canonical copy) — the **AR9331 general**
  build, self-identifies as `Version 1.1 (r1337)` (hackpascal 2021-12-15; newer than
  the r1163 builds archived on the official EOL page, so no official MD5 table
  entry exists). MD5 `13323271ead321322b12ea319c72ad53`. 115200 baud, reset
  button GPIO#11 — matches the WR703N's actual reset button
  (`ar9331_tplink_tl-wr703n_tl-mr10u.dtsi`: `gpios = <&gpio 11 ...>`).
- **Installed at flash offset 0x0–0x20000** (the "u-boot" mtd partition): the
  full-dump backup's first bytes equal the Breed binary's first bytes
  (`10 00 00 ff …`), and Breed occupies ~90 KB ≪ 128 KB, so the TP-Link MAC
  region at `0x1fc00` is untouched.
- **Breed's environment** ("环境变量") is stored *inside the Breed partition*
  (Breed web console: for TP-LINK firmware select 「Breed 内部」), so it never
  collides with the firmware or ART regions. We leave env disabled/defaults
  alone — nothing in our plan requires changing it.
- **Partition table source**: the running 19.07 boot log shows
  `5 tp-link partitions found on MTD device spi0.0` — the kernel's TP-Link
  partition parser derives kernel/rootfs from the image header; u-boot and art
  come from fixed offsets and the detected 8 MB flash size. **Breed does not
  pass `mtdparts` on the kernel cmdline**, so the ath79 image's own DTS
  `fixed-partitions` (ticket #2 plan) is authoritative — no alignment changes
  needed. The device's actual table matches the #2 8mlzma layout exactly:

  ```
  u-boot    0x000000000000-0x000000020000
  kernel    0x000000020000-0x0000001a59d8   (from tp-link header)
  rootfs    0x0000001a59d8-0x0000007f0000   (squashfs, magic hsqs at 0x1a59d8)
  rootfs_data 0x000000460000-0x0000007f0000 (squashfs-split)
  art       0x0000007f0000-0x000000800000
  firmware  0x000000020000-0x0000007f0000   (kernel+rootfs, 8000 k)
  ```

- **ART / WiFi calibration (per-unit!)**: the ART partition (0x7f0000–
  0x800000) holds the device's unique AR9331 radio calibration. Verified in
  the backups: valid eeprom blob at `0x7f1000` (`02 02 00 03` header,
  exactly 0x440 bytes) — the precise region the DTS `cal_art_1000` cell
  (`reg = <0x1000 0x440>`) reads. WiFi works on the current firmware, which is
  the live proof the calibration is present and valid. **Never bake ART into
  the image** (it is per-unit and the DTS already reads it from flash); keep
  per-unit dumps under `backup/wr703n/art/`.
- **Device identity**: LAN MAC at `0x1fc00` = `38:83:45:3F:44:90` (used for
  both eth0 and wmac per the DTS `macaddr_uboot_1fc00` cell).

## Answer (conclusion)

**Flashing, recovery, and acceptance are built around Breed's web recovery
console; every path preserves the Breed partition and the ART partition.**

### 1. Flash backups (assets, committed)

| Path | Content | MD5 |
|---|---|---|
| `backup/wr703n/20260828_full/wr703n_backup_full_MAC_4490.bin` | whole 8 MB flash (Breed + current 19.07 + ART) | `bd1974024f9140a22e0f7e681613ed09` |
| `backup/wr703n/art/wr703n_backup_art_MAC_4490.bin` | 64 KB ART dump (cal at +0x1000) | `6fcdcefee9e213b7fad2f3456d8343f7` |
| `backup/wr703n/art/wr703n_backup_art_MAC_11AD.bin` | byte-identical copy of the above | `6fcdcefee9e213b7fad2f3456d8343f7` |
| `backup/wr703n/bootloader/breed-ar9331.bin` | Breed binary (single canonical copy) | `13323271ead321322b12ea319c72ad53` |

> ⚠️ Note: the two ART files are **identical** (same MD5). The MAC suffix on
> the 11AD copy does not correspond to any MAC found in the ART data or the
> full dump (the unit's LAN MAC ends in `44:90`); if 11AD was meant to label a
> *second* unit's ART, that copy is actually this unit's dump and must be
> replaced with the real one before being trusted.

### 2. Flashing procedure

- **Rehearsal (done by the user, passed)**: restored the whole-flash backup
  via Breed 编程器固件 (programmer-firmware page, TP-LINK/auto layout);
  the unit booted back to the current firmware and Breed re-entry worked. This
  validated the Breed flash channel and the restore path before any real flash.
- **First flash of the new image (primary path)**: hold reset on power-on →
  Breed web console at `http://192.168.1.1` → 固件更新 → **常规固件**
  (normal firmware) page → upload **only the 固件 (firmware) field**: the
  OpenWrt **factory** image (`openwrt-ath79-tiny-tplink_tl-wr703n-*-squashfs-factory.bin`,
  8Mlzma / TP-Link layout; select TP-LINK or auto-detect) → flash → device
  reboots into the new image. **Leave the bootloader and art fields empty** —
  Breed writes only what is uploaded, so Breed itself and the ART partition
  are preserved (this is the 刷不死 mechanism: Breed also strips any embedded
  bootloader from firmware it flashes).
- **Routine upgrades**: from within OpenWrt via LuCI or `sysupgrade` with the
  **sysupgrade** image — writes only the firmware partition
  (0x20000–0x7f0000); Breed and ART are never touched.
- **Fallback if Breed rejects the factory image** (not expected): try the
  sysupgrade image in the same 常规固件 field; both carry a TP-Link V1 header.
- **ART restore** (only if ART is ever lost/corrupted): 常规固件 page, upload
  the 64 KB ART dump in the **art field** (writes 0x7f0000–0x800000). Do this
  before booting the image, since the ath79 DTS reads calibration from ART.

### 3. Recovery

- **Standard**: hold reset on power-on → Breed web console at
  `http://192.168.1.1` → reflash. Verified working on this unit by the user.
  Breed **auto-enters web flashing mode when firmware fails to boot** — a
  bricked image cannot strand the unit (the 刷不死 property).
- **Whole-unit restore**: 编程器固件 page with `wr703n_backup_full_MAC_4490.bin`
  (TP-LINK/auto layout) restores Breed + firmware + ART in one shot (rehearsed).
- **Last resort** (only if Breed itself is lost): TTL serial (3.3 V, 115200)
  console and/or an SPI programmer; reinstall Breed from
  `backup/wr703n/bootloader/breed-ar9331.bin` and re-verify the
  MAC at `0x1fc00` after any bootloader write (Breed manual's own warning).

### 4. Post-flash acceptance tests

1. Boot log shows the 8 MB table: `firmware` 0x20000–0x7f0000, `art`
   0x7f0000–0x800000.
2. Valid MACs: `cat /sys/class/net/eth0/address` (expect `38:83:45:3F:44:90`
   or at least not `ff:ff:ff:ff:ff:ff`); wlan0 MAC valid.
3. Wi-Fi client joins the upstream network and obtains an address (DHCP or
   upstream static lease) — a working radio also proves ART calibration was
   read correctly from 0x7f1000.
4. SSH works with a modern client (dropbear **ed25519** hostkey — ticket #6;
   fixes the macOS `No matching algo hostkey` failure).
5. LuCI reachable; root password set on first boot (ticket #6 first-boot flow).
6. DCP-1510 enumerates as usblp: `usblp 1-1:1.0: usblp0: USB Bidirectional
   printer … vid 0x04F9 pid 0x02D0` (ticket #3).
7. p910nd listens on TCP 9100 (`netstat -lnt`); print test from Windows and
   macOS (ticket #4: RAW 9100 port).
8. Reset-button → Breed web console still reachable after the flash.

## Evidence

- User Q&A (grilling rounds 1–3): Breed installed via off-board programmer
  during the 8 MB mod; reset-button Breed entry confirmed by the user; 19.07
  backup no longer available, whole-flash backup used for the rehearsal
  instead (rehearsal passed); ART backups labeled by MAC suffix and provided
  for the repo.
- Live device (user-supplied kernel log): `5 tp-link partitions found on MTD
  device spi0.0` with the exact 8 MB table above; WiFi confirmed working.
- Breed web console (user-supplied text): env storage is 「Breed 内部」 for
  TP-LINK firmware — inside the Breed partition, no firmware/ART collision.
- Backups (in-repo, MD5s above): full dump head = Breed binary head; ART dump
  == full-dump 0x7f0000–0x800000 byte-for-byte; squashfs magic `hsqs` at
  0x1a59d8; LAN MAC `38:83:45:3F:44:90` at 0x1fc00; cal blob `02 02 00 03`
  at 0x7f1000.
- [Breed manual](https://breed.hackpascal.net/) and the
  [English overview](https://www.scribd.com/document/740425657/breed-manual-en):
  AR9331 general build (115200, reset GPIO#11), WR703N in the supported list,
  8 MB SPI-NOR flash supported, reset-button web recovery, auto web mode on
  boot failure, firmware flashing strips embedded bootloaders.

## Downstream effect

- Unblocks the **build-spec phase** (the map's destination): build and keep
  **both** artifacts — `factory.bin` (Breed web-console flashing, the first-
  flash path) and `sysupgrade.bin` (routine upgrades); ship the #2 8mlzma
  DTS as decided (table already proven on the unit); no ART baking, no
  bootloader in the image; keep the `backup/wr703n/` dumps (incl. the Breed
  binary) as recovery assets.
- Resolves the map's fog: the bootloader path is **compatible** with the
  selected image (partition table comes from the firmware, not Breed), and the
  "safe flashing/recovery" fog item is now the procedure above.
- Domain vocabulary recorded in `CONTEXT.md` (Breed, ART).

## Files touched / to touch for the build

No source changed in this ticket (planning only). Assets added:
`backup/wr703n/` (full flash, ART dumps, bootloader incl. the Breed binary).
Build-phase effect: produce factory + sysupgrade images from the
#2 8mlzma layout; no other flashing-side changes.
