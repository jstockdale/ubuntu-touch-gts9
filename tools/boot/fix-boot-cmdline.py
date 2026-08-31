#!/usr/bin/env python3
"""fix-boot-cmdline.py - retarget the baked CONFIG_CMDLINE panel selection
from the 11" Tab S9 panel to the Ultra's, by padded in-place replacement.

Usage: ./fix-boot-cmdline.py <boot.img> [output.img]
Default output: <boot.img base>-gts9u.img
"""
import sys, pathlib

OLD = b"msm_drm.dsi_display0=GTS9_ANA38407_AMSA10FA01: msm_drm.lcd_id=800004 sec_common_fn.lcd_id=800004"
NEW_CORE = b"msm_drm.dsi_display0=GTS9U_ANA38407_AMSA46AS02:"
# lcd_id args intentionally dropped: ss_dsi reads the real manufacture ID from
# the DDIC at panel init; revisit with the true Ultra ID from
# /sys/class/lcd/panel/manufacture_id once the panel is lit, if rev-gated
# behavior needs it at boot.

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = pathlib.Path(sys.argv[1])
    dst = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_name(src.stem + "-gts9u.img")

    data = src.read_bytes()
    n = data.count(OLD)
    if n == 0:
        sys.exit("needle not found - is this the built gts9uwifi boot.img?")
    if n > 1:
        sys.exit(f"needle found {n} times - refusing ambiguous patch")

    pad = len(OLD) - len(NEW_CORE)
    assert pad >= 0, "replacement longer than original"
    new = NEW_CORE + b" " * pad
    assert len(new) == len(OLD)

    patched = data.replace(OLD, new, 1)
    assert len(patched) == len(data)
    dst.write_bytes(patched)

    i = patched.find(NEW_CORE)
    print(f"patched 1 occurrence, size unchanged ({len(data)} bytes)")
    print("context:", patched[max(0, i-30):i+len(new)+10].decode(errors="replace"))
    print(f"wrote: {dst}")

if __name__ == "__main__":
    main()
