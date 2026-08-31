# Ubuntu Touch on the Samsung Galaxy Tab S9 family

Build system, fixes, patches, tools, and engineering documentation for porting
Ubuntu Touch (Halium 13, UT 24.04 "noble") to the Galaxy Tab S9 WiFi tablets.

Snapshot assembled 2026-08-30 from the July–August 2026 porting campaign
(28 working conversations, reconciled — see `archive/`). Owner: John Stockdale.

## Device matrix

| | Tab S9 11" | Tab S9+ | Tab S9 Ultra |
|---|---|---|---|
| Codename | **gts9wifi** | **gts9pwifi** | **gts9uwifi** |
| Model | SM-X710 | SM-X810 | SM-X910 |
| Status | Daily-driven on Azkali's upstream port | **Port kit complete, unexecuted** | **Lead port — ~fully working** |
| Panel | GTS9_ANA38407_AMSA10FA01 | GTS9P_ANA38407_AMSA24VU05 | GTS9U_ANA38407_AMSA46AS02 |
| Touch IC | STM FTS1BA90A (Goodix on some revs) | STM FTS1BA90A | Goodix GT9916 berlin |
| SUPER (PIT) | 11,643,387,904 | 11,714,691,072 | 11,744,051,200 |
| Firmware base | X710XXU5CYD9 (A13) | X810XXU1AWHA (A13, rev-1) | X910XXS5CYG1 (A15, rev 5) |

**Build against the exact firmware vintages in [FIRMWARE.md](FIRMWARE.md)**
— the flashable images stage vendor partitions carved from those specific
packages, and all on-silicon validation happened against them.

All three are SM8550 "kalama": **one halium kernel binary serves the family**
(Azkali's `kernel-samsung-gts9wifi` @ `android13-5.15-halium`). Only the DTB
(selected from the untouched stock `dtbo` partition), panel data, and vendor
blobs differ. 5G siblings (X716B/X816B/X916B) are future work — add
`devices/gts9*5g/` when an unlockable unit lands; the flashers already
hard-reject X916 hardware.

**The authoritative current-truth document is
[`docs/knowledge/PORT-STATE.md`](docs/knowledge/PORT-STATE.md)** — per-device
status, the five-bug audio chain, every landed fix, hardware facts, and the
open-issues ledger.

## Layout

- `devices/<codename>/` — per-device build script, skeleton (device repo
  overlay), OSRC import bundle, reference data (PIT, DTS), device docs.
- `common/scripts/` — the canonical v3 build-stage scripts (merged
  dedupe+audit swap, LP-budget super.sh, strict make-flashable), kept
  byte-identical with the gts9uwifi skeleton copies — edit here, re-install
  there; see `common/scripts/README.md`.
- `fixes/` — standalone installable fixes (audio bring-up, virtual headphone
  jack, touchpad rotation, S-Pen pointer).
- `patches/upstream/` — patches destined for Halium / UBports. **Both are
  still unsent** — this is the highest-leverage open work.
- `tools/` — firmware extraction, boot-image surgery, LP inspection,
  diagnostics.
- `docs/knowledge/` — keep-forever reference (port state, audio playbook,
  S-Pen guide). `docs/postmortems/`, `docs/status-archive/` — dated records
  (some claims superseded; read the archive README).
- `archive/` — full provenance: the 28 conversation transcripts, the mining
  notes, raw diagnostic logs, session one-offs, superseded script versions,
  and (git-ignored) proprietary binaries with a hash manifest.

## Quick start

**Build for the Ultra** (proven pipeline; needs the X910 firmware donor):

```
tar: devices/gts9uwifi/skeleton/ is the unpacked samsung-gts9u device repo
SKEL=devices/gts9uwifi/skeleton IMPORTS=devices/gts9uwifi/imports \
SRC_PARTS=~/out-x910/parts  devices/gts9uwifi/build-gts9uwifi.sh
```

**Port the S9+** (unexecuted; follow the runbook end to end):
[`devices/gts9pwifi/docs/gts9pwifi-port-runbook.md`](devices/gts9pwifi/docs/gts9pwifi-port-runbook.md)

## License & credits

Original work © 2026 John Stockdale and Off by One, Inc., under the
[BSD 3-Clause License](LICENSE). This repo contains and derives from
third-party work (Samsung OSRC / Qualcomm GPL-2.0 kernel code, Azkali's
`samsung-gts9` Halium device repo) under their own licenses — scope in
[NOTICE](NOTICE). Not affiliated with Samsung, Qualcomm, UBports, or Halium.

## The rules (learned the hard way)

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before touching a device. The short
version: durable fixes live in the skeleton overlay or on /data (everything
else dies on reflash); never install desktop-GL apps in the rootfs; never
`rmmod machine_dlkm`; never let the S9+ unit take an OTA.
