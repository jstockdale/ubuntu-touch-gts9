# gts9pwifi (SM-X810) hardware findings – canonical A13 confirmation

Updated 2026-08-27 after: A13 OSRC overlays inspected (uploaded), stock firmware
X810XXU1AWHA surgically sampled via ranged reads (PIT + boot + dtbo, 39 MB fetched
of 8.6 GB), azkali tree cross-checked.

## Verdicts – now confirmed at A13/AWG1 vintage (canonical dts)

| Subsystem | gts9pwifi (SM-X810) | Config symbol (lego.config) |
|---|---|---|
| Panel | `GTS9P_ANA38407_AMSA24VU05` + `.dat` | – |
| Touch | STM FTS1BA90A, fw `tsp_stm/fts1ba90a_gts9p.bin` | `CONFIG_TOUCHSCREEN_STM_FTS1BA90A=m` |
| S-Pen | Wacom wez01, fw `wez01_gts9p.bin` | `CONFIG_EPEN_WACOM_WEZ01=m` |
| Folio kbd | stm32 pogo, fw `stm32_gts9family.bin` | – |
| WLAN/BT | same cnss node naming as base (runs kiwi_v2 there) | §2b unchanged |

No goodix config for gts9pwifi – the `goodix,gt9916` dts node is inert kalama
reference cruft (single occurrence, phone-res coords, also present in base dts).
Canonical-vs-mirror r04 dts drift: ~13% of lines → always build imports from the
A13 zips, mirror is identity-reference only.

## OSRC package structure – CORRECTION

The A13 release is **base + overlays**, not standalone drops:
1. **`SM-X818U_13_Opensource.zip`** – the full kernel_platform base (X818USQU1AWG1).
   REQUIRED, still to download (earlier advice to skip it was wrong).
2. `SM-X810_13_Opensource_dts.zip` (have) – gts9pwifi overlay: dts r00/r02/r04 +
   Makefile, gts9pwifi `lego.config`, `kalama-gki_defconfig`, sm5714/sm5440
   battery dtsi, generated headers.
3. AWH8-named zip (`SM-X818U_13_Opensource_X818USQU1AWH8_…`, have) – AWH8 delta: **updated `GTS9P_ANA38407_AMSA24VU05_panel.{c,h}`**,
   SELF_DISPLAY, sm5714 typec, sec_battery; also gts9p (5G) dts – not our target.

Assembly order for imports: base → dts overlay → AWH8 delta.
The panel `.dat` + display Kbuild live in the base zip.

## Stock firmware X810XXU1AWHA (samfw/s10.ooo link – verified)

`SAMFW.COM_SM-X810_XAR_X810XXU1AWHA_fac.zip`, 9,225,074,787 B, resumable.
Members: AP / BL / CSC_OXM / HOME_CSC_OXM (deflate). PIT name inside CSC:
`GTS9PWIFI_EUR_OPEN.pit` – device identity double-confirmed.

PIT (unit = 4096 B/block, calibrated against extracted boot.img):

| Partition | Bytes |
|---|---|
| **SUPER** | **11,714,691,072**  (X910: 11,744,051,200 → 28 MiB smaller; do NOT inherit the skeleton default) |
| BOOT / VENDOR_BOOT | 100,663,296 each |
| INIT_BOOT | 8,388,608 |
| RECOVERY | 109,576,192 |
| DTBO | 16,777,216 (image carries **3 DT entries** = board revs r00/r02/r04) |
| VBMETA | 131,072 |

- boot.img is GKI-generic (no baked panel cmdline; ABL injects at runtime).
- vendor_boot.img sits AFTER super in the AP tar – pull from the full local
  download if ever needed; not required now.
- GTS9P panel.c self-identifies via DDIC reads (`manufacture_id_dsi`, A1h; even
  checks 0x800004/0x800005 internally) → plan: bare
  `msm_drm.dsi_display0=GTS9P_ANA38407_AMSA24VU05:` in halium.config, no lcd_id
  args. Belt-and-braces: capture stock `/proc/cmdline` during unit prep.

## Remaining actions

1. Portal (one captcha): download `SM-X818U_13_Opensource.zip` (base).
2. Build box: pull the samfw zip (resumable) – sandbox disk can't host extraction.
3. Unit prep: Download-mode fuse/binary check; stock `/proc/cmdline` capture;
   TWRP gts9p boot test + FULL backup incl. EFS before any flash.
4. Then: assemble `gts9p-imports`, write `x810-extract.sh` +
   `build-gts9pwifi.sh` (SUPER=11714691072, panel sed, fts1ba90a fatal check,
   wez01 warn check unchanged). [SUPERSEDED 2026-08-30: wez01 is now FATAL – see the addendum below.]

## 2026-08-27 addendum – assembly complete

Base zip received and verified: `SM-X818U_13_Opensource.zip` = X818USQU1AWG1
full drop (Kernel.tar.gz 753 MB + Platform.tar.gz). Input set complete.

- Panel activation mechanism: `GTS9P_….conf` = `export CONFIG_PANEL_GTS9P_ANA38407_AMSA24VU05_WQXGA=y`,
  pulled in by the Kbuild `include` → merged Kbuild alone wires the panel, no
  defconfig append. Merged Kbuild ships in gts9p-imports (GTS9P block inserted
  after the GTS9 block, xxd shell vars suffixed `_GTS9P`, XXD/SED defs deduped).
- Touch module name: **`stm_ts_fts1b90a.ko`** (Samsung's own truncated TARGET
  spelling in the fts1ba90a Makefile – do not "correct" it). Fatal check in
  build-gts9pwifi.sh keys on this; `wez01.ko` stays warn-only.
  [SUPERSEDED 2026-08-30: wez01.ko is now build-FATAL - the wacom
  drivers/input wiring ships in gts9p-imports, so a missing pen module
  means broken wiring, not an expected gap.]
- Driver drift, azkali vs X818U base (documented, azkali's proven copies win;
  first suspects if gts9p touch/pen ever misbehaves): fts_ts.c 14 changed
  lines / 3297; wacom_i2c.c 148 / 3662; plus fts_ts.h, fts_sec.c, wacom_dev.h,
  wacom_reg.h. Symbols confirmed in azkali `vendor/kalama-gki_defconfig`
  (FTS1BA90A line 1345, WEZ01 line 1369).
- AWH8 panel.c/h confirmed different from base → delta applied in the bundle.
- Artifacts: `gts9p-imports.tar.gz`
  (sha256 bce7f412…, [SUPERSEDED 2026-08-30: use `devices/gts9pwifi/imports/` at repo
  HEAD – that tarball predates the wacom drivers/input wiring]),
  `build-gts9pwifi.sh`, `x810-extract.sh`.

Remaining runway: fork samsung-gts9p skeleton (gts9u→gts9p rename checklist in
build script header) → pull + x810-extract the AWHA zip on the build box →
unit prep (fuse/binary check in Download mode, unlock, TWRP-gts9p boot test,
FULL backup incl. EFS, stock /proc/cmdline capture) → build → flash ladder:
display → touch (stm fts1ba90a) → wifi (kiwi_v2) → audio → pen (wez01).
