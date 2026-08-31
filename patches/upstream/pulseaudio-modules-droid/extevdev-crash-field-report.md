# Field report: droid-extevdev NULL io_free aborts PulseAudio on jackless devices (14.2.107–14.2.109)

**Status:** root cause already fixed upstream by Azkali in mer-hybris/pulseaudio-modules-droid
`dfda983` ("extevdev: Fix startup crash when no input device is found", 2026-07-31, PR #135),
first contained in tag **14.2.110**. This report is (a) independent field confirmation that
currently-shipping UT 24.04 images are affected, (b) system-level impact detail beyond the
commit message, (c) a version-range pin, and (d) an interim workaround for already-flashed
devices until the packaging bump lands.

## Environment

- Device: Samsung Galaxy Tab S9 11" (SM-X710, `gts9wifi`, kalama), Azkali's Halium 13 port
- OS: Ubuntu Touch 24.04 (noble), image built 2026-07-29, kernel 5.15.153
- pulseaudio-modules-droid version on device: `[FILL IN: dpkg-query -W 'pulseaudio-modules-droid*']`
  (inferred 14.2.107–14.2.109 line from the crash string, which only exists in the
  libevdev-free extevdev rewrite `746178f`, first in 14.2.107)
- Hardware relevant: no 3.5 mm jack; no input device advertises `SW_HEADPHONE_INSERT`
  (verified via `/proc/bus/input/devices` SW masks), no h2w entry in `/sys/class/switch/`

## Symptom and system-level impact

On every boot, PulseAudio aborts during `module-droid-card` init:

```
pulseaudio[7156]: could not start input device detection.
pulseaudio[7156]: Assertion 'e' failed at ../src/pulse/mainloop.c:206, function mainloop_io_free(). Aborting.
systemd[5415]: pulseaudio.service: Main process exited, code=killed, status=6/ABRT
```

The consequence is worse than a single crash: systemd retries 5×, hits
`StartLimitBurst`, then **`pulseaudio.socket` itself fails with
`service-start-limit-hit`** – so socket activation is dead for the rest of the
session and audio never recovers. Every PA client (media-hub, telephony-service,
maliit, indicator-sound) then loops on `Connection refused`.

Notably, the abort happens *after* droid sinks were created and playing: container
logcat shows `audio_hw_primary: out_write` streaming from the PA process (tid-matched)
in the same second as the abort. The card, AGM/PAL, and vendor HAL are all healthy –
the daemon is killed purely by the host-side jack-detection path. On this device the
crash is 100% reproducible per boot (it is not racy: the device simply has no
qualifying input device, ever).

## Root cause (14.2.109 source)

`src/droid/droid-extevdev.c`:

```c
static bool setup(pa_droid_extevdev *u) {
    u->fd = find_input_device();
    if (u->fd < 0) {
        pa_log("could not start input device detection.");
        return false;                       /* jackless: always taken   */
    }
    u->event = u->card->core->mainloop->io_new(...);
    ...
}

pa_droid_extevdev *pa_droid_extevdev_new(pa_card *card) {
    pa_droid_extevdev *u = pa_xnew0(pa_droid_extevdev, 1);   /* event = NULL */
    ...
    if (!setup(u))
        goto fail;
    ...
fail:
    pa_droid_extevdev_free(u);
    return NULL;
}

void pa_droid_extevdev_free(pa_droid_extevdev *u) {
    if (!u)
        return;
    u->card->core->mainloop->io_free(u->event);   /* io_free(NULL) -> assert */
    pa_xfree(u);
}
```

`find_input_device()` finds nothing on jackless hardware, `setup()` fails,
the fail path frees a never-created io event, and `mainloop_io_free()` in
`src/pulse/mainloop.c` asserts on the NULL and aborts the daemon. The caller
(`module-droid-card.c` line ~978) already tolerates a NULL return, so with the
guard in place the module degrades gracefully: no jack detection, default port
availability, speakers and BT work.

Affected: **14.2.107 ≤ version ≤ 14.2.109** on any device with no
`SW_HEADPHONE_INSERT`-capable input device (jackless tablets; also any phone
whose kernel doesn't expose the jack via evdev). The UT 24.04-1.x packaging
line (14.2.106 + the old libevdev-based extevdev debian patch 2004) is NOT
affected – that variant guards the free and checks the setup result.

## Asks

1. Merge the pending `personal/ubports_uwt_bot/update-14_2_110` bump in
   `ubports/development/core/packaging/pulseaudio-modules-droid` into
   `ubports/latest` / `ubports/24.04-2.x` and release, or
2. Land the attached one-hunk backport
   (`0001-extevdev-Fix-startup-crash-when-no-input-device-is-f.patch`,
   Azkali's upstream commit exported verbatim, authorship preserved) as a
   `debian/patches/` entry on the current 14.2.109 packaging.
   Verified `patch -p1` clean against the 14.2.109 release tarball.

## Interim workaround for already-flashed images

Attached `gts9-virtual-h2w-workaround.tar.gz`: a ~20-line uinput daemon that
creates a virtual input device advertising `SW_HEADPHONE_INSERT` /
`SW_MICROPHONE_INSERT` / `SW_LINEOUT_INSERT` with state 0 (unplugged), a system
unit for it, and a PA user-unit drop-in gating PA start on the device existing.
`find_input_device()` then succeeds, detection starts, no abort; state 0 keeps
the speaker route. Validated end-to-end on gts9wifi 2026-08-10 (PA active,
`sink.primary-out`/`sink.fast` created, audible playback). Harmless once the
fixed module lands (state-0 virtual jack ≡ no jack), and removable at that point.

Report prepared by John Stockdale (Off by One / Whitehat Hardware) with
diagnosis assistance from Claude. All credit for the fix itself: Azkali.
