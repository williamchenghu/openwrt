# Docker build — WR703N print-gateway firmware

Build the OpenWrt image for the modified TL-WR703N (8 MB flash) entirely inside
Docker on macOS (Apple Silicon native arm64 — no emulation) or Linux.

Why this shape: OpenWrt's build does hardlink/symlink-heavy work that macOS
bind mounts handle poorly, so the repo is mounted **read-only** and every
build write lands in a container-native named volume (`owrt-sdk`). The volume
persists across runs, so the toolchain compiles once and later builds are
incremental.

## Prerequisites

- Docker Desktop (or any Docker) running. On Apple Silicon the container is
  native arm64; on Intel/other hosts it is whatever the host is — both work,
  since OpenWrt cross-compiles to the `mips_24kc` target from any Linux host
  arch.
- ~15 GB free disk for the volume (toolchain + build tree).

## Quickstart

```bash
./build/build.sh
```

That single command: builds the builder image (once) → syncs the repo into the
volume → installs feeds → applies `build/openwrt.config` (device, print stack,
LuCI, SSH; DNS/DHCP off) → runs `make` → copies the images to `./bin-docker/`.

First run takes roughly 30–60 min (full toolchain). Later runs are incremental
and much faster. When it finishes:

```
bin-docker/ath79/tiny/openwrt-ath79-tiny-tplink_tl-wr703n-*-squashfs-factory.bin    # first flash (Breed web console)
bin-docker/ath79/tiny/openwrt-ath79-tiny-tplink_tl-wr703n-*-squashfs-sysupgrade.bin # routine upgrades (LuCI/SSH)
```

## Commands

| Command | What it does |
|---|---|
| `./build/build.sh` | Full pipeline: sync → feeds → config → make → copy artifacts |
| `./build/build.sh config` | Re-apply `build/openwrt.config` (no compile) |
| `./build/build.sh menuconfig` | Interactive config UI (see below) |
| `./build/build.sh build` | Recompile with the current `.config` (keeps menuconfig choices) |
| `./build/build.sh artifacts` | Copy built images out of the volume to `./bin-docker/` |
| `./build/build.sh clean-all` | Delete the volume → truly fresh toolchain next time |

## Optional: menuconfig

`build/openwrt.config` already encodes the wayfinder decisions, so most runs
need no UI. To change anything anyway:

```bash
./build/build.sh menuconfig   # full-screen UI inside the container
./build/build.sh build        # rebuild with your saved .config
```

Note `build.sh` (full pipeline) re-applies the committed config; after a
menuconfig session use the `build` command instead, or commit your choices into
`build/openwrt.config`.

## Flashing

See `docs/wayfinder/wr703n-print-gateway/build-spec.md` §6 and
`ticket-07-flashing-recovery.md`: first flash via the **Breed web console**
(常规固件, firmware field = factory image; bootloader/ART fields stay empty),
routine upgrades via LuCI/`sysupgrade`.

## Files

- `build/build.sh` — the single entrypoint (see commands above).
- `build/Dockerfile.openwrt` — Ubuntu 22.04 + OpenWrt build prerequisites;
  arch-aware (installs `gcc-multilib` on amd64 only — it does not exist on
  arm64 and is not needed there).
- `build/openwrt.config` — the committed config delta applied over
  `make defconfig`.
