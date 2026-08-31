# gts9wifi – Tab S9 11" (SM-X710)

This is **Azkali's upstream port** – the reference the whole family forks
from. The device tree, kernel, and build tooling live upstream:

- Device repo: `gitlab.com/azkali-samsung/gts9/ubports/samsung-gts9`
  (branch `halium-13`)
- Kernel: `…/kernel-samsung-gts9wifi` + 10 techpacks
  (branch `android13-5.15-halium`)
- Build tools: `halium-generic-adaptation-build-tools`
  (branch `personal/azkali/gts9-integration`)

The reference unit is daily-driven on Azkali's UT 24.04-2.x dev build
(port-composed A13 fingerprint over the A15-era X710XXU5CYD9 vendor – see
FIRMWARE.md). This repo carries **our contributions back**, not a fork:

## What we run/fix on it

- **Audio** – the 11" hits only bug #4 of the family audio chain (the
  droid-extevdev jackless abort; Azkali's 2026-07-28 snapshot ships
  pulseaudio-modules-droid-30 14.2.109, three days before the upstream fix).
  Installed fix: `fixes/audio/gts9-audio-fix-install.sh` (version-gated,
  refuses on ≥14.2.110). Upstream ask: `patches/upstream/pulseaudio-modules-droid/`.
- **S-Pen** – digitizer fully alive at evdev (`wez01.ko` loads cleanly here);
  pointer-only in apps, same Mir 1.8 ceiling as the Ultra. Pressure-sensitive
  Krita on the rootfs is proven impossible on this build – and installing
  desktop krita **breaks lomiri** (see CONTRIBUTING.md rule 3).
- **Folio touchpad** – same rotation daemon as the Ultra
  (`fixes/input-touchpad/`, name-generic).

## Open on this device

- GPS: structural HIDL-vs-AIDL mismatch (UT bridge is HIDL-1.x-only; SM8550
  vendor exposes AIDL IGnss V2). Cannot be fixed via apt; lead:
  `libgps.so.30`/gpsd in lomiri-location-serviced. PORT-STATE.md §6 #9.
- Bluetooth HAL crash-loop (~62 s SIGKILL cycle) – cold boot clears it;
  root cause uncaptured.
- The 2.x-build boot-hang from July (reserved-memory suspect) was never
  root-caused; dtbo diff still to do.
