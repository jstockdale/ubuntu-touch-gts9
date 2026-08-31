#!/bin/bash
# gts9uwifi post-flash script
# ---------------------------
# As of the 2026-08-30 parity remediation the Ultra skeleton bakes the whole
# fix set (audio chain, WiFi persistence, tp-rotate @270, pen reclass, apt
# pin, LimitNOFILE, journald, UPower, 7600M root with group-at-capacity), so
# a repo-built flash needs NO reinstallation. What remains:
#
#   sweep    - one-time cleanup of pre-skeleton debris on the CURRENT install
#              (run once after flashing a >= Tier-1 build over the old state)
#   check    - read-only acceptance checks after any flash
#
# Usage: sudo ./gts9uwifi-post-flash.sh sweep|check

set -u -o pipefail
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }
MODE="${1:-check}"

case "$MODE" in
sweep)
  echo "==== one-time debris sweep (pre-skeleton on-device fixes, now baked)"
  # Interlock: only sweep on an image that actually BAKES the replacements -
  # on a pre-Tier-1 image this would delete WiFi persistence and the
  # aud_pasthru group fix with nothing behind them.
  grep -q cfg80211 /etc/modules-load.d/gts9uwifi.conf 2>/dev/null || {
    echo "REFUSING: this image does not bake WiFi persistence (pre-Tier-1"
    echo "build?). Flash a repo-built image first, then sweep."; exit 1; }
  grep -q 'aud_pasthru_adsp.*GROUP="audio"' /usr/lib/udev/rules.d/70-gts9uwifi.rules 2>/dev/null || {
    echo "REFUSING: 70-gts9uwifi.rules lacks the GROUP=audio fix (pre-Tier-1"
    echo "build?). Flash a repo-built image first, then sweep."; exit 1; }
  mount -o remount,rw / 2>/dev/null
  for f in \
    /etc/systemd/logind.conf.d/90-gts9u.conf \
    /etc/modules-load.d/gts9u-fuelgauge.conf \
    /etc/modules-load.d/gts9u-wifi.conf \
    /etc/udev/rules.d/62-gts9u-touchpad.rules \
    /etc/udev/rules.d/71-gts9u-audiofix.rules \
    /etc/systemd/system/gts9u-audio-fix.service \
    /etc/systemd/system/gts9u-audio-macros.service \
    /etc/systemd/user/pulseaudio.service.d/50-gts9uwifi-wait-audiohal.conf ; do
    [ -e "$f" ] && { rm -f "$f"; echo "  removed $f"; }
  done
  for u in upower repowerd; do
    if [ -L "/etc/systemd/system/$u.service" ] && [ "$(readlink /etc/systemd/system/$u.service)" = "/dev/null" ]; then
      rm -f "/etc/systemd/system/$u.service"; echo "  removed $u null-mask (UPower.conf seatbelt is baked)"
    fi
  done
  systemctl daemon-reload
  udevadm control --reload-rules 2>/dev/null || true
  echo "  KEEP: /var/log/journal, /userdata/lp-metadata*.bak (rename per infra notes)"
  echo "  sweep done - reboot before the check pass"
  ;;
check)
  echo "==== acceptance checks (read-only)"
  echo "-- audio: ONLINE count (want 1):"
  grep -c ONLINE /proc/snd_debug_proc/sdp_boot_log 2>/dev/null || echo "  (proc node absent?)"
  echo "-- bringup log tail:"
  tail -6 /var/log/gts9u-audio-bringup.log 2>/dev/null || echo "  (no log yet)"
  echo "-- expect: 'modules: +0 inserted' (deduped image), finit muic/pdic/wez01 ok/live"
  echo "-- WiFi persisted:"
  grep -E 'cfg80211|kiwi' /etc/modules-load.d/gts9uwifi.conf 2>/dev/null || echo "  MISSING - old image?"
  echo "-- touchpad default (want 270):"
  grep TP_DEFAULT /etc/default/gts9u-tp-rotate 2>/dev/null || echo "  (absent)"
  echo "-- root size (want ~7.6G+ after a Tier-2 build, not 4.4G):"
  df -h / | tail -1
  echo "-- vendor_dlkm source (watch item: userdata override vs super LP):"
  findmnt /android/vendor_dlkm 2>/dev/null || echo "  (not split-mounted)"
  echo "-- pasthru node group (want audio):"
  ls -l /dev/aud_pasthru_adsp 2>/dev/null || echo "  (node absent this boot)"
  ;;
*)
  echo "usage: $0 sweep|check"; exit 2 ;;
esac
