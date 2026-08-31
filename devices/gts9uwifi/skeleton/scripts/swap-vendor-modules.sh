#!/bin/bash
set -e
PARTS=${PARTS:-"./partitions"}
BUILT=${BUILT:-$(ls -d ./workdir/tmp/system/{usr/,}lib/modules/* 2>/dev/null | head -1)}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

[ -f "$PARTS/vendor_dlkm.img" ] || { echo "no $PARTS/vendor_dlkm.img"; exit 1; }
[ -d "$BUILT" ] || { echo "no built modules at $BUILT"; exit 1; }
[ -f "$PARTS/vendor_dlkm.img.stock" ] || cp "$PARTS/vendor_dlkm.img" "$PARTS/vendor_dlkm.img.stock"

fsck.erofs --extract="$WORK" "$PARTS/vendor_dlkm.img.stock"
MODS="$WORK/lib/modules"
CTX=$(getfattr -n security.selinux --only-values "$MODS/smcinvoke_dlkm.ko" 2>/dev/null | tr -d '\0')
[ -n "$CTX" ] || CTX="u:object_r:vendor_file:s0"

# dedupe modules.load: the stock list ships duplicated 4x; vendor_modprobe.sh
# fires every line in parallel with exit codes discarded, so a duplicated list
# multiplies the spawn storm and the odds of any module silently losing the
# race (observed: lpass_cdc_va_macro, machine_dlkm -> no sound card, no audio).
# Dedup at repack fixes every image regardless of where the duplication began.
for lst in "$MODS"/modules.load*; do
    [ -f "$lst" ] || continue
    before=$(wc -l < "$lst")
    awk '!seen[$0]++' "$lst" > "$lst.dedup" && mv "$lst.dedup" "$lst"
    chown 0:0 "$lst" 2>/dev/null || true; chmod 0644 "$lst"
    setfattr -n security.selinux -v "$CTX" "$lst" 2>/dev/null || true
    echo "dedup $(basename "$lst"): $before -> $(wc -l < "$lst") lines"
done

swapped=""
for ko in $(find "$BUILT" -name '*.ko'); do
    n=$(basename "$ko")
    if [ -f "$MODS/$n" ]; then
        cp -f "$ko" "$MODS/$n"; chown 0:0 "$MODS/$n" 2>/dev/null || true; chmod 0644 "$MODS/$n"
        setfattr -n security.selinux -v "$CTX" "$MODS/$n" 2>/dev/null || true
        swapped="$swapped $n"
    fi
done
echo "swapped:$swapped"
rm -f "$PARTS/vendor_dlkm.img"
mkfs.erofs -zlz4 -T0 --force-uid=0 --force-gid=0 "$PARTS/vendor_dlkm.img" "$WORK"
ls -la "$PARTS/vendor_dlkm.img"
