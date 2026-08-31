# A — gts9uwifi (Ultra) skeleton: complete feature manifest

Audited 2026-08-30. Root: `/home/jstockdale/projects/ubuntu-touch-gts9/devices/gts9uwifi/skeleton/`
(below, `SK/` = that root). Every claim below is **VERIFIED** (file read in this pass) unless
marked REPORTED. Skeleton self-identifies as "generated 2026-08-03 from samsung-gts9
(halium-13)" (`SK/PORT-README.md:1`) — the unpacked audio-era samsung-gts9u device repo.

Binaries skipped (not read): `flashable/prebuilt/zstd`, `scripts/prebuilt/lpmake`,
`overlay/system/usr/bin/umtprd`, `.../libaalcamera.so`, firmware `.dat`/`.bin`,
`vendorboot/dtbo`, `vendorboot/vendor_dtb` (grepped `vendor_dts` text instead),
`vendorboot/initrd-touch-arm64-noloader.img`, `GTS9UWIFI_EUR_OPEN.pit`, `vbmeta.img`,
`ramdisk-overlay/bin/kmod`, `overlay/.../__pycache__/*.pyc`.

Legend for device-specificity: **[U]** = gts9u-hardcoded (name/path/value specific to the Ultra),
**[F]** = family-generic mechanism (portable to gts9wifi/gts9pwifi as-is or with rename only).

---

## 1. Systemd units (system scope), `SK/overlay/system/etc/systemd/system/` and `.../usr/lib/systemd/system/`

| Unit | Path | Subsystem | Spec |
|---|---|---|---|
| `gts9u-audio-bringup.service` | `etc/systemd/system/gts9u-audio-bringup.service` — oneshot, `After=local-fs.target`, `TimeoutStartSec=360`, ExecStart=`/usr/local/sbin/gts9u-audio-bringup` | audio | [F] mechanism, [U] name |
| `gts9u-virtual-h2w.service` | `etc/systemd/system/gts9u-virtual-h2w.service` — runs `/usr/local/lib/gts9u-virtual-h2w.py`, `Restart=on-failure` | audio | [F] mechanism, [U] name |
| `gts9-adb.service` | `usr/lib/systemd/system/gts9-adb.service` — static ADB gadget, `Conflicts=usb-moded.service`, `OnFailure=gts9-adb-recover.service` | other (USB/adb) | [F] |
| `gts9-adb-recover.service` | `usr/lib/systemd/system/gts9-adb-recover.service` — `systemctl --no-block restart gts9-adb` | other (USB/adb) | [F] |
| `gts9-efs-ro.service` | `usr/lib/systemd/system/gts9-efs-ro.service` — remount `/android/efs` ro after mount-android-partitions | boot | [F] |
| `gts9-ensure-efs-mountpoint.service` | `usr/lib/systemd/system/gts9-ensure-efs-mountpoint.service` — creates /efs mountpoint in android-rootfs.img (fingerprint calibration) | boot | [F] |
| `umtprd.service` | `usr/lib/systemd/system/umtprd.service` — Type=notify, pre-mounts functionfs at `/dev/usb-ffs/mtp` | other (MTP) | [F] |

Masked units (symlinks to `/dev/null`):
- `etc/systemd/system/adbd-prepare.service` -> /dev/null (boot/adb) [F]
- `etc/systemd/user/mtp-server-usb-moded-watcher.service` -> /dev/null (MTP) [F]
- (non-unit mask) `usr/share/halium-overlay/vendor/lib64/hw/gralloc.default.so` -> /dev/null (graphics) [F]

## 2. Wants-symlinks

- `etc/systemd/system/multi-user.target.wants/gts9u-audio-bringup.service` -> `../gts9u-audio-bringup.service` (audio)
- `etc/systemd/system/multi-user.target.wants/gts9u-virtual-h2w.service` -> `../gts9u-virtual-h2w.service` (audio)
- `usr/lib/systemd/system/multi-user.target.wants/gts9-adb.service` -> `../gts9-adb.service` (adb)
- `etc/systemd/system/mount-android-partitions.service.wants/gts9-efs-ro.service` -> `/usr/lib/systemd/system/gts9-efs-ro.service` (boot)
- `etc/systemd/system/mount-android-system.service.wants/gts9-ensure-efs-mountpoint.service` -> `/usr/lib/systemd/system/gts9-ensure-efs-mountpoint.service` (boot)

## 3. Systemd drop-ins (system scope), `SK/overlay/system/etc/systemd/system/`

| Drop-in | Content | Subsystem | Spec |
|---|---|---|---|
| `adbd.service.d/50-gts9uwifi-restart.conf` | Restart=on-failure, RestartSec=1, StartLimit 3/30s, `OnFailure=gts9-adb-recover.service` (ep0-close on gadget rebind) | adb | [F] |
| `lxc-android-config.service.d/gts9uwifi.conf` | Replaces ExecStart with `/usr/lib/gts9uwifi/start-android-container` (charger-filter + stale-property clean wrapper) | container/boot | [F] mechanism, [U] path name |
| `repowerd.service.d/50-gts9uwifi-wait-backlight.conf` | Wait ≤30s for `/sys/class/backlight/panel0-backlight/brightness`; bind-mount `/run/empty` over `/sys/class/backlight/panel` | power | [U] sysfs names, [F] idea |
| `repowerd.service.d/51-gts9uwifi-wait-battery.conf` | Hold repowerd ≤30s until UPower reports non-zero battery Percentage (anti "0.0% critical poweroff" race) | power | [F] |
| `usb-moded.service.d/override.conf` | `usb_moded --systemd --force-syslog -f` (accept cable on charger voltage; msm-eud extcon reports USB=0; long `--fallback` aliases to -d in 0.86) | other (USB) | [F] |
| `waydroid-container.service.d/50-gts9uwifi-binder.conf` | ExecStartPre=`/usr/libexec/gts9-waydroid-binder` (anbox-* binderfs nodes + lxc.namespace.keep) | container | [F] |

## 4. Systemd drop-ins (user scope), `SK/overlay/system/etc/systemd/user/`

| Drop-in | Content | Subsystem | Spec |
|---|---|---|---|
| `pulseaudio.service.d/zz-gts9u-audio.conf` | **The PA hard gate.** `ExecStartPre=/usr/bin/timeout 150 /bin/sh -c 'until [ -e /run/gts9u-audio-ready ]; do sleep 1; done'` — **no `-` prefix** (line 5; comment lines 2–4 states intent: "No '-': if bring-up never finishes, PA must not start"). Also re-execs PA via `env -u HYBRIS_USE_VENDOR_NAMESPACE`, and relaxes MemoryDenyWriteExecute/SystemCallFilter/LockPersonality/RestrictNamespaces | audio | [F] mechanism, [U] flag-file name |
| `lomiri-full-greeter.service.d/50-gts9uwifi-timeout.conf` | `TimeoutStartSec=600` | boot | [F] |
| `lomiri-full-shell.service.d/50-gts9uwifi-timeout.conf` | `TimeoutStartSec=600` | boot | [F] |

## 5. Udev rules

| Rule file | Content | Subsystem | Spec |
|---|---|---|---|
| `etc/udev/rules.d/61-gts9u-pen.rules` | S-Pen `sec_e-pen` classified as touchscreen (`ID_INPUT_TOUCHSCREEN=1`, tablet unset); long rationale comment (Mir 1.x has no zwp_tablet_v2), "Verified working 2026-08-10" | pen | [F] (`sec_e-pen` name family-shared) |
| `usr/lib/udev/rules.d/70-gts9uwifi.rules` | 269-line Android device-node ownership table (kgsl, dma_heap fix at lines 13–15, audio msm_*, radio, nfc…); line 266–269: `uhid` returned to root:root 0600 so bluetoothd can open it (BLE HID fix) | other (perm table) | [F] (generic QCom table) |
| `usr/lib/udev/rules.d/71-gts9uwifi-touch-calibration.rules` | `sec_touchscreen` -> `LIBINPUT_CALIBRATION_MATRIX="0 1 0 -1 0 1"` | touch | [F] matrix shared family-wide |
| `usr/lib/udev/rules.d/72-gts9uwifi-adb-recover.rules` | udc change event with empty `USB_UDC_DRIVER` -> restart gts9-adb.service (dwc3 role-swap teardown) | adb | [F] |
| `usr/lib/udev/rules.d/73-gts9uwifi-usb-cable.rules` | Force `POWER_SUPPLY_ONLINE=1` on usb supply; battery uevent re-trigger | power | [F] |
| `usr/lib/udev/rules.d/74-gts9-wacom.rules` | Pen calibration matrix `0 1 0 -1 0 1` for `sec_e-pen` / `*Wacom*`; header says "shared by gts9wifi/gts9uwifi" | pen | [F] |

## 6. Libinput quirks

- `etc/libinput/local-overrides.quirks` — `[Samsung S-Pen gts9u]` `MatchName=sec_e-pen`,
  `AttrInputProp=+INPUT_PROP_DIRECT`, strips `BTN_TOOL_PEN/RUBBER/STYLUS/STYLUS2`
  (makes pen-as-touch win over the tablet path). Subsystem: pen. [F] mechanism.

## 7. tmpfiles.d / sysctl / journald / power configs

- `etc/tmpfiles.d/gts9uwifi-journal.conf` — `d /var/log/journal 2755 root systemd-journal - -`
  (**persistent journald**). journald. [F]
- `etc/UPower/UPower.conf` — `CriticalPowerAction=Ignore`. power. [F]
- **sysctl drop-ins: NONE anywhere in the skeleton** (`find -name '*sysctl*'` empty). The hotspot
  TTL fix in PORT-STATE is laptop-side, so nothing expected here.
- `etc/systemd/logind.conf.d/50-gts9uwifi.conf` — ignore power/suspend/hibernate/lid keys. power. [F]

## 8. sbin / libexec / lib scripts

| Script | Role | Subsystem | Spec |
|---|---|---|---|
| `usr/local/sbin/gts9u-audio-bringup` (103 lines) | **Audio bring-up v3** (line 2). Steps: dedup-walk `modules.load` w/ blocklist + insmod fill (l.21–36); **stage-2 curated finit loader** `FINIT_MODULES="muic_sm5714 pdic_sm5714 wez01"` via python3 `syscall(273,…,flags=3)` = IGNORE_MODVERSIONS\|VERMAGIC (l.38–71); wait card ONLINE ≤90s (l.73–75); chmod 0666 `card_state`/`aud_dev/state` (l.77); clear `vendor.audio.use.primary.default` latch (l.79–83); `ctl.restart vendor.audio-hal` + wait running (l.85–91); wait for virtual h2w device warn-only (l.97–100); `touch /run/gts9u-audio-ready` (l.102) | audio (+power: charging modules) | [F] mechanism, [U] names |
| `usr/local/lib/gts9u-virtual-h2w.py` (26 lines) | uinput EV_SW jack device `gts9u-virtual-h2w`, state 0 = speakers, so droid-extevdev doesn't abort PA on jackless hw | audio | [F] |
| `usr/lib/gts9uwifi/start-android-container` (54 lines) | Container wrapper: **stale-state clean** — rotate `/dev/__properties__`, remove property sockets (l.14–18, comment: "family-portable robustness fix"); **filtered bootconfig** charger→normal, bind-mounted over container `proc/bootconfig` (l.20–27, 47–48); stock halium stage-2 selection preserved (l.29–44) | container/boot/power | [F] mechanism, [U] dir name |
| `usr/libexec/gts9-adb-gadget` (105 lines) | Static configfs ADB(+MTP) gadget, deterministic ordering, runtime-mask of usb-moded (l.21–28), forced `peripheral` mode (l.94–102). **Note: l.45 `echo "SM-X710" > product`** — 11" model string hardcoded in the Ultra skeleton | adb | [F] |
| `usr/libexec/gts9-ensure-efs-mountpoint` (46 lines) | Adds `/efs` to android-rootfs.img, grows image 16M if full | boot | [F] |
| `usr/libexec/gts9-waydroid-binder` (23 lines) | anbox-binder/hwbinder/vndbinder via BINDER_CTL_ADD, 0666, symlinks; adds `lxc.namespace.keep = ipc user time` to waydroid config | container | [F] |
| `usr/libexec/lxc-android-config/device-hacks` (81 lines) | gst plugin symlink farm sans hybris (l.3–10); force peripheral USB (l.12–14); double-tap-to-wake `aot_enable,1` + repowerd display-state mirror onto `tsp/input/enabled` (l.16–37); real Wi-Fi MAC from `/mnt/vendor/efs/wifi/.mac.info` into runtime NM conf + one-shot reconnect (l.41–70); aethercast props (l.72–74); `debug.stagefright.ccodec 4` (l.76–79); camera orientations 0 (l.81–82) | other (grab-bag) | [F] |
| `usr/libexec/lxc-android-config/mount-android-partitions` (334 lines) | Patched stock mount script; gts9 delta: `/userdata/vendor_dlkm.img` loop-mount + `/vendor_dlkm` symlink (l.96–98) | boot | [F] |
| Stray: `usr/libexec/__pycache__/gts9-waydroid-bindercpython-312.pyc` | build artifact accidentally in overlay (ships into image) | — | cleanup candidate |

## 9. Build/flash scripts, `SK/scripts/` + `SK/build.sh`

- `scripts/swap-vendor-modules.sh` (43 lines) — repacks vendor_dlkm.img: extract stock erofs,
  **modules.load dedupe** `awk '!seen[$0]++'` over every `modules.load*` with ownership/SELinux
  restore (l.22–29; comment: stock list duplicated 4x, spawn-storm loses lpass_cdc_va_macro /
  machine_dlkm → no sound card), then swaps built .ko files, re-mkfs erofs. audio/boot. [F]
- `scripts/super.sh` — lpmake super.img, `SUPER=11744051200` (**[U]** Ultra PIT size). boot.
- `scripts/make-flashable.sh` — zstd-compressed super in flashable zip. boot. [F]
- `build.sh` — clones Azkali branch `personal/azkali/gts9-integration` build tools + 10 vendor
  kernel trees; 24.04-2.x rootfs; runs swap-vendor-modules.sh at the end (l.28). [F]
- `.gitlab-ci.yml` — arm64 CI build + package upload; `USB_DR_MODE: "otg"`. [F]

## 10. deviceinfo (42 settings, all read)

Key values: codename `gts9uwifi`; kernel source Azkali `kernel-samsung-gts9wifi.git` branch
`android13-5.15-halium`; defconfig `vendor/kalama-gki_defconfig halium.config`; cmdline
`video=vfb:… bootconfig loop.max_part=7`; **`deviceinfo_kernel_wlan_chip="kiwi_v2"`** (l.25, Ultra
WCN785x — [U]) + `CONFIG_SEC_SS_CNSS_FEATURE_SYSFS=y` extra (l.26); 12 vendor module trees (l.27);
prebuilt ramdisk/dtb/dtbo/bootconfig from `vendorboot/`; header v4, os_patch_level 2025-07,
halium 13, UT release 24.04-2.x; unified recovery (xxhdpi, recovery partition 109576192 —
[U] Ultra PIT); `deviceinfo_skip_dtbo_partition="true"`.

## 11. Other overlay configs

- `etc/deviceinfo/devices/gts9uwifi.yaml` — Lomiri device config: tablet, Landscape primary,
  backlight `panel0-backlight`, flashlight `torch-sec1`, Mir backpressure/partial-updates/eglsync
  tuning. graphics. [U] name / [F] values.
- `etc/default/lsc-wrapper.d/10-force-hwc2.conf` (`MIR_ANDROID_FORCE_HWC2=1`) and
  `20-gts9uwifi-disable-overlays.conf` (`--enable-num-framebuffers-quirk=false --disable-overlays=true`). graphics. [F]
- `etc/environment.d/50-gst-no-hybris.conf` (GST plugin path to `~/.local`) and
  `hybris-ld-path.conf` (`HYBRIS_LD_LIBRARY_PATH=/system/apex/com.android.i18n/lib64`). other. [F]
- `etc/gbinder.conf` — ApiLevel 33. container. [F]
- `etc/modules-load.d/gts9uwifi.conf` — host-side `sm5714_fuelgauge`, `sm5714-charger` (comment:
  without them capacity reads 0 and UPower powers off in 2–3 min). power. [F]
- `etc/NetworkManager/conf.d/99-gts9-wifi-mac.conf` — `wifi.scan-rand-mac-address=no`. other. [F]
- `etc/sensorfw/sensord.conf.d/50-gts9uwifi.conf` — accelerometer transformation matrix
  `0,-1,0,1,0,0,0,0,1`. other. [F]
- `etc/pulse/touch.pa` — UT stock plus `module-droid-card-30 module_id=hidl_compat
  config=/etc/pulse/gts9/audio_policy_configuration.xml voice_virtual_stream=true` (l.47). audio. [F]
- `etc/pulse/gts9/audio_policy_configuration.xml`, `audio_policy_volumes.xml`,
  `default_volume_tables.xml` — droid policy XMLs (present; PORT-README l.9–10 flags
  "regenerate pulse XMLs from X910 vendor audio configs" as an open TODO — current ones are
  family/gts9 copies). audio. [F]-copied.
- `etc/apparmor.d/abstractions/base.d/gts9-mountinfo` — mountinfo read for confined apps. other. [F]
- `usr/share/apparmor/hardware/audio.d/apparmor-easyprof-ubuntu_gts9uwifi` — pulse
  client.conf.d + autospawn flag reads (audio). `video.d/...` — dma_heap read for Codec2 (video).
  `graphics.d/...android12` — i18n apex libs for libhybris. [F]
- `etc/default/usb-moded.d/device-specific-config.conf` — **`PRODUCT=SM-X710`** (l.10) — 11"
  model string in Ultra skeleton (cosmetic USB identity; also in gts9-adb-gadget l.45). [U-wrong]
- `etc/usb-moded/90-device-specific-config.ini`, `dyn-modes/mtp.ini`, `run/mtp-umtprd.ini`,
  `etc/umtprd/umtprd.conf` — MTP stack config (udc `a600000.dwc3`). other. [F]
- `etc/systemd/logind.conf.d`, UPower, tmpfiles: see §7.

## 12. halium-overlay (Android-side), `usr/share/halium-overlay/`

- `system/etc/init/hw/init.rc` (1351 lines, patched stock; `setrlimit nofile 32768` l.51 is stock Android)
- `system/etc/init/hw/init.boringssl.zygote64_32.rc` — 64-bit-only boringssl self-tests (SM8550 has no 32-bit EL0)
- `system/etc/init/init.disabled.rc` — lmkd, audio-hal-2-0, usb-hal disabled; **comment keeps
  `vendor.audio-hal` enabled for the hidl_compat shim** (audio-relevant)
- `vendor/etc/init/boringssl_self_test.rc` — drops reboot_on_failure from 32-bit vendor self-test
- `vendor/etc/init/gts9-sensors-hidl.rc` + `vendor/etc/vintf/manifest/gts9-sensors-hidl.xml` — sensors 2.1 multihal HIDL service
- `vendor/etc/init/android.hardware.usb@1.3-service.coral.rc`, `init.qcom.usb.rc` — emptied (0-line) to kill vendor USB HAL fights
- `vendor/etc/init/vndservicemanager.rc` — LD_PRELOAD libselinux_stubs
- `vendor/etc/vintf/manifest_kalama.xml` (451 lines) — trimmed vendor manifest
- `vendor/bin/hw/android.hardware.sensors@2.1-service.multihal` (script wrapper)
- `var/lib/lxc/android/config` — LXC container config (`lxc.namespace.keep = ipc user`)
- masked `vendor/lib64/hw/gralloc.default.so` -> /dev/null

## 13. Ramdisks / vendorboot / kernel-additions

- `ramdisk-overlay/init` (308 lines, stock-style halium initramfs init; no gts9-specific delta
  found by grep), `ramdisk-overlay/scripts/panic/telnet`, `ramdisk-overlay/bin/kmod` (binary)
- `vendor-ramdisk-overlay/lib/modules/modules.load` (124 lines — **one residual duplicate:
  `qrng_dlkm.ko`**), `modules.load.recovery` (416 lines, 2 duplicates), `modules.blocklist`
  (63 lines, itself contains dup `dummy_hcd`), `modules.alias`
- `vendorboot/bootconfig` (3 lines: hardware=qcom, memcg=1, usbcontroller=a600000.dwc3) — note the
  charger filtering is NOT here; it is runtime in start-android-container (ABL appends mode=charger
  at power-on, can't be pre-filtered in the image)
- `vendorboot/bootconfig.recovery` (+`boot_devices=soc/1d84000.ufshc`)
- `ramdisk-recovery-overlay/`: `init.recovery.qcom.rc`, `prop.halium` (minui rotation: touch
  ROTATION_RIGHT — portrait-mounted controller; `ro.boot.dynamic_partitions=true`),
  `recovery.fstab`, panel firmware `.dat`, touch fw `fts1ba90a_gts9.bin` (**note: STM touch fw =
  11"/S9+ controller; Ultra touch is goodix_ts_berlin per kernel-additions l.8–10 — recovery
  overlay still carries the family STM blob**)
- `kernel-additions/halium.config.append` — one live setting `CONFIG_EPEN_WACOM_WEZ01=m` (l.7);
  the rest are comment TODOs: goodix_ts_berlin import, kiwi_v2 wlan verify, PROJECT_NAME
  audio/camera per-board configs from X910 OSRC (l.8–18). pen/kernel. [U]

---

## Verification of PORT-STATE §4 expected fixes (in-skeleton)

| # | Expected fix | Verdict | Evidence |
|---|---|---|---|
| a | gts9u-audio-bringup service + script version | **PRESENT — v3** | unit `SK/overlay/system/etc/systemd/system/gts9u-audio-bringup.service` + wants-symlink; script `SK/overlay/system/usr/local/sbin/gts9u-audio-bringup` line 2: "gts9u audio bring-up v3." |
| b | PA hard-gate `zz-gts9u-audio.conf`, no-'-' prefix | **PRESENT, hard (no '-')** | `SK/overlay/system/etc/systemd/user/pulseaudio.service.d/zz-gts9u-audio.conf` line 5: `ExecStartPre=/usr/bin/timeout 150 …` (no `-`; comment l.3–4 documents intent) |
| c | virtual-h2w jack daemon + unit | **PRESENT** | `…/usr/local/lib/gts9u-virtual-h2w.py` + `…/etc/systemd/system/gts9u-virtual-h2w.service` + multi-user wants-symlink |
| d | modules.load dedupe in swap-vendor-modules.sh | **PRESENT** | `SK/scripts/swap-vendor-modules.sh` lines 22–29 (`awk '!seen[$0]++'` over `modules.load*`, chown/chmod/SELinux label restored); invoked by `SK/build.sh:28` |
| e | Stage-2 curated finit loader (muic_sm5714/pdic_sm5714/wez01) | **PRESENT** | `gts9u-audio-bringup` lines 38–71: `FINIT_MODULES="muic_sm5714 pdic_sm5714 wez01"`, syscall 273 flags=3, curated-allowlist comment |
| f | Charger-mode bootconfig filter | **PRESENT** | `SK/overlay/system/usr/lib/gts9uwifi/start-android-container` lines 20–27 + bind-mount at l.48; wired via `etc/systemd/system/lxc-android-config.service.d/gts9uwifi.conf` |
| g | Stale `/dev/__properties__` pre-start clean | **PRESENT** | `start-android-container` lines 14–18 (rotate dir, remove property sockets; "family-portable robustness fix") |
| h | Persistent journald tmpfiles.d | **PRESENT** | `SK/overlay/system/etc/tmpfiles.d/gts9uwifi-journal.conf`: `d /var/log/journal 2755 root systemd-journal - -` |
| i | UPower CriticalPowerAction=Ignore | **PRESENT** | `SK/overlay/system/etc/UPower/UPower.conf` lines 1–2 |
| j | Pen udev rule 61-gts9u-pen.rules + libinput quirk | **PRESENT** | `SK/overlay/system/etc/udev/rules.d/61-gts9u-pen.rules` (pen→touchscreen) + `SK/overlay/system/etc/libinput/local-overrides.quirks` (`sec_e-pen` strip BTN_*); plus `usr/lib/udev/rules.d/74-gts9-wacom.rules` calibration |
| k | Touch calibration rule | **PRESENT** | `SK/overlay/system/usr/lib/udev/rules.d/71-gts9uwifi-touch-calibration.rules` (`sec_touchscreen`, matrix `0 1 0 -1 0 1`) |
| l | Touchpad rotation (daemon or DTS invert) | **ABSENT** | No `gts9u-tp-rotate` (or any tp/uinput-clone daemon) anywhere in skeleton; grep of `vendorboot/vendor_dts` for `invert`/`touchpad` = 0 hits; only touchpad-adjacent text is the generic input perm rule. PORT-STATE l.83 says DTS `touchpad,invert <0x01 0x00 0x00>` is "staged" — it is NOT in this skeleton |
| m | Lomiri LimitNOFILE drop-in | **ABSENT** | grep -ri LimitNOFILE over skeleton: only hit is stock Android `init.rc:51 setrlimit nofile` (unrelated). No `lomiri-full-greeter.service.d/*nofile*`; the greeter drop-in present is only `50-gts9uwifi-timeout.conf` |
| n | Desktop-Qt5 apt pin | **ABSENT** | No `etc/apt/` directory, no `preferences*`/`Pin:` match anywhere in overlay |

## Loud expected-but-absent summary

1. **(l) Touchpad rotation — ABSENT.** Folio touchpad will be 90°-rotated on a fresh
   skeleton-built image. The daemon (gts9u-tp-rotate v0.1, per PORT-STATE l.184, family-generic)
   and/or the staged DTS `touchpad,invert` one-bit fix must be added.
2. **(m) Lomiri LimitNOFILE=65536 drop-in — ABSENT.** fd-exhaustion mitigation
   (PORT-STATE l.321) is device-live only; a rebuild/reflash loses it.
3. **(n) `/etc/apt/preferences.d/no-desktop-qt5` pin — ABSENT.** The guard against the
   krita-style desktop-GL Qt5 crash-loop (PORT-STATE l.116–120, 323) is not in the skeleton.
4. PORT-STATE l.457 itself lists "LimitNOFILE drop-in, desktop-Qt5 apt pin" (with the audio-fix
   installer) as known not-yet-captured items — this audit confirms all remain out of the skeleton.

## Secondary findings (not in the expected list)

- **Wrong USB identity strings for Ultra:** `PRODUCT=SM-X710` in
  `overlay/system/etc/default/usb-moded.d/device-specific-config.conf:10` and
  `echo "SM-X710" > …/product` in `overlay/system/usr/libexec/gts9-adb-gadget:45`
  (Ultra is SM-X910). Cosmetic (host-visible USB product name) but shows family copy-through.
- **Residual duplicate in boot-ramdisk `modules.load`:** `qrng_dlkm.ko` appears twice in
  `vendor-ramdisk-overlay/lib/modules/modules.load` (124 lines, 123 unique); 2 dups in
  `modules.load.recovery`. The dedupe fix covers vendor_dlkm at repack and the runtime walk
  dedups in-script, so impact is nil-to-minor, but the ramdisk lists were never deduped.
- **Stray `__pycache__/gts9-waydroid-bindercpython-312.pyc`** under `overlay/system/usr/libexec/`
  ships into the image.
- **Recovery touch firmware is the STM fts1ba90a blob** (`ramdisk-recovery-overlay/vendor/
  firmware_mnt/image/tsp_stm/fts1ba90a_gts9.bin`) while the Ultra touch controller is Goodix
  (per `kernel-additions/halium.config.append:8-10`) — likely inert on Ultra recovery, worth a look.
- **Pulse policy XMLs are family copies**; PORT-README l.9–10 lists regenerating them from X910
  vendor audio configs as open TODO (audio works regardless per context).
- Skeleton has its own audio-relevant Android-side guard: `init.disabled.rc` keeps
  `vendor.audio-hal` enabled for the hidl_compat shim (comment at l.17–18 of that file).
