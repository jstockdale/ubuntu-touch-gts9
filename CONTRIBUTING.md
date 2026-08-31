# Working rules for this project

Hard-won discipline from the Jul–Aug 2026 campaign. Every rule below was paid
for with a debugging session; sources cited in `docs/knowledge/PORT-STATE.md`.

## Persistence

1. **Every rootfs change dies on reflash; every /home change dies on a
   userdata wipe.** Durable fixes go in the skeleton overlay
   (`devices/*/skeleton/overlay/`) or on /data. After any reflash, run the
   post-flash checklist: audio-fix installer, `LimitNOFILE` drop-in for
   lomiri-full-greeter, the desktop-Qt5 apt pin.
2. Test binary/overlay changes reversibly first (a reboot is the oracle);
   fold into the skeleton only when proven on-device.

## Rootfs hygiene

3. **Never `apt upgrade` the UT rootfs.** Never install desktop-GL Qt apps
   (krita, gimp, blender) into the rootfs — apt will *remove* the -gles Qt
   stack and lomiri crash-loops on next login (fd exhaustion via zero
   EGLConfigs). Desktop apps go in Libertine or Waydroid. The apt pin
   `/etc/apt/preferences.d/no-desktop-qt5` guards this.
4. Watch for root-owned files under `~phablet/.local` after adb root work —
   they silently kill click .desktop generation (empty app grid).

## Kernel / modules

5. **Never `rmmod machine_dlkm`** — instant kernel panic, and there is no
   pstore/ramoops on these units.
6. Stock Samsung modules are vermagic/modversion-locked (`abX910…` model
   tags) — they cannot load on the halium kernel. Any board driver must be
   built from OSRC source. The curated exception list for
   `finit_module(…, IGNORE_MODVERSIONS|IGNORE_VERMAGIC)` is exactly:
   `muic_sm5714 pdic_sm5714 wez01`. Never blanket-finit.
7. Samsung module names are canon — do not "correct" them:
   `stm_ts_fts1b90a.ko`, `wez01.ko`, `goodix_ts_berlin.ko`,
   `qca_cld3_kiwi_v2.ko`.

## Bootloader / firmware

8. Bootloader lock state is authoritative **only in Download Mode** (`RP
   SWREV` bit-fuse line). The splash-screen "OEM LOCK" line misreports.
   Bit-fuse rev 5 is the last unlockable; rev 6 is terminal.
9. **The S9+ unit stays offline and never accepts an OTA.** It is a rev-1
   unit in a rev-6 world — one accepted update permanently ends its
   usefulness.
10. Before first flash on any unit: TWRP full backup **including EFS**, plus
    raw dumps of `efs sec_efs persist optics prism up_param`.
11. Never flash the `dtbo` partition — the port relies on the stock DTBO
    (board-id selection by ABL) over a generic kalama base DTB.

## Debugging

12. Container logcat needs `lxc-attach -n android --clear-env`.
13. Audio card state truth: `grep -c ONLINE /proc/snd_debug_proc/sdp_boot_log`
    (0 = never up, 1 = up and stable, >1 = bounced). "snd_card is ONLINE"
    never prints to dmesg.
14. When a fix "works manually but fails as a unit", first hunt for hidden
    state (the audio latch prop cost days) — run a time-matched control
    before trusting the comparison.
