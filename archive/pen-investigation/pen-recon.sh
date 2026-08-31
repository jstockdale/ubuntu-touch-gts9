#!/bin/bash
# ============================================================================
# S-Pen reconnaissance for Samsung Galaxy Tab S9 11" (SM-X710 / gts9wifi)
# READ ONLY: no insmod, no force-loads, nothing that can destabilize the device.
# Goal: determine whether the pen driver is present/loaded, whether a digitizer
#       input node exists, and whether there is a load failure (CRC / probe).
# Usage: sudo bash /tmp/pen-recon.sh 2>&1 | tee /tmp/pen-recon.txt
#        then: adb pull /tmp/pen-recon.txt
# ============================================================================
sec(){ echo; echo "===== $* ====="; }
echo "=== S9 11\" (SM-X710) S-Pen reconnaissance (READ ONLY) ==="; date -Is

sec "1. exactly which device / model / codename / build"
getprop ro.product.vendor.device 2>/dev/null
getprop ro.product.vendor.model 2>/dev/null
getprop ro.boot.hardware 2>/dev/null
getprop ro.hardware 2>/dev/null
cat /android/vendor/build.prop 2>/dev/null | grep -iE 'ro.product.*(device|model|name)' | head
echo "--- is this Azkali's image or a custom build? (ubuntu build id / channel):"
cat /etc/ubuntu-build 2>/dev/null; cat /etc/system-image/channel.ini 2>/dev/null | head -8
echo "--- kernel:"; uname -r 2>/dev/null; head -c 160 /proc/version 2>/dev/null; echo

sec "2. is a pen digitizer driver present? (wez01 = Ultra's; may differ here)"
lsmod | grep -iE 'wez|wacom|epen|e_pen|stylus|maxim|w90|w91' || echo "(no obvious pen module loaded)"
echo "--- pen .ko files on disk (any name):"
find /android/vendor_dlkm/lib/modules /android/vendor/lib/modules -iname '*wez*' -o -iname '*wacom*' -o -iname '*epen*' 2>/dev/null | head
echo "--- ALL vendor_dlkm modules whose modinfo mentions pen/wacom/digitizer:"
for m in /android/vendor_dlkm/lib/modules/*.ko; do
  modinfo "$m" 2>/dev/null | grep -qiE 'wacom|e-pen|epen|stylus|digitizer' && echo "  $(basename "$m")"
done 2>/dev/null | head

sec "3. input devices currently present - any pen/digitizer node?"
echo "--- /proc/bus/input/devices (pen-related entries, hall excluded):"
grep -B2 -A5 -iE 'wacom|e-pen|epen|pen|stylus|digitizer' /proc/bus/input/devices 2>/dev/null | grep -v -i 'hall' | head -40
echo "--- all event devices + names:"
for e in /dev/input/event*; do
  n=$(cat /sys/class/input/$(basename "$e")/device/name 2>/dev/null)
  echo "  $e: $n"
done 2>/dev/null | head -20

sec "4. i2c/spi - is the digitizer chip on the bus (even if driver not bound)?"
echo "--- i2c devices (wacom/epen chips often at addr 0x53/0x56):"
for i in /sys/bus/i2c/devices/*; do
  n=$(cat "$i/name" 2>/dev/null); echo "  $(basename "$i"): $n"
done 2>/dev/null | grep -iE 'wacom|pen|w90|w91|digitizer|0053|0056|-0056|-0053' | head
echo "--- pen-related DT nodes:"
find /sys/firmware/devicetree -iname '*pen*' -o -iname '*wacom*' 2>/dev/null | head
echo "--- i2c drivers bound for pen:"
ls /sys/bus/i2c/drivers/ 2>/dev/null | grep -iE 'wacom|pen|epen'

sec "5. dmesg - what did the pen driver do (or fail to do)?"
sudo dmesg 2>/dev/null | grep -iE 'wacom|e-pen|epen|w90[0-9]|w91[0-9]|stylus|digitizer|sec_epen' | head -25

sec "6. garage/insertion switch + hall sensor (pen detect)"
grep -B1 -A4 -iE 'hall|pen_?insert|SW_PEN' /proc/bus/input/devices 2>/dev/null | head -15
sudo dmesg 2>/dev/null | grep -iE 'pen.*insert|SW_PEN|garage|hall.*pen' | head -6

sec "7. failure-signature check (did the Ultra's CRC/probe issue happen here too?)"
echo "--- module load failures for pen-related modules:"
sudo dmesg 2>/dev/null | grep -iE 'Invalid parameters|disagrees about version|Unknown symbol in|probe.*failed.*-[0-9]' | grep -iE 'wez|wacom|epen|pen' | head
echo "--- existing libinput quirk (if any):"
cat /etc/libinput/local-overrides.quirks 2>/dev/null || echo "(no local-overrides.quirks yet)"
echo "--- does libinput see any tablet/pen device already?"
command -v libinput >/dev/null 2>&1 && libinput list-devices 2>/dev/null | grep -B1 -A3 -iE 'pen|tablet|stylus' | head -20 || echo "(libinput-tools not installed - not required)"

sec "8. session/compositor unit (for the eventual quirk-apply step)"
sudo -u phablet env XDG_RUNTIME_DIR=/run/user/32011 systemctl --user list-units 2>/dev/null | grep -iE 'lomiri|greeter|mir|unity' | head

echo; echo "=== end ==="
