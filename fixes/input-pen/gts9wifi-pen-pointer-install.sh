#!/bin/bash
# Copyright (c) 2026 John Stockdale and Off by One, Inc.
# BSD 3-Clause License - see LICENSE at the repository root.
# gts9wifi S-Pen pointer installer (touchscreen masquerade)
# ---------------------------------------------------------
# Puts the 11"'s S-Pen into the WORKING POINTER state on Mir 1.8: the
# sec_e-pen evdev node is retagged as a touchscreen (with the panel's
# calibration matrix) so the pen tracks/taps/draws as a cursor. No
# pressure/tilt - that is a Mir 1.8 compositor ceiling, not a bug here.
#
# This is the promoted installer for the config proven on-device 2026-08-27
# (previously recoverable only from archive/pen-investigation/pen-cleanup.sh).
# It does NOT install a libinput quirk - the INPUT_PROP_DIRECT quirk was a
# proven dead end on this device and pen-cleanup removed it.
#
# Rootfs rule - dies on every reflash/OTA; rerun (the post-flash script
# does). The rule applies on device events: takes effect at next Lomiri
# restart or reboot.
#
# Usage: sudo ./gts9wifi-pen-pointer-install.sh [--uninstall]

set -u -o pipefail

RULE=/etc/udev/rules.d/72-gts9wifi-spen.rules
SELF_HOME=/home/phablet/gts9wifi-pen

log() { echo "[gts9wifi-pen] $*"; }
die() { echo "[gts9wifi-pen] FATAL: $*" >&2; exit 1; }

UNINSTALL=0
for a in "$@"; do
  case "$a" in
    --uninstall) UNINSTALL=1 ;;
    *) echo "usage: $0 [--uninstall]"; exit 2 ;;
  esac
done

[ "$(id -u)" = 0 ] || die "must run as root (sudo)"

if [ "$UNINSTALL" = 1 ]; then
  rm -f "$RULE"
  udevadm control --reload-rules 2>/dev/null || true
  udevadm trigger --subsystem-match=input 2>/dev/null || true
  log "uninstalled (pen reverts to kernel-default tablet tagging - inert under Mir 1.8)."
  exit 0
fi

if ! touch /etc/udev/rules.d/.wtest 2>/dev/null; then
  log "rootfs read-only - remounting rw"
  mount -o remount,rw / || die "remount rw failed"
fi
rm -f /etc/udev/rules.d/.wtest

# Copy the panel touchscreen's calibration matrix so the pen lands where it
# points; fall back to the family policy matrix (portrait-native panel, 90
# degrees) if the touchscreen node cannot be found.
CAL=""
for dev in /dev/input/event*; do
  props=$(udevadm info --query=all --name="$dev" 2>/dev/null)
  case "$props" in
    *ID_INPUT_TOUCHSCREEN=1*)
      m=$(printf '%s\n' "$props" | sed -n 's/^E: LIBINPUT_CALIBRATION_MATRIX=//p')
      [ -n "$m" ] && { CAL="$m"; break; }
      ;;
  esac
done
[ -n "$CAL" ] || CAL="0 1 0 -1 0 1"
log "using calibration matrix: $CAL"

cat > "$RULE" <<EOF
# Samsung S-Pen (sec_e-pen) - working POINTER config (Mir 1.8).
# Presents as touchscreen so the pen tracks/taps/draws as a cursor.
# No pressure (Mir 1.8 has no tablet protocol). Revisit when Mir 2.x lands.
ACTION=="remove", GOTO="spen_end"
KERNEL!="event*", GOTO="spen_end"
ATTRS{name}=="sec_e-pen", ENV{ID_INPUT_TOUCHSCREEN}="1", ENV{ID_INPUT_TABLET}="0", ENV{LIBINPUT_CALIBRATION_MATRIX}="$CAL"
LABEL="spen_end"
EOF

udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=input 2>/dev/null || true

mkdir -p "$SELF_HOME"
cp -f "$0" "$SELF_HOME/gts9wifi-pen-pointer-install.sh" 2>/dev/null || true
chown -R phablet:phablet "$SELF_HOME" 2>/dev/null || true

log "installed $RULE"
log "takes effect on next Lomiri restart or reboot; verify with:"
log "  udevadm info --query=all --name=\$(grep -l sec_e-pen /sys/class/input/event*/device/name 2>/dev/null | head -1 | sed 's|/sys/class/input/\\(event[0-9]*\\).*|/dev/input/\\1|') | grep ID_INPUT"
