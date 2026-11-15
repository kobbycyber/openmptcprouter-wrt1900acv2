#!/bin/sh
# Sanity-check a WRT1900AC v2 (cobra) factory image before flashing.
# Usage: scripts/verify-image.sh <...-squashfs-factory.img>
#
# Flash layout (armada-385-linksys-cobra.dts): each firmware slot is 40 MiB,
# split into a 6 MiB kernel area followed by a 34 MiB UBI rootfs.
set -eu
IMG=${1:?usage: $0 <factory.img>}
SLOT=$((40 * 1024 * 1024))
KERNEL_AREA=$((6 * 1024 * 1024))
PEB=131072
ROOTFS_PEBS=$(( (SLOT - KERNEL_AREA) / PEB ))
# UBI keeps 4 PEBs for itself and reserves 20 for bad-block handling
UBI_OVERHEAD=24
rc=0
size=$(stat -c %s "$IMG")
echo "image size:      $size bytes (slot: $SLOT)"
if [ "$size" -gt "$SLOT" ]; then echo "FAIL: image is larger than the 40 MiB firmware slot"; rc=1; fi
magic=$(dd if="$IMG" bs=1 skip=$KERNEL_AREA count=4 2>/dev/null | od -An -c | tr -d ' \n')
echo "magic at 6 MiB:  $magic"
if [ "$magic" != "UBI#" ]; then echo "FAIL: no UBI header at the 6 MiB offset (kernel too large or wrong image type)"; rc=1; fi
pebs=$(( (size - KERNEL_AREA + PEB - 1) / PEB ))
free=$(( ROOTFS_PEBS - UBI_OVERHEAD - pebs ))
echo "rootfs UBI:      $pebs of $ROOTFS_PEBS erase blocks; about $(( free * 126976 / 1024 )) KiB left for the overlay"
if [ "$free" -lt 17 ]; then echo "FAIL: not enough room left for a writable overlay"; rc=1; fi
if strings -n 8 "$IMG" | grep -q "linksys,cobra"; then echo "device tree:     linksys,cobra found"; else echo "FAIL: cobra device tree not found in the kernel"; rc=1; fi
[ $rc -eq 0 ] && echo "OK" || echo "DO NOT FLASH"
exit $rc
