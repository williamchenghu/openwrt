# WR703N print-gateway firmware — reproducible build & flash guide

This is the exact procedure that produced the **verified working** firmware
(r35995-5146f45085, USB host fixed, DCP-1510 enumerating as `/dev/usb/lp0`,
p910nd listening on 9100). Follow it top to bottom on a macOS (Apple Silicon
or Intel) or Linux machine with Docker installed.

---

## 0. Prerequisites

- Docker Desktop (arm64 native — no emulation needed)
- This repository checked out
- WR703N with **8 MB flash mod** (the 4 MB stock chip cannot hold this image)
- Breed bootloader already installed (see `backup/wr703n/bootloader/breed-ar9331.bin`
  and ticket #7 findings for how it got there)

---

## 1. Build the firmware (one command)

```bash
./build/build.sh
```

That single entrypoint:
1. builds the `owrt-wr703n-builder` Docker image (one-time),
2. syncs the repo read-only into a named volume (`owrt-sdk`) — all build
   writes stay in the volume, so macOS bind-mount hardlink pitfalls never bite,
3. applies kernel patches from `build/patches/*.patch`,
4. applies `build/openwrt.config` (device, Wi-Fi, SSH, LuCI, print stack),
5. runs `make` (first run 30–60 min; later runs are incremental),
6. copies images to `bin-docker/ath79/tiny/`.

Sub-commands if needed:

| command | purpose |
|---|---|
| `./build/build.sh config` | feeds + config only (no compile) |
| `./build/build.sh build` | compile only (keeps volume .config) |
| `./build/build.sh artifacts` | copy images out of the volume |
| `./build/build.sh menuconfig` | interactive fine-tuning (rarely needed) |
| `./build/build.sh clean-all` | wipe volume, full rebuild from scratch |

### What makes this build work (do not "simplify" these away)

- **`build/patches/0099-usb-chipidea2-add-reset-handling.patch`** — the USB fix.
  Breed leaves the USB controller reset (`rst 5`) asserted; stock bootloaders
  deassert it before boot. Without this patch `ci_hdrc` reports
  `doesn't support host / no supported roles` and USB never works. The glue
  driver now deasserts the optional reset in probe.
- **`package/kernel/linux/modules/usb.mk`** — `kmod-usb-chipidea` DEPENDS on
  `kmod-usb-roles` (`roles.ko` is a hard runtime dependency of `ci_hdrc`).
- **`build/openwrt.config`** — selects `kmod-usb-core/-common/-chipidea/
  -chipidea2/-roles/-usb2/-printer`, `p910nd`, LuCI, dropbear, Wi-Fi client.
  NOTE: lines must not carry trailing `# comments` — Kconfig treats them as
  part of the value and silently drops the line (build.sh strips them).
- **`target/linux/ath79/config-6.18`** — `CONFIG_PHY_AR7100_USB=y`,
  `CONFIG_PHY_AR7200_USB=y` (AR9331 USB PHYs built into the kernel).
- **`target/linux/ath79/dts/ar9331_tplink_tl-wr703n-8m.dtsi`** — 8 MB partition
  layout (firmware `0x20000–0x7f0000`, ART at `0x7f0000`), `dr_mode = "host"`,
  `vbus-supply`, `usb_phy` enabled.

---

## 2. Verify the build before flashing

```bash
shasum -a 256 bin-docker/ath79/tiny/openwrt-ath79-tiny-tplink_tl-wr703n-squashfs-factory.bin
# expected: 97f2084f6ade086e6c5bbee7591657de81995ce8e62272a3314a6991a2061058
```

In-container sanity checks (optional but recommended):

```bash
docker run --rm -v owrt-sdk:/sdk -w /sdk/openwrt owrt-wr703n-builder sh -c '
  grep -E "CONFIG_USB_CHIPIDEA_HOST|CONFIG_USB_ROLE_SWITCH|CONFIG_PHY_AR7100_USB|CONFIG_PHY_AR7200_USB" \
    build_dir/target-mips_24kc_musl/linux-ath79_tiny/linux-6.18.44/.config
  strings build_dir/target-mips_24kc_musl/linux-ath79_tiny/linux-6.18.44/drivers/usb/chipidea/ci_hdrc_usb2.ko \
    | grep reset_control_deassert
'
```

Expect `=y` on all four configs and `reset_control_deassert` present in the module.

---

## 3. Flash via Breed

1. Power off, hold Reset, power on, keep held ~8 s → Breed web UI at `http://192.168.1.1`
   (wired, Mac static IP `192.168.1.2/24`).
2. **Firmware slot only**: choose
   `bin-docker/ath79/tiny/openwrt-ath79-tiny-tplink_tl-wr703n-squashfs-factory.bin`
3. Bootloader slot: **leave empty**. ART slot: **leave empty**.
4. **Never** use "恢复出厂 / factory reset" in Breed — it can wipe ART and kill Wi-Fi.
5. Wait for Breed to report the write finished, then reboot. First boot takes
   1–2 minutes (jffs2 format) — be patient before assuming it is bricked.

Verified image (also committed under `firmware-images/`):

```
factory:    97f2084f6ade086e6c5bbee7591657de81995ce8e62272a3314a6991a2061058
sysupgrade: 704e4d64f8e8a9780b7377cb98809c65e2ebbe029aa2e8bec2195d8cc261d3b7
```

---

## 4. Post-flash verification (device)

```sh
cat /etc/openwrt_release                     # DISTRIB_REVISION='r35995-5146f45085'
dmesg | grep -iE 'usb|ci_hdrc|phy|usblp'
# expect:
#   ci_hdrc ci_hdrc.0: EHCI Host Controller
#   ci_hdrc ci_hdrc.0: USB 2.0 started, EHCI 1.00
#   usb 1-1: new high-speed USB device ... (printer plugged in)
#   usblp 1-1:1.0: usblp0: ... vid 0x04F9 pid 0x02D0
ls -l /sys/bus/usb/devices/
find /dev -type c | grep lp                  # /dev/usb/lp0
/etc/init.d/p910nd restart && /etc/init.d/p910nd status   # running
netstat -lnt | grep 9100                     # LISTEN on 0.0.0.0:9100
```

If `dmesg` shows `doesn't support host` again, the patch did not apply —
re-run `./build/build.sh config` (it re-applies `build/patches/`) and rebuild.

---

## 5. Network + print acceptance

1. LuCI → Network → Wireless → radio0 **Scan** → join home AP.
   The new interface defaults to network `wwan`, which sits in the **wan**
   firewall zone (input REJECT) — move it to **lan** (Interfaces → wwan →
   Edit → Firewall Settings → zone `lan`, Save & Apply). Wi-Fi blips for a
   few seconds; that is normal.
2. The home router's DHCP reservation pins the device (e.g. `192.168.8.75`);
   no static config needed on the WR703N.
3. Mac: `nc -vz 192.168.8.75 9100` → `succeeded`.
4. Mac printer setup: **HP Jetdirect-Socket** (raw 9100), address = the
   device IP, queue empty. Driver: the CUPS entry for "Brother DCP-1510 series"
   works once the Mac can reach port 9100.
5. Print a test page.

---

## 6. Recovery (if a flash goes wrong)

- Breed is in the bootloader slot and survives bad firmware flashes —
  always recoverable via Reset-held power-on.
- Full-flash dumps, ART, and the Breed binary live in `backup/wr703n/`
  (untracked working copies; the two full dumps + ART + breed are the ones
  worth keeping). Reflashing a full dump restores bootloader + firmware + ART
  in one write.
