# Build notes: first build, 2026-11-15

A record of how the published image was produced and what went wrong on the way, so the
next build is shorter.

## Build machine

Cloud VM: 2 vCPUs, 7 GB RAM (memory cgroup), 31 GB free disk, Ubuntu 24.04.5, GCC 13,
building as root with `FORCE_UNSAFE_CONFIGURE=1`.

## Timeline (UTC)

| Time | Step | Duration |
|---|---|---|
| 15:30 | Clone OMR, write `config-wrt1900acv2`, fetch OpenWrt and feeds, `make defconfig` | 10 min |
| 15:43 | `tools/install toolchain/install` | 54 min |
| 16:37 | `prepare` (kernel 6.18.60 with all modules and BTF) | 40 min |
| 17:17 | `package/compile` for `openmptcprouter-full`, including the Rust toolchain from source | stopped after 4 h 08 min |
| 21:26 | Rust replaced by the official 1.99.0 release | 2 min |
| 21:28 | Remaining packages | 26 min |
| 21:54 | `target/install` (full image) | 6 min |
| 22:02 | Switch to `openmptcprouter-mini`, rebuild affected packages and the image | 26 min |

Seven hours of wall-clock time in total. Without the abandoned Rust build it would
have been an estimated five hours on two cores.

The stages are the ones upstream's CI uses:

```sh
ONLY_GET_REPO=yes ./build.sh
ONLY_PREPARE=yes ./build.sh
cd wrt1900acv2/6.18/source
make defconfig
make IGNORE_ERRORS=m tools/install toolchain/install -j3
make IGNORE_ERRORS=m prepare -j3
make IGNORE_ERRORS=m package/compile package/install package/index -j3
make IGNORE_ERRORS=m target/install -j3
make checksum
```

with `OMR_TARGET=wrt1900acv2 OMR_KERNEL=6.18 OMR_RELEASE=v0.66-snapshot OMR_HOST=127.0.0.1`
in the environment. `OMR_RELEASE` has to be set by hand in a shallow clone, because
upstream's `build.sh` derives it from the git tags. Setting `OMR_HOST` avoids a lookup
of the machine's public address at ifconfig.co.

## Problems and what fixed them

### 1. OpenVPN fails without `rst2man`

```
install: cannot stat './openvpn-examples.5': No such file or directory
```

The man pages are generated with `rst2man`. Installing `python3-docutils` fixes it.
Upstream's CI installs it too; it was simply missing on this machine. The full list of
host packages is in the README.

### 2. The Rust toolchain from source did not fit

The `rust` host package in the OMR feed sets `llvm.download-ci-llvm=false`, so it
compiles LLVM (4009 build steps) and then `rustc`.

- LLVM took from about 17:30 to 21:17 on two cores shared with the other package builds.
- At 20:27 one `cc1plus` process reached 5 GB of resident memory and was killed by the
  memory cgroup. The build resumed where it had stopped and the file went through on the
  second attempt, when less was running next to it.
- At 21:25, a few minutes into compiling `rustc` itself, the disk had 199 MB left: the
  kernel build tree is 6.8 GB (BTF debug information), the Rust source 4.2 GB and the
  finished LLVM 7.1 GB.

The build was stopped and the Rust build tree deleted. The official release was used
instead: `rustc`, `cargo` and `rust-std` for the host and for
`armv7-unknown-linux-musleabihf`, version 1.99.0, from static.rust-lang.org, checked
against the published SHA-256 files. The tarballs were placed in the package's
`build/dist` directory and installed by the package's unmodified `Host/Install` step.
`rustc --version` reports `1.99.0 (b940084d7 2026-09-28)`, the same commit as the
source tarball the feed pins. This procedure is now `scripts/use-prebuilt-rust.sh`.

`sslocal` built this way is a dynamically linked PIE for `/lib/ld-musl-armhf.so.1` that
needs only `libc.so` and `libgcc_s.so.1`, and it starts under QEMU user-mode emulation.

### 3. The full image is too big for the router

The build of `openmptcprouter-full` finished without errors and produced a 63.8 MB
factory image for a 40 MiB slot. `Device/linksys` in OpenWrt's
`target/linux/mvebu/image/cortexa9.mk` sets `KERNEL_SIZE := 6144k` but no image size, so
nothing checks it. The image was discarded.

Switching to `openmptcprouter-mini` in the same buildroot:

```sh
sed 's/^CONFIG_PACKAGE_openmptcprouter-full=y/CONFIG_PACKAGE_openmptcprouter-mini=y/' \
    .config.keep > .config
make defconfig
make IGNORE_ERRORS=m package/compile package/install package/index target/install -j3
```

`.config.keep` is the seed configuration upstream's `build.sh` saves before
`make defconfig`. Regenerating from it matters: editing the expanded `.config` would
leave every package that `full` pulled in selected. No kernel option changed, so the
kernel was not rebuilt. A clean `OMR_PACKAGES=mini` run gives the same configuration.

`scripts/verify-image.sh` exists because of this.

### 4. Package feed address in the image

`OMR_HOST=127.0.0.1` ends up in `CONFIG_VERSION_REPO`, so the image's feed for target
packages and kernel modules points at `http://127.0.0.1/release/...`. Kernel modules
for this build are only available from `packages-mvebu-cortexa9.tar.gz` in `builds/`. Set `OMR_HOST` (and
`OMR_PORT`) to a server that hosts `bin/` if online installation matters.

### 5. Disk space during the build

To get through on 31 GB, the toolchain build trees were deleted once the toolchain was
installed, keeping only `linux-dev` and the empty stamp files, which is what upstream's
CI keeps in its cache:

```sh
T=$(echo build_dir/toolchain-*)
for d in "$T"/*/; do
  [ "$(basename "$d")" = linux-dev ] && continue
  find "$d" -mindepth 1 -maxdepth 1 ! \( -type f -empty -name '.*' \) -exec rm -rf {} +
done
```

That frees 3.5 GB. The buildroot was 19 GB at the end.

### 6. Source downloads (specific to this build machine)

The machine's network proxy refused `codeload.github.com`. Two packages that are not on
the OpenWrt mirrors were affected: `shadowsocks-rust` 1.25.0 and `r8152` 2.22.1.20261021.
Their tarballs were recreated from the git tags

```sh
git archive --format=tar --prefix=shadowsocks-rust-1.25.0/ v1.25.0 | gzip -n
```

and matched the `PKG_HASH` in the feed byte for byte. On a normal connection this does
not come up.

## Errors that can be ignored

`logs/package/error.txt` in the buildroot accumulates over all passes. The entries for
`openvpn`, `rust [host]`, `shadowsocks-rust`, `v2ray-core`, `xray-core` and `r8152` date
from the interrupted passes; all of them built in the final one.

The kernel build prints `WARN: resolve_btfids: unresolved symbol bpf_cgroup_from_id`.
It did not stop the build.
