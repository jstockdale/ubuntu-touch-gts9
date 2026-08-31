#!/bin/bash
# ============================================================================
# S-Pen diagnostic - X710, quirk installed but pen still not tracking after restart.
# Goal: determine whether event10 actually emits ABSOLUTE (X/Y/pressure) events on
#       hover, or only key/button events - and whether libinput matches the quirk.
# This is READ ONLY except installing libinput-tools (needed to see libinput's view).
# Usage: sudo bash /tmp/pen-diag.sh 2>&1 | tee /tmp/pen-diag.txt   (interactive - see banner)
# ============================================================================
sec(){ echo; echo "===== $* ====="; }
echo "=== S9 11\" S-Pen diagnostic ==="; date -Is

EVN=$(awk -v RS= '/Name=.*sec_e-pen/ {match($0,/event[0-9]+/); print substr($0,RSTART,RLENGTH)}' /proc/bus/input/devices | head -1)
echo "sec_e-pen node: /dev/input/${EVN:-NOT FOUND}"

sec "1. FULL capability of the node (what axes does it actually report?)"
echo "--- raw /proc/bus/input/devices block for sec_e-pen:"
awk -v RS= '/Name=.*sec_e-pen/' /proc/bus/input/devices
echo "--- decode: does it have EV_ABS (absolute axes) and ABS_X/Y/PRESSURE?"
if command -v evtest >/dev/null 2>&1; then
  # evtest --info style: list supported events without entering capture
  ( echo; timeout 2 evtest "/dev/input/$EVN" </dev/null 2>&1 | sed -n '/Supported events/,/Testing/p' | head -60 ) || true
else
  echo "(evtest not found - unexpected, it was on the Ultra)"
fi

sec "2. sysfs capability bitmasks (definitive - what the kernel exposes)"
SYS=/sys/class/input/$EVN/device
echo "--- capabilities/abs (nonzero = has absolute axes):"
cat "$SYS/capabilities/abs" 2>/dev/null || cat /sys/class/input/$EVN/capabilities/abs 2>/dev/null
echo "--- capabilities/ev:"
cat "$SYS/capabilities/ev" 2>/dev/null || cat /sys/class/input/$EVN/capabilities/ev 2>/dev/null
echo "--- capabilities/key (BTN_TOOL_PEN=0x140, BTN_STYLUS=0x14b would be here):"
cat "$SYS/capabilities/key" 2>/dev/null || cat /sys/class/input/$EVN/capabilities/key 2>/dev/null
echo "--- abs axis ranges if present:"
for ax in "$SYS"/../input*/abs 2>/dev/null; do :; done
ls /sys/class/input/$EVN/device/ 2>/dev/null | head

sec "3. LIVE EVENT CAPTURE - hover + press the pen over the screen NOW"
echo "############################################################"
echo "##  HOVER the S-Pen just above the glass, then PRESS DOWN  ##"
echo "##  and move it around. 15 second window.                 ##"
echo "##  Starting in 3..."; sleep 1; echo "##  2..."; sleep 1; echo "##  1..."; sleep 1
echo "############################################################"
if command -v evtest >/dev/null 2>&1; then
  timeout 15 evtest "/dev/input/$EVN" 2>&1 | grep -E 'Event.*type|ABS_|BTN_|SYN|value' | head -80
else
  echo "no evtest - raw hexdump instead (hover now):"
  timeout 15 head -c 1024 "/dev/input/$EVN" | od -A d -t x1 | head -20
fi
echo "--- did ABS_X / ABS_Y / ABS_PRESSURE values appear above? that = digitizer streaming"
echo "--- if only BTN_ / key events = node isn't reporting coordinates (different problem)"

sec "4. install libinput-tools ONLY if the repo is reachable, to see libinput's classification"
if ! command -v libinput >/dev/null 2>&1; then
  # try, but don't fight it - short timeout
  timeout 40 apt-get install -y -qq libinput-tools 2>&1 | tail -2 || echo "(install skipped/failed - not fatal)"
fi
if command -v libinput >/dev/null 2>&1; then
  echo "--- does libinput apply our quirk to the node?"
  libinput quirks list "/dev/input/$EVN" 2>&1
  echo "--- how does libinput classify the device (tablet? external? keyboard?):"
  libinput list-devices 2>/dev/null | awk '/sec_e-pen/,/^$/' | head -20
else
  echo "(libinput CLI unavailable - rely on evtest result above)"
fi

sec "5. quirk file present?"
cat /etc/libinput/local-overrides.quirks 2>/dev/null
echo; echo "=== end ==="
