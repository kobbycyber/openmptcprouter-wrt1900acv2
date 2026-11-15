#!/bin/sh
# Build OpenMPTCProuter for the Linksys WRT1900AC v2 (cobra).
#
#   ./build.sh                    one-shot build with upstream's build.sh
#   PREBUILT_RUST=1 ./build.sh    staged build that installs the official Rust
#                                 binaries instead of compiling LLVM + rustc
#   PREPARE_ONLY=1 ./build.sh     stop after the buildroot is configured
#
# Environment (defaults reproduce the published image):
#   OMR_REF       openmptcprouter commit          (pinned below)
#   OMR_FEED_SRC  openmptcprouter-feeds commit    (pinned below)
#   OMR_PACKAGES  mini | full   - "full" does NOT fit this router's flash
#   OMR_KERNEL    6.18
#   OMR_RELEASE   version string baked into the image
#   OMR_HOST      host of your own package repo, baked into the image feeds
#   JOBS          parallel jobs (default: number of CPUs)
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
OMR_REF=${OMR_REF:-155a309523469afd82216d55e901c3a8320ddb26}
export OMR_FEED_SRC=${OMR_FEED_SRC:-773fed80e3b39f2ef6b810baa266d07a790d2520}
export OMR_TARGET=wrt1900acv2
export OMR_PACKAGES=${OMR_PACKAGES:-mini}
export OMR_KERNEL=${OMR_KERNEL:-6.18}
export OMR_RELEASE=${OMR_RELEASE:-v0.66-snapshot}
export OMR_HOST=${OMR_HOST:-127.0.0.1}
JOBS=${JOBS:-$(nproc)}
WORK=${WORK:-$HERE/omr}
SRC=$WORK/$OMR_TARGET/$OMR_KERNEL/source

# OpenWrt refuses to configure some host tools as root without this
[ "$(id -u)" -ne 0 ] || export FORCE_UNSAFE_CONFIGURE=1

if [ ! -d "$WORK/.git" ]; then
	mkdir -p "$WORK"
	git -C "$WORK" init -q
	git -C "$WORK" remote add origin https://github.com/Ysurac/openmptcprouter
fi
git -C "$WORK" fetch -q --depth 1 origin "$OMR_REF"
git -C "$WORK" checkout -q -f FETCH_HEAD
cp "$HERE/config-wrt1900acv2" "$WORK/config-$OMR_TARGET"
cd "$WORK"

if [ "${PREPARE_ONLY:-0}" = 1 ] || [ "${PREBUILT_RUST:-0}" = 1 ]; then
	ONLY_GET_REPO=yes sh build.sh
	ONLY_PREPARE=yes sh build.sh
	make -C "$SRC" defconfig
	[ "${PREPARE_ONLY:-0}" = 1 ] && { echo "Buildroot ready in $SRC"; exit 0; }
	make -C "$SRC" IGNORE_ERRORS=m tools/install toolchain/install -j"$JOBS"
	"$HERE/scripts/use-prebuilt-rust.sh" "$SRC"
	make -C "$SRC" IGNORE_ERRORS=m -j"$JOBS"
else
	sh build.sh -j"$JOBS"
fi

OUT=$SRC/bin/targets/mvebu/cortexa9
"$HERE/scripts/verify-image.sh" "$OUT"/*linksys_wrt1900ac-v2-squashfs-factory.img
echo "Images are in $OUT"
