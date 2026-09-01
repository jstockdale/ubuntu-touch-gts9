# SYNTHESIS: Ubuntu Touch on Samsung Galaxy Tab S9 family – authoritative port state

Synthesized 2026-08-30 from 28 claude.ai conversations (notes under `_capture/notes/`).
Owner: John Stockdale (jstockdale@gmail.com, "Whitehat Hardware / Off by One").
All work is on factory-unlocked, owner-operated devices; every fix is reversible and
upstreamable by design.

Citation convention below: `[thread.partdate]` refers to the notes file of that name,
e.g. `[porting-orig.p3]` = `porting-orig_993a1f88.p3.notes.md`, `[ultra-main.p1]` =
`ultra-main_62f05899.p1.notes.md`, `[audio-config.p2]`, `[audio-cluster]`,
`[install-boot]`, `[infra]`, `[peripherals]`, `[tabS9plus]`, `[lomiri-crash.p2]`,
`[porting-first]`, plus RECON files (`[RECON-*]`).

---

## 0. The three devices (and the future 5G variants)

| | Tab S9 (11") | Tab S9+ | Tab S9 Ultra |
|---|---|---|---|
| UT codename | **gts9wifi** | **gts9pwifi** | **gts9uwifi** |
| Model (WiFi) | **SM-X710** | **SM-X810** | **SM-X910** |
| 5G sibling (locked/for-later) | SM-X716B | SM-X816B | SM-X916B |
| SoC | SM8550 "kalama" (Snapdragon 8 Gen 2 for Galaxy) | same | same |
| GPU | Adreno 740v2 | same | same |
| Panel | 11" 1600×2560 `GTS9_ANA38407_AMSA10FA01` | 12.4" 2800×1752 `GTS9P_ANA38407_AMSA24VU05` | 14.6" 2960×1848@120 `GTS9U_ANA38407_AMSA46AS02` |
| DDIC | ANA38407 (shared family) | ANA38407 | ANA38407 |
| Touch IC | **STM FTS1BA90A** (`stm_ts_fts1b90a.ko`) – Goodix on some units | **STM FTS1BA90A** | **Goodix GT9916 berlin** (`goodix_ts_berlin.ko`) |
| S-Pen | Wacom WEZ01 (`wez01.ko`, i2c 0x56, `wacom,w90xx`) | Wacom WEZ01 | Wacom WEZ01 |
| WLAN/BT | WCN7850 "kiwi" (`qca_cld3_kiwi_v2.ko` on Ultra; stock X710 has `qca_cld3_qca6490.ko`) | WCN7850/kiwi_v2 | WCN7850/kiwi_v2 |
| Amps | Cirrus (cs35l43+cs35l45 mix) | – | 4× cs35l45 (i2c 18-0030..0033) + btfmslim_slave |
| Battery/charge | SM5714 MUIC/FG/PD + SM5440 direct charger | same | same, 9800 mAh design |
| Fingerprint | EGIS `etspi,el7xx` (EL721) UDFPS | same | same |
| Folio kbd/touchpad | stm32 pogo (EF-DX7xx) | stm32 pogo (EF-DX8xx) | stm32 pogo (EF-DX920/DX925) `sec_touchpad_pogo` |
| SUPER size (PIT) | 11,643,387,904 (Azkali's) | **11,714,691,072** (28 MiB < Ultra) | **11,744,051,200** (+96 MiB > 11") |
| Firmware on unit | Azkali dev build (port-composed A13 fingerprint over the A15-era CYD9 vendor – §5); pins **X710XXU5CYD9** | sealed at **bootloader rev 1**, target **X810XXU1AWHA** (last A13/rev 1) | bought used at **rev 5**, vendor **X910XXS5CYG1** (A15) |

Key family fact: all three are SM8550/kalama, so **one halium kernel binary serves the
family** (Azkali's `kernel-samsung-gts9wifi`, branch `android13-5.15-halium`). Only DTB,
panel data, and vendor blobs differ. NinjaSU precedent: an X710-source kernel runs on
X910 and even the X916C 5G. `[porting-first][tabS9plus][install-boot §7]`

The **5G variants (X716/X816/X916)** are the room-for-future case. X916B (international 5G)
is unlockable; US carrier variants (X916U etc.) are never unlockable. The port must
**hard-reject X916 at flash time** because it shares the gts9u-family TWRP – the update-binary
(v5 since 2026-08-30) reads `/proc/cmdline`+`/proc/bootconfig` and hard-rejects the 5G sibling
AND every wrong-family model (TWRP's baked Fold5 DTB makes prop/DT checks lie).
`[porting-orig.p2][ultra-main.p2]`

---

## 1. Per-device status

### gts9uwifi / SM-X910 (Tab S9 Ultra) – the lead port, ~fully working

This is where 90% of the engineering happened. First-ever UT pixels on a Tab S9 Ultra were
achieved 2026-08-04 `[porting-orig.p2]`; first fully working boot (charger-mode fix) same day
`[porting-orig.p4]`; first sound 2026-08-08 `[audio-config.p2]`.

**WORKS (verified on silicon):**
- **Display** – 2960×1848@120, ss_dsi ANA38407, cont_splash handoff, DDIC-read manufacture id
  0x800004 rev D, ESD armed, backlight via repowerd. `[ultra-main.p1 §2][porting-orig.p3]`
- **GPU** – Adreno 740v2, full hybris EGL 1.5 + Android/Adreno extension suite, 72 configs,
  zero llvmpipe. Certified healthy. `[audio-config.p3 §3]`
- **Touch** – Goodix GT9916 `goodix_ts_berlin` at i2c 66-005d. (TCLM calibration data empty –
  functional, accuracy worth a look.) Enumeration race across boots noted. `[porting-orig.p3][ultra-main.p1]`
- **WiFi** – kiwi_v2 (WCN785x), full association + DHCP, NetworkManager-managed. Needs
  `cfg80211`+`qca_cld3_kiwi_v2` loaded. [CORRECTED 2026-08-30: persistence was
  on-device only (`gts9u-wifi.conf` orphan); the skeleton's modules-load.d
  carried only the sm5714 pair. NOW baked (parity Tier 1).] `[porting-orig.p4]`
- **Bluetooth** – power sequencing completes, btfm_slim probed, hci0 via bluebinder. `[porting-orig.p4][ultra-main.p1]`
- **Battery/charging** – SM5714 fuelgauge honest (was 0% → UPower critical-poweroff loop);
  charging works, MUIC/PD via finit-loaded modversion-locked modules. `[porting-orig.p3][audio-config.p3 §2]`
- **Folio keyboard** – EF-DX920 stm32_pogo, mcu fw v37. `[ultra-main.p1]`
- **Audio** – SOLVED end to end (five-bug chain, §3 below). First sound + cold-boot acceptance
  (NRestarts=0, ONLINE ×1, 8.49s bringup). `[audio-config.p2]`
- **S-Pen digitizer** – `sec_e-pen`, full pressure 0–4095 / tilt ±63 / eraser / stylus button,
  streaming at evdev. Loaded via finit_module (stock `wez01.ko` CRC-diverges). `[ultra-main.p2]`
- **Settings, Lomiri desktop** – work (Settings crash was self-inflicted upower mask). `[porting-orig.p4]`

**PARTIAL / WORKAROUND:**
- **S-Pen in apps** – pointer only via touchscreen-masquerade (udev `61-gts9u-pen.rules` +
  libinput quirk). No pressure/tilt to toolkits: **Mir 1.8.3 implements no zwp_tablet_v2**.
  Platform-gated on UT's Mir 2.x/Qt6 migration (roadmap ~Q2 2026, hybris devices last). `[ultra-main.p5,p6]`
- **Folio touchpad** – 90° rotated in landscape (pad is panel-portrait-native; Lomiri rotates
  touchscreen coords but not pointer motion). Userspace daemon **gts9u-tp-rotate v0.1** (EVIOCGRAB
  + uinput clone, label 270 = landscape) works; DTS `touchpad,invert <0x01 0x00 0x00>` fix staged
  but never flashed. Two-finger scroll works in terminal, **not in Morph** (suspected qtmir
  continuous-vs-discrete wheel bug); **pinch never works** (suspected Mir/qtmir gesture gap). `[peripherals §1]`
- **Root filesystem size** – grown 4.5G→6.2G on-device via TWRP fastbootd + online resize2fs
  (deleted One UI product/system_ext LPs). Build-pipeline lpmake fix baked 2026-08-30 (see §6 #5). `[infra §1]`

**BROKEN / UNTESTED:**
- **Sensors HAL** – ISensors@2.1/2.0/1.0 not registering (multihal injection not landing); no
  auto-rotate. Genuinely open subsystem. `[porting-orig.p4][ultra-main.p1]`
- **Cameras** – all sensors probe (hi1337/hi847, EEPROM CRC pass) but no UT camera app tested;
  aux/ultrawide lenses hidden by Samsung HAL (stretch). `[ultra-main.p1]`
- **USB-C host mode** – external keyboard on Type-C dead (folio pogo works); dwc3 role-switch open. `[porting-orig.p4]`
- **Fingerprint (UDFPS)** – EL721 driver alive but biometryd integration untested. `[porting-first]`
- **GPS** – untested on the Ultra. NOT "no hardware": the WiFi models DO carry GNSS (the
  vendor image ships the AIDL IGnss service – §5). Expect the same structural HIDL/AIDL
  mismatch diagnosed on the 11" (ledger #9); confirm the vendor service starts here too.
- **Waydroid** – prime suspect for early container-kill theories; known broken on Azkali's builds.

### gts9wifi / SM-X710 (Tab S9 11") – Azkali's reference port, daily-driven

Runs Azkali's UT 24.04-2.x noble dev build (port-composed A13 fingerprint; A15-era CYD9 vendor – §5). This is the upstream port
the Ultra was forked from; the user runs it and files fixes back to Azkali.

**WORKS:** display, GPU, WiFi, BT, touch, folio keyboard, battery, **audio** (only hit bug #4 of
the five-bug chain – see §3), **S-Pen digitizer** (`wez01.ko` loads cleanly, no force-load
needed, `sec_e-pen` at event10 full pressure/tilt). `[audio-cluster][ultra-main.p5]`

**BROKEN / OPEN:**
- **Audio regressions** – Azkali's 2026-07-28 snapshot ships `pulseaudio-modules-droid-30` at
  **14.2.109** (three days before the upstream fix), so the droid-extevdev jackless-abort (bug #4)
  is dead-on-arrival on every cut from that snapshot. Fixed on-device with the virtual-h2w
  workaround (cold-boot validated: "YUP FIXED AFTER A REBOOT"). `[audio-cluster §4]`
- **S-Pen pressure** – same Mir 1.8 wall as Ultra. Native pressure-sensitive Krita is NOT
  achievable on this build (proven via xinput: XWayland exposes no tablet device). Pen ships as
  touchscreen-masquerade pointer. `[ultra-main.p5,p6]`
- **Lomiri crash-loop (self-inflicted)** – `apt install krita` (2026-08-27) pulled desktop-GL Qt5
  and **removed** `libqt5gui5-gles`/`libqt5quick5-gles`/`qtubuntu-android`/`ubuntu-touch`
  metapackages → every Qt Wayland client got zero EGLConfigs (0x3005) → maliit churn → lomiri
  fd-exhaustion (GLib "Too many open files" → SIGTRAP). Fix: remove krita, reinstall -gles pair +
  qtubuntu-android + metapackages, reboot; guard with apt pin. **Rule: desktop-GL apps go in
  Libertine/Waydroid, never the rootfs.** `[lomiri-crash.p1,p2]`
- **GPS no-fix** – structural: UT's bionic bridge `libubuntu_application_api.so` is a HIDL-1.x-only
  client spinning at 5 Hz looking for `android.hardware.gnss@1.1`, while the SM8550 vendor exposes
  only **AIDL IGnss V2**. Cannot work on this build for AIDL-only vendors; fix is the halium
  system image, not apt. Promising lead: `libgps.so.30` (gpsd) newly linked into
  lomiri-location-serviced. `[peripherals §2]`
- **Bluetooth HAL crash-loop** – `vendor.bluetooth-1-1-qti` SIGKILL every ~62 s (WCN7850 bring-up
  failure); cold-boot remedy; outcome uncaptured. `[install-boot §10]`
- **Folio touchpad** – same rotation/scroll/pinch issues as Ultra (daemon transfers unchanged).

### gts9pwifi / SM-X810 (Tab S9+) – port kit complete, unexecuted

Sealed factory-unlocked unit, kept at **bootloader rev 1** (offline; fleet firmware is at
rev 6 which is past the unlockability cliff). Full port kit produced but no build/flash run yet.
`[tabS9plus]`

**Status:** Ready-to-execute. `devices/gts9pwifi/imports/` (use the repo tree at HEAD – the
archived tarball predates the 2026-08-30 wacom wiring), `build-gts9pwifi.sh`, `x810-extract.sh`,
`GTS9PWIFI_EUR_OPEN.pit`, findings doc, and a six-phase runbook all exist. Skeleton fork
`samsung-gts9u → samsung-gts9p` not yet done. First-boot unknown = display attach with the bare
`GTS9P_ANA38407_AMSA24VU05:` panel cmdline.

**Key deltas from Ultra:** touch is STM FTS1BA90A (already in Azkali's tree, no import) not
Goodix; smaller SUPER (11,714,691,072); firmware X810XXU1AWHA (last A13/rev 1); the goodix,gt9916
dts node is inert kalama-MTP cruft (do not chase). Open variance driver: whether the Ultra's audio
chain reproduces identically. `[tabS9plus][RECON-build-scripts]`

---

## 2. Chronological project timeline (Jul → Aug 2026)

- **2026-07-08/09** – Off-device infra: Mint SIM area-code decision; Nord N10 VoLTE; hotspot TTL
  metering defeated (`ip_default_ttl=65` on laptop). `[infra §3,4,5]`
- **2026-07-19** – UT 20.04→24.04 upgrade path documented (OTA-12 then cross-base). `[infra §2]`
- **2026-07-22/23/27** – Bootloader unlock policy research: One UI 8 removed unlocking globally;
  bit-fuse gate (rev 5 last unlockable, rev 6 terminal); dead-stock sourcing playbook; mainline
  U-Boot chainload architecture. `[install-boot §1,5]`
- **2026-07-26** – gts9wifi install debugging: "45% sideload fail" = progress-bar artifact;
  unmountable /data → Format Data; 2.x build boot-hang (unresolved, reserved-memory suspect);
  root-owned ~/.local kills app grid; Waydroid RAM-fix splash freeze. `[install-boot §2,3]`
- **2026-07-31** – Waydroid Google sign-in fix (GSF android_id registration). `[install-boot §4]`
- **2026-08-03** – Original Ultra port plan (`ut-gts9uwifi-port-plan.md`): reuse generic kalama
  DTB + swap device surfaces; Phase 0 recovery-dtbo keystone. `[porting-first]`
- **2026-08-04 (marathon)** – Ultra bring-up in one very long day `[porting-orig.p1–p5]`:
  - Forensic teardown of Azkali's gts9wifi bundle; ranged-HTTP extraction of X910 firmware.
  - X910 OSRC drop imported (GTS9U panel, goodix berlin, gts9uwifi dts, wacom wiring).
  - First build (3,135,289,151 B zip); TWRP device-guard saga (v1 prop→v2 DT→v3 cmdline).
  - First pixels (cmdline panel retarget GTS9→GTS9U); OOM storm; fuel-gauge 0% poweroff fix.
  - **Charger-mode root cause**: ABL stamps `androidboot.mode=charger` on cabled boots → init
    runs `on charger` and exits. Fix: boot unplugged / start-android-container bootconfig filter.
  - First fully working boot: display+touch+kbd+WiFi+BT+battery.
  - Audio SIGSEGV investigation begins (libdroid-util `audio_hw_if`→`primary` string, then
    deeper). `[porting-orig.p5]`
- **2026-08-05/07 (ultra-main p1–p3)** – Audio archaeology corrects the postmortem: the real gate
  is the va-macro/lpass-cdc card-online path, not the string patch (reverted). Build-review findings
  F1–F9 delivered (flash-safety, module-swap audit). S-Pen kernel layer solved (finit force-load).
  `[ultra-main.p1,p2,p3]`
- **2026-08-08 (audio endgame)** – Downloaded Azkali's working gts9wifi image, diffed configs,
  ran ~23 debug rounds, isolated the **five-bug chain** and achieved **first sound**. Charging +
  GPU + touchpad-rotation + S-Pen-as-touch all landed. `[ultra-main.p4][audio-config.p1,p2,p3]`
- **2026-08-11** – Audio knowledge-transfer doc written for the 11"; virtual-h2w workaround built
  and validated with 440 Hz tone; extevdev field report + backport patch prepared. `[audio-cluster §3][audio-config.p4]`
- **2026-08-14/24** – Ultra root FS grown to 6.2 GB (fastbootd + resize2fs); gnuradio/qt6 apt
  failure (unresolved). `[infra §1]`
- **2026-08-24/26** – Folio touchpad rotation daemon (gts9u-tp-rotate v0→v0.1). `[peripherals §1]`
- **2026-08-25/26** – GPS diagnosis: structural HIDL-vs-AIDL mismatch. `[peripherals §2]`
- **2026-08-27/29 (tabS9plus)** – Tab S9+ port kickoff: hardware recon, firmware/OSRC selection,
  imports + build scripts + runbook. `[tabS9plus]`
- **2026-08-27/28/30 (ultra-main p5,p6)** – S-Pen pressure chase on the 11"; declared Mir-1.8-blocked;
  Krita-into-rootfs GL/GLES incident. `[ultra-main.p5,p6]`
- **2026-08-29** – gts9wifi sound dead on new S-Pen build (extevdev regression via packaging);
  from-scratch installer, cold-boot pass. `[audio-cluster §4]`
- **2026-08-30** – Lomiri crash root-caused to the krita/GLES-Qt removal; fresh-install audio-fix
  installer consolidated. `[lomiri-crash.p1,p2]`

---

## 3. The five-bug audio chain (the crown-jewel finding)

Signal path: PulseAudio 16.1 (phablet) → module-droid-card-30/droid-util →
`audio.hidl_compat.default.so` Halium shim (in-process via libhybris) → hwbinder → container
`android.hardware.audio.service_64` (init `vendor.audio-hal`) → `audio.primary.kalama.so`
(Samsung AHAL) → PAL (`libar-pal.so`) → AGM (`libagm.so`) → kernel card `kalama-mtp-snd-card`
(machine_dlkm + lpass_cdc macros). `[audio-config.p1–p4][audio-cluster §3]`

Each bug masked the next. In order:

1. **Module load storm.** `/vendor/bin/vendor_modprobe.sh` backgrounds every modprobe in parallel
   and discards exit codes; the Ultra's `modules.load` was **duplicated 4×** (present in the
   stock/vendor list – measured on both X710 and X910; the own-pipeline
   hypothesis was falsified by the parity audit) amplifying the storm. rx-macro and tx-macro `-EPROBE_DEFER` until **va-macro**
   registers (`lpass_cdc_is_va_macro_registered()`, lpass-cdc-rx-macro.c:4669/tx:2222). If
   `lpass_cdc_va_macro_dlkm` loses the race, the card never registers (`card_state` stays 0);
   some boots `machine_dlkm` itself drops. **va is the keystone** – one insmod cascades to ONLINE
   in ~70 ms. DT: `num-macros=3`, wsa/wsa2 disabled, so va/rx/tx are the only macros that matter.
   Fix: dedupe modules.load at build (`awk '!seen[$0]++'`) + a boot service that walks the list
   and insmods every hole.
2. **Samsung fallback latch.** A card-wait timeout makes AGM set persistent property
   `vendor.audio.use.primary.default=true`; AHAL's `adev_open` then refuses in ~1 ms
   ("adev_open: 2786: sndcard is not active", status -22) surviving service restarts. Fix:
   `setprop vendor.audio.use.primary.default false` every boot after card ONLINE. (Origin of the
   initial `true` never pinned; clear unconditionally.)
3. **Halium shim swallows errors.** `audio.hidl_compat.default.so` (`android_vendor_halium_hardware/
   audio/audio_hw.cpp`): `adev_open` logs the factory `openDevice() error -19` but **returns 0
   with a null deviceIface**; droid-util then logs "Opened hw audio device version 2.0" (the lie)
   and the first forwarded call `adev_init_check` dereferences null → PA SIGSEGV. Core-verified:
   SEGV_MAPERR fault_addr=0x0, PC = shim file offset **0x2280**. Byte-identical halium-12.0..16.0
   + master. Patch: `0001-audio_hw-fail-adev_open-when-the-devices-factory-can.patch` (early-return
   on factory failure). **Hardening only – the SEGV is the messenger, not the root cause.**
4. **droid-extevdev jackless abort.** UT jack detection scans evdev for `EV_SW`+`SW_HEADPHONE_INSERT`;
   a jackless tablet has none → error path calls `mainloop_io_free()` on a never-created io event →
   PA assert `mainloop.c:206` → SIGABRT (rc=134). Independent of 1–3. **This was the ONLY bug the
   11" hit** (its card comes up cleanly). Upstream fix = mer-hybris `dfda983` / PR #135, first in
   tag **14.2.110** (14.2.107–14.2.109 affected). Workaround: `gts9u-virtual-h2w` uinput daemon
   advertising SW_HEADPHONE/MIC/LINEOUT state 0.
5. **Stale container HAL + node perms.** (5a) `vendor.audio-hal` started before the card is up
   keeps a permanently-failed in-process AGM → `setprop ctl.restart vendor.audio-hal` after
   card ONLINE + latch clear. (5b) The container AGM opens `/sys/kernel/snd_card/card_state`
   **O_RDWR** from Android's uid space; host `chgrp audio` (gid 29) is meaningless there →
   `chmod 0666` on `card_state` and `/sys/kernel/aud_dev/state`.

**Bring-up order (the boot service, `gts9u-audio-bringup` v4):** walk modules.load deduped →
wait `card_state==1` (≤90 s, FATAL) → chmod 0666 both nodes → clear latch → `ctl.restart
vendor.audio-hal` + wait running → wait for virtual jack → `touch /run/gts9u-audio-ready`. The
PulseAudio drop-in `zz-gts9u-audio.conf` **hard-gates on the flag** (no `-` prefix; a non-gated
start races into the crash loop and re-poisons the latch) and runs
`env -u HYBRIS_USE_VENDOR_NAMESPACE pulseaudio`. `[audio-config.p2,p4]`

**Exonerated suspects (do not re-investigate):** systemd sandbox hardening; HYBRIS_USE_VENDOR_NAMESPACE
(nuance: set → in-process HAL fails cleanly, no sinks, no crash; working config strips it);
LD_PRELOAD=libtls-padding.so (but it breaks lxc-attach logcat → use `--clear-env`);
HYBRIS_LD_LIBRARY_PATH; host /dev/snd perms; socket activation. The "foreground works, unit crashes"
context-dependence was an **illusion from a missing time-matched control** (the latch flipped
between runs). `[audio-config.p2][audio-cluster §3]`

**Diagnostic keys:** `grep -c ONLINE /proc/snd_debug_proc/sdp_boot_log` (0=never up, 1=up&stable,
>1=came up then tore down – "snd_card is ONLINE" prints ONLY to this Samsung 64K proc buffer, never
dmesg); container logcat needs `lxc-attach -n android --clear-env`; shim logs carry pid 0 (hybris
liblog) vs vendor service real pid. **NEVER `rmmod machine_dlkm`** – instant kernel panic, and
there is no pstore/ramoops (`dump_sink=0x0`).

**Related kernel bug (upstreamable, undrafted):** `lpass_cdc_unregister_macro` (lpass-cdc.c ~722-761)
zeroes `macro_params[id].num_dais` before subtracting from `priv->num_dais`, so the count never
decrements; any macro unbind is unrecoverable without reboot. `[audio-config.p1]`

---

## 4. Landed fixes catalog (with mechanism)

### Boot / display / power
- **Panel cmdline retarget** – halium.config `CONFIG_CMDLINE` (with `CMDLINE_FORCE=y`) inherited the
  11" `msm_drm.dsi_display0=GTS9_ANA38407_AMSA10FA01:`; ABL can't override, so DSI never matched.
  Fix: sed in build script to the device panel (`GTS9U_...AMSA46AS02:` / `GTS9P_...AMSA24VU05:`),
  lcd_id args dropped (ss_dsi reads DDIC at init). Bridge tool `fix-boot-cmdline.py` (padded in-place
  boot.img patch). `[porting-orig.p2]`
- **Charger-mode** – ABL stamps `androidboot.mode="charger"` in vendor_boot bootconfig on cabled
  boots → init runs `on charger` and cleanly exits (the "38-second death"). `ro.boot.mode` is
  read-only from bootconfig. Fix: `start-android-container` wrapper bind-mounts a sed-filtered
  `/proc/bootconfig` (charger→normal) into the container namespace; recovery tool
  `fix-vendor-boot-mode.py`. `[porting-orig.p4]`
- **Fuel gauge / charging** – `sm5714_fuelgauge`/`sm5714-charger` and MUIC/PD `muic_sm5714`/
  `pdic_sm5714` are modversion-locked against the halium kernel (plain insmod EINVAL). Loaded via
  `finit_module(fd,"",3)` (IGNORE_MODVERSIONS|IGNORE_VERMAGIC, syscall 273 on arm64) – the same
  recipe as wez01. Made permanent as the bringup "stage 2 curated finit loader" (allowlist:
  `muic_sm5714 pdic_sm5714 wez01`, never blanket-finit). `[porting-orig.p3][audio-config.p3 §2]`
- **UPower critical-poweroff** – `/etc/UPower/UPower.conf CriticalPowerAction=Ignore` seatbelt
  (once the fuel gauge is honest). `[porting-orig.p4]`
- **Stale-props container SEGV** – recreate `/dev/__properties__` (0711) + rm property_service
  sockets before each container start (folded into start-android-container). `[porting-orig.p3]`
- **Persistent journald** – tmpfiles.d creates `/var/log/journal` so early-boot logs survive OOM. `[porting-orig.p3]`

### Audio
- **Five-bug bringup service** – `gts9u-audio-bringup` v4 + oneshot unit; `zz-gts9u-audio.conf`
  PA gate; `gts9u-virtual-h2w.service`/`.py` uinput jack; modules.load dedupe in
  swap-vendor-modules.sh (restore SELinux xattr). See §3. `[audio-config.p2,p3]`
- **11" virtual-h2w workaround** – `gts9-virtual-h2w.py` + `.service` + `55-gts9wifi-wait-h2w.conf`
  + self-copying `install.sh`; the polished `gts9-audio-fix-install.sh` adds `--force`/`--uninstall`,
  a version gate refusing install on ≥14.2.110, and no-reboot recovery. Validated cold-boot. `[audio-cluster][lomiri-crash.p2]`
- **Upstream patches** – `0001-audio_hw-...` (Halium shim, hardening); `0001-extevdev-...` (Azkali's
  dfda983 backport, verbatim); both with companion docs (`shim-crash-analysis.md`,
  `extevdev-crash-field-report.md`). **Send to Azkali/UBports still open.** `[audio-cluster]`
- **Config restore** – Gemini had wrongly rewritten `audio_policy_configuration.xml` to version 1.0
  (deleting 56 lines: all mic inputs, r_submix, xi:includes) – the version warning is cosmetic;
  restore from Azkali's halium-13 repo. `touch.pa` must be
  `module-droid-card-30 module_id=hidl_compat config=/etc/pulse/gts9/audio_policy_configuration.xml
  voice_virtual_stream=true` (the module_id→primary edit was a self-inflicted regression). `[audio-cluster §1][ultra-main.p4]`

### Input
- **S-Pen force-load** – stock `wez01.ko` CRC-diverges only on `kmem_cache_alloc_trace` (pointer-only
  use); finit_module flags 3. Proper fix = build wez01 in-tree so CRCs match. `[ultra-main.p2]`
- **S-Pen as pointer** – udev `61-gts9u-pen.rules` (ID_INPUT_TOUCHSCREEN=1, TABLET=0) + libinput
  quirk (`+INPUT_PROP_DIRECT`, strip BTN_TOOL_PEN/RUBBER/STYLUS) so the touchscreen path wins.
  Pressure/tilt platform-gated on Mir 2.x. `[audio-config.p3 §4][ultra-main.p5]`
- **Folio touchpad rotation** – `gts9u-tp-rotate` daemon (name-generic, works family-wide); DTS
  `touchpad,invert <0x01 0x00 0x00>` (driver `stm,touchpad`, cells `<x_invert y_invert xy_switch>`)
  staged for the v5 build. `[peripherals §1][audio-config.p3 §5]`
- **Touch calibration** – `71-gts9uwifi-touch-calibration.rules` sets `LIBINPUT_CALIBRATION_MATRIX
  "0 1 0 -1 0 1"` (90° panel rotation). `[RECON-skeletons]`

### App grid / OS hygiene
- **Root-owned ~/.local** kills click .desktop generation → `chown -R phablet`, rerun click hooks,
  clear caches, reboot. `[install-boot §2]`
- **Lomiri fd exhaustion** – `LimitNOFILE=65536` drop-in on lomiri-full-greeter (mitigation). `[lomiri-crash.p1]`
- **GLES-Qt reversal** – remove desktop-GL krita, reinstall `libqt5gui5-gles`/`libqt5quick5-gles`/
  `qtubuntu-android`/metapackages; apt pin `/etc/apt/preferences.d/no-desktop-qt5` (Pin-Priority -1).
  [CORRECTED 2026-08-30: the pin had been recorded as landed but existed
  nowhere as a file, and its on-device application was never confirmed.
  Artifact now at `fixes/hygiene/no-desktop-qt5` + baked in the Ultra
  skeleton; 11" install via the post-flash script; verify on-device per
  `docs/checklists/gts9wifi-next-access.md`.] `[lomiri-crash.p2]`

### Infra
- **Root FS grow** – TWRP fastbootd (userspace) `delete-logical-partition product`+`system_ext`,
  bisect group ceiling to 6,210,715,648 B, online `resize2fs`. LP metadata restore MUST be first
  1 MiB only. Pipeline lpmake fix (system→8e9, group→super capacity) still open. [DONE 2026-08-30 – §6 #5] `[infra §1]`
- **Hotspot TTL** – `net.ipv4.ip_default_ttl=65` laptop-side (Halium kernel may lack xt_TTL). `[infra §5]`

### Build pipeline (findings F1–F9)
- F1: update-binary v4 [since superseded by v5 – §7] – zstd `-t` integrity pre-pass + marker-file pipeline-failure detection
  (old `unzip|dd` masked a partial-super soft-brick as success).
- F2: swap-vendor-modules v2 [since merged into v3 – §7] – LEFTOVER/UNLANDED audit + allowlist strict mode (the class that cost
  the va_macro hunt) + modules.load dedupe.
- F3/F4/F7/F9: build wrapper – preflight (zip/file/pahole/perl), atomic firmware tarball, host-arch
  lpmake detection, PARTS→SRC_PARTS rename.
- F5: prune stale 11" panel `.dat` + STM touch fw from the Ultra skeleton.
  [CORRECTED 2026-08-30: F5 had been recorded as landed but was never
  executed – the three files were still in the skeleton. Executed in
  parity Tier 1.]
- F6: super.sh strict mode.
- F8: goodix_ts_berlin missing = build-fatal; wez01 missing = warning
  [wez01 warn→FATAL on both devices 2026-08-30 – §7].
- Plus audio-overlay sanity gate (V3). `[ultra-main.p1,p2][RECON-build-scripts]`

---

## 5. Hardware / firmware facts worth preserving

### Partition & LP facts
- **SUPER sizes (PIT, byte-exact):** gts9wifi 11,643,387,904 · gts9pwifi 11,714,691,072 ·
  gts9uwifi 11,744,051,200. All PITs 4096 B/block, 99 entries. RECOVERY 109,576,192 on all.
  BOOT/VENDOR_BOOT 100,663,296; INIT_BOOT 8,388,608; DTBO 16,777,216; VBMETA 131,072. `[porting-orig.p1][tabS9plus]`
- **Ultra super LP (Azkali-built, group `ubuntu`):** system 4,718,592,000 (ext4 UT rootfs) ·
  system_ext 145,027,072 · system_dlkm 348,160 · product 1,347,670,016 · vendor 1,725,878,272
  (erofs) · vendor_dlkm 35,713,024 (erofs) · odm 872,448. `[porting-orig.p1]`
- **UFS device geometry (fastboot):** sda raw LUN ~256 GB; super 0x2B6000000; userdata 0x38075F7000.
  Partitions ≥16 get blkext major 259 (sda16→259:0 … sda25→259:9). Root = `system` LP inside super
  (NOT a loop image); /android is a separate ~425M loop0; /home+/userdata on sda34 (f2fs) survive
  reflashes. `[infra §1]`
- **Named partitions:** sda16 dsp, sda17 firmware_mnt, sda20 firmware-modem, sda34 userdata.

### Firmware / bootloader
- **Bootloader bit fuse** = digit after XXU/XXS in the build string, visible in Download Mode
  (`RP SWREV`). **Rev 5 = last unlockable** (Android 15 / One UI 7, e.g. X710XXS5CYG1);
  **rev 6 = terminal** (One UI 8.5, e.g. X710XXS6DZB6). One UI 8 hides the OEM Unlocking
  toggle, but the fuse decides: a fuse-rev 5 unit on One UI 8.0 rolls back to One UI 7
  (Odin BL+AP+full CSC) and unlocks normally [2026-08-31, owner-confirmed]. `[install-boot §1]`
- **Per-unit firmware:** gts9wifi pins **X710XXU5CYD9** (2025-04 patch; the "A13"
  in the shipped fingerprint `:13/TP1A.../X710XXU5CYD9` is port-composed – the
  CYD9 firmware release itself is the April-2025/A15-era quarterly, one XXS
  security respin behind our archived CYG1 packages); gts9uwifi
  vendor **X910XXS5CYG1** (A15, rev 5, patch 2025-07-01); gts9pwifi target **X810XXU1AWHA** (last
  A13/rev 1). Kernel generation 5.15.153 / KMI 30958166 across all. `[porting-orig.p1,p2][tabS9plus]`
- **Sourcing rules:** WiFi SKUs only (X710/X810/X910); verify bit fuse in Download Mode before setup;
  keep off WiFi through setup; disable auto-update; avoid refurbs and X816/X916U carrier variants;
  boot-splash "OEM LOCK" line is correct on a healthy boot chain, but a broken boot
  chain can make it show the wrong state (an unlocked unit with a mis-built custom
  ROM displayed as locked) – Download Mode is authoritative. `[install-boot §1,2]`
- **Odin:** BL+AP+full CSC (not HOME_CSC) for cross-major downgrade; routes images by filename inside
  the tar. No fastboot in Samsung bootloader (Odin/Heimdall only); fastbootd works from TWRP. `[install-boot §1,2]`

### Device-tree / kernel architecture
- Base DTB flashed in vendor_boot is **generic `qcom,kalama` v2** (msm-id 0x207, board-id 0 0, zero
  Samsung strings, byte-identical across the family); board description comes from the **stock dtbo
  partition** (`skip_dtbo_partition=true`, never flashed). Ultra dtbo = 2 entries (board-id 00/03);
  S9+ = 3 (r00/r02/r04); 11" = 4. `[porting-first][porting-orig.p1,p2]`
- Kernel: `kernel-samsung-gts9wifi` @ `android13-5.15-halium`, defconfig
  `vendor/kalama-gki_defconfig halium.config`, clang r450784e, LLVM/LTO. `CONFIG_EPEN_WACOM_WEZ01=m`
  and `CONFIG_TOUCHSCREEN_GOODIX_BRL=m` (Ultra) / `CONFIG_TOUCHSCREEN_STM_FTS1BA90A=m` (11"/+) in
  defconfig; Samsung's LEGO build injects Kconfig/Makefile wiring at build time (hence the 4-line
  static wiring in the imports). `[porting-orig.p1,p2][tabS9plus]`
- **Module names (do not "correct"):** touch = `stm_ts_fts1b90a.ko` (Samsung's truncated spelling of
  fts1ba90a) / `goodix_ts_berlin.ko`; pen = `wez01.ko` (not wacom.ko); WLAN = `qca_cld3_kiwi_v2.ko`. `[tabS9plus][porting-orig.p2]`
- **Module swap:** `swap-vendor-modules.sh` extracts stock vendor_dlkm erofs, replaces same-named
  .ko with halium-built ones (SELinux ctx from smcinvoke_dlkm.ko, fallback `u:object_r:vendor_file:s0`),
  repacks `mkfs.erofs -zlz4 -T0 --force-uid/gid=0`. Vermagic census: stock X910 modules
  (`5.15.153-android13-8-30958166-abX910XXS5CYG1`) cannot load on the halium kernel – the OSRC drop
  is the hard prerequisite; there is no stock-kernel shortcut (AppArmor requires a kernel rebuild). `[porting-orig.p1]`

### HAL / userspace facts
- **Audio nodes/paths:** `/sys/kernel/snd_card/card_state` (0/1 gate, AGM polls O_RDWR),
  `/sys/kernel/aud_dev/state` (write-only bookkeeping), `/proc/snd_debug_proc/sdp_boot_log` (only
  place "snd_card is ONLINE" prints); card `kalama-mtp-snd-card`; machine driver `kalama-asoc-snd`
  bound to `soc:spf_core_platform:sound` (no bind/unbind sysfs, `suppress_bind_attrs=true`); latch
  prop `vendor.audio.use.primary.default`. `[audio-config.p1,p3]`
- **GPS:** vendor `/vendor/bin/hw/android.hardware.gnss-aidl-service-qti` = **AIDL IGnss V2**; UT
  bridge `libubuntu_application_api.so` (baked into the halium system image, invisible to apt) is a
  **HIDL-1.x-only client** → structural mismatch, GPS cannot work for AIDL-only vendors. Lead:
  `libgps.so.30` in lomiri-location-serviced. `[peripherals §2]`
- **Compositor:** Mir **1.8.3** – no zwp_tablet_v2, no tablet-tool → S-Pen pressure/tilt is a hard
  compositor ceiling; apps ride the `ubuntumirclient` QPA. Mir 2.x migration roadmapped ~Q2 2026
  (Miroil-gated on Qt6), hybris devices last. `[ultra-main.p5,p6]`
- **Package versions (exact):** `pulseaudio-modules-droid-30 14.2.109-0ubports1+...gbpa4beff`
  (2026-07-28 snapshot, 3 days before dfda983/14.2.110); `-28`/`-29` at 14.2.102; pulseaudio 16.1;
  `pulseaudio-modules-droid-hidl 1.5.1`; Mir 1.8.3-0ubports1; qtmir-qt5-mir1 0.7.2; lomiri 0.5.0;
  krita 5.2.2. `[audio-cluster][ultra-main.p6]`
- **Repos:** `gitlab.com/azkali-samsung/gts9/ubports/*` – device `samsung-gts9` (branch `halium-13`,
  project 58785718); `kernel-samsung-gts9wifi` + 10 techpacks (branch `android13-5.15-halium`);
  build tools (branch `personal/azkali/gts9-integration`). AGM @ CodeLinaro `LA.VENDOR.13.2.1.c25`.
  Halium shim @ `Halium/android_vendor_halium_hardware` branch `halium-13.0`. Firmware donor tarball
  `download.azka.li/samsung/tab-s9/firmware/ubuntu-touch-kalama-firmware-v.tar.xz`. `[audio-config.p1][porting-orig.p1]`
- **Coexistence:** the agcarbajo mainline postmarketOS port (Linux 7.2-rc3, v1.71, GNOME/Wayland
  2960×1848@120, rootfs-on-microSD) never touches super/userdata → coexists with the UT install. `[install-boot §6]`

---

## 6. Open issues ledger (as of 2026-08-30)

**Highest leverage (upstream, unsent):**
1. Send Azkali/UBports: bump `pulseaudio-modules-droid-30` to ≥14.2.110 (or cherry-pick dfda983);
   file on the packaging tracker (scope: all jackless halium-13 24.04 devices on -30). Aug 11
   deliverables (field report, patch, tarball) believed on the build box. `[audio-cluster §4]`
2. Submit the Halium shim patch (`0001-audio_hw-...`) to `android_vendor_halium_hardware`. `[audio-config.p2]`
3. Draft the `lpass_cdc_unregister_macro` kernel accounting patch. `[audio-config.p1]`

**gts9uwifi (Ultra):**
4. Sensors HAL (ISensors@2.1 multihal not registering) – genuinely open. `[porting-orig.p4]`
5. ~~Bake the resized system-LP size + group budget into the pipeline.~~ **DONE
   2026-08-30** (deviceinfo 7600M + super.sh v3 group-at-capacity; parity Tier 2). `[infra §1]`
6. Touchpad: daemon now BAKED in the skeleton (default 270; Tier 1). Remaining:
   the `touchpad,invert <0x01 0x00 0x00>` DTS bake – deliberately deferred until
   the stm32_pogo DT parser is read (one-bit mirror risk); reconcile the sed'd
   copy in the build-box working tree either way; after the bake, flip daemon
   default 270→0. `[peripherals §1]`
7. USB-C host mode dead; cameras/UDFPS untested; touch enumeration race across boots. `[porting-orig.p4,p5]`
8. Boot-time PD negotiation lands plain USB/rp(2) (pdic loads at t≈12s) – one replug renegotiates. `[audio-config.p3]`

**gts9wifi (11"):**
9. GPS structural HIDL/AIDL mismatch – verify libgps/gpsd-provider lead; possibly write a standalone
   gbinder AIDL NMEA→TCP client (with QMI_LOC_STOP shutdown discipline). `[peripherals §2]`
10. Bluetooth HAL crash-loop outcome uncaptured. `[install-boot §10]`
11. Confirm the krita-removal/GLES-reinstall was executed; archive live audio-fix artifacts off-device. `[lomiri-crash.p2]`
12. 2.x build boot-hang (reserved-memory reclaim suspect) – dtbo diff never done. `[install-boot §2]`

**gts9pwifi (S9+):**
13. Execute the port: skeleton fork gts9u→gts9p, firmware pull + extract, unit prep (unlock, TWRP
    trust-verify, EFS backup, stock /proc/cmdline capture), build, flash, bring-up ladder. `[tabS9plus]`
14. Open variance: whether the Ultra's audio chain reproduces on gts9p; whether gts9p TWRP is trustworthy. `[tabS9plus]`

**Cross-cutting / platform-gated:**
15. S-Pen pressure/tilt to apps – waits for UT Mir 2.x/Qt6 (~Q2 2026, hybris last). Interim:
    touchscreen-masquerade pointer; Waydroid+Krita-Android untested path. `[ultra-main.p6]`
16. Touchpad two-finger scroll broken in Morph (qtmir continuous-vs-discrete wheel); pinch broken
    (Mir/qtmir gesture gap) – both likely upstream, affecting all UT touchpad devices. `[peripherals §1]`
17. Retro EFS backups of the base S9 and Ultra units (pristine, never PIT'ed – intact). `[tabS9plus]`
18. gnuradio/qt6 apt install fails (qt6-base-abi no provider) – use radioconda under /home. `[infra §1]`

**Persistence discipline (recurring):** every image flash wipes the rootfs and every userdata wipe
removes /home; fixes that survive live on /data or in the skeleton overlay. Post-flash:
run `fixes/post-flash/<device>-post-flash.sh` (and keep the kit off-device). `[install-boot §2][lomiri-crash.p2]`

**Fleet update 2026-08-31:** new-in-box **rev 1** test units acquired for all
three models (S9+, X710, X910) – the rev 1 / AWHA path moves from assembled to
testable; hash-pin the AWHA packages in FIRMWARE.md when downloaded.

**New ledger items (2026-08-30 parity audit):**
19. ~~Merge the two swap-vendor-modules.sh generations (dedupe + audit).~~ **DONE**
    (v3 in common/ + skeleton, report-only default; per-device allowlist triage
    still pending – do it on each device's next build). `[E-build-scripts-parity]`
20. Send the goodix-berlin import + wiring + `CONFIG_TOUCHSCREEN_GOODIX_BRL=m`
    upstream to Azkali's kernel tree – gives Goodix-rev 11" units working touch;
    fully formed in `devices/gts9uwifi/imports/`, currently stranded. `[F-kernel-imports]`
21. Three-panel merged display `msm/Kbuild` (GTS9+GTS9P+GTS9U, `_SUFFIXED`
    vars): the two import bundles whole-file-overwrite Kbuild and are mutually
    exclusive on a shared tree (fine today – each build clones fresh). Do when
    unifying trees; until then never apply both bundles to one checkout. `[F-kernel-imports]`
22. update-binary v5 sed-safe device check: verified by fork simulation
    (13/13 gates, correct accept/reject matrix) but not yet exercised on a
    physical flash – eyeball its ui_print output on the next TWRP install. `[parity Tier 2]`
23. 11" preventive audio hardening installer created (bugs 1/2/5,
    `fixes/audio/gts9wifi-audio-hardening-install.sh`) – INSTALL on next
    device access via the post-flash script. `[D-audio-parity §3]`

**New ledger items (2026-08-31 build/skeleton/subsystems review, deferred LOWs;
the HIGH/MED findings were fixed same-day – see §8):**
24. Build wrappers: bare `[ -f ]`/`grep -q` sanity gates die messageless under
    `set -e` in scripts whose runs take hours – wrap in named-error gates or a
    small `assert()` helper. `[H-build-logic L3]`
25. update-binary: failure markers are `touch`ed inside the failing subshell; if
    /tmp is full at that exact moment the marker itself fails and (without
    pipefail) the failure passes silently. Pre-create markers and DELETE on
    success instead. Pipefail-capable ash covers it today. `[H-build-logic L5]`
26. update-binary: sibling reject matches 4-char model tokens (`x810` etc.) as
    raw substrings of cmdline+bootconfig – a coincidental substring causes a
    spurious hard reject (fails safe, never cross-flashes). Anchor on the known
    bootloader keys if a false positive ever appears in the field. `[H-build-logic L6]`
27. Ultra pen udev rules encode opposite intents: `61-gts9u-pen.rules` clears
    `ID_INPUT_TABLET`, `74-gts9-wacom.rules` (lexically later) re-sets it to 1,
    so 61's clear is dead code. Inert today (the libinput quirk strips the pen
    buttons so the touchscreen path wins) – drop one side for coherence, then
    re-verify pen pointer + eraser on-device. `[I-skeleton L1]`
28. `fixes/input-touchpad/gts9u-tp-rotate/install.sh` has no `--uninstall`
    (every other fix installer has one) – add for symmetry. `[I-skeleton L2]`

## 7. 2026-08-30 parity remediation (summary of what changed)

Five-tier remediation executed against the parity-audit findings (full audit:
`archive/notes/parity/`, review `docs/reviews/PARITY-REVIEW-2026-08-30.md`):
Tier 1 skeleton gaps (WiFi persistence, GROUP=audio, tp-rotate baked @270,
LimitNOFILE, apt pin, F5 prune, dedupe ramdisk lists, identity strings, h2w
uinput belt, v4 header); Tier 2 build system (merged swap v3, super.sh v3
LP budget + 7600M root, make-flashable v2, update-binary v5 sed-safe check,
explicit SUPER export, true comments, wez01 FATAL both devices); Tier 3
gts9p kit docs (runbook fork recipe incl. uppercase pass, new build gates;
the wacom input wiring files landed with Tier 2); Tier 4 gts9wifi hardening + pen
installer + hygiene artifacts + post-flash kits + next-access checklist;
Tier 5 these record corrections + upstream submission packs.

## 8. 2026-08-31 build/skeleton review + subsystems framework (what changed)

Four adversarial reviews (build logic, skeleton integrity, subsystems checklist,
subsystems script) over the build wrappers, common scripts, flasher, overlay
units, and the new subsystems materials. All HIGH/MED findings fixed same day:

- **Flasher** (`update-binary`): `conv=fsync` on both dd writes; bundled-zstd
  fallback verifies unzip rc + non-empty + executable before trusting it.
- **Bring-up** (`gts9u-audio-bringup`): HAL restart now verifies the pid
  actually changed (old pid captured via `init.svc_debug_pid`/pgrep; warns and
  re-sleeps if the restart was a no-op).
- **Units**: `gts9u-tp-rotate.service` dropped `After=multi-user.target`
  (ordering cycle with its own WantedBy could silently drop the start job) –
  both the skeleton and fixes-kit copies.
- **Installers**: `$`-escaping fixed in the 11" audio-fix PA gate heredoc and
  the 55-conf (systemd unit `%`/`$` semantics ate `$n`; the gates never
  actually waited); uninstall paths now remount rw first (three installers).
- **mount-android-partitions**: the vendor_dlkm override hack is now guarded
  (only fires for the vendor_dlkm mountpoint when the override image exists
  and nothing is mounted yet) with all inner mounts failure-tolerant.
- **Post-flash sweep**: also removes fixes-kit-named debris
  (`gts9u-load-audio-macros.service`, `50-gts9u-audio-wait.conf`).
- **Build wrappers**: FWTAR staleness guard (repack when any SRC_PARTS image
  is newer; invalidates the preserved vendor_dlkm.img.stock); module-presence
  gate scoped to the newest built modules dir; dead `J` knob removed.
- **swap-vendor-modules**: BUILT auto-detect takes the NEWEST modules dir;
  post-swap getfattr verification warns loudly when SELinux labels didn't
  apply (unprivileged host).
- **super.sh**: an explicitly-set-but-missing `LPMAKE` is now a hard error
  (typo no longer silently masked by the prebuilt fallback).
- **make-flashable**: names which vbmeta (built vs skeleton) was packaged.
- **New**: `docs/checklists/SUBSYSTEMS.md` (UBports portStatus-aligned family
  matrix + extras + port-diagnostics rows, evidence policy: `+`/`-` require
  on-silicon record) and `tools/diagnostics/subsystems-check.sh` (read-only
  on-device sweep emitting a paste block keyed to the matrix).
- **Record corrections**: GPS is NOT "no hardware" on WiFi models (vendor
  ships AIDL IGnss; the 11" diagnosis is a software mismatch, ledger #9) –
  Ultra section + checklist fixed; SD card: family HAS a microSD slot.
- Deferred LOWs recorded as ledger items 24–28.
