# RECON: gts9uwifi device-skeleton tarballs + import/validation packs

Recon pass 2026-08-30 over `_capture/files/`. All tarballs extracted and
diffed under `_capture/scratch/{orig,working,audio,gts9u-imports,gts9p-imports,validation}`.

## TL;DR

- **`audio-config/outputs/gts9uwifi-skeleton-audio.tar.gz` is canonical.** It is a
  strict superset of the original skeleton: +7 new files, +2 wants-symlinks,
  1 file replaced, 1 script improved, nothing lost.
- The "three" skeletons are really **two**: the original
  (`porting-orig/outputs/gts9uwifi-skeleton.tar.gz`) and the user's re-upload
  (`audio-config/uploads/gts9uwifi-skeleton__2__tar.gz`, also
  `ultra-main/uploads/gts9uwifi-skeleton__2__tar.gz`) are **byte-identical
  tarballs** — md5 `abbf05902541decf654b881de74d20fd` for all three copies.
  The audio tarball is md5 `9ff0bf6e0816ceb80ad9141b1bfd7a7e`.
- Entry counts: orig/working 221 tar entries, audio 236 (+15 = 7 files
  + 2 symlinks + 7 new dirs, −1 removed file... net matches).
- The audio tarball also carries the **S-Pen-as-touchscreen input fix**
  (udev rule + libinput quirks, dated 2026-08-10, "Verified working"), i.e. it
  is really an "audio + pen input" skeleton, newer than its name suggests.

## 1. What the skeleton is, structurally

Single top dir `samsung-gts9u/` — a Halium 13 / UT 24.04 (`24.04-2.x`) device
tree for **gts9uwifi = Samsung Galaxy Tab S9 Ultra Wi-Fi (SM-X910)**.

```
samsung-gts9u/
├── deviceinfo                  # the port's identity/build config (see below)
├── build.sh, .gitlab-ci.yml, .gitignore, PORT-README.md
├── GTS9UWIFI_EUR_OPEN.pit      # Odin partition table (SUPER=11744051200)
├── vbmeta.img
├── kernel-additions/halium.config.append
├── overlay/system/             # rootfs overlay (the bulk of the port)
├── ramdisk-overlay/            # bin/kmod, init, panic/telnet scripts
├── ramdisk-recovery-overlay/   # recovery.fstab, panel firmware .dat, tsp_stm fw
├── vendor-ramdisk-overlay/lib/modules/   # modules.{load,load.recovery,alias,blocklist}
├── vendorboot/                 # prebuilt dtbo, vendor_dtb + vendor_dts,
│                               # bootconfig(.recovery), initrd-touch-arm64-noloader.img
├── scripts/                    # make-flashable.sh, super.sh, swap-vendor-modules.sh,
│                               # prebuilt/lpmake
└── flashable/                  # META-INF update-binary, prebuilt/zstd, README
```

### deviceinfo highlights
- codename `gts9uwifi`, aarch64, kernel source
  `gitlab.com/azkali-samsung/gts9/ubports/kernel-samsung-gts9wifi.git`
  branch `android13-5.15-halium`; defconfig `vendor/kalama-gki_defconfig + halium.config`;
  clang `r450784e`, LLVM build.
- Prebuilt boot ramdisk `vendorboot/initrd-touch-arm64-noloader.img`; prebuilt
  dtb/dtbo from `vendorboot/`; `skip_dtbo_partition=true`; bootimg header v4,
  `has_init_boot_partition=true`; os 13, patch level 2025-07.
- `deviceinfo_kernel_wlan_chip="kiwi_v2"` (WCN785x, not qca6490) +
  `CONFIG_SEC_SS_CNSS_FEATURE_SYSFS=y` extra opt.
- Vendor modules list: mm-drivers (msm_ext_display/sync_fence/hw_fence), mmrm,
  securemsm, display-drivers/msm, graphics-kernel, audio-kernel, wlan
  (platform + qcacld-3.0), bt-kernel, camera-kernel, eva-kernel.
- Unified recovery (`use_unified_recovery=true`, xxhdpi, recovery partition
  109576192 = matches PIT), system partition 4500M, halium_version 13.

### Modules lists
- `vendor-ramdisk-overlay/lib/modules/modules.load` — 124 lines (boot set:
  sec_* debug, qcom clk/icc/ipcc, tsens, regulators, ufs, display path...).
- `modules.load.recovery` — 416 lines (full recovery set).
- `overlay/system/etc/modules-load.d/gts9uwifi.conf` — loads
  `sm5714_fuelgauge` + `sm5714-charger` (without them capacity reads 0 and
  UPower powers the tablet off ~2–3 min after boot).

### Overlay (`overlay/system/`) — key config groups
- **HAL/container**: `etc/gbinder.conf` (ApiLevel 33);
  `usr/share/halium-overlay/` overlaying the Android side — lxc `config`,
  `vendor/etc/init/*.rc` (incl. `gts9-sensors-hidl.rc`, vndservicemanager,
  boringssl_self_test, qcom usb), vintf `manifest_kalama.xml` +
  `gts9-sensors-hidl.xml`, `vendor/lib64/hw/gralloc.default.so`,
  sensors@2.1 multihal binary; `usr/lib/gts9uwifi/start-android-container`.
- **Graphics**: `etc/default/lsc-wrapper.d/10-force-hwc2.conf` +
  `20-gts9uwifi-disable-overlays.conf`; apparmor graphics.d android12.
- **Audio (pre-fix state)**: `etc/pulse/touch.pa` (standard UT per-user PA
  policy) + `etc/pulse/gts9/audio_policy_configuration.xml`,
  `audio_policy_volumes.xml`, `default_volume_tables.xml`; PA drop-in
  `50-gts9uwifi-wait-audiohal.conf` (tolerant 90 s wait for the vendor audio
  HAL, `-` prefixed = never blocks PA). Apparmor audio.d gts9uwifi.
- **Power/display**: repowerd `config-gts9uwifi.xml` + wait-backlight /
  wait-battery drop-ins; UPower.conf; logind drop-in.
- **Input**: udev `70-gts9uwifi.rules`, `71-…-touch-calibration.rules`,
  `72-…-adb-recover.rules`, `73-…-usb-cable.rules`, `74-gts9-wacom.rules`.
- **USB/MTP/ADB**: usb-moded config + mtp dyn-mode, umtprd (binary + conf +
  service), gts9-adb-gadget/gts9-adb(.recover).service, adbd-prepare.
- **Storage/EFS**: gts9-efs-ro.service, gts9-ensure-efs-mountpoint(.service)
  wired via `.wants` symlinks into mount-android-partitions/-system.
- **Misc**: NetworkManager wifi-mac conf, sensorfw conf, Waydroid binder
  drop-in + `gts9-waydroid-binder` helper, environment.d (hybris ld path,
  gst-no-hybris), tmpfiles journal conf, deviceinfo yaml
  (`etc/deviceinfo/devices/gts9uwifi.yaml`), aalcamera Qt mediaservice plugin,
  panel firmware `.dat` files under `usr/lib/firmware`.
- Lomiri greeter/shell timeout drop-ins under `etc/systemd/user/`.

### PORT-README.md (orig)
Generated 2026-08-03 from samsung-gts9 (halium-13); verified against
X910XXS5CYG1 PIT, stock kernel 5.15.153-android13-8-30958166, DTBO
board-ids 00/03. TODO list = exactly what the import packs later delivered
(GTS9U panel import, goodix_ts_berlin, gts9u DTS, wacom Kconfig wiring).

## 2. Deltas between the three skeleton tarballs

### orig vs working copy (`gts9uwifi-skeleton__2__tar.gz`)
**None.** Identical tarball bytes (same md5, three copies:
`porting-orig/outputs/`, `audio-config/uploads/`, `ultra-main/uploads/`).
File-content md5 sweep and symlink-target sweep both come back identical.
The `__2__` upload is just the user round-tripping the original back into
later sessions. (Note: `diff -rq` alone "errors" on two paths — those are the
dangling `.wants` symlinks, present and identical in both.)

### working vs audio (`gts9uwifi-skeleton-audio.tar.gz`) — the audio delta
All inside `samsung-gts9u/`; file dates 2026-08-08 → 08-10.

**Added (7 files + 2 symlinks + 7 dirs):**

| Path (under `overlay/system/`) | Purpose |
|---|---|
| `usr/local/sbin/gts9u-audio-bringup` (103-line sh) | v3 boot bring-up: manual walk of vendor_dlkm `modules.load` (deduped, blocklist-honored) to fill holes left by the parallel modprobe storm; curated `finit_module(…, IGNORE_MODVERSIONS\|VERMAGIC)` stage via python3 for `muic_sm5714 pdic_sm5714 wez01` (charging + S-Pen); waits `card_state=1` (90 s); chmods `card_state`/`aud_dev/state` 0666 for container AGM; clears Samsung latch `vendor.audio.use.primary.default`; `ctl.restart vendor.audio-hal`; waits for virtual h2w device; touches `/run/gts9u-audio-ready` |
| `etc/systemd/system/gts9u-audio-bringup.service` | oneshot, `TimeoutStartSec=360` (v1's 240 could kill the script mid-wait), RemainAfterExit |
| `etc/systemd/system/gts9u-virtual-h2w.service` | runs the uinput jack daemon, Restart=on-failure |
| `usr/local/lib/gts9u-virtual-h2w.py` | virtual EV_SW uinput device advertising SW_HEADPHONE/MIC/LINEOUT_INSERT, state 0 — droid-extevdev treats "no jack switch device" as fatal and aborts PA via null `mainloop_io_free()`; this sidesteps it |
| `etc/systemd/system/multi-user.target.wants/{gts9u-audio-bringup,gts9u-virtual-h2w}.service` | enable symlinks (`-> ../…`) |
| `etc/systemd/user/pulseaudio.service.d/zz-gts9u-audio.conf` | PA gates hard (no `-`, `timeout 150`) on `/run/gts9u-audio-ready`; strips `HYBRIS_USE_VENDOR_NAMESPACE`; relaxes sandboxing (MemoryDenyWriteExecute=no, empty SystemCallFilter, LockPersonality=no, RestrictNamespaces=no) |
| `etc/udev/rules.d/61-gts9u-pen.rules` | S-Pen (`sec_e-pen`) classified as touchscreen (no zwp_tablet_v2 in UT 24.04 Lomiri/Mir 1.x); "Verified working 2026-08-10" |
| `etc/libinput/local-overrides.quirks` | `[Samsung S-Pen gts9u]`: +INPUT_PROP_DIRECT, strips BTN_TOOL_PEN/RUBBER/STYLUS/STYLUS2 so the touchscreen path wins |

**Removed (1):**
- `etc/systemd/user/pulseaudio.service.d/50-gts9uwifi-wait-audiohal.conf` —
  the old tolerant HAL-wait drop-in, superseded by `zz-gts9u-audio.conf`
  ("two drop-ins double-resetting ExecStart is merge-order roulette").

**Modified (1):**
- `scripts/swap-vendor-modules.sh` — +14 lines: dedupe every
  `modules.load*` at repack (`awk '!seen[$0]++'`), restore mode/owner and
  selinux xattr, print `before -> after` line report. Rationale in-script:
  stock list ships **4x duplicated**; `vendor_modprobe.sh` fires every line in
  parallel with exit codes discarded, so duplication multiplies the storm and
  the odds of any module silently losing the race (observed drops:
  `lpass_cdc_va_macro`, `machine_dlkm` → no sound card).

Everything else (vendorboot blobs, PIT, vbmeta, modules lists, all other
overlay files) is hash-identical across all three tarballs.

**Companion doc**: `audio-config/outputs/CHANGES-audio.md` describes exactly
this patchset (2026-08-08 "first-sound session"), including the five-bug
chain it closes and the one live-device fixup (Timeout 240→360 sed). The
matching `audio-config/outputs/build-gts9uwifi.sh` adds a pre-build sanity
block verifying these artifacts exist before the multi-hour build.

## 3. Import packs (display/input driver sources)

### `porting-orig/outputs/gts9u-imports.tar.gz` (50 files) — Tab S9 **Ultra**
Overlay bundle onto the two azkali repos (`kernel-samsung-gts9wifi` +
`display-drivers`, branch android13-5.15-halium). Provenance: SM-X910 EUR
OSRC drop 2025-05-07 (CYD9-era, kernel 5.15.153 / KMI 30958166).
`IMPORT-GUIDE.md` contents:
- **New**: `drivers/input/touchscreen/goodix/berlin/` (Samsung
  sec_input-integrated Goodix Berlin; module `goodix_ts_berlin` name-matches
  stock vendor_dlkm so swap-vendor-modules auto-replaces it);
  `arch/arm64/boot/dts/.../gts9uwifi/` r00/r03 DTS (only needed if rebuilding
  the Ultra DTBO); `display-drivers/msm/samsung/GTS9U_ANA38407_AMSA46AS02/`
  full panel driver + `panel_data_file/*.dat`.
- **Merged replacements (4)**: input Kconfig/Makefile (wacom wez01 wiring),
  touchscreen Kconfig/Makefile (goodix wiring); plus `msm/Kbuild` GTS9U block
  (13 lines) after the GTS9 block — both panels compile into one msm_drm.ko,
  runtime-selected via DT.
- `halium.config.gts9u-append`: note `CONFIG_EPEN_WACOM_WEZ01=m` already in
  kalama-gki_defconfig; Samsung's LEGO build injects wiring at build time —
  the static Kconfig/Makefile wiring here is the whole S-Pen kernel
  enablement.
- **Verified NOT needing import**: camera-kernel (kalama.mk already has
  gts9u branches), audio-kernel (family filter includes gts9uwifi), wlan
  (kiwi_v2_defconfig present; deviceinfo selects it).

### `tabS9plus-port/outputs/gts9p-imports.tar.gz` (26 files) — Tab S9 **Plus**
Same overlay pattern for gts9pwifi (SM-X810). `MANIFEST.md`:
- gts9pwifi DTS (r00/r02/r04 + Makefile) from `SM-X810_13_Opensource_dts.zip`
  (X810XXU1AWG1); `GTS9P_ANA38407_AMSA24VU05` panel from SM-X818U base zip
  with `_panel.c/.h` overridden from the AWH8 delta; Kbuild = azkali Kbuild +
  GTS9P block (vars suffixed `_GTS9P`, XXD/SED defs deduped).
- **Deliberately excluded** (azkali tree wins): stm/fts1ba90a touchscreen
  (azkali drifts 14 lines — halium patches), wacom wez01 (~148-line drift),
  config fragment (symbols already in defconfig); cmdline retarget is a sed
  in `build-gts9pwifi.sh`, not an append.

## 4. `gts9u-compile-validation.tar.gz` (VALIDATION.md, 2026-08-03)
Compile-proof of the gts9u-imports bundle on the halium tree (Ubuntu clang
18.1.3, 1-core container, full build deferred to hardware):
- Kconfig merge works: `CONFIG_EPEN_WACOM_WEZ01=m` and
  `CONFIG_TOUCHSCREEN_GOODIX_BRL=m` both land in `.config`.
- `wez01.ko` (2,874,272 B) clean compile — **module is named `wez01`, not
  `wacom`** (matters for modules.load/modinfo).
- `goodix_ts_berlin.ko` (5,078,768 B) clean, name matches stock vendor_dlkm.
- `gts9uwifi_eur_open_w00_r00.dts` → `gts9u_r00.dtbo` via dtc -@.
- **Caveat**: the .ko files are proof-of-compile only (clang 18,
  external-module mode, no MODVERSIONS CRCs) — shippables come from the
  pinned r450784e toolchain build. Remaining watchpoint: msm_drm full link
  with the GTS9U panel object (low risk).

## 5. Canonical verdict

- **Skeleton**: `audio-config/outputs/gts9uwifi-skeleton-audio.tar.gz`
  (md5 `9ff0bf6e…`). Strict superset of the original; encodes the debugged
  first-sound configuration + verified pen-input fix + the modules.load
  dedupe build fix. The original and `__2__` uploads are the same bytes and
  matter only as the pre-audio baseline.
- **Imports**: both packs are current and complementary
  (`gts9u-imports` = Ultra, `gts9p-imports` = Plus); no other versions exist
  in the capture.
- **Known post-tarball drift**: CHANGES-audio.md notes the live tablet ran a
  v1 unit with `TimeoutStartSec=240`; the tarball ships 360 (correct). The
  audio tarball's bringup already includes the finit_module stage for
  wez01/muic/pdic, i.e. it is newer than the "separate pen loader, later"
  note in CHANGES-audio's log-reading section.

## Extraction locations
- `_capture/scratch/orig/`, `scratch/working/`, `scratch/audio/` — skeletons
- `_capture/scratch/gts9u-imports/`, `scratch/gts9p-imports/`,
  `scratch/validation/` — import packs + validation
- `scratch/{orig,working,audio}.md5` / `.links` — the comparison manifests
