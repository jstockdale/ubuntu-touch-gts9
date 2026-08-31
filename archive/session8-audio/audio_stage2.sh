#!/bin/bash
set -u
MOD=/usr/lib/pulse-16.1+dfsg1/modules/libdroid-util-30.so
WORK=/var/tmp/droidfix
sudo umount "$MOD" 2>/dev/null; sudo mount --bind "$WORK/patched.so" "$MOD"

echo "=== 1. the EXACT droid-util lines around the failure (context, not just the error) ==="
pkill -9 pulseaudio 2>/dev/null; sleep 1
sudo lxc-attach -n android -- logcat -c 2>/dev/null
timeout 20 pulseaudio -n -vvvv --daemonize=no --file=/etc/pulse/touch.pa > "$WORK/s2.log" 2>&1
echo "--- 15 lines BEFORE the 'Failed to open audio hw device' ---"
grep -n "Failed to open audio hw device" "$WORK/s2.log" | head -1
L=$(grep -n "Failed to open audio hw device" "$WORK/s2.log" | head -1 | cut -d: -f1)
[ -n "$L" ] && sed -n "$((L>20?L-20:1)),$((L+2))p" "$WORK/s2.log"

echo ""
echo "=== 2. does droid-util log the module_id / hidl path it's using? ==="
grep -nE "hidl|module_id|hw module|Loaded hw|Opened hw|api|version|profile|flags|output" "$WORK/s2.log" | head -20

echo ""
echo "=== 3. HAL side: full verbose around the open (adev_open + what comes right after) ==="
sudo lxc-attach -n android -- logcat -d -v brief 2>/dev/null | grep -iE "audio_hw_primary|adev|open_output|open_input|check|invalid|EINVAL|param|config|stream" | tail -25

echo ""
echo "=== 4. KEY TEST: is it the config= path? try WITHOUT explicit config (let HAL/droid autodetect) ==="
sed 's| config=/etc/pulse/gts9/audio_policy_configuration.xml||' /etc/pulse/touch.pa > "$WORK/noconfig.pa"
pkill -9 pulseaudio 2>/dev/null; sleep 1
timeout 20 pulseaudio -n -vv --daemonize=no --file="$WORK/noconfig.pa" > "$WORK/noconfig.log" 2>&1
echo "  no-config result:"
grep -nE "Opened hw|Created sink|Failed to open|error|droid-card.*fail" "$WORK/noconfig.log" | head -6

echo ""
echo "=== 5. also try: module_id=primary instead of hidl_compat ==="
sed 's|module_id=hidl_compat|module_id=primary|' /etc/pulse/touch.pa > "$WORK/primid.pa"
pkill -9 pulseaudio 2>/dev/null; sleep 1
timeout 20 pulseaudio -n -vv --daemonize=no --file="$WORK/primid.pa" > "$WORK/primid.log" 2>&1
echo "  module_id=primary result:"
grep -nE "Opened hw|Created sink|Failed to open|error|droid-card.*fail" "$WORK/primid.log" | head -6
echo ""
echo "=== patch still bound. UNDO later: sudo umount $MOD ==="
