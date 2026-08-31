# FIRMWARE — exact stock packages these ports are built against

Copyright (c) 2026 John Stockdale and Off by One, Inc. — BSD 3-Clause (see LICENSE).

**Use the same firmware we built and validated against.** The build stages
the vendor partition set (vendor / vendor_dlkm / odm / product / system_ext /
system_dlkm) carved from ONE specific factory package into the flashable
super image, and everything validated on silicon — the vendor-module swap,
the finit allowlist, the five-bug audio chain, the panel/touch/pen firmware
paths — was validated against exactly these vintages. A different vintage is
an untested port: bootloader/dtbo vs vendor skew is a real failure class
(one vintage, no skew — runbook Phase 3.6.4).

## First rule: match the firmware series to YOUR bootloader binary

The bootloader binary revision (the digit after `XXU`/`XXS`) is a one-way
fuse: flashing a higher-binary package permanently burns the bit fuse to
that revision. A new-in-box unit ships at **rev 1** — if it ever takes a
5-series package it becomes a rev-5 unit forever. So:

- **Read your unit's binary in Download Mode first** (`RP SWREV` line).
- **Use the last firmware of YOUR series** as the port's donor package.
  A rev-1 unit targets 1-series firmware; a rev-5 unit targets 5-series.
  Never flash above your current binary unless you deliberately accept
  the irreversible fuse burn (and never above 5 — that is the cliff).
- The port itself does not require changing series: you extract the donor
  parts from your own series' package and build against those. The
  bring-up mechanism is vintage-agnostic by construction (modules.load is
  completed from whatever vendor_dlkm your package provides; the swap
  script audits the module set) — but only the vintages below have been
  validated on silicon.

**Support policy:** we intend 1-series and 5-series units to both work
without cross-series reflashing — those are the two bootloader
generations we own test hardware for. rev-5 is validated (Ultra) /
daily-driven (11"); rev-1 test hardware is now on hand (new-in-box S9+,
X710, and X910), so the 1-series path is moving from assembled to
tested. Revisions 2–4 follow the same match-your-series rule (last build
of your own series); recommended builds for those may be added if test
hardware appears.

## Tested / assembled against (the exact packages we used)

| | Build | Android / patch | Bootloader binary | Status | Package |
|---|---|---|---|---|---|
| **Tab S9 Ultra** (SM-X910, gts9uwifi) | **X910XXS5CYG1** | Android 15 / 2025-07-01 | rev 5 | **validated on silicon** (the lead port) | full factory zip for X910XXS5CYG1 (e.g. from samfw.com, SM-X910; ~15 GB) |
| **Tab S9+** (SM-X810, gts9pwifi) | **X810XXU1AWHA** | Android 13 / last rev-1 build | rev 1 | port kit assembled against it (port unexecuted) | `SAMFW.COM_SM-X810_XAR_X810XXU1AWHA_fac.zip` — exactly **9,225,074,787 bytes**; `unzip -T` must pass |
| **Tab S9 11"** (SM-X710, gts9wifi) | X710XXU5CYD9 | Android 13 / 2025-04-01 | rev 5 | daily-driven (Azkali's upstream build pins it) | n/a — Azkali's port ships its own firmware donor tarball |

## Recommended per bootloader series

| Device | rev-1 unit (Android-13 target) | rev-5 unit (Android-15 target) |
|---|---|---|
| SM-X910 (Ultra) | **X910XXU1AWHA** (last A13 build, 2023-08-20) | **X910XXS5CYG1** (A15, tested — the lead port) |
| SM-X810 (S9+) | **X810XXU1AWHA** (last A13 build; the assembled kit target) | X810XXS5CYG1 (A15, family-analogous, untested) |
| SM-X710 (11") | **X710XXU1AWHA** (last A13 build, 2023-08-20) | X710XXU5CYD9 (A15, Azkali's pin) |

**Last Android-13 build = `XXU1AWHA` for all three** — verified against
sammobile's US (XAR) firmware history for X710 and X910 (both show AWHA,
2023-08-20, as the final Android-13 release before the Android-14 BWK6
build); X810 matches per our own assembled-kit record. All three are
bootloader binary 1.

Why AWHA and not a later binary-1 build: these tablets kept bootloader
binary **1 through Android 14** (e.g. `XXU1BWK6`, Nov 2023) and only
fused to binary 5 at Android 15. So "last binary-1" (an A14 build) and
"last Android-13" (AWHA) are different — and this port needs the
**Android-13 vendor base** (halium-13 / 5.15.153 kernel generation), so
**target AWHA**, not BWK6.

New-in-box note: a unit manufactured later may ship pre-loaded with a
newer **binary-1** build (even Android 14 BWK6). Flashing AWHA onto it is
a lateral flash *within binary 1* — no fuse burn, allowed — because you
are not going above the unit's current bootloader binary. (Anti-rollback
is keyed to the bootloader binary, not the Android version.) Read the
binary in Download Mode first to be sure it is still 1.

Treat any not-tested cell as an untested port: extract, build, and walk
the bring-up ladder rather than assuming parity.

Verification the extractors enforce for you:

- `tools/extract/x910-extract.sh` — parses the LP metadata and reports
  `SUPER_DEVICE_SIZE`; the X910 value must be **11,744,051,200**
  (GTS9UWIFI_EUR_OPEN.pit).
- `tools/extract/x810-extract.sh` — **hard-fails** unless the raw super is
  byte-exactly **11,714,691,072** (GTS9PWIFI_EUR_OPEN.pit), so a wrong or
  truncated package cannot silently poison the geometry.

TODO: pin the X910 package's exact distribution filename + sha256 on the
next local download (the original extraction was done by ranged streaming;
the build string above is the authoritative identity).

## Kernel source drops (OSRC) the imports were assembled from

- **gts9uwifi**: SM-X910 EUR OSRC drop, 2025-05-07 release (CYD9-era —
  same 5.15.153 / KMI 30958166 generation as the port's base; build target
  `gts9uwifi_eur_open`).
- **gts9pwifi**: `SM-X818U_13_Opensource.zip` (base, X818USQU1AWG1)
  + `SM-X810_13_Opensource_dts.zip` (gts9pwifi overlay)
  + the AWH8-named delta zip — applied in that order.
  All from opensource.samsung.com (not redistributed here; see NOTICE).

## The rules that keep your unit alive

- **Rev 5 is the last unlockable revision; rev 6 is terminal.** One UI 8
  removed bootloader unlocking globally. Download Mode is the only
  authoritative readout (the splash-screen "OEM LOCK" line misreports).
- **Never accept an OTA on a project unit.** Current fleet builds are
  binary 6 — past the cliff. This matters doubly for the rev-1 S9+: one
  accepted update permanently ends its usefulness.
- Cross-major restores go through Odin with **BL + AP + full CSC** (not
  HOME_CSC). Archive your factory package before first flash — old builds
  rot off mirrors, and your archived copy is the unit's permanent way back.
- If a unit ships on an EARLIER build than the target vintage, Odin-align
  it to the target first so bootloader/dtbo/vendor match the extracted
  parts (runbook Phase 3.6.4); then re-capture stock `/proc/cmdline`.
