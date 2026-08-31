#!/bin/bash
set -u
MOD=/usr/lib/pulse-16.1+dfsg1/modules/libdroid-util-30.so
WORK=/var/tmp/droidfix

echo "=== 1. re-apply the proven patch (bind) ==="
sudo umount "$MOD" 2>/dev/null
[ -f "$WORK/patched.so" ] || { echo "patched.so missing - rerun previous script"; exit 1; }
sudo mount --bind "$WORK/patched.so" "$MOD"
echo "  audio_hw_if count now: $(strings -a "$MOD" | grep -c audio_hw_if) (expect 0)"

echo "=== 2. FULL PA init log - where does it fail NOW, past the open? ==="
pkill -9 pulseaudio 2>/dev/null; sleep 1
sudo lxc-attach -n android -- logcat -c 2>/dev/null
# verbose, capture EVERYTHING after 'Opened hw audio device'
timeout 25 pulseaudio -n -vvvv --daemonize=no --file=/etc/pulse/touch.pa > "$WORK/full.log" 2>&1
echo "  exit=$?"
echo "--- everything from 'Opened hw' onward ---"
awk '/Opened hw audio device/{f=1} f' "$WORK/full.log" | head -40
echo "--- any error/warn/assert in the whole log ---"
grep -nE "error|fail|assert|SIGSEGV|Segmentation|E: |W: .*droid|refus|cannot|unable|No such" "$WORK/full.log" | tail -20

echo "=== 3. HAL side - did it get further than adev_open? ==="
sudo lxc-attach -n android -- logcat -d 2>/dev/null | grep -iE "adev_open|open_output|open_input|primary|stream|error|fail" | tail -15
