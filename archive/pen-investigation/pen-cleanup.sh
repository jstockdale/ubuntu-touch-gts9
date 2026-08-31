#!/bin/bash
# ============================================================================
# Unwind / cleanup after pen-pressure testing (X710)
#
# Current state after testing:
#  - 72-gts9wifi-spen.rules was REMOVED (pen is tablet-tagged, cursor does NOT
#    track the pen right now - neither pressure nor pointer is active).
#  - local-overrides.quirks (INPUT_PROP_DIRECT) still present (harmless leftover).
#  - xinput, krita, krita-data installed via apt.
#
# This script (default) puts the pen back to the WORKING POINTER state
# (touchscreen-masquerade: track/tap/draw, no pressure) and removes the dead-end
# INPUT_PROP_DIRECT quirk. Krita and xinput are LEFT INSTALLED.
#
# Run AS phablet:  sudo bash /tmp/pen-cleanup.sh
#   - default: restore working pointer pen
#   - BARE=1  : instead strip everything to stock (no rule, no quirk) - pen inert
# ============================================================================
sec(){ echo; echo "===== $* ====="; }
echo "=== pen testing cleanup ==="; date -Is
mount -o remount,rw / 2>/dev/null

if [ "${BARE:-0}" = "1" ]; then
  sec "BARE mode: strip to stock (pen will be inert in desktop)"
  rm -f /etc/udev/rules.d/72-gts9wifi-spen.rules 2>/dev/null && echo "removed spen udev rule"
  rm -f /etc/libinput/local-overrides.quirks 2>/dev/null && echo "removed libinput quirk"
  udevadm control --reload-rules 2>&1
  udevadm trigger --name-match=/dev/input/event10 2>&1
  echo "--- pen tags now (stock - should be ID_INPUT_TABLET=1, its native default):"
  udevadm info --query=all --name=/dev/input/event10 2>/dev/null | grep -iE 'ID_INPUT'
  echo "done. Pen is at kernel default (tablet), no rules. Cursor won't track it."
  echo "=== end ==="
  exit 0
fi

sec "1. restore the WORKING POINTER pen (touchscreen masquerade)"
# copy the touchscreen's calibration matrix
CAL=$(udevadm info --query=all --name=/dev/input/event8 2>/dev/null | sed -n 's/^E: LIBINPUT_CALIBRATION_MATRIX=//p')
[ -z "$CAL" ] && CAL="0 1 0 -1 0 1"
RULE=/etc/udev/rules.d/72-gts9wifi-spen.rules
cat > "$RULE" <<EOF
# Samsung S-Pen (sec_e-pen) - working POINTER config (Mir 1.8).
# Presents as touchscreen so the pen tracks/taps/draws as a cursor.
# No pressure (Mir 1.8 has no tablet protocol). Revisit when Mir 2.x lands.
ACTION=="remove", GOTO="spen_end"
KERNEL!="event*", GOTO="spen_end"
ATTRS{name}=="sec_e-pen", ENV{ID_INPUT_TOUCHSCREEN}="1", ENV{ID_INPUT_TABLET}="0", ENV{LIBINPUT_CALIBRATION_MATRIX}="$CAL"
LABEL="spen_end"
EOF
echo "installed $RULE:"
cat "$RULE"

sec "2. remove the dead-end INPUT_PROP_DIRECT quirk (did nothing useful)"
rm -f /etc/libinput/local-overrides.quirks 2>/dev/null && echo "removed local-overrides.quirks" || echo "(quirk already gone)"

sec "3. reload udev + retrigger"
udevadm control --reload-rules 2>&1
udevadm trigger --name-match=/dev/input/event10 2>&1
sleep 1
echo "--- pen tags now (want ID_INPUT_TOUCHSCREEN=1 for pointer tracking):"
udevadm info --query=all --name=/dev/input/event10 2>/dev/null | grep -iE 'ID_INPUT|CALIBRATION'

sec "4. what's LEFT installed (intentionally kept)"
echo "krita:  $(dpkg -l 2>/dev/null | awk '/^ii/ && $2=="krita"{print $3}')  (kept)"
echo "xinput: $(dpkg -l 2>/dev/null | awk '/^ii/ && $2=="xinput"{print $3}')  (kept - tiny, harmless)"
echo "To remove them if you want: sudo apt remove --purge krita krita-data xinput"

sec "5. NOTE - to make the pointer pen persist + take effect now"
echo "The udev rule applies to new device events; to see it now, restart Lomiri"
echo "AT THE DEVICE (drops session) or reboot:"
echo "  sudo -u phablet env XDG_RUNTIME_DIR=/run/user/32011 systemctl --user restart lomiri-full-greeter.service"
echo; echo "=== end ==="
