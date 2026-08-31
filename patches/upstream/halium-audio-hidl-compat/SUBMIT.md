# Ready-to-send: Halium shim null-deref hardening

Everything below is prepared; the send is the only missing step.

## Where to file
- Project: `github.com/Halium/android_vendor_halium_hardware`
  (branch `halium-13.0`; the affected code is byte-identical across
  halium-12.0…16.0 and master — say so in the PR and offer to target
  whichever branch they prefer).
- Attach/PR: `0001-audio_hw-fail-adev_open-when-the-devices-factory-can.patch`
  (3-line early-return in `audio/audio_hw.cpp` `adev_open`), with
  `shim-crash-analysis.md` linked as the evidence dossier.

## Suggested title
`audio_hw: fail adev_open when the device factory cannot open the vendor
device (fixes PA SIGSEGV crash-loop on open failure)`

## Suggested body (paste and adjust)
> `audio.hidl_compat.default.so`'s adev_open logs the HIDL factory
> openDevice() failure (e.g. -19) but returns 0 with a null deviceIface.
> The caller (pulseaudio-modules-droid via droid-util) believes the device
> opened; the first forwarded call (adev_init_check) dereferences null and
> PulseAudio SIGSEGVs (SEGV_MAPERR, fault_addr 0x0 — core-verified on a
> Samsung SM8550 tablet, PC at shim file offset 0x2280), crash-looping PA
> at every boot on any device whose vendor HAL fails to open.
>
> This patch propagates the factory failure instead. Note this is
> HARDENING, not a root-cause fix for whatever made the vendor HAL fail —
> with it, PA gets a clean open failure and no sinks instead of a crash
> loop, which is also far easier to diagnose in the field. Full analysis
> (disassembly, core, reproduction) in the linked crash-analysis document.

## Also worth drafting while in this area (ledger #3)
`lpass_cdc_unregister_macro` (lpass-cdc.c ~722–761) zeroes
`macro_params[id].num_dais` before subtracting from `priv->num_dais`, so
the count never decrements and any macro unbind is unrecoverable without a
reboot. Kernel-side, separate target (Azkali's kernel tree / CodeLinaro).
Not yet drafted.
