#!/bin/bash
# build-gts9uwifi.sh - end-to-end Ubuntu Touch build for Tab S9 Ultra (SM-X910)
#
# Inputs (all produced in prior sessions):
#   SRC_PARTS - path to out-x910/parts/      (x910-extract.sh output:
#               vendor.img odm.img product.img system_ext.img
#               system_dlkm.img vendor_dlkm.img)   [legacy name PARTS accepted]
#   SKEL      - path to samsung-gts9u/       (gts9uwifi-skeleton.tar.gz)
#   IMPORTS   - path to gts9u-imports/       (gts9u-imports.tar.gz)
#
# Host needs: git curl wget zstd lz4 xxd bc bison flex libssl-dev libelf-dev
#             erofs-utils attr rsync python3 zip file dwarves(pahole)
#             android-sdk tools NOT required.
#             ~50 GB free disk, real cores (kernel + 10 techpacks).
#
# Usage:
#   SKEL=~/samsung-gts9u IMPORTS=~/gts9u-imports SRC_PARTS=~/out-x910/parts \
#     ./build-gts9uwifi.sh
set -euo pipefail

# --- 0. dependency preflight (fail fast - a kernel build is hours; nothing
#        should bail mid-run on a missing tool) --------------------------------
#     zip: consumed by scripts/make-flashable.sh (the very last step)
#     file: consumed by the lpmake arch detection below
#     pahole: required by the kernel link when CONFIG_DEBUG_INFO_BTF=y
#             (kalama-gki base enables it) - cheap to require unconditionally
#     perl: kernel build scripts
missing=""
for t in git curl wget tar xz zstd lz4 xxd bc bison flex make gcc python3 \
         rsync cpio getfattr setfattr mkfs.erofs fsck.erofs \
         img2simg simg2img dtc fakeroot zip file pahole perl; do
    command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
hdrs=""
[ -e /usr/include/openssl/ssl.h ] || hdrs="$hdrs libssl-dev"
[ -e /usr/include/gelf.h ] || hdrs="$hdrs libelf-dev"
if [ -n "$missing$hdrs" ]; then
    echo "missing prerequisites:$missing$hdrs" >&2
    echo "  sudo apt install$missing$hdrs" >&2
    echo "  (getfattr/setfattr = attr; mkfs.erofs/fsck.erofs = erofs-utils;" >&2
    echo "   img2simg/simg2img = android-sdk-libsparse-utils; dtc = device-tree-compiler;" >&2
    echo "   pahole = dwarves)" >&2
    exit 1
fi
echo "[gts9u-build] note: the rootfs stage invokes sudo (system-image assembly) - it will prompt" >&2

SKEL="${SKEL:?path to samsung-gts9u skeleton}"
IMPORTS="${IMPORTS:?path to gts9u-imports bundle}"
SRC_PARTS="${SRC_PARTS:-${PARTS:-}}"
[ -n "$SRC_PARTS" ] || { echo "SRC_PARTS (or legacy PARTS) required: path to out-x910/parts" >&2; exit 1; }
WORK="${WORK:-$PWD/gts9u-build}"
J="${J:-$(nproc)}"

log() { echo "[gts9u-build] $*" >&2; }

for f in vendor.img odm.img product.img system_ext.img system_dlkm.img vendor_dlkm.img; do
    [ -f "$SRC_PARTS/$f" ] || { echo "missing $SRC_PARTS/$f" >&2; exit 1; }
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

# sanity: audio bring-up chain shipped in overlay (first-sound session, 2026-08-08)
#         gts9u-audio-bringup completes modules.load (storm belt), gates PA via
#         /run/gts9u-audio-ready; virtual h2w satisfies droid-extevdev's jack scan;
#         swap script dedupes the quadruplicated modules.load at repack.
AO=overlay/system
if [ ! -x "$AO/usr/local/sbin/gts9u-audio-bringup" ]; then
    echo "[gts9u-build] FATAL: audio bring-up files missing from staged skeleton." >&2
    echo "  Your workdir has a pre-audio samsung-gts9u/ (staging is skipped when the" >&2
    echo "  dir exists). Remove it and rerun so the updated SKEL is staged:" >&2
    echo "    rm -rf $WORK/samsung-gts9u" >&2
    exit 1
fi
[ -f "$AO/usr/local/lib/gts9u-virtual-h2w.py" ]
[ -L "$AO/etc/systemd/system/multi-user.target.wants/gts9u-audio-bringup.service" ]
[ -L "$AO/etc/systemd/system/multi-user.target.wants/gts9u-virtual-h2w.service" ]
grep -q gts9u-audio-ready "$AO/etc/systemd/user/pulseaudio.service.d/zz-gts9u-audio.conf"
[ ! -e "$AO/etc/systemd/user/pulseaudio.service.d/50-gts9uwifi-wait-audiohal.conf" ]
grep -q 'seen\[\$0\]' scripts/swap-vendor-modules.sh
grep -q 'LEFTOVER' scripts/swap-vendor-modules.sh   # merged v3: dedupe AND audit
[ -f "$AO/etc/libinput/local-overrides.quirks" ]
[ -f "$AO/etc/udev/rules.d/61-gts9u-pen.rules" ]
grep -q "finit stage" "$AO/usr/local/sbin/gts9u-audio-bringup"
# parity-remediation additions (2026-08-30): WiFi persistence, touchpad
# rotation, and the sed-safe flasher device check must be in the staged tree.
grep -q 'qca_cld3_kiwi_v2' "$AO/etc/modules-load.d/gts9uwifi.conf"
[ -L "$AO/etc/systemd/system/multi-user.target.wants/gts9u-tp-rotate.service" ]
grep -q 'MODEL_WIFI="x910"' flashable/META-INF/com/google/android/update-binary
log "hardware overlay verified (audio + finit stage + pen reclass + dedupe + wifi + tp-rotate)"

# 3. stage the X910 firmware bundle where build.sh expects it ----------------
#    skeleton build.sh does: [ -f $(basename $FIRMWARE) ] || wget $FIRMWARE
#    then: tar xf $(basename $FIRMWARE) -C partitions
FWTAR="ubuntu-touch-kalama-firmware-x910.tar.xz"
export FIRMWARE="https://localhost/$FWTAR"     # basename match skips the wget
if [ ! -f "$FWTAR" ]; then
    log "packing $FWTAR from $SRC_PARTS (a few minutes)"
    rm -f "$FWTAR.tmp"
    tar cJf "$FWTAR.tmp" -C "$SRC_PARTS" \
        vendor.img odm.img product.img system_ext.img system_dlkm.img vendor_dlkm.img
    mv "$FWTAR.tmp" "$FWTAR"   # atomic: an interrupted pack can't pass the -f check on rerun
fi

# 4. full build: kernel + techpacks + boot images + rootfs + recovery --------
#    (wez01.ko and goodix_ts_berlin.ko compile pre-validated against this
#     tree; first full-link watchpoint is msm_drm with the GTS9U panel.)
./build.sh

# 5. vendor module swap against the X910 vendor_dlkm -------------------------
#    build.sh already extracted the firmware tar into partitions/ and ran the
#    merged swap-vendor-modules.sh v3: modules.load dedupe (audio bug #1) PLUS
#    the LEFTOVER/UNLANDED audit. With no scripts/swap-allowlist.txt the audit
#    is REPORT-ONLY - read its LEFTOVER list in the build log; to enforce,
#    copy swap-allowlist.txt.template to swap-allowlist.txt and triage.
#    Verify the two imported modules were built: touch OR pen missing = FATAL
#    (both are core hardware on this device and both are proven to compile).
missing_core=0
for m in wez01.ko goodix_ts_berlin.ko; do
    found=$(find workdir/tmp/system -name "$m" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        log "built: $m -> $found"
    else
        echo "[gts9u-build] FATAL: $m not in built module set" >&2
        echo "  (goodix = no touch, wez01 = no pen; check the input wiring" >&2
        echo "   imports before flashing anything)" >&2
        missing_core=1
    fi
done
[ "$missing_core" -eq 0 ] || exit 1

# 6. super + flashable zip ---------------------------------------------------
#    SUPER exported explicitly (X910 GTS9UWIFI_EUR_OPEN.pit) so super.sh can
#    never fall back to a wrong geometry if the skeleton default is ever
#    edited or the skeleton is forked (the V4/gts9p defense-in-depth pattern,
#    backported). super.sh v3 sets the LP group ceiling to super capacity, so
#    the on-device root-grow headroom survives rebuilds; the root size itself
#    comes from deviceinfo_system_partition_size (7600M).
#    scripts/prebuilt/lpmake is aarch64 - locate a host-runnable lpmake
#    first. A preset LPMAKE env is respected as-is.
export SUPER=11744051200
if [ -n "${LPMAKE:-}" ]; then
    log "using preset LPMAKE: $LPMAKE"
elif ! command -v lpmake >/dev/null 2>&1; then
    HOSTARCH=$(uname -m | tr _ -)   # x86_64 -> x86-64, matching file(1) wording
    LPMAKE=""
    while IFS= read -r -d '' cand; do
        # arch filter first: candidates are ELFs from the fetched build tools;
        # anything not matching the host arch (e.g. the aarch64 prebuilt)
        # can never run here.
        case "$(file -b "$cand")" in
            *"$HOSTARCH"*) ;;
            *) continue ;;
        esac
        # exec probe: 126 = wrong format / not executable, 127 = not found.
        # lpmake with no args exits nonzero after printing usage - that's fine.
        rc=0; "$cand" >/dev/null 2>&1 || rc=$?
        if [ "$rc" -ne 126 ] && [ "$rc" -ne 127 ]; then
            LPMAKE="$cand"
            break
        fi
    done < <(find workdir -name lpmake -type f -print0 2>/dev/null)
    if [ -z "$LPMAKE" ]; then
        echo "no host-runnable lpmake found (skeleton prebuilt is aarch64);" >&2
        echo "  install one on PATH or export LPMAKE=/path/to/x86_64/lpmake" >&2
        exit 1
    fi
    export LPMAKE
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
