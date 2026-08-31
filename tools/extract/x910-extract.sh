#!/bin/bash
# x910-extract.sh - Extract Ubuntu Touch porting inputs from SM-X910 stock firmware
#
# Input:  a samfw/Frija-style firmware zip (AP_*, BL_*, CSC_* tar.md5 inside)
#         or an already-extracted directory containing those tars.
# Output: out-x910/
#           stockimgs/   boot.img init_boot.img vendor_boot.img dtbo.img
#                        vbmeta.img recovery.img  (+ .pit from CSC)
#           parts/       vendor.img odm.img product.img system_ext.img
#                        system_dlkm.img vendor_dlkm.img   (from super)
#           info.txt     LP geometry (super size, groups), partition table,
#                        vendor build identity
#
# Deps: bash, python3, lz4, tar, unzip. No lpunpack/simg2img needed -
#       sparse + LP parsing are embedded below.
#
# Usage: ./x910-extract.sh SM-X910_..._fac.zip
set -euo pipefail

# --- 0. dependency preflight (fail fast, before any heavy work) --------------
missing=""
for t in unzip tar lz4 python3; do
    command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
if [ -n "$missing" ]; then
    echo "missing required tools:$missing" >&2
    echo "  sudo apt install$missing" >&2
    exit 1
fi
command -v fsck.erofs >/dev/null 2>&1 || \
    echo "note: erofs-utils not installed - vendor identity step will be skipped (sudo apt install erofs-utils)" >&2

SRC="${1:?usage: $0 <firmware.zip | extracted-dir>}"
OUT="${OUT:-out-x910}"
mkdir -p "$OUT/stockimgs" "$OUT/parts" "$OUT/tmp"

log() { echo "[x910] $*" >&2; }

# --- 1. locate AP / CSC tars -------------------------------------------------
WORK="$OUT/tmp"
if [ -d "$SRC" ]; then
    AP=$(ls "$SRC"/AP_*.tar.md5 "$SRC"/AP_*.tar 2>/dev/null | head -1)
    CSC=$(ls "$SRC"/CSC_*.tar.md5 "$SRC"/CSC_*.tar 2>/dev/null | head -1)
else
    log "listing zip"
    APN=$(unzip -Z1 "$SRC" | grep -E '^AP_.*\.tar(\.md5)?$' | head -1)
    CSCN=$(unzip -Z1 "$SRC" | grep -E '^CSC_.*\.tar(\.md5)?$' | head -1)
    [ -n "$APN" ] || { echo "no AP_*.tar(.md5) in zip"; exit 1; }
    log "extracting $APN (this is the ~13 GB one)"
    unzip -o -q "$SRC" "$APN" -d "$WORK"
    [ -n "$CSCN" ] && unzip -o -q "$SRC" "$CSCN" -d "$WORK"
    AP="$WORK/$APN"; CSC="$WORK/${CSCN:-}"
fi
log "AP:  $AP"
log "CSC: ${CSC:-none}"

# --- 2. pull needed members from AP (tar.md5 is a tar with md5 appended) -----
# Names as shipped by Samsung on SM8550: <name>.img.lz4
WANT_SMALL="boot.img.lz4 init_boot.img.lz4 vendor_boot.img.lz4 dtbo.img.lz4 vbmeta.img.lz4 vbmeta_system.img.lz4 recovery.img.lz4"
log "extracting small images from AP"
tar -xf "$AP" -C "$OUT/stockimgs" $WANT_SMALL 2>/dev/null || {
    # tolerate missing members: extract whatever exists
    for m in $WANT_SMALL; do tar -xf "$AP" -C "$OUT/stockimgs" "$m" 2>/dev/null || true; done
}
for f in "$OUT/stockimgs"/*.lz4; do
    [ -e "$f" ] || continue
    lz4 -d -f -q "$f" "${f%.lz4}" && rm -f "$f"
done
ls -la "$OUT/stockimgs" >&2

# --- 3. PIT from CSC ---------------------------------------------------------
if [ -n "${CSC:-}" ] && [ -f "$CSC" ]; then
    PITN=$(tar -tf "$CSC" | grep -m1 '\.pit$' || true)
    if [ -n "$PITN" ]; then
        tar -xf "$CSC" -C "$OUT/stockimgs" "$PITN"
        log "PIT: $PITN"
    fi
fi

# --- 4. super.img.lz4 -> sparse -> carve partitions (streaming, no raw super)
log "streaming super.img.lz4 (sparse decode + LP carve, no full raw image written)"
PYCARVE="$OUT/tmp/carve_super.py"
cat > "$PYCARVE" <<'PYEOF'
import sys, os, struct

outdir, infopath = sys.argv[1], sys.argv[2]
src = sys.stdin.buffer
info = open(infopath, 'w')

def say(*a):
    print(*a, file=sys.stderr)
    print(*a, file=info)

# ---- sparse image reader: presents a linear read/skip interface ------------
class Sparse:
    def __init__(self, f):
        h = f.read(28)
        magic, major, minor, fhs, chs, blk, total_blks, total_chunks, _ = \
            struct.unpack('<IHHHHIIII', h)
        if magic != 0xed26ff3a:
            raise SystemExit(f"not a sparse image (magic {magic:#x}) - "
                             "Samsung super should be sparse")
        self.f, self.blk = f, blk
        self.chunks_left = total_chunks
        self.total = total_blks * blk
        self.cur = None      # (kind, remaining_bytes, fill4)
        say(f"sparse: block={blk} total_bytes={self.total} chunks={total_chunks}")
    def _next_chunk(self):
        while self.chunks_left:
            ch = self.f.read(12)
            ctype, _, cblks, csz = struct.unpack('<HHII', ch)
            self.chunks_left -= 1
            n = cblks * self.blk
            if ctype == 0xCAC1:   # raw
                self.cur = ('raw', n, None); return
            if ctype == 0xCAC2:   # fill
                fill = self.f.read(4)
                self.cur = ('fill', n, fill); return
            if ctype == 0xCAC3:   # don't care
                self.cur = ('zero', n, None); return
            if ctype == 0xCAC4:   # crc
                self.f.read(4); continue
            raise SystemExit(f"unknown chunk {ctype:#x}")
        self.cur = ('eof', 0, None)
    def read(self, n, sink):
        """copy n linear bytes into sink (callable or None to discard)"""
        while n > 0:
            if not self.cur or self.cur[1] == 0:
                self._next_chunk()
                if self.cur[0] == 'eof':
                    raise SystemExit("EOF in sparse stream")
            kind, rem, fill = self.cur
            take = min(n, rem)
            if kind == 'raw':
                left = take
                while left:
                    b = self.f.read(min(left, 1 << 22))
                    if not b: raise SystemExit("short read")
                    if sink: sink(b)
                    left -= len(b)
            else:
                if sink:
                    pat = (fill * ((1 << 20) // 4)) if kind == 'fill' else bytes(1 << 20)
                    left = take
                    while left:
                        c = min(left, len(pat))
                        sink(pat[:c]); left -= c
            self.cur = (kind, rem - take, fill)
            n -= take

sp = Sparse(src)
pos = 0
def seek_to(off):
    global pos
    assert off >= pos, f"cannot seek backwards ({off} < {pos})"
    sp.read(off - pos, None); pos = off
def copy_to(path, ln):
    global pos
    with open(path, 'wb') as o:
        sp.read(ln, o.write)
    pos += ln

# ---- LP metadata ------------------------------------------------------------
buf = bytearray()
def cap(b): buf.extend(b)
seek_to(0); sp.read(3 << 20, cap); pos = 3 << 20
d = bytes(buf)

g = d[4096:4148]
gmagic, = struct.unpack('<I', g[:4])
assert gmagic == 0x616c4467, hex(gmagic)
meta_max, slots, lbs = struct.unpack('<III', g[40:52])
hdr_off = 4096 + 4096 * 2
h = d[hdr_off:hdr_off + 256]
magic, major, minor, header_size = struct.unpack('<IHHI', h[:12])
assert magic == 0x414C5030
tables_size, = struct.unpack('<I', h[44:48])
def desc(o): return struct.unpack('<III', h[o:o + 12])
po, pn, ps = desc(80); eo, en, es = desc(92); go, gn, gs = desc(104); bo, bn, bs = desc(116)
t = d[hdr_off + header_size: hdr_off + header_size + tables_size]

groups = []
for i in range(gn):
    e = t[go + i * gs: go + (i + 1) * gs]
    name = e[:36].rstrip(b'\0').decode()
    flags, mx = struct.unpack('<IQ', e[36:48])
    groups.append(name)
    say(f"group '{name}' max={mx}")

exts = []
for i in range(en):
    e = t[eo + i * es: eo + (i + 1) * es]
    ns, tt, td, tsrc = struct.unpack('<QIQI', e[:24])
    exts.append((ns * 512, td * 512))

bdev = t[bo:bo + bs]
fs, align, aoff, size = struct.unpack('<QIIQ', bdev[:24])
say(f"SUPER_DEVICE_SIZE={size}")

want = {'vendor', 'odm', 'product', 'system_ext', 'system_dlkm', 'vendor_dlkm'}
plan = []
for i in range(pn):
    e = t[po + i * ps: po + (i + 1) * ps]
    name = e[:36].rstrip(b'\0').decode()
    attrs, fe, ne, gi = struct.unpack('<IIII', e[36:52])
    pieces = exts[fe:fe + ne]
    total = sum(p[0] for p in pieces)
    say(f"partition {name:<14} group={groups[gi]:<10} size={total:<12} extents={pieces}")
    base = name.rstrip('_ab').rstrip('_')  # tolerate _a suffixes
    key = name[:-2] if name.endswith(('_a', '_b')) else name
    if key in want and not name.endswith('_b') and total > 0:
        plan.append((name, key, pieces))

# carve in stream order; multi-extent partitions get pieces concatenated,
# which is only valid if extents are listed in linear order - assert that.
jobs = []
for name, key, pieces in plan:
    offs = [o for (l, o) in pieces]
    assert offs == sorted(offs), f"{name}: non-monotonic extents, use lpunpack instead"
    for idx, (l, o) in enumerate(pieces):
        jobs.append((o, l, key, idx, len(pieces)))
jobs.sort()
open_files = {}
for o, l, key, idx, npieces in jobs:
    seek_to(o)
    path = os.path.join(outdir, key + '.img')
    mode = 'ab' if idx else 'wb'
    with open(path, mode) as fo:
        sp.read(l, fo.write)
    pos = o + l
    say(f"carved {key} piece {idx+1}/{npieces} ({l} bytes)")
say("done")
info.close()
PYEOF

set +o pipefail
tar -xOf "$AP" super.img.lz4 | lz4 -d -q - - | python3 "$PYCARVE" "$OUT/parts" "$OUT/info.txt"
rc=$?
set -o pipefail
[ "$rc" -eq 0 ] || { echo "super carve failed (python rc=$rc)"; exit 1; }
for f in vendor odm product system_ext system_dlkm vendor_dlkm; do
    [ -s "$OUT/parts/$f.img" ] || { echo "carve incomplete: missing $OUT/parts/$f.img"; exit 1; }
done
log "all six partitions carved and verified"

# --- 5. vendor identity (best effort, needs erofs-utils or debugfs) ---------
if command -v fsck.erofs >/dev/null 2>&1; then
    T=$(mktemp -d)
    if fsck.erofs --extract="$T" "$OUT/parts/vendor.img" >/dev/null 2>&1; then
        grep -E "^ro.product.vendor.device|^ro.product.vendor.model|^ro.vendor.build.fingerprint|^ro.vendor.build.security_patch" \
            "$T/build.prop" | tee -a "$OUT/info.txt"
    fi
    rm -rf "$T"
else
    echo "note: install erofs-utils and re-run for vendor build.prop identity" >> "$OUT/info.txt"
fi

log "complete -> $OUT"
log "high-value artifacts to share for remote analysis (~60 MB):"
log "  $OUT/stockimgs/dtbo.img vendor_boot.img boot.img *.pit  +  $OUT/info.txt"
