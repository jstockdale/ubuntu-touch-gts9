#!/bin/bash
# PROVEN FIX (partial): halium libdroid-util hardcodes module name "audio_hw_if";
# Samsung's HAL rejects it with -19 (ENOSYS). Patch to "primary" (NUL-padded,
# same length). Confirmed: Samsung HAL logs "adev_open: primary" and returns a
# device (the -19 crash is GONE). A SECOND gate remains (version EINVAL, below).
# Apply to all installed generations. Deliver permanently via halium-overlay.
set -eu
for M in /usr/lib/pulse-16.1+dfsg1/modules/libdroid-util-*.so; do
  python3 - "$M" <<EOF
import pathlib,sys,shutil
p=pathlib.Path("$M"); b=p.read_bytes()
old=b"audio_hw_if\x00"; new=b"primary\x00\x00\x00\x00\x00"
n=b.count(old)
if n:
    shutil.copy(p, str(p)+".orig")
    p.write_bytes(b.replace(old,new,n))
    print(f"{p.name}: patched {n} (backup .orig)")
else:
    print(f"{p.name}: no audio_hw_if (already patched or N/A)")
EOF
done
