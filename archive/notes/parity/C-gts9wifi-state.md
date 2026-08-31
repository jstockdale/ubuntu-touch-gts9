# Parity audit C — true state of gts9wifi (Tab S9 11", SM-X710)

Audited 2026-08-30. Device runs **Azkali's upstream UT 24.04-2.x noble dev build**
(2026-07-28 packaging snapshot, channel `24.04-2.x/arm64/android9plus/rc`, A13 vendor
X710XXU5CYD9). Nothing skeleton-level is ours on this device — **every one of our
changes is on-device only** (rootfs `/etc`+`/usr/local` = dies on reflash;
`/home/phablet` = survives reflash, dies on userdata wipe/Format Data — proven
2026-08-29 when a flash took userdata and erased the whole audio fix including its
self-copy).

Evidence classes: **VERIFIED** = I read the file in the snapshot repo;
**REPORTED** = a doc/notes file claims it (on-device state is inherently REPORTED —
no device access in this audit).

---

## 1. Our fixes installed on the 11" right now, and where they live

### 1a. Audio — extevdev jackless-abort workaround (bug #4, the only audio bug this device has)

Canonical installer **VERIFIED read in full**:
`/home/jstockdale/projects/ubuntu-touch-gts9/fixes/audio/gts9-audio-fix-install.sh`.
What it installs, exactly:

| Piece | Path | Persistence class |
|---|---|---|
| Daemon (python3-evdev uinput, EV_SW SW_HEADPHONE_INSERT+SW_MICROPHONE_INSERT, state 0 forever, name `gts9-virtual-h2w`) | `/usr/local/bin/gts9-virtual-h2w` (script line 26) | **rootfs — DIES on reflash/OTA** |
| System unit (Type=simple, `ExecStartPre=-/sbin/modprobe uinput`, Restart=on-failure, WantedBy=multi-user.target) | `/etc/systemd/system/gts9-virtual-h2w.service` (line 27) | **rootfs — DIES on reflash/OTA** |
| PA gate drop-in (fail-open `ExecStartPre=-` shell loop, bounded 30 s, polls `/sys/class/input/input*/name` for the device) | `/home/phablet/.config/systemd/user/pulseaudio.service.d/50-gts9-h2w-gate.conf` (lines 28–29, 213–219) | **userdata — survives reflash, dies on userdata wipe** |
| Installer self-copy | `/home/phablet/gts9-audio-fix/install.sh` (lines 225–233) | **userdata — survives reflash, dies on userdata wipe** |

Behavior (VERIFIED in script): re-execs itself via sudo; full preflight before
mutating anything (python3, python3-evdev, /dev/uinput with modprobe attempt,
phablet user, /home mounted, `/usr/local/bin` + `/etc/systemd/system` writable);
**version gate** — reads which `module-droid-card-N` `/etc/pulse/touch.pa` loads,
derives package name (default `-30`), and **refuses to install on ≥ 14.2.110**
(`FIXED_IN=14.2.110`, lines 30, 124–128; `--force` overrides, `--uninstall`
retires cleanly keeping `$FIX_HOME`); verifies the virtual device appears within
10 s; reloads phablet's user manager; prints acceptance steps.

**Reflash-durability verdict: partial by design.** The script's own header (lines
17–19) says it: "Rerun after every OTA/reflash: the rootfs pieces (/usr/local/bin
daemon + /etc/systemd/system unit) do not survive them; the gate drop-in and this
installer's self-copy live on userdata." After a reflash the fix is inert (gate
fails open after 30 s, PA starts, extevdev aborts ×5, socket start-limit-hit →
audio dead) until `install.sh` is rerun. A userdata wipe removes even the
self-copy — the off-device repo copy is the only durable home (it exists,
VERIFIED).

**On-device status (REPORTED):** live and cold-boot validated. The
`gts9-virtual-h2w` input device was present on the 2026-08-30 boot (event13,
`_capture/notes/lomiri-crash_404564a2.p1.notes.md` §"Device / build context");
cold-boot acceptance passed 2026-08-29 ("YUP FIXED AFTER A REBOOT",
`audio-cluster.notes.md` §4).

**⚠ Layout drift, unresolved:** `audio-cluster.notes.md` §4 describes the Aug-29
on-device install as putting the daemon at
`/home/phablet/gts9-audio-fix/gts9-virtual-h2w.py` (userdata) with gate
`55-gts9wifi-wait-h2w.conf`; the repo's canonical installer (VERIFIED) writes the
daemon to `/usr/local/bin` with gate `50-gts9-h2w-gate.conf`. The
lomiri-crash p2 notes flag the repo script as a *reconstruction* never diffed
against the on-device original (PORT-STATE §6 #11: "archive live audio-fix
artifacts off-device" — still open). Until that diff happens, the exact on-device
layout is uncertain; what is certain is that a rootfs unit is involved either way
and a rerun is required per reflash.

Secondary variant (VERIFIED present):
`fixes/audio/gts9-virtual-h2w/{gts9-virtual-h2w.py,.service,55-gts9wifi-wait-h2w.conf,install.sh}`
— the Aug-11 minimal-dependency variant; its `install.sh` (VERIFIED) writes
daemon `/usr/local/bin/gts9-virtual-h2w.py`, unit `/etc/systemd/system/`, and —
note — puts the PA drop-in at **`/etc/systemd/user/pulseaudio.service.d/55-gts9wifi-wait-h2w.conf`
(rootfs, dies on reflash)**, unlike the canonical installer's userdata gate.
`fixes/audio/README.md` (VERIFIED) marks `gts9-audio-fix-install.sh` as CANONICAL.

### 1b. Lomiri fd-exhaustion mitigation — LimitNOFILE drop-in

REPORTED created 2026-08-30 (`lomiri-crash_404564a2.p1.notes.md` §"Fixes landed"):
`~/.config/systemd/user/lomiri-full-greeter.service.d/60-nofile.conf` containing
`[Service]\nLimitNOFILE=65536`. **Userdata** — survives reflash, dies on userdata
wipe. **No installer exists** anywhere in the repo (VERIFIED absent) — it is a
one-off hand-written file. Mitigation only ("bigger bucket, not a plugged hole").

### 1c. GLES-Qt restoration + krita removal (the 2026-08-27 self-inflicted incident)

The `apt install krita` transaction removed `libqt5gui5-gles`,
`libqt5quick5-gles`, `qtubuntu-android`, `ubuntu-touch`,
`ubuntu-touch-android9plus` (apt history VERIFIED-quoted in
`lomiri-crash_404564a2.p2.notes.md` §1). The reversal (remove krita, reinstall
the five packages, reboot) was prescribed in-session but **never confirmed
executed in the transcript** (p2 "Open issues"); the ultra-main p6 follow-up war
story has the user saying he "got it fixed" manually — so REPORTED-recovered,
exact steps uncaptured. Rootfs change: re-dies on reflash anyway (a fresh image
ships the -gles pair, so a reflash actually *heals* this one).

### 1d. S-Pen touchscreen-masquerade pointer

REPORTED installed in-session 2026-08-27/28 (ultra-main p5 §Arc 2, p6):
`/etc/udev/rules.d/72-gts9wifi-spen.rules` (ID_INPUT_TOUCHSCREEN=1,
ID_INPUT_TABLET=0, LIBINPUT_CALIBRATION_MATRIX "0 1 0 -1 0 1") plus libinput
quirk `/etc/libinput/local-overrides.quirks`. **Both rootfs — die on reflash.**

**⚠ LOUD FLAG — persistence unconfirmed:** ultra-main p6 open issue #2 says
`pen-cleanup.sh` (which writes the persistent masquerade rule and deletes the
dead quirk) was **never confirmed run**; the pointer behavior observed may have
been session-state only (a running compositor keeps boot-time classification),
and "reboot would leave pen inert given on-disk state". Whether the pen still
works after the reboots since then is undetermined in the record. The scripts
survive only in `archive/pen-investigation/` (VERIFIED: `pen-interim.sh`,
`pen-cleanup.sh` present) — **there is no maintained installer**;
`fixes/input-pen/README.md` (VERIFIED) explicitly says "no standalone installer
here" and points at the *Ultra skeleton's* `61-gts9u-pen.rules`, which does not
help the 11".

### 1e. Misc /home survivors

- `~/setup-sdr.sh` (REPORTED, install-boot §2): idempotent RTL-SDR post-reflash
  setup (rewrites rootfs udev rule `/etc/udev/rules.d/99-rtlsdr.rules`). /home.
- Root-owned `~/.local` fix (chown + click hook rerun) — hygiene procedure, not
  an artifact; recurs whenever adb-root touches /home.

### 1f. The post-reflash checklist (consolidated)

Order-independent; all required after any image reflash, ALL of it after a
userdata wipe (bring the repo copies):

| # | Item | Installer exists? | Dies on reflash? | Dies on userdata wipe? |
|---|---|---|---|---|
| 1 | Audio fix — rerun `install.sh` | **YES** — `fixes/audio/gts9-audio-fix-install.sh` (VERIFIED) + self-copy `/home/phablet/gts9-audio-fix/install.sh` | rootfs pieces yes | yes (everything) |
| 2 | `LimitNOFILE=65536` lomiri-full-greeter drop-in | **NO** — hand-file only | no (userdata) | yes |
| 3 | Desktop-Qt5 apt pin `/etc/apt/preferences.d/no-desktop-qt5` | **NO** — and see §2: may never have existed on-device | yes (rootfs) | n/a |
| 4 | S-Pen masquerade rule + quirk cleanup | **archive-only** (`archive/pen-investigation/pen-cleanup.sh`; not a maintained fix) | yes (rootfs) | n/a |
| 5 | RTL-SDR udev rule via `~/setup-sdr.sh` | YES (on /home, REPORTED) | rule yes | script yes |
| 6 | (if adopted, §2) touchpad rotation daemon `install.sh` | YES — `fixes/input-touchpad/gts9u-tp-rotate/install.sh` (VERIFIED) | yes (/usr/local/sbin + /etc) | no |

**Gap, loud:** CONTRIBUTING.md rule 1 (VERIFIED) names the three-item checklist
(audio, LimitNOFILE, apt pin) but **no single post-flash script exists** that
executes it — lomiri-crash p2 §5 explicitly recommended consolidating "into one
post-flash script"; never done. Items 2–4 have no installer at all.

---

## 2. Ultra-side improvements the 11" has NEVER received (and should)

1. **Folio touchpad rotation daemon** (`gts9u-tp-rotate` v0.1). VERIFIED present
   with installer at `fixes/input-touchpad/gts9u-tp-rotate/` (daemon, orient CLI,
   unit, `.default`, `install.sh`). Name-generic by design — finds the pad by
   evdev name `sec_touchpad_pogo`, mirrors caps via ioctl, "works on any device
   with a sec_touchpad_pogo input node (all three tablets' folio keyboards)"
   (`fixes/input-touchpad/README.md`, VERIFIED). The 11"'s EF-DX710/DX720 folio
   has the identical 90°-in-landscape defect (PORT-STATE §1 gts9wifi BROKEN list:
   "same rotation/scroll/pinch issues as Ultra (daemon transfers unchanged)").
   **No evidence it was ever installed on the 11".** Should get. (Scroll-in-Morph
   and pinch will remain broken — upstream Mir/qtmir, §6 #16 — the daemon fixes
   only rotation.)
2. **modules.load dedupe / module-walker guard (audio bug #1 armor).** The 11"
   carries the SAME 4× duplicated `modules.load` (457 lines / 357 unique,
   REPORTED measured on-device, audio-cluster §3 "Latent on 11") — the storm
   amplifier behind the Ultra's va-macro race. Every 11" boot so far has won the
   race; that is luck, not a fix. The Ultra's remedies (build-time
   `awk '!seen[$0]++'` in `common/scripts/swap-vendor-modules.sh` + the
   bringup-service module walk) have never been ported; for the 11" the right
   shape is either an ask to Azkali (dedupe in his image) or a small standalone
   walker service. Consolidated open issue audio-cluster #2.
3. **Persistent journald.** Ultra skeleton ships
   `overlay/system/etc/tmpfiles.d/gts9uwifi-journal.conf` = `d /var/log/journal
   2755 root systemd-journal - -` (VERIFIED read). The 11" has no equivalent;
   its debugging sessions repeatedly fought volatile early-boot logs (pre-NTP
   "Jan 20 1970" timestamps, uncaptured BT crash-loop outcome). One-line
   tmpfiles.d drop — but rootfs, so it belongs in the post-flash script.
4. **UPower `CriticalPowerAction=Ignore`.** Ultra skeleton
   `overlay/system/etc/UPower/UPower.conf` (VERIFIED). Lower priority for the
   11" — its fuel gauge has always read honestly on Azkali's build, so the
   0%-poweroff loop never occurred there. Cheap seatbelt if a post-flash script
   exists anyway; not urgent.
5. **Desktop-Qt5 apt pin** `/etc/apt/preferences.d/no-desktop-qt5`
   (Pin-Priority -1 on `libqt5gui5t64 libqt5gui5 libqt5quick5`). **Status:
   planned, never confirmed created anywhere.** VERIFIED: the pin text exists
   only as prose in PORT-STATE §4 (line 323) and CONTRIBUTING.md rule 3 — there
   is NO pin file in the repo (no `preferences.d` path anywhere outside docs),
   and lomiri-crash p2 records the prescription with the whole fix "not yet
   confirmed applied by end of transcript". Treat as **absent on-device until
   proven otherwise**. This is the guard against a repeat of the 2026-08-27
   lomiri takedown; the 11" (the only daily-driven, apt-tinkered unit) needs it
   most. Also flagged in p2 as an image-hardening ask for Azkali.
6. **Stale-props container clean** (recreate `/dev/__properties__` 0711 before
   container start — VERIFIED in Ultra skeleton
   `overlay/system/usr/lib/gts9uwifi/start-android-container` lines 15–17).
   The 11" has never exhibited the stale-props SEGV (Ultra bring-up artifact);
   **do not port proactively** — file under "known remedy if the 11" container
   ever SEGVs on restart".
7. NOT applicable from PORT-STATE §4: panel cmdline retarget (11" is the panel
   the family inherited), charger-mode bootconfig filter (Azkali's build boots
   cabled fine), fuel-gauge/MUIC finit loads and wez01 force-load (all modules
   load cleanly on the 11" — wez01 clean-load VERIFIED-reported in ultra-main
   p5 Arc 2), root-FS grow (Azkali sizes his own super).

---

## 3. Fixes the 11" does NOT need (bugs it never had) — and why

- **Audio bugs #1, #2, #3, #5 of the five-bug chain** (PORT-STATE §3;
  audio-cluster §3 s0-log diagnosis, REPORTED from on-device capture
  2026-08-10): card 0 `kalama-mtp-snd-card` registers cleanly, `card_state=1`,
  ONLINE ×1 at 13.16 s, `devices_deferred` empty, all 5 lpass_cdc macros loaded
  (#1 latent only — see §2 item 2); latch prop `vendor.audio.use.primary.default`
  unset (#2); `vendor.audio-hal` serving, shim streaming `out_write` — the shim
  null-deref (#3) only fires when `adev_open` fails downstream, which it doesn't
  here; no stale-HAL restart or node chmod needed (#5) — though the root-EACCES
  oddity on `/sys/kernel/aud_dev/state` (owner uid 1013) is noted-and-parked.
  **Only bug #4 (extevdev jackless abort) ever manifested on the 11"**, and only
  because the 2026-07-28 snapshot ships `pulseaudio-modules-droid-30` 14.2.109.
  Corollary: the whole `gts9u-audio-bringup` v3/v4 machinery is Ultra-only and
  must NOT be ported (fixes/audio/README.md VERIFIED: "The Ultra does not use
  these installers" — and inversely).
- **`gts9u-audio-fix/` macro loader and `apply-string-patch.sh`** — superseded
  even on the Ultra (VERIFIED marked "do not install" in fixes/audio/README.md;
  the string patch was REVERTED as it blocks the hidl_compat handshake).
- **Charger-mode fix, fuel-gauge finit, stale-props clean, panel retarget,
  wez01 force-load, root-FS grow** — see §2 item 7.
- **Goodix berlin touch import** — not needed *on this unit*: John's X710 is
  STM-rev (`stm_ts_fts1b90a`, touch works). See §4 for the family angle.

---

## 4. Unique open items on the 11" — status + what the repo already has

1. **GPS no-fix — structural HIDL/AIDL mismatch** (peripherals §2; PORT-STATE
   §6 #9). Diagnosis closed and solid: the bionic bridge
   `/android/system/lib64/libubuntu_application_api.so` (baked into the halium
   system image, invisible to apt) is a HIDL-1.x-only client spinning at 5 Hz
   for `android.hardware.gnss@1.1`, while the vendor exposes only AIDL IGnss V2.
   Cannot be fixed via apt; deterministic failure. **Nothing in the repo
   addresses it** — no patch, no client code. Documented leads, none executed:
   `libgps.so.30` (gpsd) newly linked into lomiri-location-serviced
   (discriminators queued, unrun); standalone gbinder AIDL NMEA→TCP client
   design (with QMI_LOC_STOP shutdown discipline); three-part question set for
   Azkali (drafted, unsent).
2. **Bluetooth HAL crash-loop** (`vendor.bluetooth-1-1-qti` SIGKILL every ~62 s,
   WCN7850 bring-up failure; install-boot §10; PORT-STATE §6 #10). Diagnosis-only
   session 2026-08-30; first remedy = full power-off cold boot; escalation
   checklist written (dmesg btpower/cnss, rfkill, container logcat, efs mount
   check). **Outcome never captured** — status unknown right now. Nothing in the
   repo addresses it.
3. **2.x-build boot-hang from 2026-07-26** (install-boot §2; PORT-STATE §6 #12).
   The then-current 2.x zip hung at the Samsung splash where the older
   "ramfix-broken-waydroid" build booted; reserved-memory reclaim (Azkali's
   Waydroid RAM dtbo edit) is the suspect; the proposed dtbo/boot.img diff was
   never done and the A/B on initialized /data never completed. Note the tension:
   the device now daily-drives a 24.04-2.x rc-channel build, so *some* later cut
   boots — but the root cause was never established, meaning the failure mode
   could return in any future RAM-tuned build. Nothing in the repo addresses it
   (the two build zips are not archived here).
4. **Goodix-rev S9 units lack touch on Azkali's port** — family/community item,
   not John's unit. PORT-STATUS-gts9uwifi.md §8 (lines 196–203, VERIFIED):
   "the S9 is dual-sourced (Goodix @0x5d or STM @0x49 by hw rev); Goodix-rev S9
   units likely lack touch on the current port – the same import fixes them";
   §9 correction (lines 237–242): X710 stock vendor_dlkm has no goodix module;
   the source ships with the SM-X910 OSRC drop. **The import EXISTS in our repo**
   — VERIFIED at
   `devices/gts9uwifi/imports/kernel-samsung-gts9wifi/drivers/input/touchscreen/goodix/berlin/`
   (goodix_brl_hw.c, goodix_cfg_bin.c, Kconfig, Makefile, etc.) — but it only
   helps a gts9wifi unit if built into a kernel/vendor_dlkm that a Goodix-rev
   11" actually flashes. Azkali's upstream build does not carry it (his unit is
   STM-rev). So: **addressed in principle, undelivered in practice** — a natural
   upstream contribution (send the import + Kconfig wiring to Azkali) rather
   than an on-device fix for John.
5. Carried non-unique opens for completeness: S-Pen pressure Mir-1.8-blocked
   (platform-gated ~Q2 2026, §6 #15); Morph scroll + pinch (upstream, §6 #16);
   upstream sends still not done (extevdev packaging ask ≥14.2.110 + shim patch
   — both patch files VERIFIED present under `patches/upstream/`, both with
   field reports; the *send* is the missing step, §6 #1–2).

---

## Loud absences (one screen)

- **No post-flash consolidation script** despite CONTRIBUTING.md rule 1 naming
  the checklist. Items: audio installer (exists), LimitNOFILE (no installer),
  apt pin (no installer, possibly never created), pen rule (archive-only).
- **Apt pin `/etc/apt/preferences.d/no-desktop-qt5`: no file anywhere** — repo
  or (as far as the record shows) device. The catalog entry in PORT-STATE §4
  reads as landed; the underlying transcript says prescribed-only.
- **S-Pen on-disk persistence unconfirmed** — pen may be inert after reboot if
  `pen-cleanup.sh` never ran; no maintained installer for the 11" pen config.
- **On-device audio-fix artifacts never archived/diffed** against the repo's
  reconstructed canonical installer (layout drift documented above).
- **Touchpad daemon never installed on the 11"** though it transfers unchanged.
- **modules.load 4× duplication latent** on the 11" with no guard.
- **BT crash-loop outcome and GLES-reinstall execution both uncaptured.**
