#!/bin/bash
# ============================================================================
# S-Pen: libinput classification check (X710)
# Digitizer is CONFIRMED working (full ABS axes, live values). Quirk is installed.
# Question: does libinput actually APPLY the INPUT_PROP_DIRECT quirk, and how does
# it then classify sec_e-pen? That decides quirk-fix vs Lomiri-compositor-gap.
# Usage: sudo bash /tmp/pen-li.sh 2>&1 | tee /tmp/pen-li.txt
# ============================================================================
sec(){ echo; echo "===== $* ====="; }
echo "=== libinput classification of sec_e-pen ==="; date -Is
EVN=$(awk -v RS= '/Name=.*sec_e-pen/ {match($0,/event[0-9]+/); print substr($0,RSTART,RLENGTH)}' /proc/bus/input/devices | head -1)
echo "node: /dev/input/${EVN}"

sec "1. ensure libinput-tools (try hard - we need it now)"
if ! command -v libinput >/dev/null 2>&1; then
  mount -o remount,rw / 2>/dev/null
  # clear space if apt complains, then try install
  apt-get install -y -qq libinput-tools 2>&1 | tail -3
fi
command -v libinput >/dev/null 2>&1 && echo "libinput: OK" || { echo "libinput STILL unavailable"; df -h / | tail -1; }

sec "2. DOES the quirk apply? (the decisive line)"
if command -v libinput >/dev/null 2>&1; then
  echo "--- libinput quirks list /dev/input/$EVN :"
  libinput quirks list "/dev/input/$EVN" 2>&1
  echo ""
  echo "--- expected: a line showing AttrInputProp / INPUT_PROP_DIRECT if the quirk matched"
else
  echo "(no libinput CLI)"
fi

sec "3. how does libinput CLASSIFY the device? (tablet vs external vs keyboard)"
if command -v libinput >/dev/null 2>&1; then
  libinput list-devices 2>/dev/null | awk 'BEGIN{p=0} /Device:/{p=0} /sec_e-pen/{p=1} p{print} /^$/{if(p)exit}' | head -25
fi

sec "4. the quirk file libinput is reading"
echo "--- /etc/libinput/local-overrides.quirks:"
cat /etc/libinput/local-overrides.quirks 2>/dev/null
echo "--- is there a SYSTEM quirks dir that might override/conflict?"
ls /usr/share/libinput/*.quirks 2>/dev/null | head
grep -rl 'sec_e-pen\|Samsung' /usr/share/libinput/ 2>/dev/null | head

sec "5. LIVE libinput events - hover + press the pen NOW (15s)"
if command -v libinput >/dev/null 2>&1; then
  echo "########################################################"
  echo "##  HOVER + PRESS the S-Pen over the screen NOW       ##"
  echo "##  3..."; sleep 1; echo "##  2..."; sleep 1; echo "##  1..."; sleep 1
  echo "########################################################"
  timeout 15 libinput debug-events --device "/dev/input/$EVN" 2>&1 | head -60
  echo "--- TABLET_TOOL_* events with pressure = libinput sees it as a working tool"
  echo "--- POINTER_* or nothing = classification problem"
fi
echo; echo "=== end ==="
