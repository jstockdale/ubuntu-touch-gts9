# Ready-to-send: extevdev packaging ask (Azkali / UBports)

Everything below is prepared; the send itself is the only missing step.
File against the `pulseaudio-modules-droid` packaging used by Azkali's
gts9 images (and CC the UBports packaging tracker – the scope is every
jackless halium-13 24.04 device on the -30 module).

## Where to file
- Azkali's tracker: `gitlab.com/azkali-samsung/gts9/ubports` (or direct
  contact – he has standing interest in Tab S9 family reports).
- Attach: `0001-extevdev-Fix-startup-crash-when-no-input-device-is-f.patch`
  (verbatim mer-hybris `dfda983` backport onto 14.2.109) and
  `extevdev-crash-field-report.md`.

## Suggested title
`pulseaudio-modules-droid-30 14.2.109 crashes PA at boot on jackless
devices – please bump to >= 14.2.110 (or cherry-pick dfda983)`

## Suggested body (paste and adjust)
> The 2026-07-28 image snapshot ships pulseaudio-modules-droid-30 at
> 14.2.109 – three days before upstream dfda983 / PR #135 (first in tag
> 14.2.110). On any device with no physical headphone jack (all Tab S9
> tablets), droid-extevdev's jack scan finds no EV_SW/SW_HEADPHONE_INSERT
> device and its error path calls mainloop_io_free() on a never-created io
> event: PA asserts (mainloop.c:206), SIGABRTs, and crash-loops at every
> boot. Affected window: 14.2.107–14.2.109.
>
> Field report with symptoms, versions, bisection, and cold-boot
> validation of the fix attached; the dfda983 backport applies cleanly to
> 14.2.109 if a full version bump is inconvenient.
>
> Ride-along, if of interest (same images, separate issues):
> 1. vendor_dlkm modules.load ships every line duplicated 4x (measured
>    457/357 on X710) – vendor_modprobe fires all lines in parallel, so
>    the duplication amplifies the boot module-storm; a dedupe at image
>    assembly (`awk '!seen[$0]++'`) removes it.
> 2. kiwi_v2 builds enable CONFIG_IPA_OPT_WIFI_DP but no dataipa tree is
>    present – we force it off in our builds; a defconfig patch is
>    available.
> 3. Consider shipping /etc/apt/preferences.d pins for desktop-GL
>    libqt5gui5/libqt5quick5 (Pin-Priority -1): one `apt install krita`
>    removes the -gles stack and crash-loops lomiri.

## After it lands
Our on-device workaround self-retires: `gts9-audio-fix-install.sh` refuses
to install on >= 14.2.110.
