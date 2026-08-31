#!/bin/bash
# Patch the Android-side hidl_compat shim: audio_hw_if -> primary
# (same length: "audio_hw_if"=11, "primary"=7, pad with NULs -> 11)
# Test on a COPY via overlay bind. Fully reversible.
set -u
SHIM=/android/system/lib64/hw/audio.hidl_compat.default.so
WORK=/tmp/shimfix
mkdir -p "$WORK"

echo "=== 1. confirm the exact string(s) in the shim ==="
strings -a -t x "$SHIM" | grep -nE "audio_hw_if|audio_hw_primary|primary" | head

echo "=== 2. copy + patch ==="
cp "$SHIM" "$WORK/patched.so"
python3 - "$WORK/patched.so" <<'EOF'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
b = f.read_bytes()
# "audio_hw_if\0" (12 bytes incl NUL) -> "primary\0\0\0\0\0" (7 + 5 NUL = 12)
old = b"audio_hw_if\x00"
new = b"primary\x00\x00\x00\x00\x00"
assert len(old) == len(new) == 12
n = b.count(old)
print(f"  occurrences of audio_hw_if\\0: {n}")
if n == 0:
    # maybe no trailing-NUL variant; try bare (padded outside)
    old2 = b"audio_hw_if"
    n2 = b.count(old2)
    print(f"  bare audio_hw_if: {n2} (NOT patching bare - would corrupt adjacent string)")
    sys.exit("no NUL-terminated audio_hw_if found - inspect layout before patching")
nb = b.replace(old, new, n)
assert len(nb) == len(b)
f.write_bytes(nb)
print(f"  patched {n} occurrence(s), size {len(b)} unchanged")
# verify
assert b"audio_hw_if\x00" not in nb
assert b"primary\x00" in nb
print("  verified: audio_hw_if gone, primary present")
EOF

echo "=== 3. bind the patched copy over the shim (reversible) ==="
sudo mount --bind "$WORK/patched.so" "$SHIM" && echo "bind mounted" || { echo "bind failed"; exit 1; }
ls -la "$SHIM"

echo "=== 4. test PA against the bound shim ==="
pkill -9 pulseaudio 2>/dev/null; sleep 1
sudo lxc-attach -n android -- logcat -c 2>/dev/null
timeout 30 pulseaudio -n --daemonize=no --file=/etc/pulse/touch.pa > "$WORK/run.log" 2>&1
echo "exit=$?"
echo "--- PA output ---"
grep -nE "Opened hw|Created sink|Created source|error|Segmentation|SIGSEGV|couldn|droid-card|primary" "$WORK/run.log" | head -20
echo "--- HAL logcat ---"
sudo lxc-attach -n android -- logcat -d 2>/dev/null | grep -iE "adev_open|openDevice|primary|error -|loadAudio" | tail -12

echo ""
echo "=== 5. if sinks exist, this is the fix. To UNDO: sudo umount $SHIM ==="
