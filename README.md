# OpenMPTCProuter for the Linksys WRT1900AC v2 (cobra)

[OpenMPTCProuter](https://github.com/Ysurac/openmptcprouter) (OMR) ships images for the
Linksys WRT3200ACM and WRT32X but not for the WRT1900AC v2. This repository adds the
missing target, documents how to build it, and publishes a prebuilt image.

> **Status: built and statically verified, not yet booted on a real router.**
> The checks that were run are listed under [Verification](#verification). Flash it
> knowing that, and keep the [recovery](#recovery) steps at hand.

| | |
|---|---|
| Device | Linksys WRT1900AC **v2** (code name *cobra*, Armada 385, 88W8864 Wi-Fi) |
| OMR version | v0.66-snapshot, `develop` branch, kernel 6.18.60 |
| Package set | `openmptcprouter-mini` (see [Why mini](#why-mini-and-not-full)) |
| Built | 2026-11-15 |

This is **not** for the WRT1900AC v1 (*mamba*) or the WRT1900ACS (*shelby*). The v2 has
`v2` on the label under the router.

## Downloads

Images are attached to the [releases](../../releases) of this repository.

| File | Size | Use |
|---|---|---|
| `…linksys_wrt1900ac-v2-squashfs-factory.img` | 33,685,504 bytes | Flash from the stock Linksys firmware |
| `…linksys_wrt1900ac-v2-squashfs-sysupgrade.bin` | 30,710,434 bytes | Flash from OpenWrt or OpenMPTCProuter |
| `packages-mvebu-cortexa9.tar.gz` | | Kernel modules and target packages for this exact kernel |
| `packages-arm_cortex-a9_vfpv3-d16.tar.gz` | | All other packages from the build, including the ones left out of the image |

SHA-256:

```
6daa8302399359cc0de79696f93f4efea965d71af5bd66b1ac03c5f5c0e8a8f0  …squashfs-factory.img
ab6ca0046996d26031e98e774be8e92dddf7db8038ce3836424f1e26831a304f  …squashfs-sysupgrade.bin
```

The package list, the full build configuration and the checksums are also kept in
[`builds/v0.66-snapshot-6.18-mini/`](builds/v0.66-snapshot-6.18-mini).

## Why mini and not full

The WRT1900AC v2 has two firmware slots of 40 MiB each. A slot is split into a 6 MiB
kernel area and a 34 MiB rootfs (from `armada-385-linksys-cobra.dts`):

| Partition | Offset | Size |
|---|---|---|
| `kernel1` (whole slot 1) | `0x0a00000` | 40 MiB |
| `rootfs1` | `0x1000000` | 34 MiB |
| `kernel2` (whole slot 2) | `0x3200000` | 40 MiB |
| `rootfs2` | `0x3800000` | 34 MiB |

The WRT3200ACM that OMR supports has larger slots. Built for the WRT1900AC v2:

| Package set | Kernel | Rootfs (squashfs) | Factory image | Fits |
|---|---|---|---|---|
| `openmptcprouter-full` | 5.15 MB | 54.8 MB | 63.8 MB | **No** |
| `openmptcprouter-mini` | 5.15 MB | 25.6 MB | 33.7 MB | Yes |

OpenWrt does not check the image size for this device, so the full build completes
without an error and produces an image that must not be flashed. Most of the difference
is two binaries: `v2ray` (35 MB) and `xray` (29 MB) before compression.

With the mini image the rootfs takes 209 of the slot's 272 erase blocks. After UBI's own
overhead about 4.8 MB is left for the writable overlay (settings and extra packages).

## What is in the image

962 packages; the complete list is in
[`packages.manifest`](builds/v0.66-snapshot-6.18-mini/packages.manifest).

| Included | Not included |
|---|---|
| MPTCP kernel and `mptcpd` | V2Ray, Xray |
| Shadowsocks-Rust (`sslocal`) and Shadowsocks-libev | MPTCP BPF schedulers, `bpftool` |
| Glorytun TCP and UDP, OpenVPN, DSVPN, MLVPN | WireGuard, mqvpn |
| PPPoE; USB tethering (RNDIS, CDC-Ether, QMI kernel modules) | ModemManager, `uqmi` |
| `mwlwifi` with the 88W8864 firmware, `mv88e6xxx` DSA switch | |
| LuCI with the OMR apps (tracker, bypass, DSCP, quota, SQM) | |

## Flashing

Check the file first:

```sh
sha256sum -c sha256sums.txt
scripts/verify-image.sh openmptcprouter-*-squashfs-factory.img
```

**From stock Linksys firmware:** open the router's web interface, go to
*Connectivity → Basic → Router Firmware Update → Manual*, choose the `factory.img` and
start. The router writes it to the slot that is not currently running and reboots into it.

**From OpenWrt or an older OpenMPTCProuter:** copy the `sysupgrade.bin` to `/tmp` and run

```sh
sysupgrade -n -v /tmp/openmptcprouter-*-squashfs-sysupgrade.bin
```

`-n` discards the old configuration, which OMR needs. Coming from a pre-DSA OpenWrt
(19.07 or older) the image is refused with "Config cannot be migrated from swconfig to
DSA"; add `-F` in that case.

After the first boot OMR uses its own defaults (LAN address `192.168.100.1`, user
`root`), not the Linksys or OpenWrt ones. The router also needs an OMR server (VPS) to
aggregate links; that side is covered by the upstream documentation.

### Recovery

The previous firmware stays in the other slot.

- **Without access to the router:** switch it on, and switch it off again as soon as the
  power LED lights up. Do this three times, then let it boot normally. The bootloader
  falls back to the other slot.
- **With SSH access:** `fw_printenv boot_part` shows the active slot (1 or 2);
  `fw_setenv boot_part 1` or `2` selects the other one, then `reboot`.

### Installing more packages

The image's own package feed points at the build machine (`CONFIG_VERSION_REPO` is
`http://127.0.0.1/...`, because no package server was set up for this build), so kernel
modules cannot be installed online. Take them from `packages-mvebu-cortexa9.tar.gz`
instead; they match this kernel exactly and are signed with the key the image trusts:

```sh
scp kmod-wireguard-*.apk root@192.168.100.1:/tmp/
ssh root@192.168.100.1 apk add /tmp/kmod-wireguard-*.apk
```

Mind the 4.8 MB of free space.

## Building

### Requirements

| | From-source Rust (upstream default) | `PREBUILT_RUST=1` |
|---|---|---|
| Disk | 60 GB (suggested, not measured) | 30 GB |
| RAM | 16 GB (suggested, not measured) | 8 GB |
| Time on 2 vCPUs | not completed, see below | about 5 hours (estimate) |

Any x86-64 Linux works; the published image was built on Ubuntu 24.04. Build as a normal
user where possible.

```sh
sudo apt-get update
sudo apt-get install build-essential asciidoc-base binutils bzip2 gawk gettext git \
  libncurses-dev zlib1g-dev libssl-dev libelf-dev libglib2.0-dev patch unzip rsync \
  flex bison swig uglifyjs p7zip-full msmtp texinfo xmlto autoconf automake libtool \
  autopoint device-tree-compiler python3-pyelftools python3-docutils python3-setuptools \
  llvm clang dwarves quilt zstd file wget curl
```

`llvm`/`clang` are needed for the BPF parts of the kernel build, `dwarves` for BTF, and
`python3-docutils` for the OpenVPN man pages (without it `openvpn` fails to build).

### Build

```sh
git clone https://github.com/kobbycyber/openmptcprouter-wrt1900acv2
cd openmptcprouter-wrt1900acv2
./build.sh                    # everything from source, as upstream does it
PREBUILT_RUST=1 ./build.sh    # recommended on small machines
```

`build.sh` in this repository is a thin wrapper. It

1. checks out OpenMPTCProuter at the pinned commit into `omr/`,
2. copies [`config-wrt1900acv2`](config-wrt1900acv2) next to the upstream target configs,
3. runs upstream's `build.sh` with `OMR_TARGET=wrt1900acv2 OMR_PACKAGES=mini OMR_KERNEL=6.18`,
4. runs [`scripts/verify-image.sh`](scripts/verify-image.sh) on the result.

Images end up in `omr/wrt1900acv2/6.18/source/bin/targets/mvebu/cortexa9/`.

To do the same by hand in an existing OpenMPTCProuter checkout:

```sh
cp config-wrt1900acv2 /path/to/openmptcprouter/
cd /path/to/openmptcprouter
OMR_TARGET=wrt1900acv2 OMR_PACKAGES=mini OMR_KERNEL=6.18 ./build.sh -j"$(nproc)"
```

Useful variables (all optional): `OMR_REF` and `OMR_FEED_SRC` to build other commits,
`OMR_HOST` to bake the address of your own package server into the image, `JOBS`,
`WORK` for the build directory, `PREPARE_ONLY=1` to stop once the buildroot is
configured.

### The Rust toolchain

Shadowsocks-Rust needs a Rust cross compiler. OMR's `rust` host package builds LLVM and
`rustc` from source, which is by far the most expensive part of the build: on the
2 vCPU / 7 GB / 31 GB machine used here it ran for four hours, had one compiler job
killed for using more than 5 GB of RAM, and then filled the disk.

[`scripts/use-prebuilt-rust.sh`](scripts/use-prebuilt-rust.sh) avoids that. It downloads
the official Rust release of the version the feed pins (1.99.0), verifies the published
SHA-256 sums, and hands the tarballs to the package's own install step. The compiler is
the same version built from the same source commit (`b940084d7`), and the feed is not
modified. `PREBUILT_RUST=1 ./build.sh` calls it at the right moment.

### How the target was added

The pinned OpenWrt tree already has the device profile `linksys_wrt1900ac-v2`; OMR just
has no target config that selects it. [`config-wrt1900acv2`](config-wrt1900acv2) is
modelled on upstream's `config-wrt3200acm`:

```
CONFIG_TARGET_mvebu=y
CONFIG_TARGET_mvebu_cortexa9=y
CONFIG_TARGET_mvebu_cortexa9_DEVICE_linksys_wrt1900ac-v2=y
CONFIG_PACKAGE_kmod-mwlwifi=y
CONFIG_PACKAGE_mwlwifi-firmware-88w8864=y
CONFIG_PACKAGE_luci-app-advanced-reboot=y
# The Linksys kernel partition is 6 MB
# CONFIG_KERNEL_CC_OPTIMIZE_FOR_PERFORMANCE is not set
CONFIG_KERNEL_CC_OPTIMIZE_FOR_SIZE=y
CONFIG_KERNEL_ARM_MODULE_PLTS=y
```

The kernel is built for size because of the 6 MiB kernel area. `luci-app-advanced-reboot`
is requested the way upstream does for the WRT3200ACM, but upstream's feed setup does
not install that package into the buildroot, so the option is dropped and it is not in
the image.

### Pinned sources

| Component | Commit |
|---|---|
| [Ysurac/openmptcprouter](https://github.com/Ysurac/openmptcprouter) (`develop`) | `155a309523469afd82216d55e901c3a8320ddb26` |
| [Ysurac/openmptcprouter-feeds](https://github.com/Ysurac/openmptcprouter-feeds) (`develop`) | `773fed80e3b39f2ef6b810baa266d07a790d2520` |
| openwrt/openwrt | `dd72c4c198330e208c2357625693a03996cae741` |
| openwrt/packages | `1cc5d4c5b8b6e57fde9dac55ab9e3367407b0160` |
| openwrt/luci | `4a3d16e914564ccf239802ad8dd57026c3860dd0` |
| openwrt/routing | `ea8633da9c461a9bdc62a0323439d31180762e03` |

The OpenWrt commits are the ones upstream's `build.sh` pins at that OMR commit. Toolchain:
GCC 14.4.0, musl 1.2.6, binutils 2.46.1; package architecture `arm_cortex-a9_vfpv3-d16`.

### Changing the package set

The limit is the 34 MiB rootfs. To trade packages, keep `OMR_PACKAGES=mini`, add or
remove `CONFIG_PACKAGE_...` lines in `config-wrt1900acv2`, rebuild, and run
`scripts/verify-image.sh` on the new `factory.img`. It fails if the image is larger than
the slot, if the kernel has outgrown its 6 MiB, or if too little is left for the overlay.
The Xray package alone is 11 MB compressed, so it only fits if other things go.

## Verification

Done on the published image:

- Kernel is 5,150,815 bytes (limit 6,291,456); the UBI rootfs starts at the 6 MiB offset.
- Factory image is 32.1 MiB of the 40 MiB slot.
- The kernel carries the `linksys,cobra` device tree; the sysupgrade metadata lists
  `linksys,wrt1900ac-v2`, `armada-385-linksys-cobra` and `linksys,cobra`.
- `kmod-mwlwifi`, `mwlwifi-firmware-88w8864` and `kmod-dsa-mv88e6xxx` are installed.
- `sslocal`, `openvpn` and `busybox` from the rootfs start under QEMU ARM user-mode
  emulation (`-cpu cortex-a9`), linked against the image's own musl.
- `build.sh` with `PREPARE_ONLY=1` was run from a clean directory and produces the same
  configuration as the published image (apart from build logging).
- `scripts/use-prebuilt-rust.sh` was run from a clean state in the finished buildroot.

Not done:

- No boot on hardware. Wi-Fi, the switch, the LEDs and the dual-slot upgrade path are
  untested.
- The published image came out of a staged build (full first, then mini in the same
  buildroot), not out of a single `./build.sh` run. The wrapper has not been run from
  start to finish.

More detail on what happened during that build is in
[`docs/build-notes.md`](docs/build-notes.md).

## License and credits

OpenMPTCProuter is the work of Yannick Chabanois (Ycarus) and contributors and is
licensed under the GPL v3; the files in this repository follow the same license. The
image contains OpenWrt and many other free software packages under their own licenses;
the sources are the pinned commits above.
