#!/usr/bin/env python3
"""lp_inspect.py - read-only inspector for Android LP (super) partition metadata.

Parses the liblp on-disk format directly: geometry block, metadata header,
partition/extent/group/block-device tables. Verifies all checksums before
trusting anything. Never writes.

Usage:
    python3 lp_inspect.py /userdata/lp-metadata.bak
    sudo python3 lp_inspect.py /dev/sda25
    python3 lp_inspect.py super.img --target 8000000000 --grow system
"""

import argparse
import hashlib
import os
import struct
import sys

SECTOR = 512
GEOMETRY_OFFSET = 4096
GEOMETRY_MAGIC = 0x616C4467
HEADER_MAGIC = 0x414C5030
LINEAR, ZERO = 0, 1


def die(msg):
    print("ERROR: %s" % msg, file=sys.stderr)
    sys.exit(1)


def cstr(b):
    return b.split(b"\x00", 1)[0].decode("utf-8", "replace")


def align_up(x, a):
    return x if a == 0 or x % a == 0 else x + a - (x % a)


def human(n):
    return "%d bytes (%.2f GiB / %.2f GB)" % (n, n / 2**30, n / 1e9)


def main():
    ap = argparse.ArgumentParser(description="Read-only LP metadata inspector")
    ap.add_argument("path", help="metadata dump, super image, or super block device")
    ap.add_argument("--slot", type=int, default=0, help="metadata slot to read (default 0)")
    ap.add_argument("--grow", default="system", help="partition to analyze growth for")
    ap.add_argument("--target", type=int, default=8_000_000_000,
                    help="desired total size in bytes for --grow partition")
    args = ap.parse_args()

    # ---- prerequisites, fail fast -------------------------------------------
    if sys.version_info < (3, 6):
        die("python3 >= 3.6 required")
    if not os.path.exists(args.path):
        die("%s not found" % args.path)
    try:
        f = open(args.path, "rb")
    except PermissionError:
        die("cannot open %s for reading - use sudo for block devices" % args.path)

    # ---- geometry (primary at 4096, backup at 8192) -------------------------
    f.seek(GEOMETRY_OFFSET)
    g = f.read(4096)
    if len(g) < 60:
        die("input too small - need at least the first 16 KiB of super")
    magic, gsize = struct.unpack_from("<II", g, 0)
    if magic != GEOMETRY_MAGIC:
        die("geometry magic 0x%08x != 0x%08x - not LP metadata? "
            "(dump must start at byte 0 of the super partition)" % (magic, GEOMETRY_MAGIC))
    gsum = g[8:40]
    meta_max, slot_count, lbs = struct.unpack_from("<III", g, 40)
    if hashlib.sha256(g[:8] + b"\x00" * 32 + g[40:gsize]).digest() != gsum:
        die("geometry checksum mismatch - corrupt or truncated dump")
    if not (0 <= args.slot < slot_count):
        die("slot %d out of range (metadata_slot_count=%d)" % (args.slot, slot_count))

    print("geometry: OK  metadata_max_size=%d  slots=%d  logical_block=%d"
          % (meta_max, slot_count, lbs))

    # ---- metadata header + tables for the chosen slot -----------------------
    slot_off = 3 * 4096 + args.slot * meta_max
    f.seek(slot_off)
    hdr = f.read(meta_max)
    if len(hdr) < 128:
        die("truncated read at slot offset %d - dump too small (grab >= 1 MiB of super)" % slot_off)
    magic, vmaj, vmin, hsize = struct.unpack_from("<IHHI", hdr, 0)
    if magic != HEADER_MAGIC:
        die("header magic 0x%08x != 0x%08x at slot %d" % (magic, HEADER_MAGIC, args.slot))
    hsum = hdr[12:44]
    (tsize,) = struct.unpack_from("<I", hdr, 44)
    tsum = hdr[48:80]
    if hashlib.sha256(hdr[:12] + b"\x00" * 32 + hdr[44:hsize]).digest() != hsum:
        die("header checksum mismatch - corrupt metadata")
    tables = hdr[hsize:hsize + tsize]
    if len(tables) < tsize:
        die("truncated tables - dump too small")
    if hashlib.sha256(tables).digest() != tsum:
        die("tables checksum mismatch - corrupt metadata")
    descs = [struct.unpack_from("<III", hdr, 80 + i * 12) for i in range(4)]
    print("metadata: OK  version %d.%d  slot %d  (header %dB, tables %dB)"
          % (vmaj, vmin, args.slot, hsize, tsize))

    def table(i):
        off, num, esz = descs[i]
        return [tables[off + j * esz: off + (j + 1) * esz] for j in range(num)]

    parts_raw, exts_raw, groups_raw, bdevs_raw = (table(i) for i in range(4))

    extents = []
    for e in exts_raw:
        ns, tt, td, tsrc = struct.unpack_from("<QIQI", e, 0)
        extents.append({"sectors": ns, "type": tt, "start": td, "src": tsrc})

    groups = []
    for e in groups_raw:
        flags, gmax = struct.unpack_from("<IQ", e, 36)
        groups.append({"name": cstr(e[:36]), "flags": flags, "max": gmax})

    bdevs = []
    for e in bdevs_raw:
        fls, algn, aoff, size = struct.unpack_from("<QIIQ", e, 0)
        bdevs.append({"first_sector": fls, "align": algn, "align_off": aoff,
                      "size": size, "name": cstr(e[24:60])})
    if not bdevs:
        die("no block devices in metadata - malformed")
    sup = bdevs[0]
    align = sup["align"] or (1 << 20)

    parts = []
    for e in parts_raw:
        attrs, fei, ne, gi = struct.unpack_from("<IIII", e, 36)
        pexts = extents[fei:fei + ne]
        size = sum(x["sectors"] for x in pexts) * SECTOR
        parts.append({"name": cstr(e[:36]), "attrs": attrs, "extents": pexts,
                      "size": size, "group": groups[gi]["name"] if gi < len(groups) else "?%d" % gi})

    # ---- report: block device, partitions, groups ---------------------------
    print("\nsuper (%s): %s  first_sector=%d  align=%d"
          % (sup["name"], human(sup["size"]), sup["first_sector"], sup["align"]))

    print("\npartitions:")
    for p in sorted(parts, key=lambda p: min((x["start"] for x in p["extents"]), default=0)):
        emap = ", ".join("%s@%d+%d" % ("lin" if x["type"] == LINEAR else "zero",
                                       x["start"], x["sectors"]) for x in p["extents"]) or "(no extents)"
        print("  %-14s %12d B  %-8.8s group=%s  [%s]"
              % (p["name"], p["size"], "RO" if p["attrs"] & 1 else "RW", p["group"], emap))

    print("\ngroups:")
    gsizes = {}
    for grp in groups:
        used = sum(p["size"] for p in parts if p["group"] == grp["name"])
        gsizes[grp["name"]] = used
        cap = human(grp["max"]) if grp["max"] else "unlimited (0)"
        rem = ("remaining %s" % human(grp["max"] - used)) if grp["max"] else ""
        print("  %-24s max=%s  used=%s  %s" % (grp["name"], cap, human(used), rem))

    # ---- free-extent map ----------------------------------------------------
    lin = sorted((x for x in extents if x["type"] == LINEAR and x["src"] == 0),
                 key=lambda x: x["start"])
    end_sector = sup["size"] // SECTOR
    free, cur = [], sup["first_sector"]
    for x in lin:
        if x["start"] > cur:
            free.append((cur, x["start"]))
        cur = max(cur, x["start"] + x["sectors"])
    if cur < end_sector:
        free.append((cur, end_sector))
    usable = 0
    print("\nfree regions on super:")
    for s, e in free:
        us = align_up(s * SECTOR, align) // SECTOR
        u = max(0, e - us) * SECTOR
        usable += u
        print("  sectors %d..%d  (%.1f MiB raw, %.1f MiB usable after alignment)"
              % (s, e, (e - s) * SECTOR / 2**20, u / 2**20))
    print("  total usable: %s" % human(usable))

    # ---- growth analysis ----------------------------------------------------
    tgt = next((p for p in parts if p["name"] == args.grow), None)
    if tgt is None:
        die("partition %r not in metadata (see list above)" % args.grow)
    want = align_up(args.target, align)
    delta = want - tgt["size"]
    print("\ngrow %r: %s -> %s  (delta %s)"
          % (args.grow, human(tgt["size"]), human(want), human(delta)))
    if delta <= 0:
        print("  target <= current size; nothing to do.")
        return
    print("  extent space: %s (need %s) -> %s"
          % (human(usable), human(delta), "OK" if usable >= delta else "INSUFFICIENT"))
    grp = next(g for g in groups if g["name"] == tgt["group"])
    if grp["max"]:
        newuse = gsizes[grp["name"]] - tgt["size"] + want
        ok = newuse <= grp["max"]
        print("  group budget %r: new usage %s vs max %s -> %s"
              % (grp["name"], human(newuse), human(grp["max"]), "OK" if ok else "EXCEEDED"))
        ceil_now = grp["max"] - (gsizes[grp["name"]] - tgt["size"])
        print("  max %r size within current budget: %s"
              % (args.grow, human((ceil_now // align) * align)))
        freed = sum(p["size"] for p in parts if p["name"] in ("product", "system_ext"))
        if freed:
            ceil_del = ceil_now + freed
            print("  ... after deleting product+system_ext (+%s budget & extents): %s"
                  % (human(freed), human((min(ceil_del, ceil_now + freed) // align) * align)))
    else:
        print("  group budget %r: unlimited -> OK" % grp["name"])


if __name__ == "__main__":
    main()
