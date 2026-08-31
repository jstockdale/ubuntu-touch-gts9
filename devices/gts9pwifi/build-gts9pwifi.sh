#!/bin/bash
# Copyright (c) 2026 John Stockdale and Off by One, Inc.
# BSD 3-Clause License - see LICENSE at the repository root.
# build-gts9pwifi.sh - end-to-end Ubuntu Touch build for Tab S9+ (SM-X810)
# Forked from build-gts9uwifi.sh; family split notes:
#   touch  : STM FTS1BA90A (stm_ts_fts1b90a.ko) - in azkali tree already, NOT
#            goodix berlin (that's Ultra-only). No touch driver import needed.
#   pen    : wacom wez01 - driver SOURCE in azkali tree already, but the
#            drivers/input/{Kconfig,Makefile} WIRING is not (Samsung's LEGO
#            build injects it upstream); gts9p-imports carries the merged
#            wacom-only pair (2026-08-30) and this script gates on it.
#   panel  : GTS9P_ANA38407_AMSA24VU05 via gts9p-imports (dir + .dat + merged
#            Kbuild whose .conf include exports the CONFIG_PANEL_* symbol).
#   cmdline: bare panel string, lcd_id args dropped (GTS9P panel.c self-IDs
#            via DDIC A1h reads; verify against stock /proc/cmdline once).
#   SUPER  : 11714691072 (X810 PIT GTS9PWIFI_EUR_OPEN.pit, 2860032 blk * 4096)
#            - 28 MiB SMALLER than the X910 skeleton default. Exported below.
#
# Inputs (all produced in prior sessions):
#   SRC_PARTS - path to out-x810/parts/      (x810-extract.sh output:
#               vendor.img odm.img product.img system_ext.img
#               system_dlkm.img vendor_dlkm.img)   [legacy name PARTS accepted]
#   SKEL      - path to samsung-gts9p/       (fork of gts9uwifi skeleton per
#               the runbook Phase 1 recipe: content seds + uppercase/identity
#               pass + file renames - audio bringup, virtual-h2w, tp-rotate,
#               their three systemd units + wants symlinks, PA drop-in, pen
#               rule -> gts9p equivalents)
#   IMPORTS   - path to gts9p-imports/       (gts9p-imports.tar.gz)
#
# Host needs: git curl wget zstd lz4 xxd bc bison flex libssl-dev libelf-dev
#             erofs-utils attr rsync python3 zip file dwarves(pahole)
#             android-sdk tools NOT required.
#             ~50 GB free disk, real cores (kernel + 10 techpacks).
#
# Usage:
#   SKEL=~/samsung-gts9p IMPORTS=~/gts9p-imports SRC_PARTS=~/out-x810/parts \
#     ./build-gts9pwifi.sh
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
echo "[gts9p-build] note: the rootfs stage invokes sudo (system-image assembly) - it will prompt" >&2

SKEL="${SKEL:?path to samsung-gts9p skeleton}"
IMPORTS="${IMPORTS:?path to gts9p-imports bundle}"
SRC_PARTS="${SRC_PARTS:-${PARTS:-}}"
[ -n "$SRC_PARTS" ] || { echo "SRC_PARTS (or legacy PARTS) required: path to out-x810/parts" >&2; exit 1; }
WORK="${WORK:-$PWD/gts9p-build}"
J="${J:-$(nproc)}"

log() { echo "[gts9p-build] $*" >&2; }

for f in vendor.img odm.img product.img system_ext.img system_dlkm.img vendor_dlkm.img; do
    [ -f "$SRC_PARTS/$f" ] || { echo "missing $SRC_PARTS/$f" >&2; exit 1; }
done

mkdir -p "$WORK"
cd "$WORK"

# 1. device repo -------------------------------------------------------------
if [ ! -d samsung-gts9p ]; then
    cp -r "$SKEL" samsung-gts9p
    log "device repo staged"
fi
cd samsung-gts9p

# 2. pre-clone kernel + display-drivers and apply the gts9p imports ----------
#    build.sh / setup skip cloning when the target dir already exists, so we
#    populate them first and overlay the bundle on top.
#    Unlike the Ultra: NO goodix import (gts9p touch = stm fts1ba90a, already
#    in-tree and proven on the base-S9 port). Kernel-side imports are the
#    gts9pwifi dts dir PLUS the merged drivers/input/{Kconfig,Makefile}
#    (wacom wiring - the wez01 SOURCE is in-tree but its wiring is not).
KDIR="workdir/downloads/kernel-samsung-gts9wifi"
if [ ! -d "$KDIR" ]; then
    git clone --depth 1 -b android13-5.15-halium \
        https://gitlab.com/azkali-samsung/gts9/ubports/kernel-samsung-gts9wifi.git "$KDIR"
fi
# OSRC-derived files ship mode 0444; make any prior copies writable, then
# force-copy so reruns are always clean.
[ -d "$KDIR/arch/arm64/boot/dts/samsung/galaxytab/gts9pwifi" ] && \
    chmod -R u+w "$KDIR/arch/arm64/boot/dts/samsung/galaxytab/gts9pwifi"
cp -rf "$IMPORTS/kernel-samsung-gts9wifi/." "$KDIR/"
chmod -R u+w "$KDIR/arch/arm64/boot/dts/samsung/galaxytab/gts9pwifi"
log "kernel imports applied (gts9pwifi dts r00/r02/r04 + wacom input wiring)"
# CONFIG_CMDLINE in halium.config hardcodes the 11" panel selection (and
# CONFIG_CMDLINE_FORCE makes it authoritative) - retarget to the S9+ panel.
# lcd_id args dropped: GTS9P panel.c reads the DDIC (manufacture_id, A1h) at
# init and even branches on 0x800004/0x800005 internally - attachment does not
# gate on cmdline lcd_id. Cross-check once against stock /proc/cmdline.
sed -i 's|msm_drm.dsi_display0=GTS9_ANA38407_AMSA10FA01: msm_drm.lcd_id=800004 sec_common_fn.lcd_id=800004|msm_drm.dsi_display0=GTS9P_ANA38407_AMSA24VU05:|' \
    "$KDIR/arch/arm64/configs/halium.config"
grep -q "dsi_display0=GTS9P_ANA38407_AMSA24VU05" "$KDIR/arch/arm64/configs/halium.config"
log "kernel cmdline retargeted to GTS9P panel"

DDIR="workdir/downloads/vendor/qcom/opensource/display-drivers"
if [ ! -d "$DDIR" ]; then
    mkdir -p "$(dirname "$DDIR")"
    git clone --depth 1 -b android13-5.15-halium \
        https://gitlab.com/azkali-samsung/gts9/ubports/display-drivers.git "$DDIR"
fi
[ -d "$DDIR/msm/samsung/GTS9P_ANA38407_AMSA24VU05" ] && chmod -R u+w "$DDIR/msm/samsung/GTS9P_ANA38407_AMSA24VU05"
[ -f "$DDIR/msm/samsung/panel_data_file/GTS9P_ANA38407_AMSA24VU05.dat" ] && chmod u+w "$DDIR/msm/samsung/panel_data_file/GTS9P_ANA38407_AMSA24VU05.dat"
cp -rf "$IMPORTS/display-drivers/." "$DDIR/"
chmod -R u+w "$DDIR/msm/samsung/GTS9P_ANA38407_AMSA24VU05" "$DDIR/msm/samsung/panel_data_file/GTS9P_ANA38407_AMSA24VU05.dat"
log "display imports applied (GTS9P panel + AWH8 panel.c/h + merged Kbuild)"

# 2b. wlan: kiwi_v2 profile enables IPA offload (CONFIG_IPA_OPT_WIFI_DP),
#     which requires the dataipa tree - absent from the halium build. IPA is
#     de-facto disabled on the working gts9wifi port too (stock ipam.ko cannot
#     load against the halium kernel), so force it off for kiwi as well.
#     (The dts cnss node says qcom,cnss-qca6490 on gts9p AND gts9wifi - legacy
#     node naming, not chip identity; both are WCN7850/kiwi. Base port proves it.)
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

# sanity: touch + pen enabled in the tree we just cloned (in-tree, no import)
grep -q 'CONFIG_TOUCHSCREEN_STM_FTS1BA90A=m' "$KDIR/arch/arm64/configs/vendor/kalama-gki_defconfig"
grep -q 'CONFIG_EPEN_WACOM_WEZ01=m' "$KDIR/arch/arm64/configs/vendor/kalama-gki_defconfig"
[ -d "$KDIR/drivers/input/touchscreen/stm/fts1ba90a" ]
[ -d "$KDIR/drivers/input/wacom" ]
# sanity: wacom KERNEL WIRING landed (the armed defconfig symbol sat inert
# without it - Samsung's LEGO build injects it at build time upstream; our
# imports now carry the merged drivers/input/{Kconfig,Makefile}, wacom-only,
# no goodix references). Without this, wez01.ko silently never builds.
grep -q 'source "drivers/input/wacom/Kconfig"' "$KDIR/drivers/input/Kconfig"
grep -q 'CONFIG_EPEN_WACOM_WEZ01.*wacom/' "$KDIR/drivers/input/Makefile"
# sanity: panel wired through the merged Kbuild + dts present
grep -q 'GTS9P_ANA38407_AMSA24VU05' "$DDIR/msm/Kbuild"
[ -f "$KDIR/arch/arm64/boot/dts/samsung/galaxytab/gts9pwifi/gts9pwifi_eur_open_w00_r04.dts" ]

# sanity: audio bring-up chain shipped in overlay (ported from the gts9u
#         first-sound session, 2026-08-08; skeleton fork renames gts9u->gts9p).
#         gts9p-audio-bringup completes modules.load (storm belt), gates PA via
#         /run/gts9p-audio-ready; virtual h2w satisfies droid-extevdev's jack
#         scan; swap script dedupes the quadruplicated modules.load at repack.
AO=overlay/system
if [ ! -x "$AO/usr/local/sbin/gts9p-audio-bringup" ]; then
    echo "[gts9p-build] FATAL: audio bring-up files missing from staged skeleton." >&2
    echo "  Your workdir has a pre-audio samsung-gts9p/ (staging is skipped when the" >&2
    echo "  dir exists), or the skeleton fork missed the gts9u->gts9p rename." >&2
    echo "  Remove it and rerun so the updated SKEL is staged:" >&2
    echo "    rm -rf $WORK/samsung-gts9p" >&2
    exit 1
fi
[ -f "$AO/usr/local/lib/gts9p-virtual-h2w.py" ]
[ -L "$AO/etc/systemd/system/multi-user.target.wants/gts9p-audio-bringup.service" ]
[ -L "$AO/etc/systemd/system/multi-user.target.wants/gts9p-virtual-h2w.service" ]
grep -q gts9p-audio-ready "$AO/etc/systemd/user/pulseaudio.service.d/zz-gts9p-audio.conf"
# stale superseded PA drop-in must NOT exist (the fork sed would happily
# rename an old 50-gts9uwifi-wait-audiohal.conf right past us - restored
# negative gate, V3 parity)
[ ! -e "$AO/etc/systemd/user/pulseaudio.service.d/50-gts9pwifi-wait-audiohal.conf" ]
grep -q 'seen\[\$0\]' scripts/swap-vendor-modules.sh
grep -q 'LEFTOVER' scripts/swap-vendor-modules.sh   # merged v3: dedupe AND audit
[ -f "$AO/etc/libinput/local-overrides.quirks" ]
[ -f "$AO/etc/udev/rules.d/61-gts9p-pen.rules" ]
grep -q "finit stage" "$AO/usr/local/sbin/gts9p-audio-bringup"
# parity-remediation additions (2026-08-30): WiFi persistence, touchpad
# rotation, and the sed-safe flasher device check must have survived the fork.
grep -q 'qca_cld3_kiwi_v2' "$AO/etc/modules-load.d/gts9pwifi.conf"
[ -L "$AO/etc/systemd/system/multi-user.target.wants/gts9p-tp-rotate.service" ]
grep -q 'MODEL_WIFI="x810"' flashable/META-INF/com/google/android/update-binary
# sibling-reject generator must be intact (a literal model list would have
# been mangled by the fork sed - the generator uses x71/x81/x91 prefixes)
grep -q 'for p in x71 x81 x91' flashable/META-INF/com/google/android/update-binary
if grep -riqE 'gts9u|x910' flashable/META-INF/com/google/android/update-binary; then
    echo "[gts9p-build] FATAL: Ultra tokens survive in flashable/update-binary -" >&2
    echo "  the fork rename was incomplete; a half-converted device check can" >&2
    echo "  cross-flash. Redo the skeleton fork seds (case-insensitively" >&2
    echo "  verify: grep -rni 'gts9u|x910')." >&2
    exit 1
fi
log "hardware overlay verified (audio + finit stage + pen reclass + dedupe + wifi + tp-rotate + flasher)"

# 3. stage the X810 firmware bundle where build.sh expects it ----------------
#    skeleton build.sh does: [ -f $(basename $FIRMWARE) ] || wget $FIRMWARE
#    then: tar xf $(basename $FIRMWARE) -C partitions
FWTAR="ubuntu-touch-kalama-firmware-x810.tar.xz"
export FIRMWARE="https://localhost/$FWTAR"     # basename match skips the wget
if [ ! -f "$FWTAR" ]; then
    log "packing $FWTAR from $SRC_PARTS (a few minutes)"
    rm -f "$FWTAR.tmp"
    tar cJf "$FWTAR.tmp" -C "$SRC_PARTS" \
        vendor.img odm.img product.img system_ext.img system_dlkm.img vendor_dlkm.img
    mv "$FWTAR.tmp" "$FWTAR"   # atomic: an interrupted pack can't pass the -f check on rerun
fi

# 4. full build: kernel + techpacks + boot images + rootfs + recovery --------
#    (fts1ba90a + wez01 are azkali-native and already build on the base-S9
#     port; first full-link watchpoint is msm_drm with the GTS9P panel.)
./build.sh

# 5. vendor module swap against the X810 vendor_dlkm -------------------------
#    build.sh already extracted the firmware tar into partitions/ and ran the
#    merged swap-vendor-modules.sh v3: modules.load dedupe (audio bug #1) PLUS
#    the LEFTOVER/UNLANDED audit. The X810 module set has NEVER been triaged -
#    on the first build, read the LEFTOVER report in the build log carefully
#    (this is exactly the va_macro-class check); then copy
#    swap-allowlist.txt.template to swap-allowlist.txt and enforce.
#    Verify the two hardware-critical modules: touch OR pen missing = FATAL
#    (the wacom wiring now ships in gts9p-imports, so wez01 must build).
missing_core=0
for m in stm_ts_fts1b90a.ko wez01.ko; do
    found=$(find workdir/tmp/system -name "$m" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        log "built: $m -> $found"
    else
        echo "[gts9p-build] FATAL: $m not in built module set" >&2
        echo "  (stm_ts_fts1b90a = no touch - check CONFIG_TOUCHSCREEN_STM_FTS1BA90A;" >&2
        echo "   wez01 = no pen - check the imported drivers/input wacom wiring)" >&2
        missing_core=1
    fi
done
[ "$missing_core" -eq 0 ] || exit 1

# 6. super + flashable zip ---------------------------------------------------
#    X810 SUPER from GTS9PWIFI_EUR_OPEN.pit: 2,860,032 blocks * 4096 B.
#    28 MiB SMALLER than the skeleton's X910 default (11744051200) - exporting
#    explicitly so super.sh can never fall back to the wrong geometry.
#    scripts/prebuilt/lpmake is aarch64 - locate a host-runnable lpmake first.
#    A preset LPMAKE env is respected as-is.
export SUPER=11714691072
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
ZIP=out/ubuntu-touch-gts9pwifi-24.04-2.x.zip ./scripts/make-flashable.sh

log "done."
log "flash (TWRP gts9p build - verify it boots + backs up BEFORE trusting it;"
log "       pre-fuse-bit-6 unit, FULL backup incl. EFS first):"
log "  adb push $(realpath out/ubuntu-touch-gts9pwifi-24.04-2.x.zip) /data/"
log "  TWRP Install -> /data -> zip   (leaves stock dtbo in place - correct;"
log "                                  dtbo carries the 3 board-rev entries)"
log "  adb shell twrp reboot system"
log "first contact is USB rndis/ssh into the halium initrd; then the ladder:"
log "  display -> touch (stm fts1ba90a) -> wifi (kiwi_v2) -> audio -> evtest pen (wez01)"
