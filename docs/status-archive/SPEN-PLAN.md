# S-Pen (Wacom EMR) Enablement – gts9uwifi + gts9wifi backport

Goal: working S-Pen on the Ubuntu Touch port for the Tab S9 Ultra (SM-X910),
designed so the identical pieces land on the Tab S9 (SM-X710) afterward.
All hardware facts below were read directly out of the stock DTBOs
(X910XXS5CYG1 and the repo's gts9wifi reference dtbo) and the halium kernel
tree – none are assumed.

## 1. Hardware map (verified, both boards)

| Item                | gts9uwifi (X910)            | gts9wifi (X710)             |
|---------------------|-----------------------------|-----------------------------|
| Digitizer           | Wacom WEZ01, I²C @ 0x56     | identical node @ 0x56       |
| DT compatible       | `wacom,w90xx`, status okay  | `wacom,w90xx`               |
| Firmware file       | `wez01_gts9u.bin` (in X910 vendor) | `wez01_gts9.bin` (confirmed at `/vendor/firmware/wez01_gts9.bin`) |
| Pressure / tilt / hover | 4095 levels / ±63° / 255-step height | same property set |
| Extras in DT        | garage + dual-garage, cover detection, AOP mode, boot_addr 0x09, elec cal tables | same family |
| Attach detect       | `hall_wacom` hall-sensor node | same                       |

The DT node arrives via the **stock dtbo partition** (untouched by the port),
so no DT work is required on either board. The pen surface is part of the
Wacom layer, independent of the main touch IC (Ultra: Goodix Berlin @0x5d;
S9: Goodix @0x5d or STM @0x49 depending on hw rev).

## 2. Kernel piece

- Driver source: `drivers/input/wacom/` in the halium kernel tree
  (`kernel-samsung-gts9wifi`, branch `android13-5.15-halium`):
  `wacom_i2c.c`, `wacom_i2c_sec.c`, `wacom_i2c_elec.c`, `wez01_flash.c`
  (in-driver firmware flashing), `wacom_dev.h`, `wacom_reg.h`.
- Config: `CONFIG_EPEN_WACOM_WEZ01` (tristate; module name `wacom`).
  Add `CONFIG_EPEN_WACOM_WEZ01=m` to `halium.config`.
- **Wiring caveat (VERIFIED REQUIRED: drivers/input/Kconfig sources neither wacom nor sec_input):** `drivers/input/Makefile` in this
  tree contains no wacom hook. If `make` doesn't pick the symbol up, add the
  standard two lines:
  - `drivers/input/Kconfig`: `source "drivers/input/wacom/Kconfig"`
  - `drivers/input/Makefile`: `obj-$(CONFIG_EPEN_WACOM_WEZ01) += wacom/`
- Dependencies already satisfied: the driver leans on the `sec_input` core
  (`sec_cmd`, `sec_input_notifier`, tsp log) which is present and already
  built (its modules ship in the current vendor_dlkm swap set), and on
  `sec_class` (in the initrd module list).

## 3. Module delivery & load

The halium build installs its module set into the rootfs
(`workdir/tmp/system/{usr/,}lib/modules/…`); udev coldplug autoloads by
OF modalias when the I²C device from the stock DT probes. `wacom.ko`
should therefore autoload with zero extra plumbing once built. Belt and
braces:

- Add `wacom.ko` to the *vendor_dlkm swap awareness*: it will not name-match
  anything in stock vendor_dlkm (stock ships **no** wacom module – verified,
  363-module census), so it must live in the rootfs tree; nothing to swap.
- Optional explicit load: a `modules-load.d` entry (or appending to the
  overlay's module lists) guards against modalias misses.
- Firmware: the driver requests `wez01_gts9u.bin` / `wez01_gts9.bin`;
  present in each board's stock vendor at `/vendor/firmware/`. The halium
  container exposes vendor at `/vendor` (symlink into /android), and the ACK
  firmware loader searches `/vendor/firmware` after
  `firmware_class.path=/vendor/firmware_mnt/image`. Validate on bench that
  the request resolves; if not, a one-line udev firmware path or symlink
  into the rootfs `/lib/firmware` fixes it.

## 4. Input-stack piece (Ubuntu Touch side)

- The driver registers a distinct input device for the pen (Samsung's
  `sec_e-pen`), exposing ABS_X/Y at digitizer resolution, ABS_PRESSURE,
  ABS_TILT_X/Y, ABS_DISTANCE (hover), BTN_TOOL_PEN/BTN_TOOL_RUBBER,
  BTN_STYLUS (side button).
- udev rules (device repo overlay, one file shared by both boards):
  1. permissions: covered by the existing `input/event*` rule
     (system:input 0660) – verify group access for Mir.
  2. classification: ensure `ID_INPUT_TABLET=1` (libinput usually infers
     this from BTN_TOOL_PEN; add an explicit hwdb/udev property if not).
  3. calibration: pen coordinates share the panel mount, so the same
     90°-rotation matrix used for `sec_touchscreen`
     (`LIBINPUT_CALIBRATION_MATRIX="0 1 0 -1 0 1"`) must be applied to the
     wacom event node – new rule matching the wacom input name.
- Phase A target (both boards): pen as high-precision pointer + hover +
  side button in Lomiri via libinput/Mir tablet handling.
- Phase B (validation, honest unknowns): pressure/tilt delivery into apps
  depends on qtmir/Mir tablet-tool event forwarding; if Mir delivers
  tablet events but qtmir flattens them to pointer, pressure-aware apps
  won't see levels without upstream work. Scope: verify with `evtest`
  first (kernel truth), then `libinput debug-events`, then in-shell.
- Garage/attach events surface via the hall sensor and driver sysfs
  (sec_class) – usable later for palm-off/pen-detected UX; out of scope
  for initial landing. BLE Air Actions: out of scope (no UT concept).

## 5. Bench validation ladder

1. `modinfo wez01.ko` (Samsung names the module wez01, not wacom) → confirm vermagic + OF alias `i2c:wacom,w90xx*`.
2. Boot; `dmesg | grep -i wacom` → probe, fw version, flash-if-needed path
   (`wez01_flash` logs).
3. `ls /dev/input/by-path/ | grep -i pen` / `evtest` → hover, contact,
   pressure range 0–4095, tilt, button.
4. `libinput debug-events` → tool proximity/tip/pressure seen as tablet.
5. Lomiri: cursor tracking, hover, tap, side-button behavior.
6. Regression check: main touchscreen (Goodix) unaffected; pogo keyboard
   (`stm32_pogo_v3`) unaffected.

## 6. Backport checklist → gts9wifi (X710)

Identical by construction; the deltas are only:
- firmware name `wez01_gts9.bin` (already in X710 vendor – verified);
- the udev calibration rule matches the same wacom device name (confirm the
  X710 unit's reported name string matches the Ultra's);
- test matrix must cover both touch-IC revisions (Goodix @0x5d and
  STM @0x49) to confirm no sec_input interaction regressions.
Everything else – config flag, Makefile wiring, module placement, rules –
is shared and lands from the same commits.

## 7. Pieces summary (the "carefully noted" list)

1. `halium.config`: `CONFIG_EPEN_WACOM_WEZ01=m`.
2. (If needed) `drivers/input/{Kconfig,Makefile}` two-line wiring.
3. Rootfs module tree gains `wacom.ko` (automatic once built).
4. Overlay: udev rule file `74-gts9-wacom.rules`
   (calibration matrix + tablet classification), shared by both boards.
5. Kernel config: CONFIG_EPEN_WACOM_WEZ01=m already present in vendor/kalama-gki_defconfig on both boards (verified) - wiring lines alone activate it.
6. Firmware: none to add – stock vendor already carries
   `wez01_gts9{,u}.bin`; bench-verify loader path resolution.
6. Optional: modules-load.d fallback entry; garage/hall UX later.
7. Validation ladder §5 on Ultra first, then replay on X710.

## Build-time correction (2026-08-03, first successful gts9uwifi assembly)
Stock X910 vendor_dlkm DOES ship wez01.ko (earlier census grep missed the
name). Consequence: wez01 is already in vendor modules.load, so the swapped
halium build loads via the standard vendor path automatically - the
modalias-autoload and modules-load.d fallbacks in section 3 are moot.
Confirmed in the swap: wez01.ko and goodix_ts_berlin.ko both replaced
name-matched stock modules; vendor_dlkm repacked at 36,626,432 B with
--force-uid=0/--force-gid=0 (non-root build path).
