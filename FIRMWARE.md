# FIRMWARE – exact stock packages these ports are built against

Copyright (c) 2026 John Stockdale and Off by One, Inc. – BSD 3-Clause (see LICENSE).

**Use the same firmware we built and validated against.** The build stages
the vendor partition set (vendor / vendor_dlkm / odm / product / system_ext /
system_dlkm) carved from ONE specific factory package into the flashable
super image, and everything validated on silicon – the vendor-module swap,
the finit allowlist, the five-bug audio chain, the panel/touch/pen firmware
paths – was validated against exactly these vintages. A different vintage is
an untested port: bootloader/dtbo vs vendor skew is a real failure class
(one vintage, no skew – runbook Phase 3.6.4).

## First rule: match the firmware series to YOUR unit's rev

**What "rev" means: the bootloader fuse revision** – a one-way hardware bit
fuse tracked by the digit after `XXU`/`XXS` in a firmware build string
(`X910XX`**`S5`**`CYG1` = rev 5), read from the `RP SWREV` line in Download
Mode. Samsung also calls it the "binary"; firmware packages of a given rev
are that rev's "series" (1-series, 5-series). Flashing a higher-rev package
**permanently burns the fuse forward** – it can never be lowered.

**Rev 5 is the last revision whose bootloader can be unlocked. Rev 6 and
later can NEVER be unlocked.** One UI 8 hides the OEM Unlocking toggle, but
the fuse decides: a rev 5 unit that already took One UI 8.0 can be rolled
back to One UI 7 and unlocked (see [FLASHING.md](FLASHING.md)). Current
official updates are rev 6; a new-in-box unit ships at rev 1, and one
accepted OTA ends its porting usefulness forever.

- **Read your unit's rev in Download Mode first** (`RP SWREV` line –
  authoritative; the boot-splash "OEM LOCK" line is right on a healthy boot
  chain but a broken one can make it show the wrong state).
- **Use the last firmware of YOUR unit's series** as the port's donor
  package. A rev 1 unit targets 1-series firmware; a rev 5 unit targets
  5-series. Never flash above your current rev unless you deliberately
  accept the irreversible fuse burn (and never above 5 – that is the cliff).
- The port itself does not require changing series: you extract the donor
  parts from your own series' package and build against those. The
  bring-up mechanism is vintage-agnostic by construction (modules.load is
  completed from whatever vendor_dlkm your package provides; the swap
  script audits the module set) – but only the vintages below have been
  validated on silicon.

**Support policy:** we intend 1-series and 5-series units to both work
without cross-series reflashing – those are the two bootloader
generations we own test hardware for. rev 5 is validated (Ultra) /
daily-driven (11"); rev 1 test hardware is now on hand (new-in-box S9+,
X710, and X910), so the 1-series path is moving from assembled to
tested. Revisions 2–4 follow the same match-your-series rule (last build
of your own series); recommended builds for those may be added if test
hardware appears.

## Tested / assembled against (the exact packages we used)

| | Build | Android / patch | Bootloader binary | Status | Package |
|---|---|---|---|---|---|
| **Tab S9 Ultra** (SM-X910, gts9uwifi) | **X910XXS5CYG1** | Android 15 / 2025-07-01 | rev 5 | **validated on silicon** (the lead port) | `XAR-X910XXS5CYG1-20250728211620.zip` – 15,273,971,024 bytes (sha256 below) |
| **Tab S9+** (SM-X810, gts9pwifi) | **X810XXU1AWHA** | Android 13 / last rev 1 build | rev 1 | port kit assembled against it (port unexecuted) | `SAMFW.COM_SM-X810_XAR_X810XXU1AWHA_fac.zip` – exactly **9,225,074,787 bytes**; `unzip -T` must pass |
| **Tab S9 11"** (SM-X710, gts9wifi) | X710XXU5CYD9 | Android 15 era / 2025-04-01 patch¹ | rev 5 | daily-driven (Azkali's upstream build pins it) | n/a – Azkali's port ships its own firmware donor tarball; our archived rescue/reference package is **X710XXS5CYG1** (see hashes below) |

¹ The shipped gts9wifi port's vendor fingerprint reads
`gts9wifi:13/TP1A.220624.014/X710XXU5CYD9` – an Android-13 platform ID
glued to the CYD9 build string. That identity is port-composed (halium-13
ports assemble the fingerprint); the CYD9 *firmware release* itself is the
April 2025 / Android-15-era quarterly.

### CYD9 vs CYG1 – sequencing of the two rev 5 vintages in play

`XXU5CYD9` (Azkali's pin) is the **April 2025 full/feature quarterly**
(XXU train, patch 2025-04-01); `XXS5CYG1` (our archived packages, and the
Ultra port's donor) is its **security-only successor one quarter later**
(XXS train, July 2025, patch 2025-07-01). Same Android generation (C =
third OS = Android 15 era), same bootloader rev 5, identical kernel
generation (5.15.153 / KMI 30958166 – the stock kernel strings differ
only by model/build tag). Flashing CYG1 stock over a CYD9-based unit for
rescue is lateral and fuse-neutral, and the CYD9-donor / CYG1-donor
interop is exactly what the working family ports already demonstrate.

## Recommended per bootloader series

| Device | rev 1 unit (Android-13 target) | rev 5 unit (Android-15 target) |
|---|---|---|
| SM-X910 (Ultra) | **X910XXU1AWHA** (last A13 build, 2023-08-20) | **X910XXS5CYG1** (A15, tested – the lead port) |
| SM-X810 (S9+) | **X810XXU1AWHA** (last A13 build; the assembled kit target) | X810XXS5CYG1 (A15, family-analogous, untested) |
| SM-X710 (11") | **X710XXU1AWHA** (last A13 build, 2023-08-20) | X710XXU5CYD9 (A15, Azkali's pin) |

**Last Android-13 build = `XXU1AWHA` for all three** – verified against
sammobile's US (XAR) firmware history for X710 and X910 (both show AWHA,
2023-08-20, as the final Android-13 release before the Android-14 BWK6
build); X810 matches per our own assembled-kit record. All three are
bootloader rev 1.

Why AWHA and not a later rev 1 build: these tablets stayed at bootloader
**rev 1 through Android 14** (e.g. `XXU1BWK6`, Nov 2023) and only fused
to rev 5 at Android 15. So "the last rev 1 build" (an A14 build) and
"last Android-13" (AWHA) are different – and this port needs the
**Android-13 vendor base** (halium-13 / 5.15.153 kernel generation), so
**target AWHA**, not BWK6.

New-in-box note: every new-in-box unit observed so far ships on
Android 13 at rev 1, so the AWHA target is either already installed or
one same-Android-13 flash away. Verify the rev in Download Mode before
anything regardless. (Rev 1 technically spans through the Android 14
BWK6 build per the firmware history, but a NIB unit shipping A14 has not
been observed; if you ever meet one, treat getting it to AWHA as
unverified territory.)

Treat any not-tested cell as an untested port: extract, build, and walk
the bring-up ladder rather than assuming parity.

Verification the extractors provide (x810 enforces; x910 reports):

- `tools/extract/x910-extract.sh` – parses the LP metadata and reports
  `SUPER_DEVICE_SIZE`; the X910 value must be **11,744,051,200**
  (GTS9UWIFI_EUR_OPEN.pit).
- `tools/extract/x810-extract.sh` – **hard-fails** unless the raw super is
  byte-exactly **11,714,691,072** (GTS9PWIFI_EUR_OPEN.pit), so a wrong or
  truncated package cannot silently poison the geometry.

## Reference package archive – SHA256 (hashed 2026-08-31)

The exact archives this project builds against, held in the project's
private storage and hashed by streaming the full files end to end (each
verified to begin with a genuine Samsung factory tar member for the
expected build – not an error page). Verify any copy you obtain against
these before extracting:

| Archive | Bytes | SHA256 |
|---|---|---|
| `SM-X810-XAR-X810XXU1AWHA_fac.zip` (the samfw `SAMFW.COM_SM-X810_XAR_X810XXU1AWHA_fac.zip`, archived under a shortened name – same bytes) | 9,225,074,787 | `9df2a2cd26fe080e99fb6946e95bdf1415708087008dd27ae6b42194b9553c3e` |
| `XAR-X710XXS5CYG1-20250728211550.zip` | 15,272,300,480 | `2714fc70cd3ae61e83fc79466a1379103a5e4524791ad00cb8f7a08036f209b1` |
| `XAR-X910XXS5CYG1-20250728211620.zip` | 15,273,971,024 | `a14779c80b6d93b0092c1a7f29e8a4cd5f25954001b6b3b6c4312e2ea9117a7f` |

MD5 (for tooling that wants it): X810 AWHA `6d6171b7dd5a92c38b413f2bdf677d5c`;
X710 CYG1 `be7dd8f3c319e118cafb619f9e1db0cd`;
X910 CYG1 `ab94491d2a8109af2b52b2098ced25bb`.

All three are US (XAR) region packages. The two CYG1 archives are the
rev 5 rescue/reference set (pulled 2025-07-28); the AWHA archive is the
S9+ port's donor. Samsung firmware is not redistributed from this repo –
source your own copy (samfw.com or equivalent) and hash-verify it. The
X710/X910 **1-series (AWHA)** packages recommended above for the
new-in-box units are not yet in the archive; hash-pin them here when
downloaded.

## Kernel source drops (OSRC) the imports were assembled from

- **gts9uwifi**: SM-X910 EUR OSRC drop, 2025-05-07 release (CYD9-era –
  same 5.15.153 / KMI 30958166 generation as the port's base; build target
  `gts9uwifi_eur_open`).
- **gts9pwifi**: `SM-X818U_13_Opensource.zip` (base, X818USQU1AWG1)
  + `SM-X810_13_Opensource_dts.zip` (gts9pwifi overlay)
  + the AWH8-named delta zip – applied in that order.
  All from opensource.samsung.com (not redistributed here; see NOTICE).

## The rules that keep your unit alive

- **Rev 5 is the last unlockable revision; rev 6 is terminal.** One UI 8
  removed bootloader unlocking globally. Treat Download Mode as the
  authoritative readout: the boot-splash "OEM LOCK" line is correct on a
  healthy boot chain, but a broken boot chain can make it show the wrong
  state (observed: an unlocked unit running a mis-built custom ROM
  displayed as locked) – don't make irreversible decisions from the
  splash screen.
- **Never accept an OTA on a project unit.** Current official builds are
  rev 6 – past the cliff. This matters doubly for the rev 1 S9+: one
  accepted update permanently ends its usefulness.
- Stock flashing goes through **Odin 3.14** (Windows) loading **BL + AP +
  CSC or HOME_CSC** (HOME_CSC preserves data; full CSC wipes – required for
  cross-major rollbacks). Walkthrough: [FLASHING.md](FLASHING.md). Archive
  your factory package before first flash – old builds rot off mirrors, and
  your archived copy is the unit's permanent way back.
- If a unit ships on an EARLIER build than the target vintage, Odin-align
  it to the target first so bootloader/dtbo/vendor match the extracted
  parts (runbook Phase 3.6.4); then re-capture stock `/proc/cmdline`.
