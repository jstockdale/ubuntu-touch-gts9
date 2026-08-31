#!/bin/bash
# build-gts9uwifi.sh - end-to-end Ubuntu Touch build for Tab S9 Ultra (SM-X910)
#
# Inputs (all produced in prior sessions):
#   SKEL    - path to samsung-gts9u/          (gts9uwifi-skeleton.tar.gz)
#   IMPORTS - path to gts9u-imports/          (gts9u-imports.tar.gz)
#   PARTS   - path to out-x910/parts/         (x910-extract.sh output:
#             vendor.img odm.img product.img system_ext.img
#             system_dlkm.img vendor_dlkm.img)
#
# Host needs: git curl wget zstd lz4 xxd bc bison flex libssl-dev libelf-dev
#             erofs-utils attr rsync python3 android-sdk tools NOT required.
#             ~50 GB free disk, real cores (kernel + 10 techpacks).
#
# Usage:
#   SKEL=~/samsung-gts9u IMPORTS=~/gts9u-imports PARTS=~/out-x910/parts \
#     ./build-gts9uwifi.sh
set -euo pipefail

# --- 0. dependency preflight (fail fast - a kernel build is hours; nothing
#        should bail mid-run on a missing tool) --------------------------------
missing=""
for t in git curl wget tar xz zstd lz4 xxd bc bison flex make gcc python3 \
         rsync cpio getfattr setfattr mkfs.erofs fsck.erofs \
         img2simg simg2img dtc fakeroot; do
    command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
hdrs=""
[ -e /usr/include/openssl/ssl.h ] || hdrs="$hdrs libssl-dev"
[ -e /usr/include/gelf.h ] || hdrs="$hdrs libelf-dev"
if [ -n "$missing$hdrs" ]; then
    echo "missing prerequisites:$missing$hdrs" >&2
    echo "  sudo apt install$missing$hdrs" >&2
    echo "  (getfattr/setfattr = attr; mkfs.erofs/fsck.erofs = erofs-utils;" >&2
    echo "   img2simg/simg2img = android-sdk-libsparse-utils; dtc = device-tree-compiler)" >&2
    exit 1
fi
echo "[gts9u-build] note: the rootfs stage invokes sudo (system-image assembly) - it will prompt" >&2

SKEL="${SKEL:?path to samsung-gts9u skeleton}"
IMPORTS="${IMPORTS:?path to gts9u-imports bundle}"
PARTS="${PARTS:?path to out-x910/parts}"
WORK="${WORK:-$PWD/gts9u-build}"
J="${J:-$(nproc)}"

log() { echo "[gts9u-build] $*" >&2; }

for f in vendor.img odm.img product.img system_ext.img system_dlkm.img vendor_dlkm.img; do
    [ -f "$PARTS/$f" ] || { echo "missing $PARTS/$f"; exit 1; }
done

mkdir -p "$WORK"
cd "$WORK"

# 1. device repo -------------------------------------------------------------
if [ ! -d samsung-gts9u ]; then
    cp -r "$SKEL" samsung-gts9u
    log "device repo staged"
fi
cd samsung-gts9u

# 2. pre-clone kernel + display-drivers and apply the gts9u imports ----------
#    build.sh / setup skip cloning when the target dir already exists, so we
#    populate them first and overlay the bundle on top.
KDIR="workdir/downloads/kernel-samsung-gts9wifi"
if [ ! -d "$KDIR" ]; then
    git clone --depth 1 -b android13-5.15-halium \
        https://gitlab.com/azkali-samsung/gts9/ubports/kernel-samsung-gts9wifi.git "$KDIR"
fi
# OSRC-derived files ship mode 0444; make any prior copies writable, then
# force-copy so reruns are always clean.
[ -d "$KDIR/drivers/input/touchscreen/goodix" ] && chmod -R u+w "$KDIR/drivers/input/touchscreen/goodix"
cp -rf "$IMPORTS/kernel-samsung-gts9wifi/." "$KDIR/"
chmod -R u+w "$KDIR/drivers/input/touchscreen/goodix" "$KDIR/arch/arm64/boot/dts/samsung/galaxytab/gts9uwifi"
log "kernel imports applied (goodix/berlin, wacom wiring, gts9uwifi dts)"
# append the config fragment exactly once
grep -q TOUCHSCREEN_GOODIX_BRL "$KDIR/arch/arm64/configs/halium.config" || \
    cat "$IMPORTS/kernel-samsung-gts9wifi/arch/arm64/configs/halium.config.gts9u-append" \
        >> "$KDIR/arch/arm64/configs/halium.config"
# CONFIG_CMDLINE in halium.config hardcodes the 11" panel selection (and
# CONFIG_CMDLINE_FORCE makes it authoritative) - retarget to the Ultra panel
# and drop the 11"-specific lcd_id args (ss_dsi reads the DDIC at init).
sed -i 's|msm_drm.dsi_display0=GTS9_ANA38407_AMSA10FA01: msm_drm.lcd_id=800004 sec_common_fn.lcd_id=800004|msm_drm.dsi_display0=GTS9U_ANA38407_AMSA46AS02:|' \
    "$KDIR/arch/arm64/configs/halium.config"
grep -q "dsi_display0=GTS9U_ANA38407_AMSA46AS02" "$KDIR/arch/arm64/configs/halium.config"
log "kernel cmdline retargeted to GTS9U panel"

DDIR="workdir/downloads/vendor/qcom/opensource/display-drivers"
if [ ! -d "$DDIR" ]; then
    mkdir -p "$(dirname "$DDIR")"
    git clone --depth 1 -b android13-5.15-halium \
        https://gitlab.com/azkali-samsung/gts9/ubports/display-drivers.git "$DDIR"
fi
[ -d "$DDIR/msm/samsung/GTS9U_ANA38407_AMSA46AS02" ] && chmod -R u+w "$DDIR/msm/samsung/GTS9U_ANA38407_AMSA46AS02"
[ -f "$DDIR/msm/samsung/panel_data_file/GTS9U_ANA38407_AMSA46AS02.dat" ] && chmod u+w "$DDIR/msm/samsung/panel_data_file/GTS9U_ANA38407_AMSA46AS02.dat"
cp -rf "$IMPORTS/display-drivers/." "$DDIR/"
chmod -R u+w "$DDIR/msm/samsung/GTS9U_ANA38407_AMSA46AS02" "$DDIR/msm/samsung/panel_data_file/GTS9U_ANA38407_AMSA46AS02.dat"
log "display imports applied (GTS9U panel + merged Kbuild)"

# 2b. wlan: kiwi_v2 profile enables IPA offload (CONFIG_IPA_OPT_WIFI_DP),
#     which requires the dataipa tree - absent from the halium build. IPA is
#     de-facto disabled on the working gts9wifi port too (stock ipam.ko cannot
#     load against the halium kernel), so force it off for kiwi as well.
WDIR="workdir/downloads/vendor/qcom/opensource/wlan"
if [ ! -d "$WDIR" ]; then
    mkdir -p "$(dirname "$WDIR")"
    git clone --depth 1 -b android13-5.15-halium \
        https://gitlab.com/azkali-samsung/gts9/ubports/wlan.git "$WDIR"
fi
KIWICFG="$WDIR/qcacld-3.0/configs/kiwi_v2_defconfig"
if ! grep -q "halium: no dataipa" "$KIWICFG"; then
    cat >> "$KIWICFG" <<'KEOF'

# halium: no dataipa tree in this build; IPA offload is de-facto disabled on
# the working gts9wifi port too (stock ipam.ko can't load). Software datapath.
CONFIG_IPA_OPT_WIFI_DP := n
CONFIG_IPA_OFFLOAD := n
KEOF
fi
grep -q "CONFIG_IPA_OPT_WIFI_DP := n" "$KIWICFG"
log "kiwi_v2 IPA offload disabled (software datapath)"

# sanity: symbols reachable
grep -q 'source "drivers/input/wacom/Kconfig"' "$KDIR/drivers/input/Kconfig"
grep -q 'goodix/berlin' "$KDIR/drivers/input/touchscreen/Makefile"
grep -q 'GTS9U_ANA38407_AMSA46AS02' "$DDIR/msm/Kbuild"

# 3. stage the X910 firmware bundle where build.sh expects it ----------------
#    skeleton build.sh does: [ -f $(basename $FIRMWARE) ] || wget $FIRMWARE
#    then: tar xf $(basename $FIRMWARE) -C partitions
FWTAR="ubuntu-touch-kalama-firmware-x910.tar.xz"
export FIRMWARE="https://localhost/$FWTAR"     # basename match skips the wget
if [ ! -f "$FWTAR" ]; then
    log "packing $FWTAR from $PARTS (a few minutes)"
    tar cJf "$FWTAR" -C "$PARTS" \
        vendor.img odm.img product.img system_ext.img system_dlkm.img vendor_dlkm.img
fi

# 4. full build: kernel + techpacks + boot images + rootfs + recovery --------
#    (wez01.ko and goodix_ts_berlin.ko compile pre-validated against this
#     tree; first full-link watchpoint is msm_drm with the GTS9U panel.)
./build.sh

# 5. vendor module swap against the X910 vendor_dlkm -------------------------
#    build.sh already extracted the firmware tar into partitions/ and ran
#    swap-vendor-modules.sh; verify the two new modules made it.
for m in wez01.ko goodix_ts_berlin.ko; do
    found=$(find workdir/tmp/system -name "$m" 2>/dev/null | head -1)
    [ -n "$found" ] && log "built: $m -> $found" || log "WARNING: $m not in module set - check wiring"
done

# 6. super + flashable zip ---------------------------------------------------
#    skeleton super.sh defaults SUPER=11744051200 (X910 PIT-verified).
#    scripts/prebuilt/lpmake is aarch64 - locate a host-runnable lpmake first
#    (the fetched android build-tools bundle usually carries one).
if ! command -v lpmake >/dev/null 2>&1; then
    for cand in $(find workdir -name lpmake -type f 2>/dev/null); do
        if "$cand" --help >/dev/null 2>&1 || [ "$("$cand" 2>&1 | head -c 5)" != "" ]; then
            case "$(file -b "$cand")" in *aarch64*) continue;; esac
            export LPMAKE="$cand"; break
        fi
    done
    [ -n "${LPMAKE:-}" ] || { echo "no host-runnable lpmake found (prebuilt is aarch64);" >&2
        echo "  install one on PATH or export LPMAKE=/path/to/x86_64/lpmake" >&2; exit 1; }
    log "using lpmake: $LPMAKE"
fi
PARTS=./partitions OUT=out/super.img ./scripts/super.sh
ZIP=out/ubuntu-touch-gts9uwifi-24.04-2.x.zip ./scripts/make-flashable.sh

log "done."
log "flash (TWRP, pre-fuse-bit-6 unit, FULL backup incl. EFS first):"
log "  adb push $(realpath out/ubuntu-touch-gts9uwifi-24.04-2.x.zip) /data/"
log "  TWRP Install -> /data -> zip   (leaves stock dtbo in place - correct)"
log "  adb shell twrp reboot system"
log "first contact is USB rndis/ssh into the halium initrd; then the ladder:"
log "  display -> touch (goodix) -> wifi (kiwi_v2) -> audio -> evtest pen (wez01)"
