#!/bin/bash
# Copyright (c) 2026 John Stockdale and Off by One, Inc.
# BSD 3-Clause License - see LICENSE at the repository root.
# x810-extract.sh - produce out-x810/parts/ for build-gts9pwifi.sh from the
# stock X810XXU1AWHA firmware (SAMFW.COM_SM-X810_XAR_X810XXU1AWHA_fac.zip).
#
# Output contract (consumed by build-gts9pwifi.sh SRC_PARTS):
#   $OUT/parts/{vendor,odm,product,system_ext,system_dlkm,vendor_dlkm}.img (raw)
#
# Usage:
#   FW=~/SAMFW.COM_SM-X810_XAR_X810XXU1AWHA_fac.zip ./x810-extract.sh
#   FW may also be: a directory containing AP_*.tar.md5, or the AP tar itself.
#   OUT=${OUT:-./out-x810}   KEEP_INTERMEDIATE=1 keeps super images around.
#
# Disk: ~35 GB transient (zip already on disk + 11.7G raw super + ~9G parts).
set -euo pipefail

log() { echo "[x810-extract] $*" >&2; }

# --- 0. dependency preflight (fail fast) ------------------------------------
missing=""
for t in unzip tar lz4 simg2img lpunpack stat awk; do
    command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
if [ -n "$missing" ]; then
    echo "missing prerequisites:$missing" >&2
    echo "  unzip/tar/awk: sudo apt install unzip tar gawk" >&2
    echo "  lz4:           sudo apt install lz4" >&2
    echo "  simg2img:      sudo apt install android-sdk-libsparse-utils" >&2
    echo "  lpunpack:      pip install lpunpack   (or use lpunpack from AOSP otatools)" >&2
    exit 1
fi

FW="${FW:?path to SAMFW fac zip, a dir containing AP_*.tar.md5, or the AP tar}"
OUT="${OUT:-$PWD/out-x810}"
# X810 SUPER from GTS9PWIFI_EUR_OPEN.pit: 2,860,032 blocks * 4096 B.
# (X910 was 11744051200 - do NOT cross-wire these.)
SUPER_EXPECTED="${SUPER_EXPECTED:-11714691072}"

free_kb=$(df -Pk "$(dirname "$OUT")" | awk 'NR==2{print $4}')
if [ "$free_kb" -lt $((35*1024*1024)) ]; then
    echo "need ~35 GB free at $(dirname "$OUT") (have $((free_kb/1024/1024)) GB)" >&2
    exit 1
fi

mkdir -p "$OUT/parts" "$OUT/tmp"
cd "$OUT/tmp"

# --- 1. locate the AP tar and pull super.img.lz4 ----------------------------
extract_super_from_tar() {  # $1 = tar path or '-' for stdin
    # .tar.md5 = plain tar with an md5 line appended; --occurrence stops us
    # cleanly at the member, before tar can trip on the trailing bytes.
    tar -x --occurrence=1 -f "$1" super.img.lz4
}

if [ ! -e "$FW" ]; then
    echo "FW does not exist: $FW" >&2; exit 1
fi

if [ -f super.img.lz4 ]; then
    log "reusing existing tmp/super.img.lz4"
elif [ -d "$FW" ]; then
    AP=$(find "$FW" -maxdepth 1 -name 'AP_*.tar*' | head -1)
    [ -n "$AP" ] || { echo "no AP_*.tar(.md5) inside dir $FW" >&2; exit 1; }
    log "extracting super.img.lz4 from $(basename "$AP")"
    extract_super_from_tar "$AP"
elif [[ "$FW" == *.zip ]]; then
    AP=$(unzip -Z1 "$FW" | grep -m1 '^AP_.*\.tar\(\.md5\)\?$' || true)
    [ -n "$AP" ] || { echo "no AP_*.tar(.md5) member inside zip $FW" >&2; exit 1; }
    log "streaming super.img.lz4 out of $AP (decompresses the AP member; takes a few minutes)"
    unzip -p "$FW" "$AP" | extract_super_from_tar -
else
    log "treating $FW as the AP tar itself"
    extract_super_from_tar "$FW"
fi
[ -s super.img.lz4 ] || { echo "super.img.lz4 extraction produced nothing" >&2; exit 1; }

# --- 2. decompress + unsparse ----------------------------------------------
if [ ! -f super.raw ]; then
    log "lz4 -d super.img.lz4"
    lz4 -d -q -f super.img.lz4 super.img
    magic=$(od -An -tx4 -N4 super.img | tr -d ' ')
    if [ "$magic" = "ed26ff3a" ]; then
        log "sparse image detected -> simg2img"
        simg2img super.img super.raw
        rm -f super.img
    else
        mv super.img super.raw
    fi
fi

# --- 3. PIT cross-check: raw super must match the partition exactly ---------
sz=$(stat -c%s super.raw)
if [ "$sz" -ne "$SUPER_EXPECTED" ]; then
    echo "super.raw is $sz bytes, expected $SUPER_EXPECTED (GTS9PWIFI_EUR_OPEN.pit)." >&2
    echo "  Wrong firmware package, or PIT drift - stop and investigate before" >&2
    echo "  building; super.sh geometry depends on this. Override with" >&2
    echo "  SUPER_EXPECTED=<bytes> only if you have re-verified the PIT." >&2
    exit 1
fi
log "super.raw size matches PIT: $sz bytes"

# --- 4. lpunpack the logical partitions ------------------------------------
log "lpunpack -> parts/"
lpunpack super.raw "$OUT/parts"

want="vendor.img odm.img product.img system_ext.img system_dlkm.img vendor_dlkm.img"
bad=0
for f in $want; do
    if [ -s "$OUT/parts/$f" ]; then
        log "  $f  $(stat -c%s "$OUT/parts/$f") bytes"
    else
        echo "[x810-extract] missing expected logical partition: $f" >&2
        bad=1
    fi
done
[ "$bad" -eq 0 ] || { echo "lpunpack output incomplete - inspect $OUT/parts" >&2; exit 1; }
# system.img is also produced but unused: UT replaces it wholesale.

if [ "${KEEP_INTERMEDIATE:-0}" != "1" ]; then
    rm -f "$OUT/tmp/super.img.lz4" "$OUT/tmp/super.raw"
    log "intermediates removed (KEEP_INTERMEDIATE=1 to keep)"
fi

log "done. SRC_PARTS=$OUT/parts"
