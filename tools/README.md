# Tools

Device-agnostic utilities from the porting campaign.

## extract/

- `x910-extract.sh` – carve the six dynamic-partition donor images
  (`parts/`) plus boot/vendor_boot/dtbo/vbmeta/recovery, the PIT, and an
  `info.txt` out of the SM-X910 factory zip. Self-contained.
- `x810-extract.sh` – same for SM-X810 (`SAMFW.COM_SM-X810_XAR_X810XXU1AWHA_fac.zip`);
  needs `simg2img`/`lpunpack`; **hard-fails unless raw super is byte-exactly
  11,714,691,072** so a wrong package cannot poison the geometry.

## boot/

- `capture-boot.sh` – adb snapshotter for crash-looping boots (grabs
  dmesg/journal/props on a timer before the device dies).
- `fix-boot-cmdline.py` – padded in-place `CONFIG_CMDLINE` patch of a built
  boot.img (panel-string retarget without a rebuild).
- `fix-vendor-boot-mode.py` – rewrites `androidboot.mode=charger` → normal in
  vendor_boot bootconfig (recovery tool for the cabled-boot charger-mode trap;
  the durable fix is the container wrapper's bootconfig filter).

## lp/

- `lp_inspect.py` – **read-only** LP (super) metadata inspector.
- `probe-lp-ceiling.ps1` – ⚠ **NOT read-only**: bisects the LP group ceiling
  by *committing* sizes via fastbootd. Only against a device you can restore.

## diagnostics/

- `subsystems-check.sh` – READ-ONLY on-device subsystem sweep for any
  family device: auto-fills the machine-checkable rows of
  `docs/checklists/SUBSYSTEMS.md` (WiFi, BT, sound chain, battery,
  sensors, pen, folio, USB, ...) and prints the remaining manual list plus
  a paste-ready results block. Run after every build/flash round.
- `audio-diag-nb1.sh` – read-only audio triage ladder (H1/H2/H3 hypotheses:
  card state, PA state, extevdev presence) for the 11" no-sound cases.

## dev/

- `verify-flasher-fork.sh` – behavioral test harness for the update-binary
  device check, exercising the REAL script text of both the Ultra original
  and the runbook-forked gts9p variant against a full accept/reject matrix
  (21 scenarios). Run after touching the flasher or the fork recipe; the
  build gates assume its invariants hold.
