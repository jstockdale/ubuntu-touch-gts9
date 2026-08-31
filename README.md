# Ubuntu Touch on the Samsung Galaxy Tab S9 family

Build system, fixes, patches, tools, and engineering documentation for porting
[Ubuntu Touch](https://ubports.com) (UT 24.04 "noble" on a
[Halium](https://halium.org) 13 base) to the Samsung Galaxy Tab S9 **WiFi**
tablets: the 11" (SM-X710), the S9+ (SM-X810), and the S9 Ultra (SM-X910).

This is a working porting repository, not a polished distribution:

- **There are no prebuilt images to download.** Every flashable zip is built
  from source, and the build additionally needs a multi-gigabyte Samsung
  factory firmware package as a donor — Samsung firmware is **not**
  redistributed here; you source and hash-verify your own copy
  (see [FIRMWARE.md](FIRMWARE.md)).
- Flashing custom software can permanently damage your device and voids your
  warranty. Some mistakes documented here — notably bootloader fuse burns —
  are **irreversible by design**. Read
  [Before you touch a device](#before-you-touch-a-device) first. Everything
  is provided as-is, without warranty (see [LICENSE](LICENSE)).

The authoritative, continuously updated status document is
[`docs/knowledge/PORT-STATE.md`](docs/knowledge/PORT-STATE.md) — per-device
status, every landed fix, hardware facts, and the open-issues ledger.

## ⚠ The bootloader fuse — read this before anything else

Samsung tablets carry a **one-way hardware fuse** tracking the bootloader
revision — **"rev"** throughout these docs: the digit after `XXU`/`XXS` in a
firmware build string (`X910XX`**`S5`**`CYG1` = rev 5), shown as `RP SWREV`
on the Download Mode screen. Flashing firmware with a higher rev burns the
fuse forward **permanently** — it can never be lowered again.

**Rev 5 is the last revision whose bootloader can be unlocked. Rev 6 and
later can NEVER be unlocked** — Samsung removed bootloader unlocking in
One UI 8, and current official updates are rev 6. One accepted OTA on a
rev ≤ 5 tablet permanently ends its usefulness for porting. Therefore:

- **Never accept an OTA on a unit you intend to port.** Keep it offline
  through setup; disable auto-update.
- **Check the rev in Download Mode** (`RP SWREV` line) before buying, before
  unlocking, before flashing — the boot-splash "OEM LOCK" line is usually
  right but can show stale state; Download Mode is authoritative.
- Use firmware matching your unit's rev — rules and per-rev recommendations
  in [FIRMWARE.md](FIRMWARE.md).

## Device matrix

| | Tab S9 11" | Tab S9+ | Tab S9 Ultra |
|---|---|---|---|
| Codename | **gts9wifi** | **gts9pwifi** | **gts9uwifi** |
| Model | SM-X710 | SM-X810 | SM-X910 |
| Status | Works — runs [Azkali's upstream port](https://gitlab.com/azkali-samsung/gts9/ubports); this repo adds fixes | **Untested** — full port recipe assembled, never executed | **Lead port** — boots and is usable; known gaps below |
| Panel | GTS9_ANA38407_AMSA10FA01 | GTS9P_ANA38407_AMSA24VU05 | GTS9U_ANA38407_AMSA46AS02 |
| Touch IC | STM FTS1BA90A (Goodix on some revisions) | STM FTS1BA90A | Goodix GT9916 berlin |
| SUPER (PIT) | 11,643,387,904 | 11,714,691,072 | 11,744,051,200 |
| Donor firmware | X710XXU5CYD9 (rev 5, A15 era¹) | X810XXU1AWHA (rev 1, A13) | X910XXS5CYG1 (rev 5, A15) |

¹ The shipped 11" port composes an Android-13 platform fingerprint over the
CYD9 vendor; the CYD9 firmware release itself is Android-15 era — details in
[FIRMWARE.md](FIRMWARE.md).

**What works on the lead port (Ultra):** display at 2960×1848@120, GPU (full
hybris EGL), touch, WiFi, Bluetooth, battery/charging, audio, folio keyboard,
S-Pen as a pointer, Lomiri and Settings.
**Known gaps:** no auto-rotate (sensors HAL open), cameras untested, USB-C
host mode dead, fingerprint untested, S-Pen pressure blocked upstream on
Mir 1.x. Full honest ledger: [PORT-STATE.md §1](docs/knowledge/PORT-STATE.md).

All three tablets are SM8550 "kalama", so **one Halium kernel binary serves
the whole family** (Azkali's `kernel-samsung-gts9wifi`, branch
`android13-5.15-halium`). Only the DTB (selected by the bootloader from the
untouched stock `dtbo` partition), panel data, and vendor blobs differ. The
5G siblings (SM-X716B/X816B/X916B) are not supported; the flash scripts
hard-reject 5G hardware. Only the WiFi, bootloader-unlockable models apply —
US carrier variants can never be unlocked.

## Before you touch a device

Beyond the fuse rules above, the working rules in
[CONTRIBUTING.md](CONTRIBUTING.md) were each paid for with a debugging
session — read them before flashing anything. The ones that protect you from
irreversible or hard-to-undo damage:

1. **Back up before first flash:** a TWRP full backup *including EFS*, plus
   raw dumps of `efs sec_efs persist optics prism up_param`, plus an
   archived copy of your factory firmware package (old builds rot off
   mirrors — your copy is the unit's permanent way back).
2. **Never flash the `dtbo` partition.** The port depends on the stock DTBO.
3. On a running port: never `apt upgrade` the rootfs, never install
   desktop-GL Qt apps into it (Lomiri crash-loops), and never
   `rmmod machine_dlkm` (instant kernel panic).
4. Rootfs changes die on reflash. Durable fixes go in the skeleton overlay
   or on /data; after any reflash, run the device's
   [`fixes/post-flash/`](fixes/post-flash/) script.

## Start here

**"I have a Tab S9 11" and just want Ubuntu Touch."**
Don't start from this repo — install Azkali's upstream gts9wifi port (the
reference port this family effort builds on; see his
[GitLab](https://gitlab.com/azkali-samsung/gts9/ubports) for current install
material), then come back for the quality-of-life fixes in
[`fixes/`](fixes/) (audio, S-Pen pointer, touchpad rotation). See
[`devices/gts9wifi/README.md`](devices/gts9wifi/README.md).

**"I have a Tab S9 Ultra and want to build and flash the port."**
This is the proven pipeline, but it is a from-source build, not a download.
You need a Linux build box (~50 GB free), an unlocked rev ≤ 5 unit with the
family TWRP, and your own donor firmware package:

1. Verify your unit's rev and obtain the matching donor firmware,
   hash-verified — [FIRMWARE.md](FIRMWARE.md).
2. Extract the donor partitions:
   `tools/extract/x910-extract.sh <factory.zip>` (it reports the PIT-exact
   super geometry for you).
3. Build, from the repo root:
   ```bash
   SKEL=$PWD/devices/gts9uwifi/skeleton IMPORTS=$PWD/devices/gts9uwifi/imports SRC_PARTS=~/out-x910/parts devices/gts9uwifi/build-gts9uwifi.sh
   ```
   — and follow [`devices/gts9uwifi/README.md`](devices/gts9uwifi/README.md)
   for the real, current instructions (prerequisites, flashing via TWRP,
   first-boot notes).

**"I have a Tab S9+."**
Nobody has run Ubuntu Touch on an S9+ yet. This repo contains a complete,
carefully assembled — but **unexecuted** — port kit: build script, kernel
import bundle, firmware extractor, reference PIT/DTS, and a six-phase
runbook. If you have an unlockable unit and porting experience, you could be
the first:
[`devices/gts9pwifi/docs/gts9pwifi-port-runbook.md`](devices/gts9pwifi/docs/gts9pwifi-port-runbook.md).

**"I want to contribute."**
Genuinely wanted, in rough order of leverage:

- The patches in [`patches/upstream/`](patches/upstream/) (Halium and
  pulseaudio-modules-droid) are written but not yet submitted upstream.
- Test reports for the untested cells in
  [FIRMWARE.md](FIRMWARE.md) (rev 1 builds on any device; the S9+ port).
- Open engineering problems ledgered in
  [PORT-STATE.md §6](docs/knowledge/PORT-STATE.md): sensors HAL /
  auto-rotate, USB-C host mode, cameras, GPS on the 11".

Open a GitHub issue or PR; read [CONTRIBUTING.md](CONTRIBUTING.md) before
testing on hardware.

## Repository layout

- [`FIRMWARE.md`](FIRMWARE.md) — exact stock firmware vintages the ports are
  built against, per-rev recommendations, package hashes, and the
  fuse-safety rules. Read before downloading anything.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — operating rules for anyone with a
  device in hand, plus how to contribute.
- `devices/<codename>/` — per-device material. `gts9uwifi/` is complete
  (build script, skeleton, imports, docs); `gts9pwifi/` is the unexecuted
  port kit (build script, imports, reference PIT/DTS, runbook); `gts9wifi/`
  documents the upstream port and what this repo adds to it.
- `common/scripts/` — the canonical build-stage scripts (vendor-module swap,
  super-image assembly, flashable packaging), kept byte-identical with the
  gts9uwifi skeleton copies — edit here, re-install there
  ([`common/scripts/README.md`](common/scripts/README.md)).
- [`fixes/`](fixes/) — standalone installable fixes: `audio/`, `input-pen/`,
  `input-touchpad/`, `hygiene/` (apt pin + greeter fd-limit guards), and
  `post-flash/` (per-device restore-everything scripts to run after any
  reflash). Who installs what: [`fixes/README.md`](fixes/README.md).
- `patches/upstream/` — patches destined for Halium / UBports projects
  (not yet submitted; each dir has a ready-to-send SUBMIT.md).
- `tools/` — `extract/` (firmware donor extraction), `boot/` (boot-image
  surgery), `lp/` (super/LP inspection), `diagnostics/`, `dev/` (flasher
  verification harness).
- `docs/` — `knowledge/` (keep-forever reference: PORT-STATE.md, the audio
  playbook, the S-Pen porting guide), `postmortems/`, `reviews/`,
  `checklists/`, and `status-archive/` (dated snapshots, some superseded —
  read its README).
- `archive/` — historical working material and provenance from the original
  porting effort; `archive/binaries/` and `archive/osrc/` are git-ignored
  proprietary artifacts (hashes in `archive/binaries/MANIFEST.md`).

## Glossary

- **Ubuntu Touch (UT)** — the mobile Ubuntu distribution maintained by
  [UBports](https://ubports.com).
- **Halium** — the [project](https://halium.org) that runs Linux distros on
  Android hardware by reusing the Android kernel and vendor HALs inside a
  container. This port is Halium 13 (Android 13 container base).
- **Azkali** — the Halium developer whose upstream
  [gts9wifi port](https://gitlab.com/azkali-samsung/gts9/ubports) and kernel
  tree this family effort builds on and contributes back to.
- **rev** — the bootloader fuse revision (see the warning section above).
- **Skeleton** — the Halium "device repo" for a device (deviceinfo, overlay
  files, flashable packaging) that the build script stages;
  `devices/gts9uwifi/skeleton/` is a fork of Azkali's `samsung-gts9`.
- **Imports** — kernel source imported from Samsung's Open Source Release
  (**OSRC**, opensource.samsung.com) drops — panel, touch, and pen drivers
  plus DTS — so board drivers can be built against the Halium kernel; stock
  Samsung modules are vermagic-locked and cannot load.
- **Donor firmware** — the stock Samsung factory package from which the
  build carves the proprietary vendor partitions (`vendor`, `vendor_dlkm`,
  `odm`, …) staged into the flashable image. You supply it yourself;
  vintage matters ([FIRMWARE.md](FIRMWARE.md)).
- **SUPER / LP / PIT** — Android's dynamic-partition container (`super`),
  its Logical Partition metadata, and Samsung's Partition Information Table
  fixing its exact byte size per model.
- **DTB / dtbo** — device-tree blobs; the port deliberately keeps the stock
  `dtbo` partition so the bootloader selects the right board DTB.

## License & credits

Original work © 2026 John Stockdale and Off by One, Inc., under the
[BSD 3-Clause License](LICENSE). This repo contains and derives from
third-party work (Samsung OSRC / Qualcomm GPL-2.0 kernel code, Azkali's
`samsung-gts9` Halium device repo) under their own licenses — scope in
[NOTICE](NOTICE). Samsung firmware and proprietary blobs are never
redistributed from this repository.

Not affiliated with Samsung, Qualcomm, UBports, or Halium. Thanks to Azkali
for the upstream gts9 port this family effort stands on.
