# Ubuntu Touch gts9wifi → gts9uwifi (SM-X910) Port – Status & Plan

Updated: 2026-08-03. All "verified" items were confirmed directly against the
shipped `ubuntu-touch-gts9wifi-24.04-2.x.zip` (2026-07-29 build), Azkali's
sources at `gitlab.com/azkali-samsung/gts9/ubports`, and the
`samsung-sm8550-tab` community sources – not inferred from documentation.

## 1. Verified architecture of the existing gts9wifi port

Halium 13, GKI-style, built by `halium-generic-adaptation-build-tools`
(branch `personal/azkali/gts9-integration`) driven by `samsung-gts9/deviceinfo`.

- Kernel: Samsung X710 OSRC 5.15 tree + halium patches, built with the
  generic `vendor/kalama-gki_defconfig` + `halium.config`. The kernel image
  is board-agnostic within the kalama (SM8550) family. Shipped kernel reads
  `Linux version 5.15.153 #1 SMP PREEMPT`, plain vermagic (no Samsung ab-tag).
- Techpack DLKM repos (display, graphics, camera, audio, wlan, bt, securemsm,
  mmrm, mm-drivers, eva): pristine imports of the **X710XXU5CYD9** BSP,
  zero halium patches. The halium delta lives in the main kernel
  (dwc3-msm role-switch ordering, usb_notify OTG-boost gating, LSM config,
  DT carveout experiments) and in the userspace overlay.
- boot.img (v4): bare gzip GKI kernel, no ramdisk, empty cmdline.
- init_boot.img (v4): halium initrd (lz4), loads 124 early modules
  (clocks/regulators/UFS/SMMU/SMEM – board-neutral set).
- vendor_boot.img (v4): **generic Qualcomm Kalama SoC DTB** (452,771 B,
  byte-identical to `vendorboot/vendor_dtb`, zero `gts9` strings),
  cmdline `video=vfb:... firmware_class.path=/vendor/firmware_mnt/image
  bootconfig loop.max_part=7`, bootconfig
  `androidboot.hardware=qcom / memcg=1 / usbcontroller=a600000.dwc3`.
- DTBO: `deviceinfo_skip_dtbo_partition="true"` – nothing flashes dtbo.
  The **stock Samsung dtbo partition stays in place** and ABL applies the
  board overlay over the flashed generic base DTB. The repo's
  `vendorboot/dtbo` (4 entries, "Samsung GTS9WIFI PROJECT", board-ids
  00/01/02/04) is a rebuilt reference; the cont_splash DT experiment on it
  was reverted upstream.
- super (11,643,387,904 B), LP metadata parsed from the shipped image:
  system 4,718,592,000 (UT rootfs, ext4) · system_ext 145,027,072 ·
  system_dlkm 348,160 (stock Samsung stub: zram/zsmalloc only) ·
  product 1,347,670,016 · vendor 1,725,878,272 (EROFS) ·
  vendor_dlkm 35,713,024 (EROFS, repacked) · odm 872,448 (stub, `etc` only).
  Group `ubuntu` max 7,974,100,992. All partitions are single-extent.
- vendor identity: `gts9wifi / SM-X710`, fingerprint
  `samsung/gts9wifixx/gts9wifi:13/TP1A.220624.014/X710XXU5CYD9:user/release-keys`,
  security patch 2025-04-01.
- update-binary (matches repo bit-for-bit): asserts
  `ro.product.device == gts9wifi`, dd's boot/init_boot/vendor_boot/vbmeta to
  the current slot, streams `super.img.zst` → `/dev/block/by-name/super`.
- Module strategy (`scripts/swap-vendor-modules.sh`): vendor_dlkm is
  extracted (EROFS), every name-matched .ko is replaced by the halium-built
  one, repacked `mkfs.erofs -zlz4`.

## 2. The decisive constraint (verified)

vermagic census over all 363 modules in the shipped vendor_dlkm:

- 342 × `5.15.153 SMP preempt mod_unload modversions aarch64` (halium-built)
- 15 × `5.15.153-android13-8-30958166-abX710XXU5CYD9 ...` (stock leftovers)

With `modversions` and mismatched vermagic, stock Samsung modules **cannot
load** on the halium kernel. Everything functional on gts9wifi is built from
source. Stock kernel strings are model-tagged (`abX910...` on the Ultra), so
this holds identically there: **the Ultra's board drivers must exist in the
halium source tree.** (LineageOS's gts9uwifi alpha sidesteps this by running
the stock prebuilt kernel, which UT cannot – AppArmor requires a rebuild.)

## 3. What is missing for gts9uwifi (verified absences)

1. **Panel driver.** `display-drivers/msm/samsung/` contains exactly one
   panel: `GTS9_ANA38407_AMSA10FA01` (the 11" S9). The community
   `sm8550-modules` repo adds S23-family, Flip5, Fold5 panels – still no
   `GTS9U_*`. The Ultra's 14.6" 2960×1848 panel driver exists **only in
   Samsung's SM-X910 OSRC release**. Until imported and wired into
   Kconfig/Makefile, the Ultra boots headless.
2. **Board DTS.** Kernel tree has only
   `arch/arm64/boot/dts/samsung/galaxytab/gts9wifi/` (4 flattened
   per-revision monoliths, r00/r01/r02/r04). The community
   `sm8550-devicetrees` repo likewise has gts9wifi but no gts9u. Needed only
   for rebuilding an Ultra DTBO (e.g., to reproduce the modem-carveout
   reclaim – X910 WiFi also has no modem); **not needed for first boot**
   thanks to the stock-dtbo mechanism.
3. Possible touch-IC delta. gts9wifi uses STM `stm_ts_fts1b90a` (in-tree,
   halium-built). Whether the Ultra shares the IC or uses a sibling falls
   out of the X910 DTS/defconfig. `stm32_pogo_v3` (Book Cover Keyboard) is
   already in-tree.

## 4. Empirical support for kernel portability

The NinjaSU project ships kernels built from **X710** Samsung source that
users run successfully on **SM-X910** (and even X916C 5G) – consistent with
the generic-kalama-defconfig + DTBO-selects-board architecture. The halium
kernel should therefore boot the Ultra unmodified; the gap is modules, not
the kernel image.

## 5. Port plan

### Phase 1 – source imports (blocked on SM-X910 OSRC download)
- Import `GTS9U_*` panel directory from the X910 drop's display techpack
  into `display-drivers/msm/samsung/` + Kconfig/Makefile/panel-Kbuild wiring
  (mirror how GTS9_ANA38407_AMSA10FA01 is wired).
- Import `galaxytab/gts9u*` DTS + Makefile into the kernel tree.
- Diff X910 vs X710 kernel trees for board drivers absent in X710
  (touch IC, charger/fuel-gauge, speaker amp count).
- Sanity-diff the other techpacks (expected ≈ nil delta).

### Phase 2 – firmware bundle (unblocked: run `x910-extract.sh` on the 15 GB zip)
- Produces `parts/` (vendor, odm, product, system_ext, system_dlkm,
  vendor_dlkm) for `scripts/super.sh`, plus stock boot/vendor_boot/dtbo/
  vbmeta/recovery and the PIT, plus `info.txt` with the Ultra's
  SUPER_DEVICE_SIZE, LP layout, and vendor fingerprint.
- Firmware-era note: the X710 port pins X710XXU5CYD9 (2025-04 patch).
  Match the closest X910 5-series build (e.g., CYD9/CYG1-era, Android 15).
  Same-bootloader-major (v5) is required anyway for the unlock constraint.

### Phase 3 – device repo fork (`gts9uwifi`)
- `deviceinfo`: codename `gts9uwifi`; SUPER and recovery partition sizes
  from the X910 PIT/info.txt; `bootimg_os_patch_level` matching the X910
  base; everything else initially inherited.
- Rename/duplicate the ~20 `*gts9wifi*` overlay files
  (deviceinfo yaml → PrettyName "Tab S9 Ultra", udev rules, repowerd,
  sensord, systemd overrides); regenerate the pulse/audio XMLs from the
  X910 vendor's audio configs; verify `BacklightSysfsPath`
  (`panel0-backlight`) and torch path on-device.
- Touch calibration: matrix `0 1 0 -1 0 1` on `sec_touchscreen` – verify
  the Ultra's input device name and panel mount orientation on the bench.
- `update-binary`: `EXPECTED_CODENAME="gts9uwifi"` (confirm the exact
  `ro.product.device` TWRP reports on X910).
- vendorboot/: reuse the generic kalama `vendor_dtb` and bootconfig as-is
  (same SoC, same `a600000.dwc3` / `1d84000.ufshc` addresses).
- `swap-vendor-modules.sh`: unchanged mechanism against X910 vendor_dlkm;
  after Phase 1 the halium build will contain the Ultra panel/touch modules
  to swap in.

### Phase 4 – bench ladder
1. Prereq: pre-fuse-bit-6 unit, bootloader unlocked, TWRP for gts9u,
   **full backup incl. EFS + PIT** before anything else.
2. Flash boot/init_boot/vendor_boot/vbmeta + assembled X910 super;
   leave dtbo stock.
3. First contact: USB rndis/adb into the halium initrd
   (expect headless until Phase 1 panel work lands).
4. Ladder: panel → touch → WiFi (same qca6490) → audio →
   sensors → cameras (droidmedia + X910 vendor HAL; Azkali's
   qtubuntu-camera fork) → UDFPS (biometryd branch
   `personal/azkali/aidl-udfps-onuiready` is directly reusable) →
   pogo keyboard → 45 W PD negotiation.

## 6. Feature expectations for "complete support"

- Display/GPU: full once the panel driver lands (same Adreno 740 / hybris
  path). Refresh will follow the DDIC's default mode initially.
- Bigger OLED scaling: 14.6" 2960×1848 ≈ 239 PPI vs 11" ≈ 274 PPI –
  expect a GridUnit adjustment in the deviceinfo yaml for comfortable UI.
- Cameras: primary front + back photo/video first (matches what the
  gts9wifi port advertises); the aux ultrawides (8 MP rear, 12 MP front)
  depend on HAL enumeration through droidmedia – stretch goal.
- GPS: N/A – WiFi-model Tab S9s have no GNSS hardware.
- S Pen: basic input/hover via sec_touchscreen expected; pressure in apps
  is limited by UT, not the port.
- DeX-style external display: experimental in UT at best – not promised.

## 7. Open items

- [ ] Access to the 15 GB X910 firmware (Drive link currently auth-walled)
      – either open sharing or run `x910-extract.sh` locally and share
      `stockimgs/dtbo.img`, `vendor_boot.img`, `boot.img`, the `.pit`, and
      `info.txt` (~60 MB total suffices for full remote analysis:
      Ultra board-id census, panel/touch compatibles from the DTBO,
      stock kernel string, SUPER size).
- [ ] Pull SM-X910 OSRC drop (opensource.samsung.com) for Phase 1.
- [ ] Confirm exact `ro.product.device` string in X910 TWRP.
- [ ] Confirm whether Azkali's install flow ever flashes the rebuilt dtbo
      (build config says no; worth one question upstream, and he has
      standing interest in Tab S9+/Ultra reports – no hardware).
- [ ] X910 audio topology check (amp count / mixer paths) before
      regenerating pulse XMLs.

## 8. Addendum – X910 firmware surgical analysis (2026-08-03, session 3)

Drive access restored; the file is `X910XXS5CYG1` (Android 15, 2025-07 era,
5-series bootloader). Extracted via ranged HTTP + streaming inflate without
storing the 15 GB archive: `boot.img`, `dtbo.img` in hand; super.img.lz4
located at ~29.5 MB into the AP tar stream (9,088,585,073 B) for the next
carve pass; PIT (in CSC member) still pending.

Verified Ultra facts from the stock DTBO + boot image:

- Codename at DT level: "Samsung GTS9UWIFI PROJECT", two hw revisions
  (board-id 00 and 03) vs four on the S9.
- Stock kernel: `5.15.153-android13-8-30958166-abX910XXS5CYG1` – same
  5.15.153 / KMI 30958166 generation as the X710 CYD9 base; only the model
  tag differs. Confirms (a) Azkali's tree is the right generation for the
  Ultra, (b) stock X910 modules are model-tagged and unusable on the halium
  kernel, as predicted.
- **Panel: `GTS9U_ANA38407_AMSA46AS02`** (disp-model AMSA46AS02, same
  ANA38407 DDIC family as the 11") – this is the exact OSRC display
  directory name to import; wiring mirrors `GTS9_ANA38407_AMSA10FA01`.
- **Touch: Goodix Berlin @ I²C 0x5d only** (single-sourced on the Ultra),
  with `qts,trusted-touch` properties → it is the Qualcomm
  **touch-drivers techpack** goodix_berlin driver. That techpack is absent
  from the halium repo set and the goodix source is absent from the kernel
  tree (verified) → required import (from the X910 BSP techpacks), added to
  `deviceinfo_kernel_vendor_modules`. Note: the S9 is dual-sourced
  (Goodix @0x5d or STM @0x49 by hw rev); Goodix-rev S9 units likely lack
  touch on the current port – the same import fixes them.
- Audio: identical quad Cirrus CS35L45 topology (rearleft/frontleft/
  rearright/frontright @ 0x30–0x33) → X710 audio configs port ~1:1.
- Charger/PD: same SM5714 pair (`sm5714@49`, `usbpd-sm5714@33`).
- Fingerprint: Egis `etspi,el7xx`, chip EL721 – same family as the S9;
  the UDFPS biometryd branch applies to both.
- Cameras: five sensor nodes (cam-sensor 0/1/2/8/12) vs three on the S9 –
  stock DTBO covers the extra optics; enumeration through the X910 vendor
  HAL is the remaining variable.
- S-Pen: full Wacom WEZ01 node on both boards – see `SPEN-PLAN.md`
  (new workstream, backport-ready by construction).

Revised open items: SM-X910 OSRC pull now covers panel + gts9u DTS
(+ cross-check its touch-drivers techpack version); super partition carve
(script delivered, or next session via the located stream offset); PIT for
SUPER/recovery sizes; wacom Kconfig wiring check at first build.

## 9. Addendum – session 4: PIT, full firmware bundle, skeleton

- PIT `GTS9UWIFI_EUR_OPEN.pit` parsed: **SUPER = 11,744,051,200 B**
  (vs 11,643,387,904 on X710 – +96 MiB; super.sh default updated in the
  skeleton), RECOVERY = 109,576,192 (identical), INIT_BOOT 8 MiB,
  BOOT/VENDOR_BOOT partitions 96 MiB, DTBO 16 MiB. Stock super LP metadata
  independently reports the same device size.
- Full X910 firmware bundle carved remotely via streaming
  (odm/product/system_dlkm/system_ext/vendor/vendor_dlkm) – the 15 GB
  archive was never stored. Stock LP order: system (6.9 G), odm, product,
  system_dlkm, system_ext, vendor, vendor_dlkm; group
  `qti_dynamic_partitions`.
- Vendor identity verified: `ro.product.vendor.device=gts9uwifi`,
  fingerprint `...X910XXS5CYG1`, patch 2025-07-01 → update-binary
  assertion string confirmed.
- S-Pen firmware `wez01_gts9u.bin` (262,164 B) confirmed in X910
  `/vendor/firmware/`; Goodix touch firmware under `tsp_goodix/`.
- **Correction to §8:** the Ultra's touch driver ships on stock as
  `goodix_ts_berlin.ko` inside vendor_dlkm (362-module census) – a
  Samsung-built module, so its source comes with the SM-X910 OSRC drop
  (not necessarily the QC touch-drivers techpack as first hypothesized).
  X710 stock vendor_dlkm has no goodix module, consistent with Azkali's
  STM-rev unit; the import fixes Goodix-rev S9 units too.
- Wacom wiring verified missing: `drivers/input/Kconfig` sources neither
  `wacom/` nor `sec_input/` – the two-line wiring in SPEN-PLAN §2 is
  required (mirror however sec_input is included).
- Deliverable: `gts9uwifi-skeleton.tar.gz` – renamed device repo with
  verified SUPER size, patch level, codename assertion, S-Pen udev rule,
  kernel-additions notes, PIT + PORT-README included.

## 10. Addendum – session 5: SM-X910 OSRC acquired, source gap CLOSED

EUR OSRC drop (2025-05-07, CYD9-era – same 5.15.153 / KMI 30958166
generation as the port's base; build target gts9uwifi_eur_open,
PROJECT_NAME=gts9uwifi) pulled from Drive and surgically extracted.
Deliverable: `gts9u-imports.tar.gz` – overlay-ready for the two repos,
with IMPORT-GUIDE.md.

Key resolutions:
- Panel: GTS9U_ANA38407_AMSA46AS02 imported complete (incl. pre-generated
  _PDF.h + panel_data .dat). X710↔X910 msm/Kbuild differ ONLY in the panel
  block; merged Kbuild carries both, gated per-panel, runtime-selected via
  DT → one msm_drm.ko serves both boards.
- Touch: goodix/berlin source located at msm-kernel
  drivers/input/touchscreen/goodix/berlin (sec_input-integrated; module
  target literally `goodix_ts_berlin` → auto name-match in the vendor_dlkm
  swap). Imported + wired.
- S-Pen: CONFIG_EPEN_WACOM_WEZ01=m is ALREADY in vendor/kalama-gki_defconfig
  on BOTH boards; Samsung's LEGO system injects wiring at build time, which
  is why the armed symbol sat inert. The static 2×2 wiring lines in the
  bundle are the entire kernel-side enablement – gts9wifi backport included.
- Verified requiring NO import: camera-kernel (gts9u sensor branches already
  in the X710 import's kalama.mk), audio-kernel (family conf), wlan
  (kiwi_v2_defconfig already present; deviceinfo now kiwi_v2 – Ultra is
  WCN785x kiwi, caught via stock module diff qca_cld3_kiwi_v2.ko).
- DTS: gts9uwifi r00/r03 imported (matches DTBO board-ids 00/03).

Critical path is now entirely local: apply bundle → kernel/techpack build →
assemble X910 super (parts already carved) → TWRP flash → bench ladder.

## 11. Addendum – session 6: compile validation PASSED

Container caveat: 1 core / 3 GB - full build deferred to real hardware via
`build-gts9uwifi.sh`. What WAS built here, against the actual halium tree
with the bundle applied: Kconfig merge live for both new symbols;
**wez01.ko (S-Pen, 2.87 MB) and goodix_ts_berlin.ko (5.08 MB) both compile
clean**; gts9uwifi r00 DTS compiles standalone to a valid overlay. Module
naming note: Samsung's Makefile names the pen module `wez01.ko`. Deliverables:
validation tarball (.ko proofs + .config + dtbo), turnkey build-gts9uwifi.sh
(stages skeleton + imports + X910 parts, bypasses the X710 firmware fetch via
local tar basename match, builds, swaps, assembles super at 11,744,051,200,
packages the flashable zip, prints the bench ladder).

## 12. Addendum – session 7: FIRST FULL BUILD ASSEMBLED
Full pipeline completed on real hardware: kernel + all techpacks (incl.
msm_drm with GTS9U panel), rootfs, module swap (kiwi_v2 WiFi, goodix,
wez01 - the latter revealing stock ships it, correcting §the earlier census;
pen loads via standard vendor modules.load), vendor_dlkm repack non-root
with forced root ownership, lpmake super at the PIT-exact layout. Build-time
fixes folded back into artifacts: kiwi IPA offload disable, OSRC 0444 mode
hardening, img2simg/dtc/fakeroot preflight, aarch64-lpmake detection,
non-root swap. libsparse "Invalid sparse file format" probe warnings during
lpmake are benign (raw-image fallback). Next: TWRP flash + bench ladder.

## 13. Addendum – session 8: FIRST LIGHT + bring-up debugging harvest

**Ubuntu splash rendered on the ANA38407** (~5-7 s on a virgin boot) – full
chain proven: cmdline panel fix -> GTS9U probe -> cont-splash handoff ->
container -> hwcomposer -> lightdm -> splash. Kernel-side confirmed on
silicon: wez01 S-Pen (garage/survey traffic), goodix_ts_berlin (i2c-66@5d),
kiwi WiFi stack loaded, EL721 FPS, full 12 GB RAM.

Failure archaeology (each root-caused):
- Boot 1: OOM storm killed journald/container (cause TBD; logs destroyed -
  persistent journald now enabled to catch a recurrence).
- All post-storm container failures: STALE /dev/__properties__ from prior
  attempts -> AOSP init EEXIST error path NULL-deref (si_addr=0x14) SEGV.
  Clean area => container runs. Durable fix: stale-state clean in container
  pre-start (patch for whole gts9 family).
- Unit-vs-manual anomalies: second-container collisions (same name/rootfs,
  different lxcpath) - debugging shrapnel, not port bugs.
- Later container deaths: SIGINT delivered host-side = collateral of system
  shutdowns, not a container bug.
- Recurring ~2-3 min poweroffs: systemd-logind broadcast; HandlePowerKey
  mask insufficient => API-initiated. Prime suspect: UPower battery-critical
  false positive from the wez01 pen-battery power_supply (0%/discharging).
  Mitigation: mask upower+repowerd + inhibitor; proper fix: hide pen supply
  from UPower via udev (or driver reports capacity unknown).
- gts9u TWRP quirk: /var/lib/lxc + /etc live under a layer that re-locks rw
  remounts; /run drop-ins + retry-loop writes are the reliable levers.

On-device state to clean AFTER root fixes land: /etc/systemd/logind.conf.d/
90-gts9u.conf, /etc/systemd/system/{upower,repowerd}.service null-masks.
Keep: /var/log/journal. Port-side TODO: pre-start stale-clean, pen-battery
udev hide, phantom power-key source hunt (input sniffer: suspect hall/cover
or garage polarity), ready-gate apex handling review, boot-1 OOM watch.
