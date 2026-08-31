# gts9uwifi audio — full diagnosis + fix scoping (session 8)

## Status: ROOT CAUSE PROVEN. Fix is code-level (package rebuild), not config.
PA/droid audio does not initialise; every other subsystem works. This is the
one open blocker of daily-driver quality and it is now fully characterised.

## The crash, proven end-to-end
Chain (mapped to the instruction, not inferred):
1. pulseaudio loads touch.pa → `module-droid-card-30` (libdroid-util-30.so)
2. droid-util → `/android/system/lib64/hw/audio.hidl_compat.default.so` (the
   UT pulseaudio-modules-droid-hidl shim, Android-side, loads via Android
   linker namespace — NOT reachable by PA --dl-search-path)
3. shim calls `android::DevicesFactoryHalInterface::create()` (AOSP libaudiohal
   factory picker) → binds Samsung's registered `android.hardware.audio@7.1::
   IDevicesFactory/default` (pid 769) — transport WORKS
4. factory loads legacy primary device → **FAILS**:
   `E DevicesFactoryHAL: loadAudioInterface couldn't open audio hw device in
    audio.primary (Invalid argument)`  → openDevice returns **-19 (EINVAL)**
5. shim's error path leaves its device member NULL, then makes a virtual call
   through it: crash at shim offset 0x2280 `ldr x8,[x0]` with x0=0
   (`ldr x0,[x19,#336]` loaded the null; next `ldr x1,[x8,#56]; br x1` = vtable
   dispatch through null). Deterministic, environment-robust.

## VINTF / lshal facts (context)
- Vendor declares & registers audio@7.0 AND @7.1 IDevicesFactory (pid 769),
  audio.effect@7.0, and vendor.samsung.hardware.audio@1.0::ISehDevicesFactory.
- Framework asks for audio.effect@**7.1** → hwservicemanager "Cannot find" (7.0
  is what's registered) — a parallel version-skew symptom, same family.
- Primary HAL impls present: android.hardware.audio@{2,4,5,6,7.0,7.1}-impl.so;
  legacy passthrough: audio.primary.kalama.so (917 KB) + audio.primary.default.so.
- ro.hardware=qcom, ro.board.platform=kalama.

## Hypotheses ELIMINATED (do not re-try)
1. HIDL version mismatch — FALSE; both 7.0 and 7.1 register.
2. droid module generation (28/29/30) — FALSE; all three crash identically.
3. `audio_hw_if` → `primary` string swap — FALSE; string lives in
   libdroid-util (patched, no effect) and in the shim (Android-side); and the
   -19 is about the open *path/variant*, not the module name.
4. Policy XML version / 11"-vs-Ultra XML — FALSE; gts9 XML is byte-identical
   to vendor's own, both version="7.1".
5. primary module `halVersion="2.0"`→"7.1" — FALSE; droid-card's XML parser
   only honours v1.0 semantics (warns "only support version 1.0"), so the
   attribute isn't consumed on the open path.

## The actual fix — two viable paths (code-level)
### Path A (preferred): patch the droid-hidl shim
`pulseaudio-modules-droid-hidl` (source: gitlab.com/ubports or
github.com/mer-hybris/pulseaudio-modules-droid-hidl). On -19 from the legacy
`audio.primary` open, the shim should fall back to the **enum-based
`IDevicesFactory::openDevice(DeviceType)`** (the 7.1 native path) instead of
the legacy string open — OR bind Samsung's `ISehDevicesFactory` directly.
Deliverable: rebuilt audio.hidl_compat.default.so, shipped via the halium-
overlay file-bind (skeleton already overlays system/vendor files this way,
e.g. init.rc, sensors multihal). Reversible, upstreamable.
Start: disassemble the create()→openDevice sequence, add null-check +
enum-open fallback, cross-build against libaudiohal 7.1 headers.

### Path B: fix legacy audio.primary.kalama.so dlopen under hybris
The -19 ultimately = the legacy primary HAL won't load in the container's
linker namespace. Investigate its NEEDED deps + namespace visibility
(likely a Qualcomm libar-*/libaudioroute path not exposed to the hybris ns).
Deliverable: namespace/ld.config addition or dep overlay. Deeper, vendor-side.

## Immediate next actions (next session)
1. `objdump -dC audio.hidl_compat.default.so` around create()@0x2098 +
   openDevice call site; identify the exact branch that skips the 7.1 path.
2. Clone pulseaudio-modules-droid-hidl; locate DeviceHal open logic;
   prototype the -19 fallback.
3. In parallel, container-side: `linker64` the primary HAL with ABSOLUTE path
   to get its real dlopen error (tonight's relative-path attempt errored on
   the linker, not the lib); enumerate NEEDED vs namespace-visible libs.
4. Interim: device is fully usable **silent** — no audio, everything else
   (display, touch, pen, wifi, battery, charging, keyboard, settings) works.

## Provenance for upstream bug report
Samsung SM-X910 (kalama, gts9uwifi), UT 24.04-2.x, pulseaudio-modules-droid-30
14.2.109 + droid-hidl 1.5.1. Crash + -19 + VINTF skew all captured above.
