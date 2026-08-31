# gts9pwifi — Tab S9+ (SM-X810)

**Port kit complete, unexecuted.** Everything needed for the first build and
flash exists in this directory; no build has been run and the unit has not
been unlocked. Follow `docs/gts9pwifi-port-runbook.md` end to end — it is the
authoritative procedure (six phases: inputs → skeleton fork → firmware
extraction → unit prep → build → bring-up ladder).

## The unit rule

The tablet is a sealed factory unit at **bootloader binary rev 1** — the
fleet is at rev 6, which is past the unlockability cliff. **It stays offline
and never accepts an OTA.** One accepted update is a one-way door.

## Contents

- `build-gts9pwifi.sh` — V4 build wrapper: a device fork of the Ultra's V3
  (all hardening retained) with the gts9p constants: bare
  `GTS9P_ANA38407_AMSA24VU05:` panel cmdline, STM touch
  (`stm_ts_fts1b90a.ko` build-**fatal** if missing — Samsung's truncated
  spelling is intentional), `SUPER=11714691072` (28 MiB smaller than the
  Ultra — do not inherit the skeleton default).
- `x810-extract.sh` — streams the parts out of the
  `SAMFW.COM_SM-X810_XAR_X810XXU1AWHA_fac.zip` factory image; hard-fails
  unless raw super is byte-exactly 11,714,691,072.
- `imports/` — gts9p OSRC import bundle (GTS9P panel + AWH8 delta, DTS
  r00/r02/r04, merged display Kbuild). Provenance in its `MANIFEST.md`.
- `reference/GTS9PWIFI_EUR_OPEN.pit` — parsed PIT (partition sizes).
- `reference/dts/` — canonical A13/AWG1 dts + the MIRROR identity reference
  (~13% drift — build only from the A13 canonical).
- `docs/gts9p-hw-findings.md` — the hardware evidence base.

## What is still needed

1. Fork the skeleton: `samsung-gts9u → samsung-gts9p` (sed + file renames —
   exact checklist in runbook Phase 1; the gts9u skeleton lives at
   `../gts9uwifi/skeleton/`).
2. The Samsung inputs, kept out of git (`archive/osrc/` holds the two smaller
   OSRC zips; the **base** `SM-X818U_13_Opensource.zip` and the 9.2 GB AWHA
   factory zip must be re-downloaded — sources and sizes in the runbook).
3. Unit prep, build, flash, bring-up ladder (display → touch → WiFi → audio
   → pen). First-boot unknown: panel attach with the bare panel cmdline; the
   pre-planned fix is adding the stock lcd_id args captured in Phase 3.4.

Open variance to watch: whether the Ultra's five-bug audio chain reproduces
identically here (expected: yes; the bringup mechanism is vintage-agnostic).
