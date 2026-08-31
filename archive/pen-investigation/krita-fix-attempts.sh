#!/bin/bash
# ============================================================================
# Krita pressure - the fix attempts (X710)
#
# DIAGNOSIS: pressure streams perfectly from event10 (confirmed 402->2322 ramp).
# Krita HAS event10 open and the evdevtablet plugin var IS set. BUT Krita runs on
# QPA platform 'ubuntumirclient', which feeds Qt tablet input FROM MIR (no pressure).
# Qt honors the platform plugin's tablet events over the generic evdev plugin's, so
# the evdev pressure is read-but-ignored. Also lomiri/Xwayland also hold event10.
#
# GOAL: make the evdevtablet plugin the tablet source Qt actually uses, by running
# Krita on a platform that doesn't inject its own (pressureless) tablet input.
#
# These are LAUNCH COMMANDS to run AS phablet (NOT via this script as root).
# This file is a menu - read it, then run the commands at your phablet prompt.
# Quit any running Krita first (so it re-reads input).
# ============================================================================
cat <<'MENU'
=================================================================
 QUIT any running Krita first. Then try these AS phablet, in order.
 After each, open Krita's Tablet Tester (Settings > Configure Krita >
 Tablet Settings > Open Tablet Tester) and press with varying force.
=================================================================

--- ATTEMPT 1: force the plain wayland platform (not ubuntumirclient) -------------
# ubuntumirclient injects Mir's pressureless tablet input. Plain 'wayland' may not,
# letting the evdevtablet plugin be the tablet source.
QT_QPA_PLATFORM=wayland \
QT_QPA_GENERIC_PLUGINS=evdevtablet:/dev/input/event10 \
QT_WAYLAND_DISABLE_WINDOWDECORATION=1 \
krita 2>&1 | tee /tmp/krita-run.log

# If Krita won't open (black/no window), Ctrl-C and go to Attempt 2.


--- ATTEMPT 2: keep ubuntumirclient BUT disable Qt's high-level tablet from Mir ----
# Tell Qt to treat tablet-as-mouse from the platform, so the evdev plugin's native
# QTabletEvents (with pressure) are the ones Krita sees.
QT_QPA_PLATFORM=ubuntumirclient \
QT_QPA_GENERIC_PLUGINS=evdevtablet:/dev/input/event10 \
QT_XCB_TABLET_LEGACY_COORDINATES=1 \
krita 2>&1 | tee /tmp/krita-run.log


--- ATTEMPT 3: run Krita under XWayland/xcb, which has a real evdev tablet path ----
# xcb + the evdev tablet gives Qt the classic X11 tablet input (pressure works on X).
# Xwayland is already running (it had event10 open), so this may route pressure.
QT_QPA_PLATFORM=xcb \
QT_QPA_GENERIC_PLUGINS=evdevtablet:/dev/input/event10 \
krita 2>&1 | tee /tmp/krita-run.log


--- ATTEMPT 4: offscreen input test (proves the plugin CAN deliver pressure) -------
# Not for drawing - just to confirm the evdev plugin delivers pressure to Qt when
# the platform isn't competing. If the tester shows pressure here, we KNOW the
# plugin works and the fight is purely platform-input precedence.
QT_QPA_PLATFORM=eglfs \
QT_QPA_GENERIC_PLUGINS=evdevtablet:/dev/input/event10 \
krita 2>&1 | tee /tmp/krita-run.log

=================================================================
 For EACH attempt, tell me: (a) did Krita's window open? (b) does the
 Tablet Tester line vary with pressure? Also send /tmp/krita-run.log
 after whichever one you try - the plugin prints init/errors there.
=================================================================
MENU
