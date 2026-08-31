#!/bin/bash
# ============================================================================
# WHY is the pen delivered as TOUCHSCREEN (pressure -1) not TABLET/stylus? (X710)
# The Qt log shows XI2 touch events (Abs MT Position) with pressure -1 - i.e. the
# pen is classified as a multitouch TOUCHSCREEN at the X/XWayland layer, so its
# evdev pressure is flattened. We need it delivered as a tablet STYLUS.
# Run AS phablet: bash /tmp/pen-why-touch.sh 2>&1 | tee /tmp/pen-why-touch.txt
# ============================================================================
OUT=/tmp/pen-why-touch.txt
{
sec(){ echo; echo "===== $* ====="; }
echo "=== why pen = touchscreen not tablet ==="; date -Is
PEN=/dev/input/event10

sec "1. current udev tags on the pen (did the tablet tag actually stick?)"
udevadm info --query=all --name="$PEN" 2>/dev/null | grep -iE 'ID_INPUT|CALIBRATION|PROP'
echo "--- is there STILL a touchscreen masquerade rule lingering?"
ls -la /etc/udev/rules.d/72-gts9wifi-spen.rules 2>/dev/null && cat /etc/udev/rules.d/72-gts9wifi-spen.rules 2>/dev/null || echo "  (no 72-gts9wifi-spen.rules - good)"

sec "2. how does XWayland/X11 classify the pen? (xinput - the authoritative X view)"
if command -v xinput >/dev/null 2>&1; then
  DISPLAY=:0 xinput list 2>/dev/null || xinput list 2>/dev/null
  echo "--- properties of the pen device in X (look for 'Abs Pressure' axis + device type):"
  DISPLAY=:0 xinput list --long 2>/dev/null | grep -A10 -iE 'e-pen|pen|stylus|wacom' | head -30
else
  echo "(xinput not installed - install with: sudo apt install -y xinput)"
fi

sec "3. does the node advertise BTN_TOOL_PEN (stylus) vs BTN_TOUCH (touch)?"
echo "--- libinput/evdev sees which tool bits? (BTN_TOOL_PEN = stylus, must be present)"
if command -v evtest >/dev/null 2>&1; then
  timeout 2 evtest "$PEN" </dev/null 2>&1 | grep -iE 'BTN_TOOL_PEN|BTN_TOOL_RUBBER|BTN_STYLUS|BTN_TOUCH|ABS_PRESSURE|INPUT_PROP' | head
fi
echo "--- input properties (INPUT_PROP_DIRECT / POINTER):"
cat /sys/class/input/$(basename $PEN)/device/properties 2>/dev/null

sec "4. KEY: is the pen ALSO exposing a separate touch vs pen node? (Wacom often splits)"
echo "--- all sec/wacom/pen input nodes and their names:"
for e in /dev/input/event*; do
  n=$(cat /sys/class/input/$(basename $e)/device/name 2>/dev/null)
  echo "$n" | grep -qiE 'pen|wacom|touch|sec_' && echo "  $e: $n"
done

sec "5. what would make X treat it as a tablet: the udev+libinput classification"
echo "--- does libinput classify it as tablet or touchscreen? (quirk in effect?):"
cat /etc/libinput/local-overrides.quirks 2>/dev/null
echo "--- the FUZZ/CALIBRATION env that touchscreen path adds:"
udevadm info --query=all --name="$PEN" 2>/dev/null | grep -iE 'LIBINPUT|CALIBRATION|FUZZ'

echo; echo "=== end ==="
echo "NOTE: if section 1 shows ID_INPUT_TOUCHSCREEN still set, that's the bug."
echo "If section 3 shows BTN_TOOL_PEN present but X still delivers touch, the"
echo "issue is X/XWayland preferring the touch interface - fix is to force the"
echo "device to be tablet-only in X (xinput) or block the touchscreen classification."
} 2>&1 | tee "$OUT"
