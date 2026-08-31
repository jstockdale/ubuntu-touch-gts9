# Halium audio_hw shim patch

**Target:** `Halium/android_vendor_halium_hardware`, branch `halium-13.0`
(`audio/audio_hw.cpp` – the `audio.hidl_compat.default.so` shim).
Affected code is byte-identical across halium-12.0…16.0 and master.

**Status: UNSENT.** Highest-leverage open item #2 (PORT-STATE.md §6).

## What it fixes

`adev_open` logs the HIDL factory `openDevice()` failure (e.g. -19) but
**returns 0 with a null deviceIface**. The caller (pulseaudio
module-droid-card via droid-util) believes the device opened, and the first
forwarded call (`adev_init_check`) dereferences null → PulseAudio SIGSEGV
(SEGV_MAPERR, fault_addr 0x0; PC = shim file offset 0x2280 – core-verified on
gts9uwifi).

`0001-audio_hw-fail-adev_open-when-the-devices-factory-can.patch` makes
`adev_open` propagate the factory failure instead.

Note for the PR text: this is **hardening, not the root cause** – the SEGV is
the messenger for whatever made the vendor HAL fail to open (on gts9uwifi,
the card-offline latch chain). With the patch, PA gets a clean open failure
and no sinks instead of a crash loop.

`shim-crash-analysis.md` is the full evidence dossier (disassembly, core
analysis, reproduction).
