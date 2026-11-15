#!/bin/sh
# Install the official Rust release into the OpenWrt buildroot instead of
# letting the openmptcprouter "rust" host package compile LLVM and rustc.
#
# Why: that host build needs hours on a small machine, about 15 GB of disk and
# more than 5 GB of RAM for single compile jobs. The official dist tarballs are
# the same version, come from the same source commit and are installed with
# the very same Host/Install step, so nothing in the feed is modified.
#
# Usage: scripts/use-prebuilt-rust.sh <openwrt source dir>
# Run it after tools/install and toolchain/install, before building packages.
set -eu
SRC=$(cd "${1:?usage: $0 <openwrt source dir>}" && pwd)
RUST_TARGET=${RUST_TARGET:-armv7-unknown-linux-musleabihf}
RUST_HOST=${RUST_HOST:-x86_64-unknown-linux-gnu}
PKG=package/feeds/openmptcprouter/rust
VER=$(sed -n 's/^PKG_VERSION:=//p' "$SRC/$PKG/Makefile")
[ -n "$VER" ] || { echo "cannot read the rust version from $SRC/$PKG/Makefile" >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || export FORCE_UNSAFE_CONFIGURE=1

# Unpack and configure the source tree so that OpenWrt's stamps are in place
make -C "$SRC" "$PKG/host/configure"
HB=$(echo "$SRC"/build_dir/target-*/host/rustc-"$VER"-src)
[ -f "$HB/.configured" ] || { echo "rust host package is not configured in $HB" >&2; exit 1; }

# The source is only needed for a from-source build: keep the stamps only
find "$HB" -mindepth 1 -maxdepth 1 ! -name '.configured' ! -name '.prepared*' -exec rm -rf {} +
mkdir -p "$HB/build/dist"
cd "$HB/build/dist"
for c in rustc-$VER-$RUST_HOST rust-std-$VER-$RUST_HOST rust-std-$VER-$RUST_TARGET cargo-$VER-$RUST_HOST; do
	curl -fsSLO "https://static.rust-lang.org/dist/$c.tar.gz"
	curl -fsSLO "https://static.rust-lang.org/dist/$c.tar.gz.sha256"
done
sha256sum -c ./*.sha256
rm -f ./*.sha256

# Mark the compile step as done; Host/Install then installs the tarballs
touch "$HB/.built"
make -C "$SRC" "$PKG/host/compile"
"$(echo "$SRC"/staging_dir/target-*/host/bin/rustc)" --version
