#!/bin/bash
# ============================================================================
# Pen pressure - the targeted fix (X710)
# FINDINGS: pen is correctly ID_INPUT_TABLET=1 with BTN_TOOL_PEN/STYLUS/PRESSURE.
# BUT kernel property INPUT_PROP_DIRECT is NOT set (properties=0), and the libinput
# quirk that adds it is ignored by XWayland/X11. So under xcb, X doesn't treat it as
# a direct pressure tablet -> events arrive as touch with pressure -1.
#
# This installs xinput, shows exactly how X classifies the pen + whether it has a
# Pressure axis, and tries to make X treat it as a proper tablet.
# Run AS phablet:  bash /tmp/pen-xinput.sh 2>&1 | tee /tmp/pen-xinput.txt
# (uses sudo for the apt install)
# ============================================================================
OUT=/tmp/pen-xinput.txt
{
sec(){ echo; echo "===== $* ====="; }
echo "=== pen pressure: xinput inspection + fix ==="; date -Is
PEN=/dev/input/event10
export DISPLAY=${DISPLAY:-:0}
echo "DISPLAY=$DISPLAY"

sec "1. install xinput (needed to see + control X's device view)"
if ! command -v xinput >/dev/null 2>&1; then
  sudo apt-get install -y -qq xinput 2>&1 | tail -3
fi
command -v xinput >/dev/null 2>&1 && echo "xinput: OK" || echo "xinput install FAILED"

sec "2. how does X see the pen? (device list + is it slave pointer/floating?)"
xinput list 2>&1

sec "3. does the X device have a PRESSURE axis? (the decisive check)"
# find the pen's X device name/id
PID=$(xinput list --name-only 2>/dev/null | grep -iE 'e-pen|pen|stylus' | head -1)
echo "pen X device name: [$PID]"
if [ -n "$PID" ]; then
  echo "--- full properties + valuators for '$PID':"
  xinput list "$PID" 2>&1
  echo "--- device properties:"
  xinput list-props "$PID" 2>&1 | head -40
else
  echo "!! pen not found as a distinct X device - it may be merged into the touchscreen"
  echo "   (that would explain touch-with-no-pressure). Full list above shows what X has."
fi

sec "4. is the pen being delivered via the TOUCHSCREEN device instead of its own?"
echo "--- all X pointer/touch devices:"
xinput list 2>&1 | grep -iE 'touch|pen|stylus|pointer'

sec "5. ATTEMPT: float the pen as its own device + enable it (if X merged/disabled it)"
if [ -n "$PID" ]; then
  echo "--- current enabled state:"
  xinput list-props "$PID" 2>&1 | grep -i 'Device Enabled'
  # ensure enabled
  xinput enable "$PID" 2>&1 && echo "enabled $PID"
fi

echo; echo "=== end ==="
echo "WHAT TO LOOK FOR:"
echo " - Section 3: if the pen device HAS an 'Abs Pressure' valuator/axis, X CAN"
echo "   deliver pressure and the fix is making Krita use THIS device as a tablet."
echo " - If the pen has NO separate X device (merged into touchscreen), or NO"
echo "   pressure axis, then X/XWayland collapsed it to touch - that's the blocker."
} 2>&1 | tee "$OUT"
