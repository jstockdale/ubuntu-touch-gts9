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

## Per-device firmware matrix

| | Build | Android / patch | Bootloader binary | Package |
|---|---|---|---|---|
| **Tab S9 Ultra** (SM-X910, gts9uwifi) | **X910XXS5CYG1** | Android 15 / 2025-07-01 | **rev 5** (last unlockable) | full factory zip for X910XXS5CYG1 (e.g. from samfw.com, SM-X910; ~15 GB) |
| **Tab S9+** (SM-X810, gts9pwifi) | **X810XXU1AWHA** | Android 13 / last rev-1 build | **rev 1** | `SAMFW.COM_SM-X810_XAR_X810XXU1AWHA_fac.zip` — exactly **9,225,074,787 bytes**; `unzip -T` must pass |
| **Tab S9 11"** (SM-X710, gts9wifi) | X710XXU5CYD9 (informational) | Android 13 / 2025-04-01 | rev 5 | n/a — the 11" runs Azkali's upstream build, which pins this vendor base and ships its own firmware donor tarball |

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

- **Bootloader binary revision** = the digit after `XXU`/`XXS` in the build
  string, authoritative ONLY on the Download Mode screen (`RP SWREV` line —
  the splash-screen "OEM LOCK" line misreports). **Rev 5 is the last
  unlockable revision; rev 6 is terminal.** One UI 8 removed bootloader
  unlocking globally.
- **Never accept an OTA on a project unit.** Current fleet builds are
  binary 6 — past the cliff. This matters doubly for the rev-1 S9+: one
  accepted update permanently ends its usefulness.
- Cross-major restores go through Odin with **BL + AP + full CSC** (not
  HOME_CSC). Archive your factory package before first flash — old builds
  rot off mirrors, and your archived copy is the unit's permanent way back.
- If a unit ships on an EARLIER build than the target vintage, Odin-align
  it to the target first so bootloader/dtbo/vendor match the extracted
  parts (runbook Phase 3.6.4); then re-capture stock `/proc/cmdline`.
