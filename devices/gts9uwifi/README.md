# gts9uwifi — Tab S9 Ultra (SM-X910)

The lead port. First light 2026-08-04; first sound 2026-08-08; now ~fully
working. Full status: `docs/knowledge/PORT-STATE.md` §1.

**Works:** display (2960×1848@120, cont-splash), GPU (Adreno 740v2, full
hybris EGL), touch (Goodix berlin), WiFi (kiwi_v2), Bluetooth, battery +
charging (SM5714 finit-load), folio keyboard, **audio** (five-bug chain
solved — see `docs/knowledge/gts9-audio-knowledge-transfer.md`), S-Pen
digitizer (full pressure at evdev), Lomiri + Settings.

**Partial:** S-Pen is pointer-only in apps (Mir 1.8 has no zwp_tablet_v2 —
platform-gated); folio touchpad needs the rotation daemon
(`fixes/input-touchpad/`), scroll broken in Morph, pinch dead; rootfs grown
to 6.2 GB on-device but the lpmake budget is not yet baked into the build.

**Open:** sensors HAL (no auto-rotate), cameras untested, USB-C host dead,
UDFPS untested. Ledger: PORT-STATE.md §6.

## Contents

- `build-gts9uwifi.sh` — canonical build wrapper (**V3**, the audio-gate
  version; identical to the "(12)" copy used for the S9+ work). Stages
  skeleton + imports + firmware parts, clones Azkali's kernel, builds
  kernel/techpacks, swaps vendor_dlkm modules, assembles super at the
  PIT-exact 11,744,051,200, packages the flashable zip.
- `skeleton/` — the `samsung-gts9u` device repo (unpacked
  `gts9uwifi-skeleton-audio.tar.gz`, the canonical audio-era superset), with
  **one modification**: `flashable/META-INF/.../update-binary` upgraded to
  the v4 flasher (zstd integrity pre-pass + pipeline-failure marker; the v3
  it replaced is `archive/superseded/update-binary-v3`).
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
X910XXS5CYG1 factory zip. If a stale pre-audio `samsung-gts9u/` sits in the
workdir the script fails fast — remove it and rerun.

## Flash

TWRP: full backup incl. EFS first → Install the built zip from /data →
`twrp reboot system`. Never touch the dtbo partition. First boot after a cold
flash: boot **unplugged** (ABL stamps charger-mode on cabled boots; the
container wrapper filters it, but belt-and-braces on the very first boot).

## Known build-system split (pending merge)

This skeleton's `scripts/swap-vendor-modules.sh` carries the **modules.load
dedupe** (audio bug #1 fix). `common/scripts/swap-vendor-modules.sh` (v2)
carries the **LEFTOVER/UNLANDED audit + allowlist strict mode** but not the
dedupe. They forked in parallel and were never merged — merge before the next
Ultra build, or run the skeleton copy and audit by hand. Same story for
`super.sh`/`make-flashable.sh` (common/ has the strict-mode v2s).
