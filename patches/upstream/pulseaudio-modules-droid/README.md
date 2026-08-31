# pulseaudio-modules-droid extevdev fix (backport ask)

**Target:** UBports/Azkali packaging of `pulseaudio-modules-droid-30`.
**Ask:** bump to ≥ **14.2.110** or cherry-pick mer-hybris commit `dfda983`
(PR #135). Azkali's 2026-07-28 snapshot ships **14.2.109** – three days
before the upstream fix – so every image cut from it is affected.

**Status: UNSENT.** Highest-leverage open item #1 (PORT-STATE.md §6).

## What it fixes

UT jack detection (droid-extevdev) scans evdev for
`EV_SW`+`SW_HEADPHONE_INSERT`. On a jackless tablet no such device exists;
the error path then calls `mainloop_io_free()` on a never-created io event →
PA assert (`mainloop.c:206`) → SIGABRT, crash-looping PulseAudio at boot.
Scope: **every jackless halium-13 24.04 device** on -30 at 14.2.107–14.2.109.

This was the *only* audio bug on gts9wifi (the Ultra hit four more in front
of it – see PORT-STATE.md §3).

- `0001-extevdev-Fix-startup-crash-when-no-input-device-is-f.patch` –
  verbatim dfda983 backport onto 14.2.109.
- `extevdev-crash-field-report.md` – field report written for the
  Azkali/UBports issue (symptoms, versions, bisection, fix validation).

On-device workaround while unfixed: `fixes/audio/gts9-audio-fix-install.sh`
(version-gated so it self-retires once the bump lands).
