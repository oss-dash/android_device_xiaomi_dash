#!/usr/bin/env bash
#
# Build the dash kernel from source.
#
#   kernel         : kernel/xiaomi/dash/kernel-6.6      Content-Creation-Club/android_kernel_xiaomi_dash
#   device modules : kernel/xiaomi/dash/device-modules  Content-Creation-Club/android_kernel_xiaomi_dash_device_modules
#   mtk modules    : kernel/xiaomi/dash/mtk-modules     Content-Creation-Club/android_kernel_xiaomi_dash_mtk_modules
#   kleaf scripts  : kernel/xiaomi/dash/build           Content-Creation-Club/android_kernel_xiaomi_dash_build
#   output         : kernel/xiaomi/dash/out
#
# The config and the module list come from the kernel repositories, nothing
# is invented here:
#
#   gki_defconfig              the GKI 6.6 base
#   mgk_64_k66_defconfig       the MT6991 platform config
#   dash.config                the dash device config
#   android-recommended.config the base configs of a GKI build
#   ext_modules.list           the out-of-tree module directories to build
#
# The staged output has the same layout as the prebuilt kernel in
# device/xiaomi/dash-kernel, so the board config does not care where the
# kernel came from:
#
#   out/Image.lz4
#   out/kernel-uapi-headers.tar.gz
#   out/dtb/*.dtb
#   out/modules/vendor_dlkm/*.ko   + modules.load
#   out/modules/vendor_ramdisk/*.ko + modules.load + modules.load.recovery
#
# Usage: build-kernel.sh [android-tree-root]
#
set -euo pipefail

# The script stops at the first failing command, say which one it was.
trap 'rc=$?; echo "   the build stopped at line $LINENO (exit $rc)" >&2; exit $rc' ERR

# The script changes directory, so the paths to its own files have to be
# resolved before that happens.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE_DIR="$(dirname "$SCRIPT_DIR")"
TREE="${1:-$(cd "$SCRIPT_DIR/../../../.." && pwd)}"
KERNEL_SRC="$TREE/kernel/xiaomi/dash/kernel-6.6"
DEVMOD_SRC="$TREE/kernel/xiaomi/dash/device-modules"
MTKMOD_SRC="$TREE/kernel/xiaomi/dash/vendor/mediatek/kernel_modules"
KLEAF_DIR="$TREE/kernel/xiaomi/dash/build"
PREBUILT="$TREE/device/xiaomi/dash-kernel"
WS="$TREE/kernel/xiaomi/dash/ws"
OUT="$TREE/kernel/xiaomi/dash/out"
KBUILD_OUT="$WS/out"
# A clang job needs about a gigabyte of memory. Starting more jobs than the
# machine has memory for gets the build killed without a message, so cap it.
CPU_JOBS="$(nproc 2>/dev/null || echo 8)"
MEM_GB="$(awk '/^MemTotal:/ {printf "%d", $2/1048576}' /proc/meminfo 2>/dev/null || echo 0)"
if [ "${MEM_GB:-0}" -gt 0 ]; then
    MEM_JOBS=$((MEM_GB / 2))
    [ "$MEM_JOBS" -lt 1 ] && MEM_JOBS=1
    JOBS="${JOBS:-$((CPU_JOBS < MEM_JOBS ? CPU_JOBS : MEM_JOBS))}"
else
    JOBS="${JOBS:-$CPU_JOBS}"
fi

die() { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "== $* =="; }

[ -f "$KERNEL_SRC/Makefile" ] || die "kernel source not found: $KERNEL_SRC
Did you repo sync? The kernel projects are in the local manifest."
[ -f "$DEVMOD_SRC/Makefile" ] || die "device modules not found: $DEVMOD_SRC
Did you repo sync? The kernel projects are in the local manifest."

# ---------------------------------------------------------------------------
# 1. Toolchain
#
# The tree keeps several clang releases side by side, including ancient ones
# like clang-3289846 (2017). Those cannot build a 6.6 kernel, so select
# deliberately: the release the kernel pins, otherwise the newest clang-r*.
# ---------------------------------------------------------------------------
step "1/8 toolchain"
CLANG_ROOT="${CLANG_ROOT:-$TREE/prebuilts/clang/host/linux-x86}"
[ -d "$CLANG_ROOT" ] || CLANG_ROOT="$TREE/kernel/prebuilts/6.6/arm64/prebuilts/clang/host/linux-x86"
KVER="${CLANG_VERSION:-$(sed -n 's/^CLANG_VERSION=//p' "$KERNEL_SRC/build.config.constants" 2>/dev/null | head -1 || true)}"
# build.config.constants names the release r510928, the directory is
# clang-r510928. Strip the prefix so both forms name the same toolchain:
# without this the pinned release was never found and the newest clang of
# the tree (clang 22) was used instead of the pinned clang 18.
KVER="${KVER#r}"

CLANG_BIN=""
if [ -n "$KVER" ]; then
    # The kernel pins a toolchain and is tested with it. A silent fallback
    # to a newer clang is not harmless: clang 22 built this 6.6 tree into a
    # kernel that never got past the logo, while the stock and the kleaf
    # builds of the same tree use the pinned clang 18.
    if [ ! -x "$CLANG_ROOT/clang-r$KVER/bin/clang" ]; then
        ALT_CLANG_ROOT="$TREE/kernel/prebuilts/6.6/arm64/prebuilts/clang/host/linux-x86"
        [ -x "$ALT_CLANG_ROOT/clang-r$KVER/bin/clang" ] && CLANG_ROOT="$ALT_CLANG_ROOT"
    fi
    [ -x "$CLANG_ROOT/clang-r$KVER/bin/clang" ] || \
        die "the kernel pins clang-r$KVER, it is not under $CLANG_ROOT"
    CLANG_BIN="$CLANG_ROOT/clang-r$KVER/bin"
    echo "   pinned      : clang-r$KVER"
else
    for c in $(ls -d "$CLANG_ROOT"/clang-r* 2>/dev/null | sort -V || true); do
        [ -x "$c/bin/clang" ] && CLANG_BIN="$c/bin"
    done
    if [ -z "$CLANG_BIN" ]; then
        for c in $(ls -d "$CLANG_ROOT"/clang-* 2>/dev/null | sort -V || true); do
            [ -x "$c/bin/clang" ] && CLANG_BIN="$c/bin"
        done
    fi
fi
[ -n "$CLANG_BIN" ] || die "no clang toolchain found under $CLANG_ROOT"

CLANG_VER="$("$CLANG_BIN/clang" --version 2>/dev/null | head -1 || true)"
case "$CLANG_VER" in
    *"version 3."*|*"version 4."*|*"version 5."*|*"version 6."*|*"version 7."*)
        die "clang is too old for a 6.6 kernel: $CLANG_VER ($CLANG_BIN)" ;;
esac

BUILDTOOLS_BIN=""
for b in "$TREE"/prebuilts/build-tools/linux-x86/bin "$TREE"/prebuilts/build-tools/path/linux-x86/bin; do
    [ -d "$b" ] && { BUILDTOOLS_BIN="$b"; break; }
done
[ -n "$BUILDTOOLS_BIN" ] || die "no kernel build-tools found under $TREE/prebuilts/build-tools"

export PATH="$CLANG_BIN:$BUILDTOOLS_BIN:$PATH"
echo "   clang      : $CLANG_BIN"
echo "   version    : $CLANG_VER"
echo "   build-tools: $BUILDTOOLS_BIN"
command -v dtc >/dev/null || die "dtc not found (expected in $BUILDTOOLS_BIN)"

# The platforms of a driver share one source directory through a symlink.
# The driver trees of mediatek are laid out that way, the gps driver for
# example has seven platforms and all of them take their lib, hal, link,
# linux and fw_log directory from the same one.
#
# The objects of a module are written next to their source, so the seven
# platforms would write their objects into the same files and the build
# would race with itself. The fixdep of one platform finds the dependency
# file of the other one gone and the build fails with
#
#   fixdep: error opening file: .../plat/v030/lib/.gps_dl_lib_misc.o.d:
#   No such file or directory
#
# Give every platform its own copy of the shared directory. Only the
# workspace gets the copies, the repository keeps its symlinks.
expand_dir_symlinks() {
    local root="$1" pass link target todo left
    for pass in 1 2 3 4 5; do
        todo=""
        while IFS= read -r link; do
            if [ -n "$link" ] && [ -d "$link" ]; then
                todo="$todo $link"
            fi
        done < <(find "$root" -type l)
        if [ -z "$todo" ]; then
            break
        fi
        for link in $todo; do
            target="$(readlink -f "$link")"
            if [ ! -d "$target" ]; then
                continue
            fi
            rm -f "$link"
            cp -a "$target" "$link"
            # the copy must not carry the objects of an earlier build
            find "$link" \( -name '*.o' -o -name '*.ko' -o -name '.*.cmd' \
                -o -name '*.mod' -o -name '*.mod.c' -o -name 'modules.order' \
                -o -name 'Module.symvers' \) -delete
        done
    done
    # the count must not be a pipeline that can fail, the script runs with
    # set -e and pipefail and a failing pipeline stops it
    left="$(find "$root" -type l -exec test -d {} \; -print | wc -l)"
    if [ "$left" -gt 0 ]; then
        echo "   WARNING: $left directories are still shared, the build will race with itself"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# 2. Workspace
#
# build.config.mtk_kernel_device_modules expects the kernel to be called
# kernel-6.6 and the device modules to be a sibling of it.
# ---------------------------------------------------------------------------
step "2/8 workspace"
# The workspace holds the copies of the kernel and of the module trees, the
# build is incremental in it. Set KEEP_WS=1 to keep it, then a change to
# this script does not cost a full rebuild.
if [ "${KEEP_WS:-0}" != "1" ]; then
    rm -rf "$WS"
else
    echo "   reusing the workspace, the build is incremental"
fi
mkdir -p "$WS/build" "$WS/prebuilts" "$WS/vendor/mediatek"

# Everything is copied into the workspace, not linked. The kernel and the
# module trees have to be siblings, the module trees resolve the kernel
# headers and the symbol lists relative to the kernel source directory and
# relative to the output directory, and both have to end up at the same
# place:
#
#   $(srctree)/$(DEVICE_MODULES_REL_DIR)   the source side
#   $(OUT_DIR)/$(DEVICE_MODULES_REL_DIR)   the output side
#
# An external module build also writes its objects and its modules into the
# module directory, that would fill the git repositories with build
# artifacts.
# A copy is only refreshed when the source changed, the build is incremental
# in the workspace and a copy that is not refreshed builds the old sources.
copy_source() {
    local src="$1" dst="$2" stamp now
    stamp="$WS/.stamp-$(echo "$dst" | tr '/' '_')"
    now="$(git -C "$src" rev-parse HEAD 2>/dev/null || echo unknown)"
    if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$now" ] && [ -d "$dst" ]; then
        echo "   $(basename "$dst") is up to date"
        return 0
    fi
    echo "   copying $(basename "$dst")"
    rm -rf "$dst"
    cp -a "$src" "$dst"
    echo "$now" > "$stamp"
}
copy_source "$KERNEL_SRC" "$WS/kernel-6.6"
copy_source "$DEVMOD_SRC" "$WS/device-modules"
# the MTK module trees live where ext_modules.list expects them, relative to
# the kernel source directory
if [ -d "$MTKMOD_SRC" ]; then
    copy_source "$MTKMOD_SRC" "$WS/vendor/mediatek/kernel_modules"
    echo "   giving every platform its own copy of the shared directories"
    expand_dir_symlinks "$WS/vendor/mediatek/kernel_modules"
fi
ln -sfn "$KLEAF_DIR" "$WS/build/kernel"
ln -sfn "$TREE/prebuilts" "$WS/prebuilts"

# The pinned clang 18 does not know -Werror=implicit-enum-enum-cast. Some
# revisions of the trees add it, and an incremental workspace can still hold
# a copy after the source was fixed. Drop it from the workspace copy, the
# repositories themselves are not touched.
WS_HITS="$(grep -rIl --exclude-dir=.git --exclude-dir=out \
    -e '-Werror=implicit-enum-enum-cast' \
    -e '-Wno-error=implicit-enum-enum-cast' \
    "$WS/kernel-6.6" "$WS/device-modules" "$WS/vendor/mediatek/kernel_modules" \
    2>/dev/null || true)"
if [ -n "$WS_HITS" ]; then
    echo "   dropping the unsupported implicit-enum-enum-cast flag from:"
    echo "$WS_HITS" | sed "s|$WS/||" | sed -n '1,10p'
    echo "$WS_HITS" | xargs -r sed -i \
        -e 's/-Werror=implicit-enum-enum-cast//g' \
        -e 's/-Wno-error=implicit-enum-enum-cast//g'
fi

# the build uses the copy from here on
KERNEL_SRC="$WS/kernel-6.6"
echo "   $WS"

# ---------------------------------------------------------------------------
# 3. Configuration
#
# gki_defconfig is the GKI base, mgk_64_k66_defconfig the MT6991 platform
# config and dash.config the dash device config. KCONFIG_EXT_PREFIX pulls the
# device module Kconfig into the kernel so the options of the dash config are
# known.
# ---------------------------------------------------------------------------
step "3/8 config"
cd "$WS"
export ROOT_DIR="$WS"
export KERNEL_DIR="kernel-6.6"
export DEVICE_MODULES_DIR="device-modules"
export DEVCIE_MODULES_INCLUDE="-I\$(DEVICE_MODULES_PATH)/include"

# The kernel descends into the device module Kconfig with KCONFIG_EXT_PREFIX.
# The kernel does source "$(KCONFIG_EXT_PREFIX)Kconfig.ext" and
# include $(srctree)/$(KCONFIG_EXT_PREFIX)Makefile.ext, so the prefix is
# relative to the kernel source directory and has a trailing slash.
export srctree="$KERNEL_SRC"
export DEVICE_MODULES_REL_DIR="$(realpath --relative-to="$KERNEL_SRC" "$WS/$DEVICE_MODULES_DIR")"
export KCONFIG_EXT_PREFIX="$DEVICE_MODULES_REL_DIR/"

set +u
# These two are shell syntax, build.config.mtk.aarch64.mgk is make syntax and
# its variables are set below instead of sourcing it.
. "$KERNEL_SRC/build.config.common"
. "$KERNEL_SRC/build.config.aarch64"
set -u

# The device module Kconfig and include paths.
export DEVICE_MODULES_PATH="$KERNEL_SRC/$DEVICE_MODULES_REL_DIR"
export DEVCIE_MODULES_INCLUDE="-I$DEVICE_MODULES_PATH/include"
export GKI_DEVICE_MODULES_PATH="$DEVICE_MODULES_PATH"
export GKI_DEVCIE_MODULES_INCLUDE="$DEVCIE_MODULES_INCLUDE"

export KCFLAGS EXTRA_CMDS DEPMOD STOP_SHIP_TRACEPRINTK
export KCONFIG_EXT_PREFIX DEVICE_MODULES_REL_DIR

# A caller can leak a warning flag in through KCFLAGS that the pinned clang
# does not know. Drop it here, the build must be reproducible from any shell.
KCFLAGS="${KCFLAGS//-Werror=implicit-enum-enum-cast/}"
KCFLAGS="${KCFLAGS//-Wno-error=implicit-enum-enum-cast/}"

# The module trees build with -Werror. The kernel pins clang r510928, the
# tree ships a newer one which warns about things the older one did not, so
# those warnings are not fatal. The cast between two enumeration types is
# one of them, the camera tree does it.
export KCFLAGS="$KCFLAGS -Wno-error=enum-compare -Wno-error=sometimes-uninitialized"
# -Wimplicit-enum-enum-cast only exists in the newer clang. Probe with
# -Werror so an unknown option fails the probe instead of only warning;
# otherwise the option is added to the real build and fails there.
if "$CLANG_BIN/clang" -Werror -Werror=implicit-enum-enum-cast -x c -c /dev/null -o /dev/null >/dev/null 2>&1; then
    export KCFLAGS="$KCFLAGS -Wno-error=implicit-enum-enum-cast"
fi
echo "   KCFLAGS    : ${KCFLAGS:-<empty>}"

DEFCONFIG="${DEFCONFIG:-gki_defconfig}"
CONFIGS_DIR="$DEVMOD_SRC/kernel/configs"
# the order matters, the dash config is applied last and the config of the
# device tree after it, the framework compatibility matrix is picky
FRAGMENTS=()
for f in mgk_64_k66_defconfig android-recommended.config dash.config; do
    [ -f "$DEVMOD_SRC/arch/arm64/configs/$f" ] && FRAGMENTS+=("$DEVMOD_SRC/arch/arm64/configs/$f")
    [ -f "$CONFIGS_DIR/$f" ] && FRAGMENTS+=("$CONFIGS_DIR/$f")
done
[ ${#FRAGMENTS[@]} -gt 0 ] || die "no config fragments found in $DEVMOD_SRC"

echo "   defconfig : $DEFCONFIG"
for f in "${FRAGMENTS[@]}"; do echo "   fragment  : ${f#$WS/}"; done

MAKE_ARGS="${MAKE_ARGS:-}"
MAKE_ARGS="${MAKE_ARGS//-Werror=implicit-enum-enum-cast/}"
MAKE_ARGS="${MAKE_ARGS//-Wno-error=implicit-enum-enum-cast/}"
KMAKE=(make -C "$KERNEL_SRC" O="$KBUILD_OUT" -j"$JOBS" ARCH=arm64 LLVM=1
       CLANG_TRIPLE=aarch64-linux-gnu-
       CROSS_COMPILE=aarch64-linux-gnu-
       CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
       LD=ld.lld
       KCONFIG_EXT_PREFIX="$KCONFIG_EXT_PREFIX"
       DEVCIE_MODULES_INCLUDE="$DEVCIE_MODULES_INCLUDE")

"${KMAKE[@]}" $MAKE_ARGS "$DEFCONFIG"

for f in "${FRAGMENTS[@]}"; do
    echo "   merging ${f##*/}"
    "$KERNEL_SRC/scripts/kconfig/merge_config.sh" -m -O "$KBUILD_OUT" \
        "$KBUILD_OUT/.config" "$f"
done
"${KMAKE[@]}" $MAKE_ARGS olddefconfig

# The build has no signed modules (the signing key path of the device
# modules is only expanded by kleaf), so the Android GKI symbol protection
# must stay off or the modules fail to load with -EACCES and the display
# never comes up.
if grep -q '^CONFIG_MODULE_SIG_PROTECT=y' "$KBUILD_OUT/.config"; then
    echo "   WARNING: CONFIG_MODULE_SIG_PROTECT is still on, unsigned modules will be rejected"
else
    echo "   module signature protection: off"
fi

# ---------------------------------------------------------------------------
# 4. Build the kernel
# ---------------------------------------------------------------------------
step "4/8 kernel (Image modules)  [-j$JOBS]"
"${KMAKE[@]}" $MAKE_ARGS Image modules

# ---------------------------------------------------------------------------
# 5. Build the out-of-tree modules
#
# ext_modules.list names the module directories. They are listed relative to
# the MTK vendor kernel modules tree, which is the mtk-modules checkout here.
# They have to be built against the same kernel, the kernel checks the
# vermagic and the symbol CRCs of every module it loads.
# ---------------------------------------------------------------------------
step "5/8 out-of-tree modules"
EXT_LIST="$CONFIGS_DIR/ext_modules.list"
[ -f "$EXT_LIST" ] || die "missing $EXT_LIST"

build_ext() {
    local dir="$1"
    local mrel="${2:-}"
    [ -f "$dir/Makefile" ] || return 0
    # The module trees are built the way MTK builds them, their Makefile
    # calls the kernel build itself:
    #
    #   include $(wildcard $(KERNEL_SRC)/$(DEVICE_MODULES_REL_DIR)/Makefile.include)
    #   modules: $(MAKE) -C $(KERNEL_SRC) M=$(M) $(@)
    #
    # so they need KERNEL_SRC and DEVICE_MODULES_REL_DIR, and M has to be
    # relative to the kernel source directory, the module trees add their
    # headers with -I$(srctree)/$(src)/... and an absolute M= would break
    # that. OUT_DIR is where the kernel build writes, the mtk modules link
    # against the symbol list of the device modules with it.
    [ -n "$mrel" ] || mrel="$(realpath --relative-to="$KERNEL_SRC" "$dir" || true)"
    # Not every tree has the same target. Most of them have "modules", some
    # only have "all", the gps power trees, the wlan tree and the camera
    # tree among them. Asking a tree for a target it does not have fails
    # with "No rule to make target 'modules'".
    local goal="all" other
    # The target names of the tree, the ones before the colon of a rule.
    local targets
    targets="$(sed -n 's/^[[:space:]]*\([^:#]*\):.*/\1/p' "$dir/Makefile" | tr ' \t' '\n')"
    if printf '%s\n' "$targets" | grep -qx modules; then
        goal="modules"
    elif [ -z "$targets" ]; then
        # The tree has no rule of its own, it takes them from a makefile it
        # includes, the wifi driver does that.
        goal="modules"
    fi
    # A tree can take its targets from a makefile it includes, the wifi
    # driver does that, so the other target is tried when the tree does not
    # have the one that was picked.
    if [ "$goal" = "modules" ]; then other="all"; else other="modules"; fi
    echo "   -- ${dir#$WS/}  (M=$mrel, goal=$goal)"
    local logf rc attempt=0
    logf="$(mktemp)"
    while :; do
        attempt=$((attempt + 1))
        rc=0
        (
            set +e
            make -C "$dir" \
                KERNEL_SRC="$KERNEL_SRC" \
                M="$mrel" \
                DEVICE_MODULES_REL_DIR="$DEVICE_MODULES_REL_DIR" \
                OUT_DIR="$KBUILD_OUT" \
                O="$KBUILD_OUT" -j"$JOBS" ARCH=arm64 LLVM=1 \
                CLANG_TRIPLE=aarch64-linux-gnu- \
                CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
                LD=ld.lld KCONFIG_EXT_PREFIX="$KCONFIG_EXT_PREFIX" \
                DEVCIE_MODULES_INCLUDE="$DEVCIE_MODULES_INCLUDE" $MAKE_ARGS "$goal" 2>&1 | tee "$logf"
            exit "${PIPESTATUS[0]}"
        ) || rc=$?
        if [ "$rc" -eq 0 ]; then
            break
        fi
        if grep -q "No rule to make target" "$logf" && [ "$goal" != "$other" ]; then
            echo "   the tree has no $goal target, trying $other" >&2
            goal="$other"
            continue
        fi
        # The trees are fixed in the repositories, a failure here is a real
        # one and the log names the line that broke.
        rm -f "$logf"
        return "$rc"
    done
    rm -f "$logf"
}

build_ext "$WS/$DEVICE_MODULES_DIR"

# The out-of-tree module trees come from two places.
#
# The platform trees are listed in the build config of the device modules,
# that is the connectivity, gpu, mtkcam and hbt trees:
#
#   EXT_MODULES+="
#   kernel_device_modules-6.6
#   ../vendor/mediatek/kernel_modules/connectivity/common
#   ...
#
# The customer trees are listed in ext_modules.list:
#
#   ../vendor/mediatek/kernel_modules/fpsgo_cus
#   ...
#
# The paths are relative to the kernel source directory, they are used as they
# are. Without the platform trees the device is missing the wifi, gpu, camera
# and video drivers.
NBUILT=0
FAILED=""
build_tree() {
    local rel="$1"
    [ -n "$rel" ] || return 0
    case "$rel" in
        kernel_device_modules-6.6)
            # the device modules, they are built above
            return 0 ;;
        ../vendor/mediatek/tests/*)
            # the kernel test framework, not part of the device
            return 0 ;;
    esac
    local dir="$KERNEL_SRC/$rel"
    if [ ! -d "$dir" ]; then
        echo "   WARNING: $rel not found (looked for $dir)" >&2
        return 0
    fi
    if ! build_ext "$dir" "$rel"; then
        # A tree that fails does not stop the build, the other trees are
        # independent of it and it is better to know about all of them at once
        # than one per build.
        echo "   FAILED: $rel" >&2
        FAILED="$FAILED $rel"
        return 0
    fi
    NBUILT=$((NBUILT + 1))
}

PLATFORM_MODULES="$DEVMOD_SRC/build.config.mtk_kernel_device_modules"
if [ -f "$PLATFORM_MODULES" ]; then
    while read -r rel; do
        build_tree "$rel"
    done < <(sed -n '/^EXT_MODULES+="/,/^"$/p' "$PLATFORM_MODULES" | \
             grep -v '^EXT_MODULES' | grep -v '^"$' | \
             sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi

while read -r rel; do
    rel="${rel%%#*}"
    rel="$(echo "$rel" | tr -d '[:space:]')"
    build_tree "$rel"
done < "$EXT_LIST"

# The wifi driver is not in the list of the platform. The list names the trees
# of the mediatek modules, the wifi driver is built per chip combo and the
# combo of the dash is 6991_6639_new9gen2, the same one the stock kernel has.
# Without it the device has no wifi.
#
# The list of the device is the one of the kernel build system,
# kernel/kleaf/mgk_64.bzl, it names the module of every chip combo.
build_tree "../vendor/mediatek/kernel_modules/connectivity/wlan/core/gen4m/build/connac3x/6991_6639_new9gen2"
build_tree "../vendor/mediatek/kernel_modules/connectivity/wlan/core/gen4m/build/connac3x/6991_6653"

# The jank detection is in the load list of the vendor_dlkm, it is in the
# customer trees that ext_modules.list does not name.
build_tree "../vendor/mediatek/kernel_modules/afs_common_utils"
build_tree "../vendor/mediatek/kernel_modules/afs_core_cus"
echo "   built $NBUILT module tree(s)"
if [ -n "$FAILED" ]; then
    echo "   these module trees failed:" >&2
    for rel in $FAILED; do
        echo "     $rel" >&2
    done
    die "$(echo "$FAILED" | wc -w) module tree(s) failed"
fi

# ---------------------------------------------------------------------------
# 6. The device tree
#
# The device tree of the dash is an overlay, dash.dts, on top of the mt6991
# base. The kernel tree has no mediatek dts at all, they are in the device
# modules tree, so the dtb is built from there.
#
# The boot image takes the dtb of the directory of the board config and the
# bootloader reads the base and the overlay one after the other, so the two
# are put into one file.
# ---------------------------------------------------------------------------
step "6/8 device tree"
build_dtb() {
    local dts_dir="$DEVMOD_SRC/arch/arm64/boot/dts"
    local out_dir="$1"
    local cpp_inc="-I$dts_dir -I$dts_dir/mediatek -I$DEVMOD_SRC/include -I$KERNEL_SRC/include"
    local cpp_flags="-nostdinc -undef -D__DTS__ -x assembler-with-cpp"
    # The dtc of the kernel build knows the checks of the device tree, the
    # one of the build tools is older and does not know them.
    local dtc_bin="" dtc_flags="-I dts -O dtb -@ -Wno-unit_address_vs_reg"
    if [ -x "$KBUILD_OUT/scripts/dtc/dtc" ]; then
        dtc_bin="$KBUILD_OUT/scripts/dtc/dtc"
    else
        dtc_bin="$(command -v dtc || true)"
    fi
    [ -n "$dtc_bin" ] || die "no dtc found"
    mkdir -p "$out_dir"
    # The boot image takes the base dtb only: the dash board bits are an
    # overlay that the bootloader applies from the dtbo partition, the way
    # the stock image does it. The image build picks the dtb up by the
    # *.dtb glob, so the staged file keeps the tree name.
    if ! cpp $cpp_flags $cpp_inc "$dts_dir/mediatek/mt6991.dts" 2>"$out_dir/cpp-base.log" \
            | "$dtc_bin" $dtc_flags -o "$out_dir/mt6991.dtb" - 2>"$out_dir/dtc-base.log"; then
        echo "   the preprocessor said:" >&2
        head -10 "$out_dir/cpp-base.log" >&2
        echo "   the compiler said:" >&2
        head -10 "$out_dir/dtc-base.log" >&2
        die "the base device tree did not build, see $out_dir/cpp-base.log and $out_dir/dtc-base.log"
    fi
    [ -f "$out_dir/mt6991.dtb" ] || die "no base dtb"
    echo "   mt6991.dtb <- $dts_dir/mediatek/mt6991.dts ($(stat -c %s "$out_dir/mt6991.dtb") bytes)"
}

# The dtb is built from the source like the kernel itself.
DTB_DIR="$WS/dtb"
rm -rf "$DTB_DIR"
build_dtb "$DTB_DIR"

# ---------------------------------------------------------------------------
# 6. Verify before staging
#
# A module built against another kernel is rejected at load time, and a
# missing module silently disappears, so check both here.
# ---------------------------------------------------------------------------
step "7/8 verify"
RELEASE="$(cat "$KBUILD_OUT/include/config/kernel.release" 2>/dev/null || true)"
[ -n "$RELEASE" ] || die "could not read the kernel release string"
echo "   kernel release: $RELEASE"

BADVER=0
while read -r ko; do
    vm="$(strings -a "$ko" 2>/dev/null | grep -m1 '^vermagic=' | cut -d= -f2- || true)"
    case "$vm" in
        "$RELEASE"*) ;;
        *) echo "   WARNING: ${ko##*/} vermagic '${vm:-none}' does not match '$RELEASE'" >&2
           BADVER=$((BADVER + 1)) ;;
    esac
done < <(find "$KBUILD_OUT" "$WS/device-modules" "$WS/vendor/mediatek/kernel_modules" \
              -name '*.ko' -not -path '*/.tmp_*/*' 2>/dev/null)
[ "$BADVER" -eq 0 ] || die "$BADVER module(s) were built against another kernel"
echo "   all modules match the kernel"

# ---------------------------------------------------------------------------
# 7. Stage
# ---------------------------------------------------------------------------
step "8/8 stage into $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/dtb" "$OUT/modules/vendor_dlkm" "$OUT/modules/vendor_ramdisk" "$OUT/modules/system_dlkm"

IMG="$KBUILD_OUT/arch/arm64/boot/Image"
[ -f "$IMG" ] || die "no Image built at $IMG"
if [ -f "$KBUILD_OUT/arch/arm64/boot/Image.lz4" ]; then
    cp -f "$KBUILD_OUT/arch/arm64/boot/Image.lz4" "$OUT/Image.lz4"
else
    lz4 -l -12 -f "$IMG" "$OUT/Image.lz4"
fi
echo "   Image.lz4 <- $IMG"

echo "   collecting uapi headers"
make -C "$KERNEL_SRC" O="$KBUILD_OUT" -j"$JOBS" ARCH=arm64 LLVM=1 \
    CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi- LD=ld.lld \
    KCONFIG_EXT_PREFIX="$KCONFIG_EXT_PREFIX" \
    DEVCIE_MODULES_INCLUDE="$DEVCIE_MODULES_INCLUDE" $MAKE_ARGS \
    headers_install INSTALL_HDR_PATH="$WS/headers" >/dev/null
( cd "$WS/headers" && tar czf "$OUT/kernel-uapi-headers.tar.gz" . )
echo "   kernel-uapi-headers.tar.gz"

# The device tree is built from the source, the boot image takes it from the
# directory of the board config.
cp -f "$DTB_DIR/mt6991.dtb" "$OUT/dtb/mt6991.dtb"
echo "   dtb/ <- mt6991.dtb (built from the source)"

# Partition the modules the same way the device ships them and keep the auto
# load lists of the prebuilt kernel.
#
# The prebuilt kernel has modules that are installed but deliberately not
# auto loaded, 22 in vendor_dlkm and 24 in vendor_ramdisk, test and debug
# drivers like cmdq-test.ko, iommu_test.ko, mtk_et.ko. Writing a modules.load
# with every built module would load them, so the lists of the prebuilt
# kernel are used verbatim instead.
#
# A module of the load list that the kernel does not build is an error, the
# device loads it and without it the ramdisk or the dlkm is missing a driver.
# The modules that the dash config of the device modules turns off are built
# by the config fragment of the device tree, so they are not missing.
echo "   partitioning modules"
declare -A PART
for part in vendor_dlkm vendor_ramdisk system_dlkm; do
    [ -d "$PREBUILT/modules/$part" ] || continue
    for ko in "$PREBUILT/modules/$part"/*.ko; do
        [ -e "$ko" ] || continue
        name="$(basename "$ko")"
        # A module can be in more than one partition, the stock kernel has
        # the mbox driver in the vendor_dlkm and in the vendor_ramdisk.
        # Keep every partition it is in, the load list of a partition names
        # the modules it loads.
        PART["$name"]="${PART[$name]:-} $part"
    done
done

# The ramdisk loads the swap, the ramdisk list of the device tree names
# zram.ko and zsmalloc.ko, so every module of that list is staged into the
# ramdisk no matter which partition owns it in the stock layout.
while read -r m; do
    [ -n "$m" ] || continue
    case " ${PART[$m]:-} " in
        *" vendor_ramdisk "*) ;;
        *) PART[$m]="${PART[$m]:-} vendor_ramdisk" ;;
    esac
done < "$DEVICE_DIR/kernel/modules.load.platform"

# The deployment list of the device tree (kernel/modules.mk) adds modules
# the stock kernel does not ship, profiling and extra charger and
# wifi-variant drivers. Stage them into the partition the list names.
while read -r part name; do
    PART["$name"]="${PART[$name]:-} $part"
done < <(sed -n 's|.*modules/\([a-z_]*\)/\([A-Za-z0-9_.+-]*\)\.ko.*|\1 \2|p' \
             "$DEVICE_DIR/kernel/modules.mk" | sort -u)

MODCOUNT=0
while read -r ko; do
    name="$(basename "$ko")"
    for part in ${PART[$name]:-}; do
        [ -n "$part" ] || continue
        cp -f "$ko" "$OUT/modules/$part/"
    done
    MODCOUNT=$((MODCOUNT + 1))
done < <(find "$KBUILD_OUT" "$WS/device-modules" "$WS/vendor/mediatek/kernel_modules" \
              -name '*.ko' -not -path '*/.tmp_*/*' 2>/dev/null)

MISSING=""
for part in vendor_dlkm vendor_ramdisk system_dlkm; do
    dir="$OUT/modules/$part"
    src="$PREBUILT/modules/$part"
    [ -d "$src" ] || continue
    # The load lists of the other dash port, the one that boots. Its list of
    # the ramdisk has zram.ko and zsmalloc.ko, the stock list does not load
    # them, and its list of the vendor_dlkm has dio_dma_mapper.ko, the stock
    # list does not have it either.
    case "$part" in
        vendor_ramdisk) LIST="$DEVICE_DIR/kernel/modules.load.platform" ;;
        vendor_dlkm)    LIST="$DEVICE_DIR/kernel/modules.load.vendor_dlkm" ;;
        system_dlkm)    LIST="$DEVICE_DIR/kernel/modules.load.system" ;;
        *)              LIST="" ;;
    esac
    for f in modules.load modules.load.recovery modules.blocklist; do
        if [ -n "$LIST" ] && [ "$f" = "modules.load" ]; then
            [ -f "$LIST" ] || continue
        else
            [ -f "$src/$f" ] || continue
        fi
        : > "$dir/$f"
        while read -r m; do
            [ -n "$m" ] || continue
            if [ -f "$dir/$m" ]; then
                echo "$m" >> "$dir/$f"
            else
                # The device loads this module, it is not optional. A module
                # that is missing from the build leaves the ramdisk or the
                # dlkm without a driver, and that shows up as a device that
                # boots to a white screen.
                MISSING="$MISSING $part/$m"
            fi
        done < "$( [ -n "$LIST" ] && [ "$f" = "modules.load" ] && echo "$LIST" || echo "$src/$f" )"
    done
    echo "   $part: $(find "$dir" -maxdepth 1 -name '*.ko' | wc -l) module(s), $(wc -l < "$dir/modules.load" 2>/dev/null || echo 0) auto loaded"
done
echo "   staged $MODCOUNT module(s) total"

if [ -n "$MISSING" ]; then
    echo >&2
    echo "ERROR: the kernel does not build the modules the device needs:" >&2
    for m in $MISSING; do
        echo "  $m" >&2
    done
    echo >&2
    echo "The device loads them, without them it boots to a white screen." >&2
    echo "Either enable them in the kernel config, or add them to the list of" >&2
    echo "modules that dash.config disables." >&2
    exit 1
fi

echo
echo "Done. Kernel staged in $OUT"
echo "Now build the ROM:  brunch dash"
