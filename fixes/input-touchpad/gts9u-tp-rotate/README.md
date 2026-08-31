# gts9u-tp-rotate v0

Folio touchpad orientation shim for Ubuntu Touch on the Galaxy Tab S9 Ultra
(gts9uwifi). Works unmodified on any device whose folio pad enumerates as
`sec_touchpad_pogo` (pass `--device-name` otherwise).

## Why

The pogo touchpad's axes are aligned to the panel's native portrait frame.
Lomiri transforms touchscreen coordinates through the display rotation but
leaves relative pointer motion untouched, so the pad tracks correctly in
portrait and rotated 90 degrees in landscape. There is no compositor or
libinput knob for per-device pointer rotation on this stack.

## How

The daemon EVIOCGRABs the raw pad node (compositor stops seeing it) and
re-emits all events through a uinput clone with a quarter-turn transform.
The clone mirrors the source capabilities generically (read via ioctl at
startup, nothing hardcoded), so classification as a touchpad is preserved.

A quarter-turn swaps the axis ranges, and uinput absinfo is immutable after
creation, so orientation changes tear down and recreate the clone (~100 ms,
rotations are rare). Active contacts and button state are replayed into the
fresh clone. Folio detach/reattach is handled by name-based re-acquisition.

## Transform labels

0/90/180/270 are quarter-turns relative to the pad's NATIVE frame. Which of
90/270 corresponds to Lomiri's landscape is determined empirically via the
validation pass, then pinned in /etc/default/gts9u-tp-rotate as the boot
default. Once a DTS fix makes the driver landscape-native, set it back to 0.

## Operation

    sudo gts9u-tp-rotate              # foreground, identity transform
    gts9u-tp-orient 90|180|270|0      # switch live
    gts9u-tp-orient status            # log state
    sudo gts9u-tp-rotate --check      # full dry run incl. uinput cycle
    sudo systemctl start gts9u-tp-rotate

## Known limits / notes

- v0 is manual: nothing on the session or system bus exposes shell
  orientation, so auto-tracking is deferred (candidate v1 sources:
  wl_output transform via the Wayland socket, sensorfwd + rotation lock).
- The control FIFO is mode 0666: any local user can rotate the pad.
- Axis resolution is 0 on this hardware (libinput default accel behavior);
  the clone preserves that. If pointer feel differs from the raw pad, the
  cause is libinput quirk matching on the new device name - fixable with a
  hwdb entry.
- If events flow (evtest on the clone) but the cursor never moves, Mir is
  not picking up the uinput hotplug - report that, it changes the design.
