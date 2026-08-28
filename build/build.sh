#!/usr/bin/env bash
# Build the WR703N print-gateway OpenWrt image entirely inside Docker on macOS
# (also works on Linux). Your Mac's Docker Desktop (Apple Silicon native arm64,
# or Intel amd64) runs a Linux build container; the repo is mounted read-only,
# and ALL build writes land in a container-native named volume so the
# macOS-bind-mount hardlink/symlink pitfalls never bite.
#
# Usage (from the repo root):
#   ./build/build.sh            -> full: deps, feeds, config, make, copy artifacts to ./bin-docker/
#   ./build/build.sh menuconfig -> interactive LuCI/adWireless/... config (optional fine-tune)
#   ./build/build.sh config     -> just feeds + apply config (no compile)
#   ./build/build.sh artifacts  -> copy built images out of the volume to ./bin-docker/
#   ./build/build.sh clean-all  -> wipe the named volume (start a truly fresh toolchain)
#
# By default NO menuconfig is needed: build/openwrt.config carries the target,
# device, print stack, LuCI, SSH and disabled DNS from the wayfinder spec.
# To see / change any option, run: ./build/build.sh menuconfig

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="owrt-wr703n-builder"
VOL="owrt-sdk"
CTR="owrt-wr703n"
WORKDIR="/sdk/openwrt"          # inside the volume
REPO_SRC="/src"                 # repo bind-mounted read-only

OUT_DIR="$REPO_ROOT/bin-docker"

# ----------------------------------------------------------------------------
cd "$REPO_ROOT"

command -v docker >/dev/null 2>&1 || { echo "docker not found — install Docker Desktop first"; exit 1; }

prompt_confirm() {
  local msg="$1"
  read -r -p "$msg [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

ensure_image() {
  if ! docker image inspect "$IMG" >/dev/null 2>&1; then
    echo ">> Building $IMG image (one-time; base deps only)..."
    docker build -t "$IMG" -f "$REPO_ROOT/build/Dockerfile.openwrt" "$REPO_ROOT/build"
  fi
}

# Create a throwaway container, run a command in the build dir, then remove it.
# Interactive commands need the TTY flag (menuconfig is a full-screen UI).
run_in_ctr() {
  local interactive="${2:-}"
  local tty_flag=""
  [ "$interactive" = "tty" ] && tty_flag="-it"
  docker rm -f "$CTR" >/dev/null 2>&1 || true
  docker run --name "$CTR" --rm $tty_flag \
    -v "$REPO_ROOT:$REPO_SRC:ro" \
    -v "$VOL:/sdk" \
    -w "$WORKDIR" \
    "$IMG" bash -euxo pipefail -c "$1"
}

sync_source() {
  # Copy host source into the volume build tree. Preserve everything the build
  # system generates INSIDE the tree across runs (feeds checkouts + symlinks,
  # build_dir/staging_dir/dl/tmp, previous bin/ artifacts, and the volume's
  # .config) — none of these exist on the host, so --delete must never touch
  # them or incremental builds and feed symbols silently break.
  run_in_ctr '
    mkdir -p /sdk/openwrt
    # Leading slash anchors each exclude to the tree root. UNANCHORED patterns
    # would match at any depth and nuke same-named files deeper in the tree
    # (e.g. excluding "feeds" also deleted the scripts/feeds executable).
    rsync -a --delete \
      --exclude "/.git" \
      --exclude "/build_dir" \
      --exclude "/staging_dir" \
      --exclude "/dl" \
      --exclude "/tmp" \
      --exclude "/feeds" \
      --exclude "/package/feeds" \
      --exclude "/bin" \
      --exclude "/.config" \
      --exclude ".DS_Store" \
      '"$REPO_SRC"'/ /sdk/openwrt/
  '
}

feeds_and_config() {
  sync_source
  run_in_ctr '
    # Copy the committed config delta and apply it over a clean baseline.
    cp '"$REPO_SRC"'/build/openwrt.config /tmp/openwrt.config
    ./scripts/feeds update -a >/dev/null
    ./scripts/feeds install -a
    make defconfig
    # Merge OUR deltas last so they win; then normalize.
    { cat .config; \
      grep -v "^#" /tmp/openwrt.config | grep -v "^[[:space:]]*$"; } > .config.new
    mv .config.new .config
    make defconfig >/dev/null
  '
  echo ">> Config applied (host: build/openwrt.config)."
}

menuconfig() {
  sync_source
  run_in_ctr '
    if [ ! -f .config ]; then
      ./scripts/feeds update -a >/dev/null
      ./scripts/feeds install -a
      make defconfig >/dev/null
    fi
    export TERM=xterm-256color
    make menuconfig
  ' tty
}

build() {
  sync_source   # flow host edits in, but keep the .config already in the volume
  docker run --rm -v "$VOL:/sdk" -w "$WORKDIR" "$IMG" \
    test -f .config || {
      echo ">> No .config in the build volume yet — run ./build/build.sh first."; exit 1;
    }
  run_in_ctr 'make V=s -j"$(nproc)"'
}

copy_artifacts() {
  mkdir -p "$OUT_DIR"
  # Safest: fetch through a throwaway container that touches the volume.
  docker rm -f "$CTR" >/dev/null 2>&1 || true
  docker run --name "$CTR" --rm \
    -v "$VOL:/sdk" -w "$WORKDIR" "$IMG" \
    sh -c 'tar -C /sdk/openwrt/bin/targets -cf - .' \
    | tar -xf - -C "$OUT_DIR"
  echo ">> Artifacts copied to: $OUT_DIR"
}

case "${1:-all}" in
  all)
    ensure_image
    feeds_and_config
    build
    copy_artifacts
    echo "======================================================"
    echo "DONE. Images in: $OUT_DIR"
    echo "  openwrt-ath79-tiny-tplink_tl-wr703n-*-squashfs-factory.bin   (first flash via Breed web console)"
    echo "  openwrt-ath79-tiny-tplink_tl-wr703n-*-squashfs-sysupgrade.bin (routine upgrade)"
    echo "======================================================"
    ;;
  config)
    ensure_image; feeds_and_config
    ;;
  menuconfig)
    ensure_image; menuconfig
    echo ">> Saved. Rebuild with: ./build/build.sh build  (keeps your menuconfig choices)"
    ;;
  build)
    ensure_image; build
    ;;
  artifacts)
    copy_artifacts
    ;;
  clean-all)
    if prompt_confirm "Remove the '$VOL' Docker volume (deletes toolchain + all build trees)? "; then
      docker rm -f "$CTR" >/dev/null 2>&1 || true
      docker volume rm "$VOL"
      echo ">> Volume removed. Next ./build/build.sh will start a fresh toolchain (~30-60 min)."
    fi
    ;;
  *)
    echo "Unknown command: ${1:-}"; exit 1
    ;;
esac