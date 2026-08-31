# S-Pen on Tab S9 11" (SM-X710 / gts9wifi) — Findings & Notes

Device: Samsung Galaxy Tab S9 11", SM-X710, gts9wifi (Azkali's reference device).
Build: Ubuntu Touch 24.04-2.x, Mir 1.8.3, Lomiri, kernel 5.15.153.

## Hardware / driver: FULLY WORKING (no fix needed)
- `wez01.ko` loads clean at boot — NO CRC/force-load issue (unlike the Ultra).
- Digitizer node: `sec_e-pen` at `/dev/input/event10`, chip `w90xx` on i2c-58/58-0056,
  driver `wacom_w90xx` bound.
- Full evdev capability confirmed with LIVE values: ABS_X 0–14752, ABS_Y 0–23603,
  ABS_PRESSURE 0–4095, ABS_DISTANCE 0–255, ABS_TILT_X/Y ±63, BTN_TOOL_PEN,
  BTN_TOOL_RUBBER (eraser), BTN_TOUCH, BTN_STYLUS, SW_PEN_INSERTED.
- Pressure ramp captured cleanly at the evdev layer (402→2322 as pressed harder).
  THE HARDWARE PRESSURE IS PERFECT. The problem is purely software delivery.
- Separate nodes: event10 sec_e-pen, event4 hall_wacom, event8 sec_touchscreen,
  event9 sec_touchpad. Pen has its own node (not physically merged with touch).

## POINTER (no pressure): WORKS via touchscreen-masquerade
- The pen reports PROP=0 (no INPUT_PROP_DIRECT), so libinput/Mir treat it as a
  non-direct tablet and Lomiri won't map it to the screen.
- Fix that WORKS for pointer use: a udev rule tagging sec_e-pen as a TOUCHSCREEN
  (ID_INPUT_TOUCHSCREEN=1, ID_INPUT_TABLET=0) + the same calibration matrix as the
  built-in touchscreen (0 1 0 -1 0 1, from 71-gts9wifi-touch-calibration.rules).
  File: /etc/udev/rules.d/72-gts9wifi-spen.rules  (see pen-cleanup.sh / pen-interim.sh)
  Result: pen tracks / taps / draws as a cursor. NO pressure/tilt.
- NOTE: udev retrigger does NOT reclassify a device Lomiri already holds — needs a
  Lomiri restart or reboot to take effect. (A running session keeps its boot-time
  classification, which is why the pen may still "work as pointer" after you change
  the tag, until you reboot.)

## PRESSURE: BLOCKED on this build — root cause is Mir 1.8 (confirmed)
Traced exhaustively. The pen's pressure reaches the app's PROCESS (Krita had
event10 open, evdev plugin loaded) but NO input path delivers it as stylus pressure:
- Lomiri/Mir path (ubuntumirclient QPA): proximity/hover only, pressure stripped.
- xcb / XWayland path: pen delivered as `xwayland-touch` MULTITOUCH device, events
  arrive as `Abs MT Position ... pressure -1`. `xinput list` shows NO tablet device
  at all — only pointer/touch/keyboard abstractions.
- ROOT CAUSE: Mir 1.8 does NOT implement the Wayland tablet protocol (zwp_tablet_v2).
  XWayland can only re-expose what Mir provides (pointer/touch/keyboard), so there is
  no tablet device for X apps to read pressure from. Every app-facing path
  (Mir→Qt, Mir→XWayland→X) can only carry touch-without-pressure.
- The INPUT_PROP_DIRECT libinput quirk does NOT help: libinput quirks don't rewrite
  the kernel property and XWayland/X11 don't read them.
- CONCLUSION: native pressure-sensitive drawing is NOT achievable on this UT build.
  It should become possible when the UBports Mir 2.x upgrade lands (roadmapped ~Q2
  2026, NOT yet shipped; hybris devices move last). The direct-tablet udev tagging
  (ID_INPUT_TABLET=1) is what Mir 2.x will want — that config is the right one to
  restore when Mir 2 arrives.

## !!! HAZARD: do NOT `apt install krita` (or heavy desktop apps) into the UT rootfs
- `apt install krita` pulled in DESKTOP/full-OpenGL Qt as a dependency. UT on this
  hybris device runs entirely on GLES (libhybris → Android GPU stack, no desktop GL).
  The desktop-GL Qt shadowed/replaced the GLES Qt that Lomiri depends on and TOOK
  DOWN THE ENTIRE UI. (Recovered, but painful.)
- LESSON: never install desktop Qt/GL apps directly into the UT rootfs. They fight
  the shell's own GLES Qt libraries.
- CORRECT APPROACH NEXT TIME: install desktop apps in a **Libertine container** — it
  has its own isolated library stack (its own Qt/GL), so desktop-GL deps stay in the
  container and never touch the host rootfs Lomiri needs. Libertine is the designed
  path for desktop apps on UT.
  - Even so: a Libertine Krita runs under XWayland → same Mir 1.8 tablet-protocol
    wall → still likely NO pressure. Libertine protects the UI; it does NOT unlock
    pressure on Mir 1.8.

## Remaining real shot at pressure TODAY: Waydroid + Krita-Android (untested)
- Android reads input via its OWN stack (vendor HAL + InputFlinger), NOT Mir/Wayland.
  Android has mature stylus pressure (MotionEvent.getPressure) — it's how Samsung's
  own S-Pen apps work. Krita-Android consumes it. This BYPASSES the Mir 1.8 wall.
- GATING UNKNOWNS: (1) does Waydroid launch on this X710 build? (notes say Waydroid
  was broken on *Azkali's* image, but this build may differ). (2) does Waydroid's
  input bridge forward the pen with PRESSURE, or flatten it to touch like Mir does?
  (2) is the make-or-break and is not yet answered.
- Status: not yet attempted. Best remaining path to pressure art before Mir 2.x.

## Current device state (as of these notes) — see pen-cleanup.sh
- Krita/xinput installed via apt (Krita risked the UI as above — consider removing,
  or move to Libertine).
- Pen: pointer-via-masquerade is the intended interim state; run pen-cleanup.sh
  (default) to make it persist across reboots. `BARE=1` strips to stock instead.
