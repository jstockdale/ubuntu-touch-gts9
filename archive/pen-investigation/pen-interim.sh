#!/bin/bash
# ============================================================================
# S-Pen INTERIM fix (X710, Mir 1.8) - touchscreen masquerade
#
# WHY: This build runs Mir 1.8.3. Tablet-tool pressure support is a Mir 2.x
# feature (confirmed: no zwp_tablet/tablet_tool symbols in the mir1* libs, and
# qtmir classifies the pen as Button|TouchScreen|Switch, never TabletStylus).
# Pressure/tilt are NOT reachable on this compositor version. UBports has the
# Mir 2.x upgrade roadmapped (~Q2 2026, not yet shipped, hybris devices last).
#
# WHAT THIS DOES: tags sec_e-pen as a TOUCHSCREEN (which Mir 1.8 handles well)
# and applies the same calibration matrix as the built-in touchscreen, so the
# pen TRACKS, TAPS, and DRAWS as a direct pointer. Trade-off: no pressure/tilt.
#
# REVERSIBLE: when Mir 2.x lands, `rm` the rule file + the quirk and reboot to
# get back to the pressure-preserving direct-tablet config (which is what Mir 2
# will want). Undo commands printed at the end.
#
# Two phases so you don't lose your session unexpectedly:
#   Phase 1 (default): install rule + calibration, reload udev, verify. No restart.
#   Phase 2 (RESTART=1, AT THE DEVICE): restart Lomiri, then test the pen.
#
# Usage phase 1:  sudo bash /tmp/pen-interim.sh 2>&1 | tee /tmp/pen-interim.txt
# Usage phase 2:  sudo RESTART=1 bash /tmp/pen-interim.sh     (at the device)
# ============================================================================
OUT=/tmp/pen-interim.txt
{
sec(){ echo; echo "===== $* ====="; }
echo "=== S-Pen interim touchscreen-masquerade (Mir 1.8) ==="; date -Is
PEN=/dev/input/event10
TS=/dev/input/event8

sec "1. copy the touchscreen's calibration matrix (so the pen lands correctly)"
CAL=$(udevadm info --query=all --name="$TS" 2>/dev/null | sed -n 's/^E: LIBINPUT_CALIBRATION_MATRIX=//p')
echo "touchscreen calibration matrix: [${CAL:-none found}]"
# fall back to the known gts9wifi value if not readable
[ -z "$CAL" ] && CAL="0 1 0 -1 0 1" && echo "using known gts9wifi matrix: [$CAL]"

sec "2. write the touchscreen-masquerade udev rule"
mount -o remount,rw / 2>/dev/null
RULE=/etc/udev/rules.d/72-gts9wifi-spen.rules
cat > "$RULE" <<EOF
# Samsung S-Pen (sec_e-pen) on gts9wifi - INTERIM Mir 1.8 fix.
# Present as a direct touchscreen so Mir 1.8 maps it to the screen as a pointer
# (tracks/taps/draws). Same calibration matrix as the built-in touchscreen.
# Trade-off: pressure/tilt not exposed. Remove when Mir 2.x arrives.
ACTION=="remove", GOTO="spen_end"
KERNEL!="event*", GOTO="spen_end"
ATTRS{name}=="sec_e-pen", ENV{ID_INPUT_TOUCHSCREEN}="1", ENV{ID_INPUT_TABLET}="0", ENV{LIBINPUT_CALIBRATION_MATRIX}="$CAL"
LABEL="spen_end"
EOF
echo "--- written $RULE:"
cat "$RULE"

sec "3. keep the INPUT_PROP_DIRECT quirk (helps libinput treat it as direct)"
mkdir -p /etc/libinput
cat > /etc/libinput/local-overrides.quirks <<'QUIRK'
[Samsung S-Pen gts9wifi]
MatchName=sec_e-pen
AttrInputProp=+INPUT_PROP_DIRECT
QUIRK
cat /etc/libinput/local-overrides.quirks

sec "4. reload udev + retrigger, confirm the pen is now a TOUCHSCREEN"
udevadm control --reload-rules 2>&1
udevadm trigger --name-match="$PEN" 2>&1
sleep 1
echo "--- pen tags now (want ID_INPUT_TOUCHSCREEN=1, ID_INPUT_TABLET=0, CALIBRATION set):"
udevadm info --query=all --name="$PEN" 2>/dev/null | grep -iE 'ID_INPUT|CALIBRATION|LIBINPUT'

sec "5. PHASE 2 - restart Lomiri (only if RESTART=1)"
if [ "${RESTART:-0}" = "1" ]; then
  echo ">>> restarting lomiri-full-greeter.service - DROPS YOUR SESSION <<<"
  echo ">>> reconnect in ~30s, then TEST: touch pen to screen -> cursor should"
  echo ">>> move to that point; tap -> click; drag -> draw. (No pressure - expected.)"
  sleep 2
  sudo -u phablet env XDG_RUNTIME_DIR=/run/user/32011 systemctl --user restart lomiri-full-greeter.service
else
  echo "Phase 1 done. Review section 4, then run AT THE DEVICE:"
  echo "  sudo RESTART=1 bash /tmp/pen-interim.sh"
  echo "  -- or reboot. Then touch the pen to the screen and test tracking/tap/draw."
fi

sec "6. how to UNDO (when Mir 2.x lands, to restore the pressure-preserving path)"
echo "  sudo rm /etc/udev/rules.d/72-gts9wifi-spen.rules"
echo "  sudo rm /etc/libinput/local-overrides.quirks   # or keep for direct-tablet"
echo "  sudo reboot"
echo "  (then re-apply pen-tablet.sh for the direct-tablet config Mir 2 wants)"
echo; echo "=== end ==="
} 2>&1 | tee "$OUT"
