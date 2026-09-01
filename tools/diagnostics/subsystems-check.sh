#!/bin/bash
# Copyright (c) 2026 John Stockdale and Off by One, Inc.
# BSD 3-Clause License - see LICENSE at the repository root.
# subsystems-check.sh - READ-ONLY on-device subsystem sweep for the Tab S9
# family, aligned with docs/checklists/SUBSYSTEMS.md (UBports portStatus
# convention). Auto-fills the machine-checkable rows; prints the manual
# list for the rest. Never modifies device state.
#
# Run as root on a booted Ubuntu Touch device:  sudo ./subsystems-check.sh
# Output: one "ID | status | evidence" line per automatable row, then a
# paste-ready summary block for the checklist column. IDs map to matrix
# rows per the "Automated diagnostic rows" section of SUBSYSTEMS.md.

set -u
PASS=0; FAIL=0; MANUAL=0
# RESULTS can never be empty by the time it is expanded (device-identity
# rows always emit), and bash >= 4.4 tolerates empty-array expansion under
# set -u regardless.
declare -a RESULTS

res() { # id status evidence  (evidence must be single-line)
    local ev="${3//$'\n'/ }"
    RESULTS+=("$1|$2|$ev")
    case "$2" in
        +|x) PASS=$((PASS+1)) ;;
        -|+-) FAIL=$((FAIL+1)) ;;
        *) MANUAL=$((MANUAL+1)) ;;
    esac
    printf '%-28s %-3s %s\n' "$1" "$2" "$ev"
}

have() { command -v "$1" >/dev/null 2>&1; }
inputs() { cat /proc/bus/input/devices 2>/dev/null; }

# ---- device identity ---------------------------------------------------------
CODENAME="$(getprop ro.product.device 2>/dev/null)"
[ -n "$CODENAME" ] || CODENAME="$(ls /etc/deviceinfo/devices/ 2>/dev/null | grep -oE 'gts9[pu]?wifi' | head -1)"
case "$CODENAME" in
    gts9wifi*)  P=gts9  ;;
    gts9pwifi*) P=gts9p ;;
    gts9uwifi*) P=gts9u ;;
    *) P=""; echo "WARN: unknown codename '$CODENAME' - family-prefixed checks degraded" ;;
esac
echo "device: ${CODENAME:-unknown} ($(date '+%F %T'))"
echo "build:  $(grep -m1 version /etc/system-image/channel.ini 2>/dev/null || echo 'n/a') | kernel $(uname -r)"
echo "-------------------------------------------------------------------"

# ---- GPU / UI ---------------------------------------------------------------
pgrep -f lomiri >/dev/null 2>&1 \
    && res "gpu.boot-into-ui" "+" "lomiri process running" \
    || res "gpu.boot-into-ui" "-" "no lomiri process"

# ---- Actors -----------------------------------------------------------------
BL=/sys/class/backlight/panel0-backlight
if [ -r "$BL/brightness" ]; then
    res "actors.manual-brightness" "+" "backlight readable ($(cat $BL/brightness 2>/dev/null)/$(cat $BL/max_brightness 2>/dev/null))"
else
    res "actors.manual-brightness" "-" "no $BL"
fi
res "actors.notification-led" "x" "no LED hardware (family)"
res "actors.vibration" "x" "no vibration motor (family)"
[ -e /sys/class/leds/torch-sec1/brightness ] \
    && res "actors.torchlight" "?" "torch node present - test via UI tile" \
    || res "actors.torchlight" "-" "torch sysfs node absent"

# ---- Network ----------------------------------------------------------------
if grep -qE 'qca_cld3_(kiwi_v2|qca6490)' /proc/modules 2>/dev/null; then
    if ip link show 2>/dev/null | grep -q 'wlan0'; then
        STATE=$(nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep '^wlan0' | cut -d: -f2)
        res "network.wifi" "+" "wlan module + wlan0 (${STATE:-state n/a})"
    else
        res "network.wifi" "-" "wlan module loaded but no wlan0"
    fi
else
    res "network.wifi" "-" "no wlan module loaded"
fi
if [ -d /sys/class/bluetooth/hci0 ]; then
    res "network.bluetooth" "?" "hci0 present - pairing/audio test manual (watch ~62s HAL crash-loop pattern)"
else
    res "network.bluetooth" "-" "no hci0"
fi
res "network.fm-radio" "x" "no hardware (family)"
res "network.nfc" "x" "no hardware (family)"

# ---- Sound ------------------------------------------------------------------
CS=/sys/kernel/snd_card/card_state
if [ -r "$CS" ]; then
    V=$(cat "$CS" 2>/dev/null)
    ON=$(grep -c ONLINE /proc/snd_debug_proc/sdp_boot_log 2>/dev/null || true)
    [ -n "$ON" ] || ON="?"
    if [ "$V" = "1" ] && [ "$ON" = "1" ]; then
        res "sound.card" "+" "card_state=1, ONLINE x1 (stable)"
    elif [ "$V" = "1" ]; then
        res "sound.card" "+-" "card_state=1 but ONLINE count=$ON (bounced?)"
    else
        res "sound.card" "-" "card_state=$V"
    fi
else
    res "sound.card" "-" "no $CS (machine_dlkm not loaded?)"
fi
if [ "$P" = "gts9" ]; then
    res "sound.bringup" "x" "11\" uses installer fixes; no bringup service by design"
elif [ -n "$P" ] && [ -f "/var/log/${P}-audio-bringup.log" ]; then
    tail -3 "/var/log/${P}-audio-bringup.log" | grep -q "bring-up complete" \
        && res "sound.bringup" "+" "bringup completed this boot" \
        || res "sound.bringup" "+-" "bringup log present, no completion line in tail"
else
    res "sound.bringup" "-" "no /var/log/${P:-<codename>}-audio-bringup.log (skeleton build expected to have it)"
fi
grep -qi "virtual-h2w" /proc/bus/input/devices 2>/dev/null \
    && res "sound.virtual-jack" "+" "virtual h2w device registered" \
    || res "sound.virtual-jack" "-" "no virtual jack (extevdev abort risk on <14.2.110)"
# PulseAudio sinks, read-only, as phablet (root's own pactl can't reach PA)
if have pactl && [ -d /run/user/32011 ]; then
    SINKS=$(sudo -u phablet env XDG_RUNTIME_DIR=/run/user/32011 pactl list short sinks 2>/dev/null | wc -l)
    [ "${SINKS:-0}" -ge 1 ] 2>/dev/null \
        && res "sound.pa-sinks" "+" "$SINKS PulseAudio sink(s)" \
        || res "sound.pa-sinks" "-" "PA reachable but zero sinks (HAL/droid-card down?)"
else
    res "sound.pa-sinks" "?" "pactl or phablet runtime dir unavailable from this context"
fi

# ---- Battery / charging -----------------------------------------------------
CAP=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)
ST=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
case "$CAP" in
    ''|*[!0-9]*) res "misc.battery-percentage" "-" "capacity='$CAP' (fuel gauge dead? check sm5714 finit)" ;;
    *) if [ "$CAP" -ge 1 ] && [ "$CAP" -le 100 ]; then
           res "misc.battery-percentage" "+" "capacity=$CAP% status=${ST:-?}"
       else
           res "misc.battery-percentage" "-" "capacity=$CAP out of range"
       fi ;;
esac
grep -q sm5714_fuelgauge /proc/modules 2>/dev/null \
    && res "misc.charging-modules" "+" "sm5714 fuelgauge loaded" \
    || res "misc.charging-modules" "-" "sm5714_fuelgauge not loaded"
USB_ON=$(cat /sys/class/power_supply/usb/online 2>/dev/null)
AC_ON=$(cat /sys/class/power_supply/ac/online 2>/dev/null)
if [ "${USB_ON:-0}" = "1" ] || [ "${AC_ON:-0}" = "1" ]; then
    [ "$ST" = "Charging" ] || [ "$ST" = "Full" ] \
        && res "misc.online-charging" "+" "power present, status=$ST" \
        || res "misc.online-charging" "+-" "power present but status=$ST (PD replug quirk?)"
else
    res "misc.online-charging" "?" "no charger connected - plug in and re-run"
fi

# ---- AppArmor ---------------------------------------------------------------
AA=$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)
[ "$AA" = "Y" ] \
    && res "misc.apparmor" "+" "apparmor enabled in kernel" \
    || res "misc.apparmor" "-" "apparmor parameter '$AA'"

# ---- Sensors ----------------------------------------------------------------
inputs | grep -q sec_touchscreen \
    && res "sensors.touchscreen" "+" "sec_touchscreen registered" \
    || res "sensors.touchscreen" "-" "no sec_touchscreen input device"
# the skeleton rc names the live service sensors-hidl-2-1 (gts9-sensors-hidl.rc)
SVC=$(getprop init.svc.sensors-hidl-2-1 2>/dev/null)
[ -n "$SVC" ] || SVC=$(getprop init.svc.vendor.sensors 2>/dev/null)
IIO=$(ls -d /sys/bus/iio/devices/iio:device* 2>/dev/null | wc -l)
if [ "${SVC:-}" = "running" ] || pgrep -f 'multihal' >/dev/null 2>&1; then
    res "sensors.hal" "+" "sensors service running (iio=$IIO) - rotation test manual"
else
    res "sensors.hal" "-" "sensors HAL not running (svc='${SVC:-unset}', iio=$IIO) - rotation/autobrightness dead (ledger #4)"
fi
res "sensors.gps" "?" "vendor GNSS service state untested on this image (11\": AIDL/HIDL mismatch, ledger #9)"
res "sensors.proximity" "x" "no proximity sensor (family)"
res "sensors.fingerprint" "?" "biometryd untested; no reliable node probe - manual enroll test"

# ---- Family extras ----------------------------------------------------------
inputs | grep -q "sec_e-pen" \
    && res "extra.spen-evdev" "+" "sec_e-pen registered (pressure via evtest is manual)" \
    || res "extra.spen-evdev" "-" "no sec_e-pen (wez01 loaded? check finit stage)"
inputs | grep -qiE "keyboard.*pogo|pogo.*keyboard|Book Cover" \
    && res "extra.folio-keyboard" "+" "pogo keyboard registered" \
    || res "extra.folio-keyboard" "?" "no pogo keyboard (folio attached?)"
if inputs | grep -q sec_touchpad_pogo; then
    # the fixes tarball installs gts9u-* names on ANY device; skeleton builds
    # use the ${P}-prefixed name - accept either
    if { [ -n "$P" ] && systemctl is-active --quiet "${P}-tp-rotate" 2>/dev/null; } \
       || systemctl is-active --quiet gts9u-tp-rotate 2>/dev/null; then
        res "extra.folio-touchpad" "+" "pad + rotation daemon active (orientation check manual)"
    else
        res "extra.folio-touchpad" "+-" "pad present, rotation daemon not active"
    fi
else
    res "extra.folio-touchpad" "?" "no sec_touchpad_pogo (folio attached?)"
fi

# ---- USB / Misc -------------------------------------------------------------
pgrep -x adbd >/dev/null 2>&1 && res "usb.adb" "+" "adbd running" || res "usb.adb" "-" "adbd not running"
pgrep -f 'umtprd|mtp-server' >/dev/null 2>&1 \
    && res "usb.mtp" "+" "MTP daemon running" \
    || res "usb.mtp" "-" "no MTP daemon (umtprd/mtp-server)"
hwclock -r >/dev/null 2>&1 && res "misc.rtc" "+" "hwclock readable" || res "misc.rtc" "?" "hwclock unreadable from this context"
have waydroid && res "misc.waydroid" "?" "installed - functional test manual (known broken on current builds)" \
             || res "misc.waydroid" "?" "not installed"
ROOTSZ=$(df -BG --output=size / 2>/dev/null | tail -1 | tr -dc 0-9)
case "$ROOTSZ" in
    ''|*[!0-9]*) res "misc.root-size" "?" "could not read root size" ;;
    *) [ "$ROOTSZ" -ge 7 ] \
        && res "misc.root-size" "+" "root ${ROOTSZ}G (post-resize/7600M build)" \
        || res "misc.root-size" "+-" "root ${ROOTSZ}G (pre-resize build?)" ;;
esac
if [ -e /dev/mmcblk1 ] || ls /sys/class/mmc_host 2>/dev/null | grep -q .; then
    res "misc.sd-card" "?" "SD controller present - mount/format test manual"
else
    res "misc.sd-card" "?" "no card inserted or controller not visible from here"
fi
res "misc.wireless-charging" "x" "no hardware (family)"

# ---- summary ----------------------------------------------------------------
echo "-------------------------------------------------------------------"
echo "auto: $PASS ok/na, $FAIL attention, $MANUAL unknown"
echo
echo "MANUAL tests remaining (see docs/checklists/SUBSYSTEMS.md):"
cat <<'EOF'
  camera (photo/video/flash/switch), torch via UI, mic record, earphones
  (USB-C audio), volume keys, loudspeaker tone all speakers, hotspot,
  flight mode, dt2w, rotation + auto-brightness (once sensors HAL runs),
  offline charging, factory reset, shutdown/reboot cycle, recovery image
  boots, hardware video playback, MTP file copy from host, wired/wireless
  external monitor, S-Pen pointer tracking in UI, S-Pen pressure at evdev
  (evtest), touchpad orientation in landscape, touchpad scroll in terminal
  vs Morph, pinch, USB-C host mode, fingerprint enroll, SD card mount,
  GPS fix attempt, endurance (24h battery / 7d stability)
EOF
echo
echo "---- paste block for SUBSYSTEMS.md ($CODENAME, $(date '+%F')) ----"
for r in "${RESULTS[@]}"; do echo "$r"; done
