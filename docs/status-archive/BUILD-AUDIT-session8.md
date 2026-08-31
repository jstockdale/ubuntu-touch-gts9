# gts9uwifi build audit — post first-boot (session 8 close)

Method: every fix discovered live on-device tonight, checked against the
skeleton overlay + build script. Result: the build tree ALREADY carries the
full set. Tonight's device booted without them only because the flashed image
predates these overlays. **Action: rebuild + reflash promotes all of it.**

## Verified present and correct in the build tree

| Fix (why) | Location | Status |
|---|---|---|
| Panel select GTS9U_ANA38407_AMSA46AS02 (not 11" AMSA10FA01) — else DSI never binds, black screen | build-gts9uwifi.sh:83 seds halium.config (CONFIG_CMDLINE_FORCE) + verify grep :85 | ✓ baked into kernel |
| sm5714_fuelgauge + sm5714-charger autoload (else cap=0 → UPower critical-poweroff loop; charger degraded) | overlay …/modules-load.d/gts9uwifi.conf | ✓ |
| Charger-mode → normal (ABL stamps androidboot.mode="charger" on USB-attached boot; init runs `on charger`, exits, no UI) | overlay …/gts9uwifi/start-android-container — filtered /proc/bootconfig bind-mounted into container ns; wired via lxc-android-config.service.d/gts9uwifi.conf ExecStart override | ✓ (superior to a vendor_boot patch: no reflash of boot, survives ABL) |
| Stale property-area clean (prev container gen leaves /dev/__properties__ → AOSP init EEXIST-path NULL-deref SEGV) | same wrapper, pre-exec | ✓ (family-portable) |
| UPower CriticalPowerAction=Ignore (belt vs any residual false-critical) | overlay …/UPower/UPower.conf | ✓ |
| logind HandlePowerKey/Lid/Suspend=ignore (phantom key + no-session shutdowns) | overlay …/logind.conf.d/ | ✓ |
| repowerd wait-for-battery + wait-backlight (startup race → 0% critical loop; backlight node timing) | overlay …/repowerd.service.d/ | ✓ |
| Persistent journald (survives OOM/self-kill; made tonight's debug possible) | overlay …/tmpfiles.d/gts9uwifi-journal.conf | ✓ |
| PA wait for vendor.audio-hal + drop HYBRIS_USE_VENDOR_NAMESPACE | overlay …/user/pulseaudio.service.d/50-…-wait-audiohal.conf | ✓ present (see audio caveat) |
| deviceinfo: kiwi_v2 wlan, SUPER 11744051200, patch 2025-07, os13, wacom rule, DT-model update-binary v3 | skel/deviceinfo, super.sh, flashable/ | ✓ |

## Proven working on silicon this session (first boot ever)
Display (GTS9U panel, DSI, cont-splash handoff) · GPU/Mir/compositor
(rendered frames) · touch (goodix_ts_berlin, i2c-66@5d) · folio keyboard ·
S-Pen (wez01, kernel) · WiFi (kiwi_v2 + NetworkManager, scans + lists APs) ·
battery (honest 99%, sm5714 FG) · charging (sm5714-charger) · container +
FULL boot via stock unit on battery (charger-mode was the only blocker) ·
lomiri-system-settings (after UPower unmask).

## GENUINELY OPEN (carry to next session)

1. **AUDIO — droid-card SEGV.** PA loads touch.pa → module-droid-card-30 →
   hidl_compat opens Samsung HAL: "Opened hw audio device version 2.0 (API
   3.1, Android 11)" — then **SIGSEGV (status=11) immediately**, before stream
   enumeration completes. Crash is in droid-card ↔ Samsung AIDL-era HAL
   interaction, POST hw-open, NOT in XML parse (gts9 policy XML parses to
   completion; version-1.0 warning + unknown-channel-mask lines are benign).
   Container HAL side healthy: android.hardware.audio.service_64 +
   secaudiohalaidl both running. sku_kalama_qssi policy uses xi:include (x4) —
   not a drop-in donor. NEXT: capture crash backtrace (coredump/gdb on
   pulseaudio), compare droid-card-30 vs Samsung HAL HIDL/AIDL expectations;
   candidate fixes = droid-card module params (voice_virtual_stream, sample
   rate/format pinning), or a HIDL-vs-AIDL shim. This is the last major
   subsystem; everything else works.

2. **USB-C host mode** — folio (pogo) keyboard works; USB-C HID (keyboard on
   the Type-C port) did not enumerate. Check typec/port0 data_role; likely a
   dwc3 dr_mode / role-switch nudge.

3. **Input enumeration race** — touch present some boots, absent others;
   goodix vs compositor evdev-grab ordering. Candidate: udev tag / init
   ordering to pin the touch node before Mir's input backend enumerates.

4. **Sensors HAL** — ISensors@2.1/2.0/1.0 "could not find" spam;
   sensors-hal-2-1-multihal present in overlay but not resolving → no
   auto-rotate. Verify the multihal config/VINTF.

5. **Boot-1 OOM watch** — the very first post-flash boot OOM-stormed; unclear
   if reproducible with the full overlay set (memcg + no-zram). Persistent
   journald will catch a recurrence. Consider zram-enable.

## Rebuild + reflash procedure (promotes everything above)
    cd ~/projects/gts9uwifi
    cp <latest update-binary> samsung-gts9u/flashable/META-INF/com/google/android/update-binary  # v3 already noted present
    SKEL=$PWD/samsung-gts9u IMPORTS=$PWD/gts9u-imports PARTS=$PWD/out-x910/parts ./build-gts9uwifi.sh
    # reflash via TWRP sideload (no Format Data needed — userdata already UT-formatted)
    # First boot: UNPLUG USB or the wrapper's filtered bootconfig is what saves you anyway.
