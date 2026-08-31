# Operating rules & contributing

Two things live here: the **operating rules** for anyone with one of these
tablets in hand (each rule was paid for with a real debugging session —
sources in [`docs/knowledge/PORT-STATE.md`](docs/knowledge/PORT-STATE.md)),
and **how to contribute** to the project.

## Contributing

Contributions are welcome — the most useful ones right now:

- **Test reports.** The untested cells in [FIRMWARE.md](FIRMWARE.md) —
  rev 1 (AWHA) builds on any of the three devices, and the entire S9+ port
  (its runbook has never been executed) — are worth more than code. Open a
  GitHub issue with your device model, rev (from Download Mode), firmware
  build, and a bring-up log (dmesg + the acceptance checks from the device
  README).
- **The unsent upstream patches** in `patches/upstream/` — if you have
  standing in the Halium or UBports communities, carrying those forward
  helps every jackless Halium device, not just these tablets.
- **Open engineering problems** — ledgered in PORT-STATE.md §6 (sensors
  HAL/auto-rotate, USB-C host, cameras, 11" GPS).

PRs: keep the per-device layout, run `tools/dev/verify-flasher-fork.sh`
after touching the flasher or fork recipe, and never commit Samsung
firmware, carved partitions, or vendor blobs (`.gitignore` guards the known
paths; `NOTICE` explains the licensing scope).

## Operating rules

Terminology: **rev N** = the bootloader fuse revision — see the bold warning
section in the [README](README.md#-the-bootloader-fuse--read-this-before-anything-else)
and [FIRMWARE.md](FIRMWARE.md). Rev 5 is the last unlockable; rev 6+ can
never be unlocked.

### Persistence

1. **Every rootfs change dies on reflash; every /home change dies on a
   userdata wipe.** Durable fixes go in the skeleton overlay
   (`devices/*/skeleton/overlay/`) or on /data. After any reflash, run the
   consolidated post-flash script for your device
   (`fixes/post-flash/gts9wifi-post-flash.sh` on the 11";
   `fixes/post-flash/gts9uwifi-post-flash.sh sweep|check` on the Ultra) —
   and keep a copy of the kit off-device: a userdata wipe takes every
   on-device copy with it (it has happened).
2. Test binary/overlay changes reversibly first (a reboot is the oracle);
   fold into the skeleton only when proven on-device.

### Rootfs hygiene

3. **Never `apt upgrade` the UT rootfs.** Never install desktop-GL Qt apps
   (krita, gimp, blender) into the rootfs — apt will *remove* the -gles Qt
   stack and Lomiri crash-loops on next login (fd exhaustion via zero
   EGLConfigs). Desktop apps go in Libertine or Waydroid. The apt pin
   `/etc/apt/preferences.d/no-desktop-qt5` guards this.
4. Watch for root-owned files under `~phablet/.local` after adb root work —
   they silently kill click .desktop generation (empty app grid).

### Kernel / modules

5. **Never `rmmod machine_dlkm`** — instant kernel panic, and there is no
   pstore/ramoops on these units.
6. Stock Samsung modules are vermagic/modversion-locked (`abX910…` model
   tags) — they cannot load on the Halium kernel. Any board driver must be
   built from OSRC source. The curated exception list for
   `finit_module(…, IGNORE_MODVERSIONS|IGNORE_VERMAGIC)` ("finit" loading)
   is exactly: `muic_sm5714 pdic_sm5714 wez01`. Never blanket-finit.
7. Samsung module names are canon — do not "correct" them:
   `stm_ts_fts1b90a.ko`, `wez01.ko`, `goodix_ts_berlin.ko`,
   `qca_cld3_kiwi_v2.ko`.

### Bootloader / firmware

8. Read bootloader state (lock and rev) from **Download Mode** (`RP
   SWREV` line). The boot-splash "OEM LOCK" line is normally correct but
   has shown stale state in edge cases (seen while debugging a mis-built
   image) — never trust it for irreversible decisions. Full fuse rules:
   [FIRMWARE.md](FIRMWARE.md).
9. **If your unit is still rev 1, it is precious — keep it offline and
   never let it accept an OTA.** Official updates are rev 6; one accepted
   update permanently ends a unit's usefulness for porting. (The project's
   own sealed S9+ is preserved exactly this way.)
10. Before first flash on any unit: TWRP full backup **including EFS**, plus
    raw dumps of `efs sec_efs persist optics prism up_param`, plus an
    archived copy of your factory firmware package.
11. Never flash the `dtbo` partition — the port relies on the stock DTBO
    (board-id selection by the bootloader) over a generic kalama base DTB.

### Debugging

12. Container logcat needs `lxc-attach -n android --clear-env`.
13. Audio card state truth: `grep -c ONLINE /proc/snd_debug_proc/sdp_boot_log`
    (0 = never up, 1 = up and stable, >1 = bounced). "snd_card is ONLINE"
    never prints to dmesg.
14. When a fix "works manually but fails as a unit", first hunt for hidden
    state (a sticky Android property — the audio latch — cost days here) —
    run a time-matched control before trusting the comparison.
