#!/bin/bash
# The -19 module name "audio_hw_if" originates in libdroid-util (host side),
# passed through the shim to Samsung's adev_open. Patch it there.
# Use a DIFFERENT work dir not under /tmp (which is bind-visible), and verify
# the copy is genuinely separate before patching.
set -u
MOD=/usr/lib/pulse-16.1+dfsg1/modules/libdroid-util-30.so
WORK=/var/tmp/droidfix          # /var/tmp, not /tmp
mkdir -p "$WORK"

echo "=== 0. clean any stale self-bind on the shim (from prior run) ==="
sudo umount /android/system/lib64/hw/audio.hidl_compat.default.so 2>/dev/null && echo "removed stale shim bind" || echo "(no shim bind (fine))"

echo "=== 1. exact string layout in libdroid-util ==="
strings -a -t x "$MOD" | grep -nE "audio_hw_if|audio_hw_primary|\bprimary\b" | head
echo "-- NUL-terminated audio_hw_if present? --"
python3 - "$MOD" <<'EOF'
import sys,pathlib
b=pathlib.Path(sys.argv[1]).read_bytes()
for probe in [b"audio_hw_if\x00", b"audio_hw_if"]:
    print(f"  {probe!r}: {b.count(probe)}")
# show bytes around it
i=b.find(b"audio_hw_if")
if i>=0: print("  context:", b[i-4:i+20])
EOF

echo "=== 2. copy to /var/tmp and CONFIRM it's a separate inode ==="
cp "$MOD" "$WORK/patched.so"
echo "  orig:  $(stat -c '%i %n' "$MOD")"
echo "  copy:  $(stat -c '%i %n' "$WORK/patched.so")"
[ "$(stat -c %i "$MOD")" = "$(stat -c %i "$WORK/patched.so")" ] && { echo "  ERROR: same inode, abort"; exit 1; }

echo "=== 3. patch the copy: audio_hw_if -> primary (NUL-padded, same length) ==="
python3 - "$WORK/patched.so" <<'EOF'
import sys,pathlib
f=pathlib.Path(sys.argv[1]); b=f.read_bytes()
old=b"audio_hw_if\x00"; new=b"primary\x00\x00\x00\x00\x00"
assert len(old)==len(new)==12
n=b.count(old)
print(f"  audio_hw_if\\0 count: {n}")
if n==0: sys.exit("  no NUL-term audio_hw_if in libdroid-util either - STOP, need deeper look")
nb=b.replace(old,new,n); assert len(nb)==len(b)
f.write_bytes(nb)
assert b"audio_hw_if\x00" not in nb
print(f"  patched {n}, size {len(b)} unchanged, verified")
EOF
[ $? -ne 0 ] && exit 1

echo "=== 4. bind patched copy over the real module ==="
sudo mount --bind "$WORK/patched.so" "$MOD" && echo "  bound" || { echo "  bind failed"; exit 1; }
# confirm the bind actually changed the content the loader sees
echo "  post-bind audio_hw_if count: $(strings -a "$MOD" | grep -c audio_hw_if)  (expect 0)"

echo "=== 5. test PA ==="
pkill -9 pulseaudio 2>/dev/null; sleep 1
sudo lxc-attach -n android -- logcat -c 2>/dev/null
timeout 30 pulseaudio -n --daemonize=no --file=/etc/pulse/touch.pa > "$WORK/run.log" 2>&1
echo "  exit=$?"
echo "--- PA ---"; grep -nE "Opened hw|Created sink|Created source|error|Segmentation|droid-card|primary|init.*fail" "$WORK/run.log" | head
echo "--- HAL ---"; sudo lxc-attach -n android -- logcat -d 2>/dev/null | grep -iE "adev_open|openDevice|error -|primary" | tail -8

echo "=== UNDO: sudo umount $MOD ==="
