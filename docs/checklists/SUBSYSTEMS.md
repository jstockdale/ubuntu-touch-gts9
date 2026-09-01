# Subsystems checklist – Tab S9 family

The per-device feature matrix for testing and integration across the
family. The standard matrix below is aligned 1:1 with the UBports
`portStatus` specification (devices.ubuntu-touch.io/about/device-file/):
same categories, same features, canonical ids in the Feature column, so
results transfer directly to a device page later. The "Family extras" and
"Port diagnostics" sections are intentionally beyond that spec – they
cover hardware (S-Pen, folio keyboard/touchpad) and port-health signals
the standard list has no rows for.

Run [`tools/diagnostics/subsystems-check.sh`](../../tools/diagnostics/subsystems-check.sh)
as root on a booted device to auto-fill the machine-checkable rows (it is
read-only and prints a paste block keyed by the ids in the mapping section
below); the rest are manual tests described in each row.

**Status values** (UBports convention):
`+` working · `x` no hardware support · `-` hardware present, not working ·
`+-` partial (issues within a week of use) · `?` untested/unknown

**Evidence policy**: a `+` or `-` cell must be backed by an on-silicon
observation recorded in [PORT-STATE.md](../knowledge/PORT-STATE.md) or by
a dated run of the diagnostics script. Anything expected-but-unverified is
`?`, with the expectation noted in the Test column. `x` cells are hardware
facts and apply family-wide unless noted.

Column sources as of 2026-08-31: gts9wifi and gts9uwifi from the
on-silicon record in PORT-STATE.md (builds: Azkali 24.04-2.x snapshot
2026-07-28 + this repo's fixes; repo Ultra build); gts9pwifi is entirely
`?` (port defined, never executed). Re-run and re-date columns after every
build/flash round.

## Standard matrix (UBports portStatus)

| Category | Feature (id) | gts9wifi | gts9pwifi | gts9uwifi | Test / notes |
|---|---|---|---|---|---|
| Actors | Manual brightness (`manualBrightness`) | + | ? | + | Settings slider changes backlight |
| Actors | Notification LED (`notificationLed`) | x | x | x | no LED hardware |
| Actors | Torchlight (`torchlight`) | ? | ? | ? | quick-settings torch tile (rear flash) |
| Actors | Vibration (`vibration`) | x | x | x | no vibration motor on Tab S9 family |
| Camera | Flashlight (`flashlight`) | ? | ? | ? | camera app flash toggle |
| Camera | Photo (`photo`) | ? | ? | ? | camera app still capture |
| Camera | Video (`video`) | ? | ? | ? | camera app video capture |
| Camera | Switching between cameras (`switchCamera`) | ? | ? | ? | front/rear switch |
| Cellular | Carrier info, signal strength (`carrierInfo`) | x | x | x | WiFi-only models, no modem |
| Cellular | Data connection (`dataConnection`) | x | x | x | WiFi-only models |
| Cellular | Dual SIM functionality (`dualSim`) | x | x | x | WiFi-only models |
| Cellular | Incoming, outgoing calls (`calls`) | x | x | x | WiFi-only models |
| Cellular | LTE calling – VoLTE (`volte`) | x | x | x | WiFi-only models |
| Cellular | MMS in, out (`mms`) | x | x | x | WiFi-only models |
| Cellular | PIN unlock (`pinUnlock`) | x | x | x | WiFi-only models |
| Cellular | SMS in, out (`sms`) | x | x | x | WiFi-only models |
| Call Audio | Change audio routings (`audioRoutings`) | x | x | x | WiFi-only models |
| Call Audio | Voice in calls (`voiceCall`) | x | x | x | WiFi-only models |
| Call Audio | Volume control in calls (`volumeControl`) | x | x | x | WiFi-only models |
| Endurance | 24+ hours battery lifetime (`batteryLifetimeTest`) | ? | ? | ? | needs a deliberate dated 24h observation |
| Endurance | 7+ days stability (`noRebootTest`) | ? | ? | ? | uptime without reboot-worthy failure, dated |
| GPU | Boot into UI (`uiBoot`) | + | ? | + | Lomiri reaches greeter/session |
| GPU | Hardware video playback (`videoAcceleration`) | ? | ? | ? | 1080p+ video without tearing/heat |
| Misc | Waydroid (`waydroid`) | - | ? | ? | reported broken upstream on current builds; not re-tested by us |
| Misc | AppArmor patches (`apparmorPatches`) | ? | ? | ? | expected `+` (halium kernel carries them) – confirm via `misc.apparmor` script row |
| Misc | Battery percentage (`batteryPercentage`) | + | ? | + | honest capacity (Ultra: post finit fuel-gauge fix) |
| Misc | Offline charging (`offlineCharging`) | ? | ? | ? | charge while powered off, charging graphic shows |
| Misc | Online charging (`onlineCharging`) | + | ? | + | Ultra note: first PD negotiation may need one replug |
| Misc | Recovery image (`recoveryImage`) | + | ? | + | TWRP boots, touch works in recovery (used for every flash) |
| Misc | Reset to factory defaults (`factoryReset`) | ? | ? | ? | UT reset flow completes |
| Misc | RTC time (`rtcTime`) | ? | ? | ? | clock survives powered-off interval without network; `misc.rtc` script row is the readability half only |
| Misc | SD card storage (`sdCard`) | ? | ? | ? | family HAS a microSD slot (slot proven at firmware level: pmOS rootfs-on-microSD boots, see PORT-STATE) – UT-side mount/format untested |
| Misc | Shutdown / Reboot (`shutdown`) | + | ? | + | clean shutdown + reboot from UI (observed across sessions) |
| Misc | Wireless charging (`wirelessCharging`) | x | x | x | no hardware |
| Misc | Wireless External monitor (`wirelessExternalMonitor`) | ? | ? | ? | aethercast; expect `-` on Mir 1.x |
| Network | Bluetooth (`bluetooth`) | +- | ? | ? | 11": HAL crash-loop ~62s cycle seen once, cold boot clears; pair + audio test; Ultra never pair-tested |
| Network | Flight mode (`flightMode`) | ? | ? | ? | toggle kills/restores WiFi+BT |
| Network | FM radio (`fmRadio`) | x | x | x | no hardware |
| Network | Hotspot (`hotspot`) | ? | ? | ? | AP mode + client connects (TTL notes in PORT-STATE) |
| Network | NFC (`nfc`) | x | x | x | no hardware |
| Network | WiFi (`wifi`) | + | ? | + | scan, associate, DHCP, traffic |
| Sensors | Automatic brightness (`autoBrightness`) | - | ? | - | needs sensors HAL (ledger #4) |
| Sensors | Fingerprint reader (`fingerprint`) | ? | ? | ? | Ultra: EL721 driver probes, biometryd untested; enroll + unlock test |
| Sensors | GPS (`gps`) | - | ? | ? | GNSS hardware IS present on WiFi models (vendor ships AIDL IGnss); UT expects HIDL – software mismatch, ledger #9 |
| Sensors | Proximity (`proximity`) | x | x | x | no proximity sensor |
| Sensors | Rotation (`rotation`) | - | ? | - | sensors HAL not registering (ledger #4) |
| Sensors | Touchscreen (`touchscreen`) | + | ? | + | multitouch tracks accurately |
| Sensors | Double touch to wake (`dt2w`) | ? | ? | ? | dt2w gesture |
| Sound | Earphones (`earphones`) | ? | ? | ? | USB-C audio out; virtual-h2w only satisfies the jack scan – actual routing untested |
| Sound | Loudspeaker (`loudspeaker`) | + | ? | + | tone from all speakers (Ultra: quad cs35l45) |
| Sound | Microphone (`microphone`) | ? | ? | ? | record + playback |
| Sound | Volume control (`volumeControl`) | + | ? | + | hardware keys + slider move actual output level |
| USB | MTP access (`mtp`) | ? | ? | ? | file transfer from host; `usb.mtp` script row is the daemon half only |
| USB | ADB access (`adb`) | + | ? | + | adb shell over USB-C (used constantly) |
| USB | Wired External monitor (`wiredExternalMonitor`) | ? | ? | - | USB-C DP-alt: dwc3 role-switch open on Ultra (ledger) |

## Family extras (beyond the standard list)

| Feature | gts9wifi | gts9pwifi | gts9uwifi | Test / notes |
|---|---|---|---|---|
| S-Pen: pointer tracking | + | ? | + | pen moves cursor, taps (touchscreen masquerade) |
| S-Pen: pressure/tilt in apps | - | - | - | platform-gated: Mir 1.x has no tablet protocol (ledger #15) |
| S-Pen: hover + button + eraser at evdev | + | ? | + | `evtest` on `sec_e-pen` shows pressure 0–4095, tilt, keys |
| Folio keyboard | + | ? | + | pogo keyboard types |
| Folio touchpad: pointer | + | ? | + | cursor moves |
| Folio touchpad: orientation | ? | ? | + | correct in landscape (Ultra: tp-rotate @270 validated; 11" fixes-kit install untested) |
| Folio touchpad: two-finger scroll | +- | ? | +- | works in terminal, broken in Morph (ledger #16) |
| Folio touchpad: pinch | - | ? | - | Mir/qtmir gesture gap (ledger #16) |
| USB-C host mode (keyboard etc.) | ? | ? | - | external HID on Type-C (Ultra: same dwc3 role-switch issue) |

## Port diagnostics (script-only rows, no portStatus equivalent)

Port-health signals the script checks that don't map to a UBports feature.
A regression here usually precedes a visible feature regression.

| Script id | gts9wifi | gts9pwifi | gts9uwifi | What it proves |
|---|---|---|---|---|
| `sound.card` | + | ? | + | snd card_state=1, single ONLINE (no bounce) – keystone of the audio chain |
| `sound.bringup` | x | ? | + | bringup service completed this boot (11" uses installer fixes instead – `x` by design) |
| `sound.virtual-jack` | + | ? | + | virtual h2w input device present (extevdev abort guard) |
| `sound.pa-sinks` | + | ? | + | PulseAudio actually exposes ≥1 sink for phablet |
| `misc.charging-modules` | + | ? | + | sm5714 fuelgauge module loaded (finit stage) |
| `misc.online-charging` | + | ? | + | charger present ⇒ status Charging/Full |
| `misc.apparmor` | ? | ? | ? | kernel apparmor enabled=Y |
| `misc.root-size` | + | ? | + | rootfs ≥7G (7600M build / post-resize) |
| `sensors.hal` | - | ? | - | sensors service (`sensors-hidl-2-1`) running |
| `extra.spen-evdev` | + | ? | + | `sec_e-pen` registered (wez01 loaded) |

## Automated diagnostic rows – id → matrix mapping

The script's paste block uses these ids. Rows not listed here are
manual-only.

| Script id | Matrix row |
|---|---|
| `gpu.boot-into-ui` | GPU / Boot into UI |
| `actors.manual-brightness` | Actors / Manual brightness |
| `actors.notification-led`, `actors.vibration` | Actors / (hardware facts) |
| `actors.torchlight` | Actors / Torchlight (node presence only – UI test still manual) |
| `network.wifi` | Network / WiFi |
| `network.bluetooth` | Network / Bluetooth (hci presence only – pairing manual) |
| `network.fm-radio`, `network.nfc` | Network / (hardware facts) |
| `misc.battery-percentage` | Misc / Battery percentage |
| `misc.rtc` | Misc / RTC time (readability half only) |
| `misc.sd-card` | Misc / SD card storage (controller presence only – mount manual) |
| `misc.waydroid` | Misc / Waydroid (installed-check only) |
| `misc.wireless-charging` | Misc / Wireless charging |
| `sensors.touchscreen` | Sensors / Touchscreen |
| `sensors.hal` | Sensors / Rotation + Automatic brightness (prerequisite) |
| `sensors.gps` | Sensors / GPS |
| `sensors.proximity` | Sensors / Proximity |
| `sensors.fingerprint` | Sensors / Fingerprint reader (always manual – no reliable node probe) |
| `usb.adb` | USB / ADB access |
| `usb.mtp` | USB / MTP access (daemon half only – host copy manual) |
| `extra.folio-keyboard`, `extra.folio-touchpad` | Family extras / Folio rows |
| everything under "Port diagnostics" | that section directly |

## Workflow

1. After any build/flash round, run `subsystems-check.sh` as root on the
   device and fold its paste block into the device's column using the
   mapping above. Date the column header.
2. Walk the MANUAL list the script prints for the rest.
3. Script caveats: it is read-only and conservative – a script `+` on a
   presence-style row (torch node, hci0, SD controller, MTP daemon) is
   necessary, not sufficient; the matrix cell stays `?` until the manual
   half passes. A script `-` is always worth investigating.
4. A cell that regresses from `+` is a release blocker for that device
   until root-caused (regressions are exactly what this matrix exists to
   catch while integrating across the family).
5. Discrepancies between devices on the same feature are the interesting
   engineering signal – file them in the PORT-STATE ledger.
