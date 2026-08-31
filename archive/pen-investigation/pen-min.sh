#!/bin/bash
# Minimal S-Pen libinput check - X710. No apt install (avoids hangs).
# Writes to /tmp/pen-min.txt AND prints to terminal.
# Run: sudo bash /tmp/pen-min.sh
# Then: adb pull /tmp/pen-min.txt   (or just copy the terminal output)

OUT=/tmp/pen-min.txt
{
echo "=== pen minimal check ==="
date -Is

EVN=$(awk -v RS= '/Name=.*sec_e-pen/ {match($0,/event[0-9]+/); print substr($0,RSTART,RLENGTH)}' /proc/bus/input/devices | head -1)
echo "node: /dev/input/${EVN}"

echo
echo "== 1. is libinput CLI present at all? =="
if command -v libinput >/dev/null 2>&1; then
  echo "libinput: FOUND ($(command -v libinput))"
  echo
  echo "== 2. quirks list (does INPUT_PROP_DIRECT apply?) =="
  libinput quirks list "/dev/input/$EVN" 2>&1
  echo
  echo "== 3. device classification =="
  libinput list-devices 2>&1 | grep -A15 -i 'sec_e-pen' | head -20
else
  echo "libinput: NOT installed"
  echo "(that's why the previous script may have hung trying to apt-get it)"
fi

echo
echo "== 4. quirk file present + readable =="
if [ -r /etc/libinput/local-overrides.quirks ]; then
  cat /etc/libinput/local-overrides.quirks
else
  echo "quirk file MISSING or unreadable at /etc/libinput/local-overrides.quirks"
fi

echo
echo "== 5. is phablet's Lomiri actually reading a pen device? (from its input list) =="
# check what Mir/Lomiri sees via the running greeter's env - lightweight
ls -la /dev/input/event10 2>/dev/null
echo "current node PROP (still 0 means quirk not applied at kernel/libinput layer):"
awk -v RS= '/Name=.*sec_e-pen/' /proc/bus/input/devices | grep PROP

echo
echo "=== end ==="
} 2>&1 | tee "$OUT"
