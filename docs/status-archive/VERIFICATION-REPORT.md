# gts9uwifi — full verification report (item-by-item, no shortcuts)

Method: every artifact read, every executable syntax-checked in its actual
interpreter, every self-test re-run fresh, every cross-reference resolved or
explicitly flagged for on-device confirmation. Nothing waved through.

## Build pipeline
1. build-gts9uwifi.sh — bash -n PASS; all fix stages present and verified by
   line: preflight (incl. img2simg/dtc/fakeroot/attr/erofs + libssl/libelf
   headers), kernel+display pre-clone with 0444-mode hardening, panel cmdline
   sed→halium.config with verify-grep, goodix/wacom/dts overlay, kiwi IPA
   disable (idempotent, verify-grep), firmware-tar basename bypass, module-set
   confirmation (wez01/goodix), aarch64-lpmake detection, super at PIT size,
   zip. FLAG(minor): lpmake candidate test is convoluted-but-working; left
   untouched deliberately (working > pretty on a shipping script).
2. x910-extract.sh — sh PASS; embedded carve python ast-PASS; file-based
   PYCARVE (heredoc-stdin bug fixed), pipefail guard, 6-partition verify,
   dep preflight. PASS.
3. capture-boot.sh — bash -n PASS, adb preflight present. PASS.

## Patchers (self-tests re-run this session)
4. fix-boot-cmdline.py — PASS (padded replace, size preserved, neighbors intact).
5. fix-vendor-boot-mode.py — PASS. Note: superseded for normal use by the
   skeleton's filtered-bootconfig wrapper; retained as recovery tool.

## Flasher
6. update-binary v3 — sh -n PASS; BOOTINFO probe + X916 hard-reject + family
   fallback present (3 markers each); flash targets exactly {boot, init_boot,
   vendor_boot, vbmeta, super}; **zero dtbo writes** (verified 0 matches) —
   stock dtbo preserved by construction, as required.

## Skeleton overlay — every file read
7. start-android-container wrapper — sh -n PASS. Filtered /proc/bootconfig
   (charger→normal) bind-mounted into container ns + stale property/socket
   clean. Wired via lxc-android-config.service.d ExecStart override (verified
   empty-then-set form). This is the canonical charger-mode fix.
8. modules-load.d/gts9uwifi.conf — sm5714_fuelgauge + sm5714-charger, names
   match on-device .ko names. PASS.
9. UPower.conf CriticalPowerAction=Ignore — PASS.
10. logind.conf.d — consolidated to single 50- file (90- was a strict subset;
    removed). 7 Handle*=ignore keys. FIXED.
11. repowerd wait-battery — busctl path battery_battery matches on-device
    UPower object (verified against ofonod log). wait-backlight present. PASS.
12. pulseaudio wait-audiohal — HARDENED this pass: init.svc key unverified on
    Samsung AIDL stack, so wait now also accepts the observed HAL processes
    (android.hardware.audio.service / secaudiohal) via pgrep; 90s cap,
    tolerant. FIXED.
13. tmpfiles journal persistence — PASS.
14. NM wifi-mac (scan-rand off), sensord accel matrix, force-hwc2,
    LSC disable-overlays, gbinder ApiLevel 33, usb-moded -f (eud quirk,
    getopt-alias trap documented) — all read, all coherent. PASS.
15. adbd restart drop-in — OnFailure target gts9-adb-recover.service EXISTS
    plus companion udev rule (72-…-adb-recover.rules). Dangling-ref concern
    retired. PASS.
16. waydroid-container binder pre-hook — python3 (py_compile PASS); creates
    anbox-* binderfs nodes so waydroid can't fight the android container. PASS.
17. mount-android-partitions — #!/bin/bash, bash -n PASS (sh -n false alarm).
18. deviceinfo — kiwi_v2, SUPER consumed via super.sh (11744051200 in 5
    cross-refs), patch 2025-07, os13, header v4, unified recovery + PIT-exact
    recovery size. FIXED: ubuntu_touch_release 24.04-1.x → 24.04-2.x (was
    cosmetic — no ${release}-overlay dirs exist — but now matches the channel
    build.sh actually pulls).

## Imports bundle
19. Wiring: wacom Kconfig source ×1, EPEN Makefile hook ×1, goodix Kconfig
    source ×1, goodix Makefile hook ×1. PASS.
20. Merged display Kbuild: GTS9 refs = 7, GTS9U refs = 7 — symmetric dual-
    panel. PASS.
21. halium.config.gts9u-append: GOODIX_BRL=m + EPEN-already-armed note. PASS.
22. goodix berlin sources ×10, gts9uwifi dts ×2 (r00/r03 = DTBO board-ids). PASS.

## Flagged for ON-DEVICE confirmation (one command each; cannot be resolved
## from the build tree alone — honestly deferred, not skipped)
A. device-hacks placement: `systemctl cat device-hacks | grep ExecStart` —
   if it execs /usr/libexec/lxc-android-config/device-hacks (host path), our
   copy under usr/share/halium-overlay/... is inert and must be relocated.
B. audio-hal init.svc key: `getprop | grep -i "init.svc.*audio"` — feed the
   real key back into item 12's drop-in (pgrep fallback covers the interim).
C. Audio SEGV experiment #1 (cheap A/B before deep work): the unit runs PA
   with HYBRIS_USE_VENDOR_NAMESPACE removed; the foreground crash ran WITH it
   — both crashed, so it's not the differentiator, but confirm by toggling
   once under the hardened drop-in before starting the backtrace hunt.

## Verdict
Build tree is internally consistent, syntax-clean, self-tested, and carries
every root-caused fix from bring-up. Rebuild + reflash promotes the full set.
Open subsystems unchanged from BUILD-AUDIT: audio SEGV (primary), USB-C host
mode, input-enumeration race, sensors multihal, boot-1 OOM watch.
