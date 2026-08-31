#!/bin/bash
set -u
WORK=/var/tmp/droidfix; mkdir -p "$WORK"
MODDIR=/usr/lib/pulse-16.1+dfsg1/modules

echo "=== 0. patch ALL THREE generation libs (string fix) + bind each ==="
for g in 30 29 28; do
  M="$MODDIR/libdroid-util-$g.so"
  [ -f "$M" ] || continue
  sudo umount "$M" 2>/dev/null
  cp "$M" "$WORK/util-$g.so"
  python3 - "$WORK/util-$g.so" <<EOF
import pathlib
f=pathlib.Path("$WORK/util-$g.so"); b=f.read_bytes()
old=b"audio_hw_if\x00"; new=b"primary\x00\x00\x00\x00\x00"
n=b.count(old)
if n: 
    f.write_bytes(b.replace(old,new,n)); print(f"  gen $g: patched {n}")
else: print(f"  gen $g: no audio_hw_if (count 0)")
EOF
  sudo mount --bind "$WORK/util-$g.so" "$M"
done

echo ""
echo "=== 1. what version-gate strings does droid-util-30 have? (why EINVAL after open) ==="
strings -a "$MODDIR/libdroid-util-30.so" | grep -iE "version|api|unsupported|init_check|common\.|too (old|new)|hw module %|not support" | head -15

echo ""
echo "=== 2. try each generation WITH the string patch + config ==="
for g in 30 29 28; do
  echo "--- gen $g + gts9 config ---"
  sed "s|module-droid-card-30|module-droid-card-$g|g; s|module-droid-glue-30|module-droid-glue-$g|g" /etc/pulse/touch.pa > "$WORK/g$g.pa"
  pkill -9 pulseaudio 2>/dev/null; sleep 1
  timeout 18 pulseaudio -n -vv --daemonize=no --file="$WORK/g$g.pa" > "$WORK/g$g.log" 2>&1
  grep -nE "Created sink|Failed to open audio|Droid hw module|Invalid argument|error [0-9]|init.*fail" "$WORK/g$g.log" | grep -vE "fake.sco" | head -5
done

echo ""
echo "=== 3. HAL log from the LAST attempt: what does it say after adev_open now? ==="
sudo lxc-attach -n android -- logcat -d -v brief 2>/dev/null | grep -iE "audio_hw_primary|adev|init_check|invalid|EINVAL|version|not support" | tail -12

echo ""
echo "=== undo all: for g in 30 29 28; do sudo umount $MODDIR/libdroid-util-\$g.so; done ==="
