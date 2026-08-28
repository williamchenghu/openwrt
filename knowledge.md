# knowledge.md

## What this project is

**OpenWrt** — a Linux operating system / firmware build system targeting embedded devices (routers, SBCs, etc.). This repo is the core build system: it cross-compiles a toolchain, kernel, and packages, then assembles flashable firmware images. GPL-2.0 licensed.

Related, separate repos (not here): `openwrt/packages`, `openwrt/luci` (web UI), `openwrt/routing` — these are consumed as "feeds" at build time.

## Commands

Requirements: GNU/Linux, BSD or macOS (case-sensitive FS). Tools: `binutils bzip2 diff find flex gawk gcc-6+ getopt grep install libc-dev libz-dev make4.1+ perl python3.8+ rsync subversion unzip which`.

```sh
# One-time setup: fetch + install feeds into package/feeds/
./scripts/feeds update -a
./scripts/feeds install -a

# Configure (menuconfig -> .config)
make menuconfig
make defconfig              # resolve/normalize a partial config

# Build firmware for configured target (long: hours on first run)
make -j$(nproc) V=sc        # V=sc = verbose; V=s even more verbose
make download -j$(nproc)    # prefetch sources first (recommended)

# Clean levels (increasingly aggressive)
make clean        # remove build/staging dirs, bin/
make targetclean  # + toolchain
make dirclean     # + host staging + tmp (full reset)
make cacheclean   # clear ccache (if CONFIG_CCACHE=y)

# Per-package / per-target shortcuts
make package/<name>/{clean,compile,install} V=s
make target/linux/compile V=s
make kernel_menuconfig        # configure kernel options
make tools/install V=s        # host tools only
make toolchain/install V=s    # cross toolchain only
```

Build output: `bin/targets/<board>/<subtarget>/` (images + packages). Logs: `logs/` when using `make ... V=sc -j1`.

## Architecture / key directories

- `include/` — the build system's core makefiles (`rules.mk`, `package.mk`, `target.mk`, `kernel.mk`, `download.mk`, `host-build.mk`, etc.). Changes here affect everything; CI builds host tools on `include/**` and `tools/**` changes.
- `package/` — in-tree packages by category: `base-files/`, `boot/`, `devel/`, `firmware/`, `kernel/` (incl. all `kmod-*` under `kernel/linux/modules/`), `libs/`, `network/`, `system/`, `utils/`. Feeds get symlinked into `package/feeds/`.
- `target/` — per-board support. `target/linux/<board>/` has `Makefile` (ARCH, FEATURES, SUBTARGETS, KERNEL_PATCHVER), `config-<ver>`, `image/`, `patches-<ver>/`, `files/`; subtargets as subdirectories. Generic content in `target/linux/generic/` (patches, kernel version/hash files).
- `toolchain/` — cross-compiler pieces: gcc, binutils, musl/glibc, kernel-headers, gdb, mold.
- `tools/` — host-side build tools (squashfs4, firmware-utils, mkimage, ccache, ...).
- `scripts/` — build-system scripts: `feeds` (feed manager), `download.pl` (source fetch + hash check), `package-metadata.pl`, `target-metadata.pl`, `checkpatch.pl` (kernel patch lint), `getver.sh`, `kconfig.pl`, image builders (`mkits.sh`, `sysupgrade-tar.sh`, ...).
- `config/` — kconfig machinery (`Config.in` tree, `Config-build.in`, `Config-images.in`).
- `.config` — generated build config (kconfig). Never hand-edit; not committed.

**Data flow:** feeds + packages → `menuconfig` produces `.config` → `make` builds `tools/` (host) → `toolchain/` → `target/linux/` (kernel + modules) → `package/` (ipk files) → `target/.../image/` assembles sysupgrade/factory images in `bin/`.

## Conventions

- **Package Makefiles** use a fixed macro structure: `PKG_NAME`, `PKG_VERSION`, `PKG_RELEASE`, `PKG_SOURCE_URL`, `PKG_HASH`, `PKG_LICENSE`, then `include $(INCLUDE_DIR)/package.mk` and `define Package/<name>` blocks. `scripts/fixup-makefile.pl` can automate some edits.
- **Commit messages**: `<area>: <subsystem>: <summary>` — e.g. `realtek: dsa: trap EAPOL frames to the CPU on RTL93xx`. Areas commonly match top-level dirs (`package/`, `kernel:`, `tools/`, `scripts:`, or a board name).
- SPDX headers (`# SPDX-License-Identifier: GPL-2.0-only`) at top of new Makefiles/scripts.
- Kernel version bumps require updating `target/linux/generic/kernel-<ver>` (version + hash) and per-board `KERNEL_PATCHVER` where applicable.
- Patches are quilt-format under `patches-<kernel ver>/`; regenerate with `make target/linux/{refresh,clean}` / quilt workflow (`include/quilt.mk`).
- CI (GitHub Actions) mostly reuses shared workflows from `openwrt/actions-shared-workflows`; kernel CI builds all targets on `target/**` changes, tools CI on `tools/**`/`include/**`.

## Gotchas

- Absolute path must contain **no spaces**; filesystem must be case-sensitive (no Cygwin).
- Build env is picky: always use the in-tree toolchain staging paths; never install distro cross-compilers into it.
- Forgetting `./scripts/feeds install` → packages missing from `menuconfig`.
- A full `make` with no prior `make download` fails often on flaky upstream mirrors; fetch sources first.
- `<PKG_RELEASE>` bumps are required when a package's content changes without a version change.
- `make -jN V=s` output is huge; use `-j1 V=s` when debugging a specific failure.
- Kernel patches/configs are per kernel version (`patches-6.12`, `patches-6.18`); patching the wrong tree dir silently does nothing.
- macOS builds work but some targets need extra tools (e.g. `mkisofs`/`genisoimage`/`xorrisofs` for x86 ISO images).
