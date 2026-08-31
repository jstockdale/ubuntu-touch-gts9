# Audio Debugging Postmortem — Ubuntu Touch on Samsung Galaxy Tab S9 Ultra (SM-X910, gts9uwifi)

**Author's context:** halium-based UT port, kalama SoC, UT 24.04-2.x, PulseAudio
16.1 with pulseaudio-modules-droid-30 (14.2.109) + pulseaudio-modules-droid-hidl
(1.5.1). Samsung vendor HAL is HIDL android.hardware.audio@7.0/@7.1.

This documents the diagnosis of a PulseAudio init crash that blocked all audio,
the five hypotheses eliminated en route, the proven root cause and fix for the
crash, and the one remaining gate. Written so the reasoning is reusable — the
methodology matters more than the specific bug.

---

## 1. Symptom

On every boot, PulseAudio failed to initialise audio. Manual foreground run:

    module-droid-card.c: Create new droid-card
    droid-util.c: Opened hw audio device version 2.0 (compiled for API 3.1, Android 11.0.0)
    <SIGSEGV>

No sinks, no sources. The rest of the device (display, touch, wifi, battery,
etc.) worked; audio was the lone hard blocker of daily-driver quality.

---

## 2. Method

Because the crash sat behind a chain (PulseAudio host module → Android-side
compat shim → vendor HIDL service → legacy HAL), each layer had to be isolated.
Tools used, in rough order: gdb backtrace with mapping capture, objdump/nm/
strings on the Android .so's, lxc-attach + logcat with HAL-side verbose logging
raised via `setprop log.tag.* V`, linker64 --list for dependency resolution, and
mount --bind to test patched library copies without touching the read-only
Android system image.

Key discipline: **every hypothesis had to be falsifiable and falsified with
evidence**, not abandoned on a hunch. Five were.

---

## 3. Hypotheses eliminated

**H1 — HIDL version mismatch (shim wants 7.0, vendor only has 7.1 or vice versa).**
Killed by lshal: the vendor service (pid 769) registers BOTH
`android.hardware.audio@7.0::IDevicesFactory` AND `@7.1`. libaudiohal@7.1.so
contains both openDevice and openDevice_7_1. No version gap at the factory.

**H2 — Wrong droid-card module generation.** touch.pa loads `-30`; generations
28/29/30 are all installed. All three crashed identically. (Caveat that mattered
later: this first A/B ran BEFORE the string fix, so all three died at the crash,
masking any post-open difference. Re-run after the fix — still identical, so
genuinely not generation-specific.)

**H3 — The `audio_hw_if` string, patched in libdroid-util.** Correct target,
wrong copy. The string exists in host libdroid-util, but patching a copy in
/tmp and pointing PA at it via --dl-search-path did nothing, because the crash
is in the ANDROID-side shim (audio.hidl_compat.default.so) which loads through
the Android linker namespace, not PA's search path. (This looked like a failed
hypothesis but was actually a delivery-mechanism error — see Root Cause.)

**H4 — Policy XML version / 11"-vs-Ultra config.** The gts9 policy XML is
byte-identical to the vendor's own audio_policy_configuration.xml, both
version="7.1". Not an 11"-vs-Ultra difference.

**H5 — primary module halVersion="2.0" vs "7.1".** Editing the attribute did
nothing: droid-card's XML parser only honours v1.0 policy semantics (it warns
"We only support audioPolicyConfiguration version 1.0"), so the halVersion
attribute isn't consumed on the open path.

Also ruled out — **Path B, "the legacy primary HAL won't load."** linker64 --list
on audio.primary.kalama.so resolved EVERY NEEDED lib (full Qualcomm PAL/AGM
stack: libar-pal, vendor.qti.hardware.pal, libagm, plus Samsung libsecaudio*).
Zero missing. The HAL loads fine; it was never the problem.

---

## 4. Root cause (proven)

HAL-side verbose logging was the breakthrough. With `log.tag.DevicesFactoryHAL V`
and the audio HAL tags raised, retriggering PA produced, from Samsung's own
driver:

    V audio_hw_primary: adev_open: audio_hw_if
    E audio_hw_primary: devicesFactoryHal->openDevice() error -19 loading module audio_hw_if

**halium's libdroid-util passes the hardcoded legacy interface name
`audio_hw_if` as the module to open. Samsung's HAL only recognises `primary`,
so it returns -19 (ENOSYS).** droid-util then holds a NULL device pointer and
the shim dereferences it through a vtable slot — the crash, mapped precisely to
audio.hidl_compat.default.so offset 0x2280 (`ldr x8,[x0]` with x0=0, i.e.
loading the vtable from a null `this`, then `br x1` dispatching through it).

Lenient vendor HALs accept `audio_hw_if` as an alias for primary; Samsung's
does not. This is a genuine halium-on-Samsung bug.

---

## 5. Fix (proven for the crash)

Binary-patch the string in libdroid-util, same length via NUL padding:

    "audio_hw_if\0"  (12 bytes)  →  "primary\0\0\0\0\0"  (7 + 5 NUL = 12 bytes)

Applied to libdroid-util-{28,29,30}.so. **Confirmed by the HAL's own log** — post
patch it reads `adev_open: primary` and returns a device; the -19 and the SIGSEGV
are gone. The string on the failing path lives in libdroid-util (host side, in
the UT rootfs), NOT the Android shim — so it delivers as a plain rootfs overlay,
no bind needed in the shipping image.

Correcting H3: the string patch was always the right fix. The earlier failure was
that the patched copy was never loaded (wrong dir + wrong namespace), and the
first search wrongly concluded the string wasn't on the path. Lesson: verify the
patched artifact is the one actually loaded (post-bind `strings | grep` count)
before concluding a patch had no effect.

---

## 6. Remaining gate (open)

After the successful open, droid-util rejects the device with a DIFFERENT error:

    droid-util.c: Failed to open audio hw device : Invalid argument (22)   [EINVAL]

Evidence it's droid-util-internal, not Samsung: the HAL logs `adev_open: primary`
then nothing (no adev_init_check follows). The EINVAL is generated inside
droid-util on the returned device struct. The immediately preceding log line —
`droid-util.c: Droid hw module 16.1` — points at a version-compat gate:
droid-util likely validates device->common.version (or the reported API level)
and rejects Samsung's HIDL-compat device. Identical across all three generations;
independent of config= path and module_id. This is the next session's target:
disassemble droid-util's post-open init_check/version comparison and either relax
the gate or correct the reported version — or, cleaner, rebuild
pulseaudio-modules-droid from source with both the module-name and version fixes.

---

## 7. Lessons for the next halium-on-Samsung audio bring-up

1. **Raise HAL-side log tags early.** `setprop log.tag.DevicesFactoryHAL V` (and
   the audio HAL tags) turned a mute -19 into a named cause. This should be step
   one, not step ten — it would have skipped most of the hypothesis tree.
2. **Locate the crash's linker namespace before patching.** Host PA modules
   (--dl-search-path) and Android-side shims (Android linker namespace) are
   different worlds; a patch in the wrong one silently no-ops.
3. **Verify the patched artifact is the loaded artifact.** Post-bind
   `strings <target> | grep <oldstring>` returning 0 is the proof the loader
   sees your change.
4. **linker64 --list with an ABSOLUTE path** to check a vendor HAL's deps;
   relative paths error in the linker itself and give a false "it's broken."
5. **Samsung strictness:** its HAL rejects the generic `audio_hw_if` module
   alias that lenient vendors accept. Expect Samsung to be the strict one on
   any name/version handshake.

---

## 8. Provenance / upstream report seed

SM-X910 (kalama, gts9uwifi), UT 24.04-2.x, pulseaudio-modules-droid-30 14.2.109,
pulseaudio-modules-droid-hidl 1.5.1. Two defects in halium droid audio vs Samsung
kalama HIDL-compat HAL: (a) hardcoded module name `audio_hw_if` — Samsung wants
`primary` — causing -19 and a null-deref crash; (b) a post-open version gate
rejecting the device with EINVAL(22). Fix (a) proven via string patch confirmed
by HAL log; fix (b) pending disassembly. File against gitlab.com/ubports/
pulseaudio-modules-droid.
