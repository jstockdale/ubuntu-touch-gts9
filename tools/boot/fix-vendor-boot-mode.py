#!/usr/bin/env python3
# Copyright (c) 2026 John Stockdale and Off by One, Inc.
# BSD 3-Clause License - see LICENSE at the repository root.
"""fix-vendor-boot-mode.py - flip androidboot.mode=charger -> normal in a
vendor_boot image's bootconfig section, by padded in-place byte replacement
(size-preserving, no repack). Same method as fix-boot-cmdline.py.

The bootloader stamps androidboot.mode="charger" into the bootconfig trailer
of vendor_boot on some power-on conditions; Android init then runs the
`on charger` path (minimal services, then exits) instead of a normal boot.
Forcing "normal" makes init run the full boot -> UI stack.

Usage: ./fix-vendor-boot-mode.py <vendor_boot.img> [output.img]
Default output: <base>-normalmode.img
"""
import sys, pathlib

# bootconfig uses: key = "value"  (spaces around =, quoted value)
OLD = b'androidboot.mode = "charger"'
NEW = b'androidboot.mode = "normal"'   # same length: charger(7)==normal... check below

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = pathlib.Path(sys.argv[1])
    dst = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_name(src.stem + "-normalmode.img")

    data = src.read_bytes()

    # try the spaced bootconfig form first, then the compact cmdline form
    forms = [
        (b'androidboot.mode = "charger"', b'androidboot.mode = "normal"'),
        (b'androidboot.mode="charger"',   b'androidboot.mode="normal"'),
        (b'androidboot.mode=charger',      b'androidboot.mode=normal'),
    ]
    hits = []
    for old, new in forms:
        c = data.count(old)
        if c:
            hits.append((old, new, c))

    if not hits:
        sys.exit("no androidboot.mode=charger form found in this image")

    patched = data
    total = 0
    for old, new, c in hits:
        assert len(new) <= len(old), f"replacement longer than original for {old!r}"
        pad = len(old) - len(new)
        repl = new + b" " * pad          # pad with spaces (harmless in bootconfig/cmdline)
        # bootconfig lines end in \n; padding before \n is fine. For safety pad AFTER
        # the value inside quotes is wrong, so pad OUTSIDE: new + trailing spaces works
        # because bootconfig tokenizes on \n and ignores trailing WS.
        patched = patched.replace(old, repl, c)
        total += c
        print(f"  {old.decode()} -> {new.decode()} (x{c}, pad {pad})")

    assert len(patched) == len(data), "size changed"
    dst.write_bytes(patched)
    print(f"patched {total} occurrence(s), size unchanged ({len(data)} bytes)")
    print(f"wrote: {dst}")
    print("flash: fastboot flash vendor_boot <file>  (or dd to by-name/vendor_boot in TWRP)")

if __name__ == "__main__":
    main()
