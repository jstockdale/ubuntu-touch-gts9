#!/bin/bash
# ============================================================================
# Krita pressure fix - RUNNABLE (X710). Run AS phablet:  bash /tmp/krita-xcb.sh
# (NOT sudo - Krita needs your user session to display.)
#
# This ACTUALLY LAUNCHES Krita on the xcb (XWayland) platform with the evdev
# tablet plugin - the most promising pressure path, since Xwayland already has
# the pen open and X11 tablet+evdev is Qt's best-tested pressure route.
#
# It kills any running Krita first, launches, captures the init log, and after
# you close Krita it reports whether the tablet plugin engaged.
# ============================================================================
LOG=/tmp/krita-run.log
echo "=== Krita pressure attempt: xcb + evdev tablet ==="; date -Is

# must be phablet, not root
if [ "$(id -un)" = "root" ]; then
  echo "!! Run as phablet, NOT root (Krita needs your session). Re-run: bash /tmp/krita-xcb.sh"
  exit 1
fi

echo "--- quitting any running Krita so it re-reads input..."
pkill -x krita 2>/dev/null; sleep 2

echo "--- pen node state (want ID_INPUT_TABLET=1):"
udevadm info --query=all --name=/dev/input/event10 2>/dev/null | grep -iE 'ID_INPUT_TABLET|ID_INPUT_TOUCH'

cat <<'BANNER'

############################################################
#  Krita will now launch (xcb/XWayland platform).          #
#  WHEN IT OPENS:                                           #
#   1. Settings > Configure Krita > Tablet Settings         #
#   2. If offered, pick "Linux native tablet support"       #
#   3. Click "Open Tablet Tester"                           #
#   4. Press the pen HARD then SOFT on the tester pad.      #
#   5. Line varies with pressure = SUCCESS. Flat = no.      #
#  THEN CLOSE KRITA to finish this script.                  #
############################################################

BANNER
echo "launching in 3s..."; sleep 3

# Launch on xcb with the evdev tablet plugin. Tee stderr/stdout to the log.
QT_QPA_PLATFORM=xcb \
QT_QPA_GENERIC_PLUGINS=evdevtablet:/dev/input/event10 \
QT_LOGGING_RULES='qt.qpa.input*=true' \
krita 2>&1 | tee "$LOG"

echo
echo "=== Krita closed. Analyzing the log for tablet/pressure init... ==="
echo "--- tablet plugin / evdev / pressure lines:"
grep -iE 'evdev|tablet|pressure|QTabletEvent|proximity|Reading from|/dev/input/event10|Failed to open|permission' "$LOG" 2>/dev/null | head -30
echo
echo "--- did it fall back off xcb? (platform errors):"
grep -iE 'could not (load|connect|find)|xcb.*error|display|platform plugin|Reverting|available platform' "$LOG" 2>/dev/null | head -10
echo
echo ">>> Tell me: (a) did Krita's window open? (b) did the Tablet Tester line"
echo ">>> vary with pressure? Send /tmp/krita-run.log too."
echo "=== end ==="
