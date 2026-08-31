# FLASHING — Odin, unlock, TWRP, and installing Ubuntu Touch

Copyright (c) 2026 John Stockdale and Off by One, Inc. — BSD 3-Clause (see LICENSE).

The hands-on companion to [FIRMWARE.md](FIRMWARE.md) (which firmware to use)
and the device READMEs (what to flash). Read the bootloader-fuse warning in
the [README](README.md) first — some mistakes here are irreversible.

## Tooling

- **Odin 3.14** (recommended; Windows-only) for all stock-firmware and
  recovery flashing. Samsung's bootloader speaks Odin protocol only — there
  is no fastboot on these tablets (fastbootd exists later, inside TWRP).
- **TWRP** (the gts9-family build) as recovery, flashed via Odin.
- **adb** on any OS for sideloading the Ubuntu Touch zip.

## Flashing stock firmware with Odin

To put a specific firmware on the device, load these slots in Odin:

| Odin slot | File from the factory package |
|---|---|
| **BL** | `BL_*.tar.md5` |
| **AP** | `AP_*.tar.md5` |
| **CSC** or **HOME_CSC** | `CSC_*.tar.md5` / `HOME_CSC_*.tar.md5` |

- **HOME_CSC** preserves user data; **CSC** wipes (and applies the PIT
  layout). For a cross-major rollback (e.g. One UI 8.0 → 7.0) use the full
  **CSC**.
- **Preserve your bootloader rev unless you truly need to roll it forward** —
  flashing a higher-rev BL burns the fuse permanently (see FIRMWARE.md).
  Match the package to your unit's rev.

### One UI 8.0 on a rev 5 unit — still recoverable

One UI 8.0 does **not expose** the OEM Unlocking toggle — but the fuse is
what decides unlockability, not the installed OS. A unit that updated to One
UI 8.0 while its bootloader fuse is **still rev 5** can be Odin-flashed back
to a One UI 7.0 (rev 5) package — BL + AP + full CSC — and unlocked
normally. Check `RP SWREV` in Download Mode before assuming a One UI 8
device is lost: only **rev 6+** is terminal.

## Unlocking a rev 5 unit (fail-proof path, from factory reset)

Verified procedure on the project's rev 5 units:

1. Boot and run Android setup, **skipping WiFi** entirely.
2. Set the date/time **manually**, accurate to within a minute or two.
3. Turn **off** automatic software updates (Settings → Software update).
4. Enable Developer options (Settings → About → Software information → tap
   **Build number** ~7 times) and turn on **USB debugging**.
5. Sign in to your **Samsung account** (Settings → Samsung account) — the
   device must check in with Samsung's servers for the unlock toggle to arm;
   auto-update is already off, so this brief connectivity is safe.
6. Back in Developer options, **OEM Unlocking** should no longer be greyed
   out — enable it.
7. **Power off** the device.

## Flashing TWRP (Odin)

1. Open Odin on the PC. On the powered-off tablet, hold **Volume Up +
   Volume Down** and plug in USB-C — the screen turns teal and the tablet is
   in Download Mode (Odin shows a COM port).
2. In Odin: **uncheck Auto Reboot** (Options tab).
3. Load the TWRP image in the **AP** slot and Start.
4. Power off: hold **Power + Volume Down** for ~10 seconds.
5. **Immediately** hold **Power + Volume Up** — through the "Samsung Galaxy /
   Knox" splash — to boot straight into the freshly flashed TWRP.

⚠ **If stock Android boots even once, it silently restores the stock
recovery and TWRP is gone.** No harm done — just repeat the Odin flash and
the recovery-boot combo.

## Installing Ubuntu Touch (TWRP)

Take your backups FIRST (full TWRP backup including EFS + the raw partition
dumps — CONTRIBUTING.md rule 10). Then:

1. In TWRP: **Format Data** (Wipe → Format Data).
2. Connect the tablet to your computer over USB-C.
3. TWRP → **Advanced → ADB Sideload**, swipe to start.
4. On the computer:
   ```bash
   adb sideload <ubuntu-touch-build>.zip
   ```
   Tip from the field: the sideload progress meter is unreliable — an
   apparent stall around ~45% is a known progress-bar artifact, not a
   failure; let it finish.
5. Reboot to system. First boot of a fresh port: see the device README
   (on the Ultra, boot unplugged the very first time), then run the
   device's `fixes/post-flash/` script.

## Rev 1 units

The rev 1 (new-in-box) unlock flow is expected to match the rev 5 procedure
above, but it has not been re-verified on the project's rev 1 units yet —
this section will be confirmed and updated when the 1-series (AWHA)
validation happens. Rev 1 extras that already apply: keep the unit offline
except for the Samsung sign-in step, and archive its factory package before
anything else (FIRMWARE.md).
