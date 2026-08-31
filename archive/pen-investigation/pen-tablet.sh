#!/bin/bash
# ============================================================================
# S-Pen Option B: PRESSURE-PRESERVING direct-tablet path (X710)
#
# Goal: keep sec_e-pen classified as a TABLET, add INPUT_PROP_DIRECT so Mir 2.x
#       treats it as a direct (on-screen) tablet tool - preserving pressure/tilt -
#       rather than masquerading it as a touchscreen (which loses pressure).
#
# IMPORTANT: an earlier script (pen-udev.sh) may have written a TOUCHSCREEN rule
# (72-gts9wifi-spen.rules) that flips ID_INPUT_TABLET=0 / ID_INPUT_TOUCHSCREEN=1.
# That fights the direct-tablet path, so step 1 removes it. The libinput quirk
# (/etc/libinput/local-overrides.quirks, AttrInputProp=+INPUT_PROP_DIRECT) is what
# we KEEP - it adds direct-prop without changing the tablet classification.
#
# This script is in TWO PHASES so you don't lose your session unexpectedly:
#   Phase 1 (default): clean up conflicting rule, set the direct-tablet quirk,
#                      verify udev state. Does NOT restart Lomiri. Send output.
#   Phase 2 (RESTART=1, run AT THE DEVICE): restart Lomiri, then you test the pen.
#
# Usage phase 1:  sudo bash /tmp/pen-tablet.sh 2>&1 | tee /tmp/pen-tablet.txt
# Usage phase 2:  sudo RESTART=1 bash /tmp/pen-tablet.sh     (at the device)
# ============================================================================
OUT=/tmp/pen-tablet.txt
{
sec(){ echo; echo "===== $* ====="; }
echo "=== S-Pen Option B: direct-tablet (pressure-preserving) ==="; date -Is
PEN=/dev/input/event10

sec "1. remove the conflicting TOUCHSCREEN masquerade rule if present"
mount -o remount,rw / 2>/dev/null
if [ -f /etc/udev/rules.d/72-gts9wifi-spen.rules ]; then
  echo "found 72-gts9wifi-spen.rules (touchscreen masquerade) - removing it:"
  cat /etc/udev/rules.d/72-gts9wifi-spen.rules
  rm -f /etc/udev/rules.d/72-gts9wifi-spen.rules
  echo "removed."
else
  echo "no touchscreen masquerade rule present - good."
fi

sec "2. ensure the libinput quirk = direct prop, tablet classification UNCHANGED"
mkdir -p /etc/libinput
cat > /etc/libinput/local-overrides.quirks <<'QUIRK'
[Samsung S-Pen gts9wifi]
MatchName=sec_e-pen
AttrInputProp=+INPUT_PROP_DIRECT
QUIRK
echo "--- /etc/libinput/local-overrides.quirks:"
cat /etc/libinput/local-overrides.quirks

sec "3. reload udev + retrigger, then confirm the pen is a DIRECT TABLET (not touchscreen)"
udevadm control --reload-rules 2>&1
udevadm trigger --name-match="$PEN" 2>&1
sleep 1
echo "--- pen udev tags now (want: ID_INPUT_TABLET=1, NOT ID_INPUT_TOUCHSCREEN):"
udevadm info --query=all --name="$PEN" 2>/dev/null | grep -iE 'ID_INPUT|CALIBRATION|LIBINPUT|PROP'

sec "4. does Mir have tablet-tool (zwp_tablet) support compiled in? (evidence check)"
echo "--- Mir / server version:"
dpkg -l 2>/dev/null | grep -iE 'mir|miral|qtmir|lomiri-ui-toolkit' | awk '{print $2, $3}' | head
echo "--- zwp_tablet in the Mir/Wayland libs? (symbol presence = protocol support):"
for so in /usr/lib/*/libmiral.so* /usr/lib/*/mir/**/*.so /usr/lib/*/libmirserver.so* ; do
  [ -e "$so" ] && strings "$so" 2>/dev/null | grep -qiE 'zwp_tablet|tablet_tool|tablet_manager' && echo "  tablet symbols FOUND in $(basename "$so")"
done 2>/dev/null | head
echo "--- (if nothing prints, tablet protocol may not be compiled in - that would be the ceiling)"

sec "5. current classification per Qt/Lomiri (from the greeter log, most recent)"
journalctl -b 2>/dev/null | grep -iE 'Input device added.*sec_e-pen|tablet|stylus' | tail -5

sec "6. PHASE 2 - restart Lomiri (only if RESTART=1)"
if [ "${RESTART:-0}" = "1" ]; then
  echo ">>> restarting lomiri-full-greeter.service - DROPS YOUR SESSION <<<"
  echo ">>> reconnect in ~30s. Then: hover (cursor should track), press + move"
  echo ">>> (draw) and watch if strokes vary with pressure in a drawing app. <<<"
  sleep 2
  sudo -u phablet env XDG_RUNTIME_DIR=/run/user/32011 systemctl --user restart lomiri-full-greeter.service
else
  echo "Phase 1 done. Review the output (esp. sections 3 and 4), then run AT THE DEVICE:"
  echo "  sudo RESTART=1 bash /tmp/pen-tablet.sh"
  echo "  -- or reboot. Then hover / press / draw and report what the pen does."
fi
echo; echo "=== end ==="
} 2>&1 | tee "$OUT"
