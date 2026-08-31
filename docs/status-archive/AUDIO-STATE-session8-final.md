# gts9uwifi audio — state at session-8 close (READ FIRST next session)

## HEADLINE: crash SOLVED. One version-gate remains before sinks.

## What was wrong and what's fixed
The PA droid audio stack SIGSEGV'd at init on every boot. Root cause, proven
to the HAL's own log:
- halium `libdroid-util-{28,29,30}.so` passes the hardcoded legacy module
  name **`audio_hw_if`** to Samsung's audio HAL `adev_open`.
- Samsung's HAL only knows **`primary`** → returns **-19 (ENOSYS)** → droid-util
  gets a NULL device → shim dereferences it via vtable → SIGSEGV
  (mapped: audio.hidl_compat.default.so +0x2280, `ldr x8,[x0]`, x0=0).

**FIX (proven):** binary-patch the string `audio_hw_if`\0 → `primary`\0\0\0\0\0
(same 12 bytes) in libdroid-util. After patch, HAL logs `adev_open: primary`
and returns a device — the -19 and the crash are GONE. Script:
out/audio-fix/apply-string-patch.sh (patches all gens, keeps .orig backups).

## REMAINING gate (next session starts here)
After the successful open, droid-util rejects the device with **EINVAL(22)**:
  `droid-util.c: Failed to open audio hw device : Invalid argument (22)`
Key facts:
- HAL log shows `adev_open: primary` then NOTHING (no adev_init_check) — so the
  EINVAL is generated INSIDE droid-util on the returned device, before the HAL
  is called again. NOT a Samsung-side rejection.
- Immediately preceding line: `droid-util.c: Droid hw module 16.1` — strong
  suspicion this is a version-compat gate: droid-util validates
  device->common.version (or the reported 16.1 API) and rejects it.
- Identical across droid-card generations 28/29/30 (all tested WITH the string
  patch) — structural, not generation-specific.
- config= path vs no-config vs module_id=primary: all fail the same way, so
  it's not the policy XML and not the module_id.

## Next-session plan (Path A continued)
1. Disassemble libdroid-util-30.so: find where it calls adev->init_check or
   reads common.version after hw_device_open, and where it returns -EINVAL/22.
   Symbol hints: droid_open_audio_device / droid_hw_module init path.
2. Determine what version it demands vs Samsung's reported 2.0/16.1. Likely a
   `if (version < X || version != Y) return -EINVAL`. Patch the comparison, OR
   patch the device's reported version if that's cleaner.
3. Alternatively: rebuild pulseaudio-modules-droid from source
   (gitlab.com/ubports/pulseaudio-modules-droid) with the module-name fix +
   version-gate relaxed — the clean upstream form of both patches.
4. Once a sink is created: start via the session unit (not -n foreground),
   pactl list sinks, paplay to confirm the quad CS35L45 speakers.

## Permanent delivery (both patches)
Patched libdroid-util-{28,29,30}.so → skeleton overlay at
system/usr/lib/pulse-16.1+dfsg1/modules/ (host-side PA modules, plain overlay,
not even a bind needed since these are in the UT rootfs we build). Fold into
gts9uwifi-skeleton. Document + file upstream bug: halium droid-util hardcodes
audio_hw_if and version-gates too strictly for Samsung kalama HIDL-compat HAL.

## Provenance (for upstream)
SM-X910 kalama, UT 24.04-2.x, pulseaudio-modules-droid-30 14.2.109,
droid-hidl 1.5.1. adev_open: audio_hw_if→-19 (fixed→primary), then EINVAL(22)
version gate. Full logcat + disasm in session-8 transcript.

---
## S-PEN update (session-8 close, separate from audio)
evtest device scan shows NO wez01/wacom digitizer input node. Present: gpio-keys,
pmic_pwrkey/resin, meta_event, **hall_wacom** (garage/holster detect — works),
hall, hall_logical, sec_touchscreen, sec_touchpad, Book Cover Keyboard (EF-DX920).
Missing: the e-pen position/pressure device (expected sec_e-pen / wacom_e-pen).
Diagnosis shape: wez01 loaded + garage/hall half works, but the EMR DIGITIZER
input device never registered. NOT a pairing issue (EMR is passive, no BT pair
needed for position/pressure). NOT the enumeration race (touchscreen node present).
Next session: check dmesg for wez01 digitizer probe / firmware-load
(wez01_gts9u.bin) / e-pen IRQ; likely a pen-channel DT or fw dependency failed
while the holster channel succeeded.
