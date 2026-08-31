#!/bin/bash
# gts9wifi consolidated post-flash script
# ---------------------------------------
# Run as root after EVERY reflash/OTA of the 11" (Azkali image). Restores
# every fix that lives on the rootfs (they all die on reflash) and re-checks
# the userdata-resident ones. Idempotent; each step reports and continues.
#
# Run from a checkout (or self-copied kit) so the sibling installers are
# present:   sudo ./gts9wifi-post-flash.sh
#
# The kit self-copies to /home/phablet/gts9-postflash-kit/ - but keep a copy
# OFF-DEVICE too: the 2026-08-29 flash + userdata wipe took every on-device
# copy at once.

set -u -o pipefail
HERE=$(dirname "$(realpath "$0")")
FIXES=$(realpath "$HERE/..")
KIT=/home/phablet/gts9-postflash-kit

log() { echo; echo "==== $*"; }
[ "$(id -u)" = 0 ] || { echo "run as root (sudo)"; exit 1; }
FAILED=""

log "1/7 audio fix (extevdev/virtual-h2w, version-gated)"
# NOTE: the version-gate refusal on >=14.2.110 exits 0 (it is a success);
# a nonzero exit here is a REAL failure (preflight/apply error).
bash "$FIXES/audio/gts9-audio-fix-install.sh" || { echo "  REAL FAILURE - see output above"; FAILED="$FAILED audio-fix"; }

log "2/7 audio hardening (module walker + latch trap closure)"
bash "$FIXES/audio/gts9wifi-audio-hardening-install.sh" || { echo "  REAL FAILURE - see output above"; FAILED="$FAILED hardening"; }

log "3/7 S-Pen pointer (touchscreen masquerade)"
bash "$FIXES/input-pen/gts9wifi-pen-pointer-install.sh" || { echo "  REAL FAILURE - see output above"; FAILED="$FAILED pen"; }

log "4/7 apt pin (desktop-GL Qt guard) - rootfs"
mount -o remount,rw / 2>/dev/null || echo "  WARN: remount rw failed - the rootfs installs below may fail"
install -m 0644 "$FIXES/hygiene/no-desktop-qt5" /etc/apt/preferences.d/no-desktop-qt5
echo "  installed /etc/apt/preferences.d/no-desktop-qt5"

log "5/7 greeter LimitNOFILE drop-in - userdata"
D=/home/phablet/.config/systemd/user/lomiri-full-greeter.service.d
mkdir -p "$D"
install -m 0644 "$FIXES/hygiene/60-limitnofile-greeter.conf" "$D/60-limitnofile-greeter.conf"
chown -R phablet:phablet /home/phablet/.config/systemd 2>/dev/null || true
echo "  installed $D/60-limitnofile-greeter.conf"

log "6/7 persistent journald - rootfs"
mkdir -p /etc/tmpfiles.d
cat > /etc/tmpfiles.d/gts9wifi-journal.conf <<'EOF'
# persistent journald: early-boot logs must survive crashes (repeatedly
# needed during gts9 family debugging)
d /var/log/journal 2755 root systemd-journal - -
EOF
mkdir -p /var/log/journal
systemd-tmpfiles --create /etc/tmpfiles.d/gts9wifi-journal.conf 2>/dev/null || true
echo "  /var/log/journal persistent"

log "7/7 optional: touchpad rotation daemon (folio users)"
if [ -x "$FIXES/input-touchpad/gts9u-tp-rotate/install.sh" ]; then
  echo "  folio attached? run: sudo $FIXES/input-touchpad/gts9u-tp-rotate/install.sh"
  echo "  (name-generic daemon; validate the landscape label empirically on this panel)"
else
  echo "  tp-rotate installer not found next to this kit - skip"
fi

log "self-copy kit to userdata"
mkdir -p "$KIT"/{audio,input-pen,hygiene,post-flash}
cp -f "$FIXES/audio/gts9-audio-fix-install.sh" "$FIXES/audio/gts9wifi-audio-hardening-install.sh" "$KIT/audio/" 2>/dev/null || true
cp -f "$FIXES/input-pen/gts9wifi-pen-pointer-install.sh" "$KIT/input-pen/" 2>/dev/null || true
cp -f "$FIXES/hygiene/no-desktop-qt5" "$FIXES/hygiene/60-limitnofile-greeter.conf" "$KIT/hygiene/" 2>/dev/null || true
cp -f "$0" "$KIT/post-flash/" 2>/dev/null || true
chown -R phablet:phablet "$KIT" 2>/dev/null || true
echo "  $KIT populated (keep an OFF-DEVICE copy too)"

if [ -n "$FAILED" ]; then
  log "FAILURES:$FAILED - fix these before trusting the device state"
else
  log "all steps succeeded"
fi

log "done - acceptance"
echo "  reboot, then:"
echo "    grep -c ONLINE /proc/snd_debug_proc/sdp_boot_log   # want 1"
echo "    tail -5 /var/log/gts9-audio-hardening.log          # want '+0 inserted' + 'healthy boot'"
echo "    paplay a tone; pen tracks as pointer after login"
echo "    dpkg -l | grep -E 'libqt5(gui|quick)5' # only -gles rows"

[ -z "$FAILED" ] || exit 1
