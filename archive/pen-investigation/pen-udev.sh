#!/bin/bash
# ============================================================================
# S-Pen: make Mir track the pen as a direct pointer (X710)
#
# FINDINGS (from pen-mir.txt):
#  - Mir DOES enumerate sec_e-pen (event10), classifies it Button|TouchScreen|Switch.
#  - But udev tags it ID_INPUT_TABLET=1 and does NOT set ID_INPUT_TOUCHSCREEN,
#    so libinput treats it as a (non-direct) tablet -> no cursor mapping.
#  - The WORKING touchscreen (event8) has ID_INPUT_TOUCHSCREEN=1 AND a calibration
#    matrix "0 1 0 -1 0 1" (90deg) from 71-gts9wifi-touch-calibration.rules.
#    The pen has NO calibration matrix.
#
# FIX: a udev rule that, for sec_e-pen, sets ID_INPUT_TOUCHSCREEN=1 and applies the
#      SAME calibration matrix as the touchscreen. This makes Mir map it to the
#      screen as a direct pointer (tracks + taps + draws). Trade-off: pressure/tilt
#      are not carried through the touchscreen path - this is a pointer, not a
#      pressure-sensitive tablet. That is what Mir can deliver on this shell.
#
# Reversible: rm the rule file + reboot to undo.
# Usage: sudo bash /tmp/pen-udev.sh              (installs rule, reloads udev)
#        then reboot OR replug logic below; then test the pen on screen.
# Writes /tmp/pen-udev.txt.
# ============================================================================
OUT=/tmp/pen-udev.txt
{
sec(){ echo; echo "===== $* ====="; }
echo "=== S-Pen udev direct-pointer fix ==="; date -Is

sec "1. confirm the touchscreen's calibration matrix (to copy it exactly)"
echo "--- the working touchscreen rule:"
cat /usr/lib/udev/rules.d/71-gts9wifi-touch-calibration.rules 2>/dev/null
echo "--- touchscreen current matrix:"
udevadm info --query=all --name=/dev/input/event8 2>/dev/null | grep -i CALIBRATION

sec "2. write the pen udev rule"
mount -o remount,rw / 2>/dev/null
RULE=/etc/udev/rules.d/72-gts9wifi-spen.rules
cat > "$RULE" <<'EOF'
# Samsung S-Pen (sec_e-pen) on gts9wifi: present as a direct touchscreen so Mir
# maps it to the screen as a pointer, and apply the same calibration matrix as
# the built-in touchscreen (71-gts9wifi-touch-calibration.rules: 0 1 0 -1 0 1).
# Trade-off: pressure/tilt are not exposed via the touchscreen path.
ACTION=="remove", GOTO="spen_end"
KERNEL!="event*", GOTO="spen_end"

# match the S-Pen by its input device name
ATTRS{name}=="sec_e-pen", ENV{ID_INPUT_TOUCHSCREEN}="1", ENV{ID_INPUT_TABLET}="0", ENV{LIBINPUT_CALIBRATION_MATRIX}="0 1 0 -1 0 1"

LABEL="spen_end"
EOF
echo "--- written $RULE:"
cat "$RULE"

sec "3. reload udev rules + re-trigger the pen device"
udevadm control --reload-rules 2>&1
udevadm trigger --name-match=/dev/input/event10 2>&1
sleep 1
echo "--- pen udev tags AFTER reload+trigger (want ID_INPUT_TOUCHSCREEN=1 + CALIBRATION):"
udevadm info --query=all --name=/dev/input/event10 2>/dev/null | grep -iE 'ID_INPUT|CALIBRATION|LIBINPUT'

sec "4. next step"
echo "The rule is installed. For Mir to pick up the new classification, restart the"
echo "session or reboot:"
echo "  sudo -u phablet env XDG_RUNTIME_DIR=/run/user/32011 systemctl --user restart lomiri-full-greeter.service"
echo "  (drops your session - do it at the device, then hover/tap/draw with the pen)"
echo "  -- or a full reboot is the cleanest test."
echo
echo "If the pen tracks but is mirrored/rotated wrong, the calibration matrix needs"
echo "adjusting - report which way it's off and we'll flip the matrix."
echo "To undo entirely: sudo rm $RULE && reboot"
echo; echo "=== end ==="
} 2>&1 | tee "$OUT"
