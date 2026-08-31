#!/bin/bash
# ============================================================================
# Krita pressure diagnostic (X710) - hover works, pressure doesn't.
# Run this AS phablet, in a SEPARATE terminal, WHILE Krita is open (launched with
# QT_QPA_GENERIC_PLUGINS=evdevtablet:/dev/input/event10) AND while you PRESS the pen.
# Determines: is Mir holding the device? did the evdev plugin init? does pressure
# actually stream from the node right now?
# Usage: bash /tmp/krita-diag.sh 2>&1 | tee /tmp/krita-diag.txt   (some steps use sudo)
# ============================================================================
OUT=/tmp/krita-diag.txt
{
sec(){ echo; echo "===== $* ====="; }
echo "=== Krita pressure diagnostic ==="; date -Is
PEN=/dev/input/event10

sec "1. WHO has the pen node open? (Mir/lomiri vs krita - contention check)"
sudo fuser -v "$PEN" 2>&1
echo "--- processes with event10 open (via /proc fd scan):"
for pid in $(ls /proc | grep -E '^[0-9]+$'); do
  if ls -l /proc/$pid/fd 2>/dev/null | grep -q "$PEN"; then
    echo "  pid $pid: $(cat /proc/$pid/comm 2>/dev/null)"
  fi
done 2>/dev/null

sec "2. is the device EVIOCGRAB'd (exclusive) by someone? (that starves the plugin)"
echo "--- if lomiri/mir grabbed it exclusively, Qt's plugin gets nothing:"
# a grabbed device shows up differently; check if we can even read it
timeout 2 sudo cat "$PEN" >/dev/null 2>&1 && echo "  node is readable by another opener (not exclusively grabbed)" || echo "  node read blocked/empty in 2s"

sec "3. DOES pressure stream from the node RIGHT NOW? (press the pen during this!)"
echo "############################################################"
echo "##  PRESS the S-Pen HARD against the screen NOW, 8 sec    ##"
echo "##  3.."; sleep 1; echo "##  2.."; sleep 1; echo "##  1.."; sleep 1
echo "############################################################"
if command -v evtest >/dev/null 2>&1; then
  timeout 8 sudo evtest "$PEN" 2>&1 | grep -E 'ABS_PRESSURE|ABS_DISTANCE|BTN_TOUCH' | head -30
else
  timeout 8 sudo cat "$PEN" | od -A n -t x1 | head -10
fi
echo "--- if ABS_PRESSURE values appear here, the HW pressure is fine and the issue"
echo "    is purely Krita/Qt not receiving it (contention or wrong path)."

sec "4. did Krita's evdev-tablet plugin actually initialize?"
echo "--- from the krita run log (if you teed it):"
grep -iE 'evdevtablet|QEvdevTablet|tablet.*device|Reading from|/dev/input/event10|Failed|pressure' /tmp/krita-run.log 2>/dev/null | head -20
echo "--- krita process + its env (confirm the plugin var is actually set on it):"
KPID=$(pgrep -x krita | head -1); echo "krita pid: ${KPID:-not running}"
if [ -n "$KPID" ]; then
  tr '\0' '\n' < /proc/$KPID/environ 2>/dev/null | grep -iE 'QT_QPA_GENERIC|QT_QPA_PLATFORM|EVDEV|TABLET'
  echo "--- does krita have event10 open?"
  ls -l /proc/$KPID/fd 2>/dev/null | grep -q event10 && echo "  YES krita has event10 open" || echo "  NO krita does NOT have event10 open (plugin didn't grab it)"
fi

sec "5. what input devices does Qt/evdev see? (plugin discovery)"
echo "--- Qt evdevtablet reads uevent; confirm the node advertises tablet caps:"
udevadm info --query=all --name="$PEN" 2>/dev/null | grep -iE 'ID_INPUT|ABS'
echo; echo "=== end ==="
} 2>&1 | tee "$OUT"
