#!/bin/bash
# Swap halium-built kernel modules into the stock vendor_dlkm image.
#
# v2 changes (F2): the swap is now audited. Any stock module NOT replaced by
# a halium-built one keeps stock vermagic and cannot load against the halium
# kernel - a silent dead module (this is exactly the class that cost us the
# audio va_macro hunt). After swapping, this script reports:
#
#   1. LEFTOVER  - stock .ko with no same-named built module (suspect list)
#   2. UNLANDED  - built .ko with no stock counterpart (rides another
#                  vehicle - vendor ramdisk - or is silently dropped)
#
# Strict mode: if scripts/swap-allowlist.txt exists (override with
# ALLOWLIST=...), every LEFTOVER must appear in it or the script fails
# BEFORE repacking, leaving the previous vendor_dlkm.img untouched.
# Delete the allowlist file to run report-only.
set -euo pipefail

PARTS=${PARTS:-"./partitions"}
BUILT=${BUILT:-$(ls -d ./workdir/tmp/system/{usr/,}lib/modules/* 2>/dev/null | head -1)}
ALLOWLIST=${ALLOWLIST:-"$(dirname "$0")/swap-allowlist.txt"}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

[ -f "$PARTS/vendor_dlkm.img" ] || { echo "no $PARTS/vendor_dlkm.img" >&2; exit 1; }
[ -d "$BUILT" ] || { echo "no built modules at $BUILT" >&2; exit 1; }
[ -f "$PARTS/vendor_dlkm.img.stock" ] || cp "$PARTS/vendor_dlkm.img" "$PARTS/vendor_dlkm.img.stock"

fsck.erofs --extract="$WORK/x" "$PARTS/vendor_dlkm.img.stock"
MODS="$WORK/x/lib/modules"
[ -d "$MODS" ] || { echo "no lib/modules inside vendor_dlkm.img.stock" >&2; exit 1; }

CTX=$(getfattr -n security.selinux --only-values "$MODS/smcinvoke_dlkm.ko" 2>/dev/null | tr -d '\0' || true)
[ -n "$CTX" ] || CTX="u:object_r:vendor_file:s0"

# --- inventories -------------------------------------------------------------
find "$MODS"  -maxdepth 1 -name '*.ko' -printf '%f\n' | sort -u > "$WORK/stock.list"
find "$BUILT" -name '*.ko' -printf '%f\n' | sort -u > "$WORK/built.list"

# --- swap: replace every stock module for which we built a counterpart -------
swapped=0
while IFS= read -r -d '' ko; do
    n=$(basename "$ko")
    if [ -f "$MODS/$n" ]; then
        cp -f "$ko" "$MODS/$n"
        chown 0:0 "$MODS/$n" 2>/dev/null || true
        chmod 0644 "$MODS/$n"
        setfattr -n security.selinux -v "$CTX" "$MODS/$n" 2>/dev/null || true
        swapped=$((swapped + 1))
    fi
done < <(find "$BUILT" -name '*.ko' -print0 | sort -z)

# --- audit -------------------------------------------------------------------
comm -23 "$WORK/stock.list" "$WORK/built.list" > "$WORK/leftover.list"
comm -13 "$WORK/stock.list" "$WORK/built.list" > "$WORK/unlanded.list"
n_stock=$(wc -l < "$WORK/stock.list")
n_leftover=$(wc -l < "$WORK/leftover.list")
n_unlanded=$(wc -l < "$WORK/unlanded.list")

echo "swap-vendor-modules: swapped $swapped of $n_stock stock modules"

if [ "$n_leftover" -gt 0 ]; then
    echo ""
    echo "LEFTOVER ($n_leftover): stock modules NOT rebuilt by the halium tree."
    echo "These keep stock vermagic and will fail to load against the halium"
    echo "kernel if anything modprobes them:"
    sed 's/^/    /' "$WORK/leftover.list"
fi

if [ "$n_unlanded" -gt 0 ]; then
    echo ""
    echo "UNLANDED ($n_unlanded): built modules with no stock counterpart in"
    echo "vendor_dlkm (must ship via the vendor ramdisk or they are dropped):"
    sed 's/^/    /' "$WORK/unlanded.list"
fi

# --- strict mode -------------------------------------------------------------
if [ -f "$ALLOWLIST" ]; then
    sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$ALLOWLIST" \
        | grep -v '^$' | sort -u > "$WORK/allow.list" || true
    comm -23 "$WORK/leftover.list" "$WORK/allow.list" > "$WORK/violations.list"
    comm -13 "$WORK/leftover.list" "$WORK/allow.list" > "$WORK/stale.list"
    if [ -s "$WORK/stale.list" ]; then
        echo ""
        echo "note: allowlist entries that are no longer leftovers (stale, prune when convenient):"
        sed 's/^/    /' "$WORK/stale.list"
    fi
    if [ -s "$WORK/violations.list" ]; then
        echo "" >&2
        echo "FAIL: $(wc -l < "$WORK/violations.list") leftover module(s) not in $ALLOWLIST:" >&2
        sed 's/^/    /' "$WORK/violations.list" >&2
        echo "" >&2
        echo "Review each one: if the halium build SHOULD produce it (audio," >&2
        echo "codec macros, anything a working subsystem needs), enable it in" >&2
        echo "the relevant techpack config instead of allowlisting. If it is a" >&2
        echo "genuinely unused Samsung-only module, add its name to the" >&2
        echo "allowlist. vendor_dlkm.img was NOT repacked; the previous image" >&2
        echo "is still in place. Rerun this script after resolving." >&2
        exit 1
    fi
    echo ""
    echo "strict mode: all leftovers allowlisted - OK"
else
    echo ""
    echo "note: no allowlist at $ALLOWLIST - report-only mode."
    echo "Create the file (see swap-allowlist.txt template) to enforce."
fi

# --- repack ------------------------------------------------------------------
rm -f "$PARTS/vendor_dlkm.img"
mkfs.erofs -zlz4 -T0 --force-uid=0 --force-gid=0 "$PARTS/vendor_dlkm.img" "$WORK/x"
ls -la "$PARTS/vendor_dlkm.img"
