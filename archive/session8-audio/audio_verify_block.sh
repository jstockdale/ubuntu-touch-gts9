#!/bin/bash
# Meticulous Path A verification - run on device
{
echo "===== PART 1: does the shim actually call legacy openDevice(string)? ====="
echo "--- full disasm of shim around create() @0x2098 and the open call site ---"
objdump -dC /android/system/lib64/hw/audio.hidl_compat.default.so 2>/dev/null | sed -n '/2098:/,/21a0:/p' | head -50
echo ""
echo "--- what openDevice symbols does the shim import/reference? ---"
objdump -TC /android/system/lib64/hw/audio.hidl_compat.default.so 2>/dev/null | grep -iE "openDevice|DevicesFactory|IDevice" | head
echo ""
echo "--- strings: does the shim know enum-open at all? (openOutputStream/openDevice/DeviceType) ---"
strings -a /android/system/lib64/hw/audio.hidl_compat.default.so | grep -iE "openDevice|openPrimaryDevice|DeviceType|IDevicesFactory|@7\.[01]" | head

echo ""
echo "===== PART 2: which openDevice VARIANT does libaudiohal use here? ====="
echo "--- the shim links libaudiohal; find WHICH openDevice it resolves ---"
for lib in /android/system/lib64/libaudiohal*.so /android/system/lib64/libaudiohal/*.so; do
  [ -e "$lib" ] || continue
  echo "-- $lib --"
  objdump -TC "$lib" 2>/dev/null | grep -iE "openDevice|DevicesFactoryHalHidl|DeviceHalHidl" | head -6
done

echo ""
echo "===== PART 3: DIRECT HAL TEST - does Samsung's 7.1 factory accept enum-open? ====="
echo "--- is there a test tool already in the container? ---"
sudo lxc-attach -n android -- /system/bin/sh -c 'ls /system/bin/ | grep -iE "audio.*test|test.*audio|hidl.*test"' 2>/dev/null | head
echo "--- what does the factory expose? probe via vendor's own service ---"
sudo lxc-attach -n android -- /system/bin/sh -c 'dumpsys android.hardware.audio@7.1::IDevicesFactory/default 2>/dev/null | head -20' 2>/dev/null
echo "--- the SMOKING GUN: enable HAL-side verbose logging, retrigger, capture the EXACT failing call ---"
sudo lxc-attach -n android -- /system/bin/sh -c 'setprop log.tag.DevicesFactoryHAL V; setprop log.tag.AudioHAL V; setprop log.tag.HidlServiceManagement V' 2>/dev/null
echo "logging enabled - now retrigger PA and capture:"
pkill -9 pulseaudio 2>/dev/null; sleep 1
sudo lxc-attach -n android -- logcat -c 2>/dev/null
timeout 15 pulseaudio -n --daemonize=no --file=/etc/pulse/gts9/audio_policy_configuration.xml >/dev/null 2>&1 &
PA=$!
timeout 12 pulseaudio -n --daemonize=no --file=/etc/pulse/touch.pa >/tmp/pv.log 2>&1
sleep 1
echo "--- HAL-side logcat during the crash (the -19 with full context) ---"
sudo lxc-attach -n android -- logcat -d 2>/dev/null | grep -iE "DevicesFactory|audiohal|openDevice|primary|loadAudioInterface|dlopen|cannot|couldn|library" | tail -25
kill $PA 2>/dev/null

echo ""
echo "===== PART 4: WHY does audio.primary.kalama.so fail? (absolute-path linker test) ====="
sudo lxc-attach -n android -- /system/bin/sh -c 'linker64 --list /vendor/lib64/hw/audio.primary.kalama.so 2>&1' 2>/dev/null | head -20
echo "--- its NEEDED libs, and which are missing from the namespace ---"
sudo lxc-attach -n android -- /system/bin/sh -c 'for l in $(objdump -p /vendor/lib64/hw/audio.primary.kalama.so 2>/dev/null | awk "/NEEDED/{print \$2}"); do f=$(find /vendor/lib64 /system/lib64 /odm/lib64 -name "$l" 2>/dev/null | head -1); [ -z "$f" ] && echo "MISSING: $l" || true; done' 2>/dev/null
echo "(no MISSING lines above = all deps present, failure is elsewhere)"
} 2>&1
