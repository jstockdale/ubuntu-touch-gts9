# gts9uwifi — Tab S9 Ultra (SM-X910)

The lead port. First light 2026-08-04; first sound 2026-08-08; now ~fully
working. Full status: `docs/knowledge/PORT-STATE.md` §1.

**Works:** display (2960×1848@120, cont-splash), GPU (Adreno 740v2, full
hybris EGL), touch (Goodix berlin), WiFi (kiwi_v2), Bluetooth, battery +
charging (SM5714 finit-load), folio keyboard, **audio** (five-bug chain
solved — see `docs/knowledge/gts9-audio-knowledge-transfer.md`), S-Pen
digitizer (full pressure at evdev), Lomiri + Settings.

**Partial:** S-Pen is pointer-only in apps (Mir 1.8 has no zwp_tablet_v2 —
platform-gated); folio touchpad rotation daemon is baked in the skeleton
(default 270) but scroll is broken in Morph and pinch is dead (upstream
Mir/qtmir); root ships at 7600M with the LP group at capacity since
2026-08-30 (rebuilds no longer regress the on-device resize).

**Open:** sensors HAL (no auto-rotate), cameras untested, USB-C host dead,
UDFPS untested. Ledger: PORT-STATE.md §6.

## Contents

- `build-gts9uwifi.sh` — canonical build wrapper (**V3**, the audio-gate
  version). Stages
  skeleton + imports + firmware parts, clones Azkali's kernel, builds
  kernel/techpacks, swaps vendor_dlkm modules, assembles super at the
  PIT-exact 11,744,051,200, packages the flashable zip.
- `skeleton/` — the `samsung-gts9u` device repo: the canonical audio-era
  superset PLUS the 2026-08-30 parity fixes (WiFi persistence, tp-rotate
  baked @270, apt pin, LimitNOFILE, GROUP=audio, F5 prune, 7600M root,
  merged v3 scripts, v5 flasher — see "Build-system state" below; the
  superseded v3 flasher is `archive/superseded/update-binary-v3`).
- `imports/` — the SM-X910 OSRC import bundle (GTS9U panel driver, goodix
  berlin touch, gts9uwifi r00/r03 DTS, wacom wiring). See its
  `IMPORT-GUIDE.md`.
- `docs/CHANGES-audio.md` — what the audio-era skeleton changed and why.

## Build

```
SKEL=$PWD/skeleton IMPORTS=$PWD/imports SRC_PARTS=~/out-x910/parts \
  ./build-gts9uwifi.sh
```

Firmware donor parts come from `tools/extract/x910-extract.sh` against the
**X910XXS5CYG1** factory zip — the exact vintage matters, see
[FIRMWARE.md](../../FIRMWARE.md). If a stale pre-audio `samsung-gts9u/` sits in the
workdir the script fails fast — remove it and rerun.

## Flash

TWRP: full backup incl. EFS first → Install the built zip from /data →
`twrp reboot system`. Never touch the dtbo partition. First boot after a cold
flash: boot **unplugged** (ABL stamps charger-mode on cabled boots; the
container wrapper filters it, but belt-and-braces on the very first boot).

## Build-system state (2026-08-30 parity remediation)

The former swap-script split is RESOLVED: `scripts/swap-vendor-modules.sh`
is the merged v3 (modules.load dedupe + LEFTOVER/UNLANDED audit; identical
content in `common/scripts/`). The audit runs report-only until you triage
the LEFTOVER list of a build into `scripts/swap-allowlist.txt` (template
beside it). `super.sh` v3 sets the LP group ceiling at super capacity and
the root ships at 7600M (deviceinfo) — **rebuilding no longer regresses the
on-device root resize**. `make-flashable.sh` is the strict v2.
`flashable/.../update-binary` carries the v5 sed-safe device check (verified
by fork simulation) on top of the v4 flash-safety mechanics; the device-check
rewrite has not yet been exercised on a physical flash — eyeball its output
on the next TWRP install.
