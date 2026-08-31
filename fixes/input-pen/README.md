# S-Pen (Wacom WEZ01)

There is no standalone installer here — the shipped S-Pen support lives in the
gts9uwifi skeleton overlay:

- `61-gts9u-pen.rules` udev rule + libinput quirk — presents the pen as a
  touchscreen (`ID_INPUT_TOUCHSCREEN=1`, `+INPUT_PROP_DIRECT`, tool buttons
  stripped) so it works as a pointer under Mir 1.8.
- finit force-load of `wez01.ko` (stage-2 curated loader) on builds where the
  stock module CRC-diverges; a source-built wez01 makes this unnecessary.

Reference docs:

- `docs/knowledge/gts9-spen-porting-guide.md` — the family porting guide
  (kernel wiring, firmware, udev, quirks).
- `docs/status-archive/SPEN-PLAN.md`, `spen-gts9wifi-notes.md` — dated plans.

Hard ceiling: **pressure/tilt cannot reach apps on Mir 1.8.3** (no
zwp_tablet_v2). Platform-gated on UT's Mir 2.x / Qt6 migration. Full evidence
trail: `archive/pen-investigation/` and PORT-STATE.md §6 #15.
