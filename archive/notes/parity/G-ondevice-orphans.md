# G — On-device orphaned fixes audit (parity pass, 2026-08-30)

Question answered here: **which fixes exist only on a device (or only in a conversation)
and never made it into the repo's skeleton/installers** — the class that dies on the next
reflash (rootfs pieces) or userdata wipe (/home, /userdata pieces), or was never persisted
at all.

Evidence basis:
- Repo verified by reading files under `/home/jstockdale/projects/ubuntu-touch-gts9`
  (paths + line numbers cited). **VERIFIED** = I read the repo file. **REPORTED** = a
  doc/note claims it (on-device state cannot be read from here — the devices are not
  attached).
- On-device history from: `docs/status-archive/PORT-STATUS-gts9uwifi.md` §13,
  `docs/knowledge/PORT-STATE.md` §4/§6, and notes
  `porting-orig_993a1f88.p3/p4/p5`, `ultra-main_62f05899.p1–p6`,
  `audio-config_09358316.p3/p4`, `infra-cluster`, `lomiri-crash_404564a2.p2`,
  `peripherals-cluster` (all under `_capture/notes/`).

Legend for status:
- **BAKED** — represented in the repo skeleton/fixes/tools; survives a reflash built from repo.
- **ORPHANED** — exists (or existed) only on a device / a working tree outside this repo.
- **DEBRIS** — on-device debugging shrapnel; superseded; should be deleted on device.
- **OBSOLETE** — the underlying theory was falsified; drop the TODO.

---

## 1. Master ledger — every on-device change ever made

### gts9uwifi (SM-X910, Ultra) — the heavily-modified unit

| # | On-device change | Repo representation | Status / disposition |
|---|---|---|---|
| U1 | logind Handle\*=ignore drop-ins: `/run/systemd/logind.conf.d/90-gts9u-debug.conf`, persisted `/etc/systemd/logind.conf.d/90-gts9u.conf` [porting-orig.p3] | VERIFIED superseded by `devices/gts9uwifi/skeleton/overlay/system/etc/systemd/logind.conf.d/50-gts9uwifi.conf` (7 Handle\*=ignore keys) | **DEBRIS** — delete `/etc/systemd/logind.conf.d/90-gts9u.conf` on device (PORT-STATUS §13 says exactly this). /run copy self-clears. |
| U2 | upower/repowerd null-masks `/etc/systemd/system/{upower,repowerd}.service → /dev/null` [porting-orig.p3] | Replacement seatbelt VERIFIED: `overlay/system/etc/UPower/UPower.conf` = `CriticalPowerAction=Ignore` | **DEBRIS** — REPORTED already removed 2026-08-05 (porting-orig.p4 §3, the Settings-crash fix). Re-verify absent: `ls -l /etc/systemd/system/{upower,repowerd}.service`. |
| U3 | Fuel-gauge/charger persistence `/etc/modules-load.d/gts9u-fuelgauge.conf` (device-local name) [porting-orig.p3] | VERIFIED baked as `overlay/system/etc/modules-load.d/gts9uwifi.conf` (sm5714_fuelgauge + sm5714-charger, with the why-comment) | **DEBRIS** — delete the old device-local file once running a skeleton-built image. |
| U4 | WiFi persistence `/etc/modules-load.d/gts9u-wifi.conf` (`cfg80211`, `qca_cld3_kiwi_v2`) [porting-orig.p4] | **NOT in repo.** VERIFIED skeleton `modules-load.d/gts9uwifi.conf` contains ONLY the sm5714 pair; no cfg80211 anywhere in the overlay (`grep -r cfg80211 overlay/` empty) | **ORPHANED, likely still wanted.** The bringup belt (`gts9u-audio-bringup` line 26+) insmods vendor `modules.load` holes with plain `insmod` — no dependency resolution, and `cfg80211` lives in the rootfs modules tree, not vendor_dlkm's modules.load. PORT-STATE §1 claims WiFi is "persisted in modules-load.d" — for the skeleton that claim is **false**. Risk: WiFi dead on a virgin flash. Action: add `cfg80211` + `qca_cld3_kiwi_v2` to `gts9uwifi.conf` (harmless if udev/modalias already covers it) and verify on next cold flash. |
| U5 | Stale-props clean before container start (mv `/dev/__properties__`, rm property_service sockets) [porting-orig.p3] | VERIFIED `overlay/system/usr/lib/gts9uwifi/start-android-container` lines 15–18 | **BAKED.** |
| U6 | Charger-mode fix (filtered `/proc/bootconfig` bind, charger→normal) [porting-orig.p4] | VERIFIED same wrapper, lines 20–48; ExecStart override VERIFIED `overlay/.../lxc-android-config.service.d/gts9uwifi.conf`; recovery tools `tools/boot/fix-vendor-boot-mode.py`, `fix-boot-cmdline.py` VERIFIED present | **BAKED.** |
| U7 | Persistent journald `/var/log/journal` (tmpfiles) [porting-orig.p3] | VERIFIED `overlay/system/etc/tmpfiles.d/gts9uwifi-journal.conf` | **BAKED** (and PORT-STATUS §13 "Keep /var/log/journal" honored). |
| U8 | Audio five-bug bring-up: macro insmod walk, card wait, `chmod 0666 card_state`+`aud_dev/state`, latch clear, `ctl.restart vendor.audio-hal`, `/run/gts9u-audio-ready` flag [audio-config.p2/p3] | VERIFIED `overlay/system/usr/local/sbin/gts9u-audio-bringup` (lines 17–102: dedupe walk, `FINIT_MODULES="muic_sm5714 pdic_sm5714 wez01"` at :47, chmod at :77, latch loop :79, restart :85, flag :102) + unit `gts9u-audio-bringup.service` | **BAKED** (v4, finit stage included). |
| U9 | PA gate + env: `zz-gts9u-audio.conf` (hard gate on flag, no `-`; `env -u HYBRIS_USE_VENDOR_NAMESPACE`) [audio-config.p2] | VERIFIED `overlay/system/etc/systemd/user/pulseaudio.service.d/zz-gts9u-audio.conf` | **BAKED.** On-device older `50-gts9uwifi-wait-audiohal.conf` drop-in (skeleton-v2 era) is DEBRIS if still present alongside. |
| U10 | Ultra virtual-h2w jack (uinput daemon) [audio-config.p2] | VERIFIED `overlay/system/etc/systemd/system/gts9u-virtual-h2w.service` + `overlay/system/usr/local/lib/gts9u-virtual-h2w.py` | **BAKED.** |
| U11 | `touch.pa` `module_id=primary` edit (self-inflicted regression, later reverted on device) [ultra-main.p3/p4] | VERIFIED skeleton `overlay/system/etc/pulse/touch.pa:47` = correct Azkali line (`module_id=hidl_compat config=/etc/pulse/gts9/... voice_virtual_stream=true`) | **DEBRIS/RESOLVED** — skeleton correct; make sure the device copy matches (it should after any skeleton flash). |
| U12 | libdroid-util `audio_hw_if`→`primary` binary patch + `/var/tmp/droidfix` bind mounts [porting-orig.p5, ultra-main.p1] | VERIFIED repo keeps only history: `fixes/audio/apply-string-patch.sh` with README stating **REVERTED — do not install**; correct fix is `patches/upstream/halium-audio-hidl-compat/0001-audio_hw-...patch` (VERIFIED present) | **DEBRIS** — REPORTED removed on-device (post-reboot oracle passed, `droidfix` rm'd; ultra-main.p2). Nothing bakes it. Correct. |
| U13 | Older standalone macro loader units on device: `gts9u-audio-macros.service` → `gts9u-audio-fix.service` [ultra-main.p2/p3] | VERIFIED preserved only as `fixes/audio/gts9u-audio-fix/` marked **Superseded — do not install** | **DEBRIS** — if either unit file still exists on device, disable+delete (bringup service replaces them). |
| U14 | GPR node group fix `/etc/udev/rules.d/71-gts9u-audiofix.rules` (`aud_pasthru_adsp` OWNER=system **GROUP=audio** 0660) [ultra-main.p2 §5] | **NOT in repo.** VERIFIED the underlying bug is still shipped: `overlay/system/usr/lib/udev/rules.d/70-gts9uwifi.rules:201` = `GROUP="system"` (stock ueventd.rc says `system audio` — a ueventd→udev translation error) | **ORPHANED, still wanted (correctness, low urgency).** Proven NOT the audio gate, but a real latent perms bug. Action: fix line 201 in the generated rule (or ship the 71 rule) and sweep 70-gts9uwifi.rules for other DLKM-node group mistranslations (never done). |
| U15 | S-Pen force-load (finit wez01) [ultra-main.p2] | VERIFIED in bringup FINIT stage (:47) | **BAKED.** Proper fix (build wez01 in-tree so CRCs match) still open upstream-side. |
| U16 | S-Pen reclass files: `/etc/libinput/local-overrides.quirks` + `/etc/udev/rules.d/61-gts9u-pen.rules` [audio-config.p3 §4] | VERIFIED both in skeleton (`overlay/system/etc/libinput/local-overrides.quirks` with AttrEventCode strip; `61-gts9u-pen.rules`) | **BAKED** (v5). The earlier on-device quirk WITHOUT the AttrEventCode line is DEBRIS (superseded by the skeleton copy). |
| U17 | Touchpad rotation daemon gts9u-tp-rotate v0.1 installed on device, **default set to 270** [peripherals §1] | Artifact VERIFIED at `fixes/input-touchpad/gts9u-tp-rotate/` (daemon+unit+installer). **BUT** VERIFIED `gts9u-tp-rotate.default` ships `GTS9U_TP_DEFAULT=0`, and the fix is NOT in the skeleton overlay (dies on reflash unless `install.sh` re-run) | **HALF-ORPHANED.** The empirically-proven landscape value (270) lives only on-device/notes; repo default boots portrait-frame. Action: either set the shipped default to 270 with a comment, or add tp-rotate install to the post-flash checklist (done below). Its `install.sh` preserves an existing `/etc/default/gts9u-tp-rotate`, so a device redeploy keeps 270. |
| U18 | Inert touchpad calibration rule `62-gts9u-touchpad.rules` (userspace path proven dead) [audio-config.p3 §5] | VERIFIED absent from skeleton (correct) | **DEBRIS** — delete from device if present. |
| U19 | DTS `touchpad,invert = <0x01 0x00 0x00>` staged in the imports bundle on pika ("applied and verified via sed by the user") [audio-config.p3 §5] | **NOT in repo.** VERIFIED `devices/gts9uwifi/imports/.../gts9uwifi_eur_open_w00_r03.dts:10407` (and r00:10413) still carry stock `<0x00 0x01 0x01>`; gts9p imports likewise stock | **ORPHANED (in the pika working tree, not this repo).** Disposition nuanced: the later session (peripherals, 2026-08-26) reframed the DTS bake as *deliberately deferred* — daemon-first, then bake only after reading the `stm32_pogo` DT parser (cell semantics unverified; one-bit-mirror risk). So the repo carrying stock values is defensible, **but** PORT-STATE §6 #6 still lists "bake into v5" as open and the sed'd copy on pika is drift waiting to bite: a build from pika's tree and a build from this repo produce different DTBOs. Action: reconcile — either commit the triplet with a provenance comment (marked experimental) or revert pika's copy and track the punch list (read parser → bake → flip daemon default to 0). |
| U20 | Root FS grown 4.5G→6.2G (fastbootd delete product/system_ext + resize2fs; LP group ceiling raised) [infra §1] | **NOT baked.** VERIFIED `skeleton/deviceinfo:34` still `deviceinfo_system_partition_size="4500M"`; `skeleton/scripts/super.sh` / `common/scripts/super.sh` still stat-size every partition and build group from the sum (no 8e9 system, no group=super-capacity, product/system_ext still packed). Tools ARE banked: `tools/lp/lp_inspect.py`, `tools/lp/probe-lp-ceiling.ps1` VERIFIED | **ORPHANED, definitely still wanted** (PORT-STATE §6 #5). Every reflash from this repo reinstates the 4.3G/100%-full root and the self-inflicted LP group ceiling. Action: bump system to ~8e9 (or drop product/system_ext from super + first-boot grow-to-fill), set `--group` to super capacity, mind gts9p's smaller SUPER (11,714,691,072). Until then: post-reflash manual resize procedure required (below). |
| U21 | `/userdata/lp-metadata.bak` (4 MiB; restore = FIRST 1 MiB ONLY) [infra §1] | Documented in PORT-STATE/infra notes only | **ON-DEVICE ARTIFACT, keep** — rename per advice (`lp-metadata.pre-resize.RESTORE-DESTROYS-FS.bak`) and re-dump a fresh 1 MiB post-resize backup. Not repo material. |
| U22 | systemd-inhibit shutdown blockers, `/tmp/lxcA` clone configs, test bind mounts | n/a | **DEBRIS, self-clearing** (tmpfs/reboot). |
| U23 | Device-hacks relocation (host path `/usr/libexec/lxc-android-config/device-hacks`) [porting-orig.p4 §6] | VERIFIED `overlay/system/usr/libexec/lxc-android-config/device-hacks` | **BAKED.** |
| U24 | `chmod 0666` on `/sys/kernel/snd_card/card_state` + `/sys/kernel/aud_dev/state` each boot | VERIFIED bringup :77 | **BAKED** (runtime, reapplied every boot — correct, sysfs perms don't persist anyway). |
| U25 | Pen-battery udev hide + phantom power-key hunt (PORT-STATUS §13 port-side TODOs) | n/a | **OBSOLETE** — the poweroff root cause was the sm5714 fuel gauge at 0% (porting-orig.p3 #6: no pen power_supply exists on this unit). Drop both TODOs; logind masks are baked anyway (U1). |
| U26 | vendor_dlkm override file `/userdata/vendor_dlkm.img` | VERIFIED consumed by `overlay/.../mount-android-partitions:96–98` (loop-mounted over `/android/vendor_dlkm` when present) | **Watch item** — this file lives on **userdata**: a Format Data wipes it. If the running module set depends on it (rather than the super LP copy), a userdata wipe silently reverts modules. Confirm which copy the device actually uses after next flash (`findmnt /android/vendor_dlkm`). |

### gts9wifi (SM-X710, 11", Azkali's build — daily driver)

| # | On-device change | Repo representation | Status / disposition |
|---|---|---|---|
| W1 | Audio extevdev/jackless fix: virtual-h2w daemon + unit (rootfs) + PA gate drop-in (`/home/phablet/.config/...`) + self-copied installer `/home/phablet/gts9-audio-fix/install.sh` [audio-cluster, lomiri-crash.p2] | VERIFIED `fixes/audio/gts9-audio-fix-install.sh` (canonical, version-gated FIXED_IN=14.2.110 at :30/:124) and `fixes/audio/gts9-virtual-h2w/` (minimal variant: py + service + `55-gts9wifi-wait-h2w.conf` + install.sh) | **BAKED as installer** — but the repo copy is a **RECONSTRUCTION** (lomiri-crash.p2 caveat): the live, cold-boot-validated on-device artifacts were never archived off and never diffed against it. Action: `tar` the device copies (`systemctl cat 'gts9*'`, PA drop-in, `/home/phablet/gts9-audio-fix/`) and let the device win any diff. Until then treat the installer as REPORTED-equivalent, not proven identical. |
| W2 | Lomiri fd-exhaustion mitigation: `LimitNOFILE=65536` drop-in for lomiri-full-greeter in `~/.config/systemd/user/` [lomiri-crash.p1/p2] | **NOT in repo as an artifact.** VERIFIED grep: only prose mentions (CONTRIBUTING.md:11, PORT-STATE.md:321/457). Ultra skeleton's greeter drop-in has only `TimeoutStartSec=600` — no LimitNOFILE either | **ORPHANED, still wanted.** Lives on userdata (survives OTA, dies on userdata wipe). Action: commit a drop-in under `fixes/` (and consider adding to the Ultra skeleton greeter drop-in — the robustness bug is device-independent). |
| W3 | Desktop-Qt5 apt pin `/etc/apt/preferences.d/no-desktop-qt5` (Pin-Priority -1) [lomiri-crash.p2] | **NOT in repo as an artifact.** VERIFIED only prose (CONTRIBUTING.md:22, PORT-STATE.md:323) | **ORPHANED, still wanted — and possibly never even applied on-device** (lomiri-crash.p2: fix transaction "not yet confirmed executed"). Lives on rootfs → dies on every reflash/OTA. Action: commit the 5-line pin file under `fixes/`, add to Ultra skeleton overlay too, and put it in the ask-Azkali list (bake into image). |
| W4 | GLES-Qt reversal itself (remove krita; reinstall libqt5gui5-gles/libqt5quick5-gles/qtubuntu-android/metapackages; reboot) [lomiri-crash.p2] | Procedure documented (PORT-STATE §4, CONTRIBUTING rule 3) | **ON-DEVICE ACTION, execution UNCONFIRMED** in the record. Verify: `dpkg -l | grep -E 'libqt5(gui|quick)5'` shows only `-gles` rows; maliit active. |
| W5 | S-Pen pointer masquerade: `/etc/udev/rules.d/72-gts9wifi-spen.rules` + quirk; maintained by `pen-cleanup.sh` (default mode) [ultra-main.p5/p6] | **Archive only.** VERIFIED live rule text exists solely inside `archive/pen-investigation/{pen-interim.sh,pen-cleanup.sh}`; `fixes/input-pen/README.md` explicitly says "no standalone installer here" and points only at the **gts9uwifi** skeleton | **ORPHANED, still wanted.** Rootfs rule dies on any reflash and there is no live installer for the 11". Also open: whether `pen-cleanup.sh` was ever actually run (ultra-main.p6 open #2 — on-disk state may leave the pen inert after the next reboot). Action: promote a `fixes/input-pen/gts9wifi-pen-pointer-install.sh` (rule + quirk + Lomiri-restart note) out of the archive scripts; verify current on-device state first. |
| W6 | Krita + xinput still installed in rootfs post-incident [ultra-main.p6] | n/a | **DEBRIS on device** — krita must be removed as part of W4; future desktop apps go in Libertine (CONTRIBUTING rule 3). |
| W7 | wez01/S-Pen kernel-side | Nothing needed on-device (module loads clean on X710); family kernel wiring backport for Azkali sits in imports/SPEN-PLAN | **N/A / upstream item.** |
| W8 | Hotspot TTL `net.ipv4.ip_default_ttl=65` [infra §5] | Laptop-side (`gpd-mpc2` `/etc/sysctl.d/99-ttl.conf`), documented in PORT-STATE §4 | **BAKED where it lives** (not device/flash-vulnerable). |

### gts9pwifi (SM-X810, S9+) — unexecuted port

No on-device changes exist (no unlock, no build, no flash — VERIFIED `devices/gts9pwifi/`
has build script/imports/runbook but **no skeleton**; README Phase 1 = fork
`samsung-gts9u → samsung-gts9p`). **Disposition:** nothing to persist yet, but the fork
will inherit every gts9u skeleton gap listed above (U4, U14, U17, U19, U20, W2/W3
candidates) — fix them in the gts9u skeleton **before** forking, or the S9+ starts life
with the same orphan debt. Also inherit-with-care: `62-gts9u-touchpad`-class dead ends
(don't), and note gts9p SUPER = 11,714,691,072 (runbook already flags not to inherit the
Ultra default — VERIFIED README line "do not inherit the skeleton default").

---

## 2. Repo-side defects found while verifying (drift the audit surfaced)

1. **F5 prune never executed** (contradicts PORT-STATE §4's landed-F1–F9 framing).
   VERIFIED still present in the gts9u skeleton:
   - `overlay/system/usr/lib/firmware/GTS9_ANA38407_AMSA10FA01.dat` (11" panel data)
   - `ramdisk-recovery-overlay/lib/firmware/GTS9_ANA38407_AMSA10FA01.dat`
   - `ramdisk-recovery-overlay/vendor/firmware_mnt/image/tsp_stm/fts1ba90a_gts9.bin`
     (STM touch fw — Ultra is Goodix)
   Harmless-but-wrong-device files; the F5 rider (goodix firmware for TWRP-touch in
   recovery, if TWRP touch matters) is still undecided.
2. **`70-gts9uwifi.rules:201` GROUP="system"** — the ueventd→udev mistranslation for
   `aud_pasthru_adsp` (should be GROUP="audio") is still shipped; the corrective
   `71-gts9u-audiofix.rules` never entered the repo (U14).
3. **Two swap-vendor-modules.sh generations coexist**: the F2 v2 audit script
   (LEFTOVER/UNLANDED + strict allowlist, 112 lines) is at
   `common/scripts/swap-vendor-modules.sh` + `common/scripts/swap-allowlist.txt`, but the
   build actually stages `devices/gts9uwifi/skeleton/scripts/swap-vendor-modules.sh`
   (43 lines: dedupe + swap only, **no leftover audit**). `build-gts9uwifi.sh:179`'s
   comment "which now audits leftovers" is stale/wrong for the script it invokes. The
   leftover audit is precisely the check that would have caught the va_macro and wez01
   orphan-module classes — wire the common v2 into the skeleton (same for super.sh:
   skeleton 38-line vs common 65-line F6 version).
4. **`gts9u-tp-rotate.default` ships 0**, not the silicon-proven 270 (U17).
5. **`deviceinfo_system_partition_size="4500M"` + sum-based lpmake group** — the resize
   fix is unbaked (U20).
6. No post-flash-checklist artifact exists (`find -iname '*post-flash*'` empty) even
   though CONTRIBUTING.md §1 prescribes one — the checklist below is the raw material.

---

## 3. Definitive post-reflash checklists

### gts9uwifi (after flashing a repo-built zip)
Baked already (expect these to just work): charger-mode wrapper, stale-props clean,
audio bringup v4 + finit (charging/pen) + h2w + PA gate, pen reclass, logind masks,
UPower Ignore, persistent journald, touch calibration, wait-battery/backlight.
Manual steps that remain until the repo gaps close:
1. **WiFi check** — if wlan0 absent: `modprobe cfg80211 qca_cld3_kiwi_v2`; persist
   `/etc/modules-load.d/gts9u-wifi.conf` (until U4 is baked).
2. **Root resize** — TWRP fastbootd: delete `product` + `system_ext` LPs, resize
   `system` to the group ceiling, then online `resize2fs /dev/mapper/system`
   (procedure: infra §1; back up LP metadata FIRST-1-MiB rule). Until U20 is baked.
3. **Touchpad** — run `fixes/input-touchpad/gts9u-tp-rotate/install.sh`; ensure
   `/etc/default/gts9u-tp-rotate` says `GTS9U_TP_DEFAULT=270`; `systemctl start
   gts9u-tp-rotate` (until U17/U19 resolve).
4. **udev perms** — install the `aud_pasthru_adsp` GROUP="audio" rule (until U14 baked).
5. **apt pin** — write `/etc/apt/preferences.d/no-desktop-qt5` (W3; applies family-wide).
6. **LimitNOFILE drop-in** for lomiri-full-greeter (survives on userdata; re-check after
   any userdata wipe).
7. **Cleanup sweep of pre-skeleton debris** (only needed once, on the current install):
   rm `/etc/systemd/logind.conf.d/90-gts9u.conf`, any `{upower,repowerd}.service`
   null-masks, `/etc/modules-load.d/gts9u-fuelgauge.conf`,
   `62-gts9u-touchpad.rules`, old `gts9u-audio-fix.service`/`gts9u-audio-macros.service`
   units, stale PA `50-gts9uwifi-wait-audiohal.conf`. Keep `/var/log/journal`, keep
   (renamed) `/userdata/lp-metadata.*.bak`.
8. Acceptance: `grep -c ONLINE /proc/snd_debug_proc/sdp_boot_log` = 1; `finit stage:
   muic_sm5714=ok pdic_sm5714=ok wez01=ok` in `/var/log/gts9u-audio-bringup.log`;
   pen tracks; charging with cable at boot (one replug for PD — open #8).

### gts9wifi (after any Azkali reflash/OTA)
1. Run `fixes/audio/gts9-audio-fix-install.sh` (version-gated; no-op once the image
   ships ≥14.2.110). **First**: archive the live on-device originals and diff (W1).
2. Reinstall the S-Pen pointer masquerade (`72-gts9wifi-spen.rules` + quirk) — currently
   only recoverable from `archive/pen-investigation/pen-cleanup.sh` (W5).
3. Reapply the desktop-Qt5 apt pin (W3) — rootfs, dies every reflash.
4. Re-check `LimitNOFILE` greeter drop-in (userdata — survives reflash, dies on wipe) (W2).
5. Verify GLES state after the krita incident: only `-gles` Qt rows installed,
   `qtubuntu-android` present, maliit active (W4).
6. If installing the touchpad daemon here: same tarball works unchanged
   (name-generic); calibrate its default empirically.

### gts9pwifi
Nothing yet. Gate the skeleton fork on closing U4/U14/U17/U20 (+W2/W3 as overlay
candidates) in the gts9u skeleton so the S9+ inherits a clean baseline.

---

## 4. Orphan shortlist (the actual answer, ranked)

**Still wanted, no repo artifact:**
1. Root-LP resize baked into pipeline (U20) — highest-value; loss repro's a 100%-full root.
2. WiFi modules-load persistence (U4) — potential fresh-flash WiFi outage.
3. Desktop-Qt5 apt pin file (W3) — one lost apt command away from a Lomiri crash-loop.
4. LimitNOFILE greeter drop-in (W2).
5. 11" S-Pen pointer installer (W5) — only in archive scripts.
6. `aud_pasthru_adsp` GROUP fix / 70-rules sweep (U14).
7. tp-rotate default=270 + install path (U17).
8. DTS `touchpad,invert` reconciliation between pika tree and repo (U19).
9. Archive + diff of the live 11" audio-fix vs the reconstructed installer (W1).

**Debris to clean on gts9uwifi (PORT-STATUS §13 list, expanded):** 90-gts9u.conf logind
drop-in; upower/repowerd null-masks (verify already gone); gts9u-fuelgauge.conf;
62-gts9u-touchpad.rules; superseded audio units; stale PA wait-audiohal drop-in.
**Keep:** /var/log/journal, LP metadata backup (renamed).

**Obsolete TODOs (drop):** pen-battery udev hide; phantom power-key hunt (root cause was
the fuel gauge; masks baked regardless).
