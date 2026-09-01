#!/bin/bash
# Copyright (c) 2026 John Stockdale and Off by One, Inc.
# BSD 3-Clause License - see LICENSE at the repository root.
# gts9wifi audio hardening installer (bugs 1/2/5 prevention for the 11")
# -----------------------------------------------------------------------
# The 11" runs Azkali's image and has only ever HIT audio bug #4 (extevdev
# jackless abort - fixed by gts9-audio-fix-install.sh). But it measurably
# carries the bug-#1 amplifier (modules.load duplicated 4x: 457 lines / 357
# unique, measured on-device 2026-08-10) and has NO latch protection: one
# lost va-macro boot race -> AGM card-wait timeout -> persistent
# vendor.audio.use.primary.default=true -> audio dead on every later boot
# with no installed recovery. This installs the preventive subset of the
# Ultra's proven bring-up chain, adapted per the 11"'s fail-open philosophy:
#
#   1) module walker: dedupe-walk /android/vendor_dlkm modules.load and
#      insmod every hole (bug #1 belt; the Ultra's exact logic).
#   2) chmod 0666 card_state + aud_dev/state (bug #5b; also covers the
#      parked uid-1013 EACCES oddity observed on this device).
#   3) unconditionally clear the Samsung fallback latch (bug #2).
#   4) restart vendor.audio-hal ONLY if the latch had actually been set or
#      the HAL is not running (bug #5a) - a healthy boot is left alone.
#
# Differences from the Ultra bringup - deliberate, do not "fix":
#   - fail-open: every step is warn-only and the service always exits 0.
#     There is NO PulseAudio gate here; PA startup is untouched (Azkali's
#     own 50-gts9wifi-wait-audiohal.conf remains in place, unmodified).
#   - no finit stage: muic/pdic/wez01 load cleanly on this device's image.
#   - latch clear retries only briefly (15s vs the Ultra's 60s FATAL loop):
#     by this point up to 210s of waits have passed so the property service
#     is up in practice, and a failed clear is a WARN, never a wedge.
#
# Idempotent. Rootfs pieces die on reflash - rerun after every OTA/reflash
# (fixes/post-flash/gts9wifi-post-flash.sh does this for you).
#
# Usage: sudo ./gts9wifi-audio-hardening-install.sh [--uninstall]

set -u -o pipefail

SCRIPT=/usr/local/sbin/gts9-audio-hardening
UNIT=/etc/systemd/system/gts9-audio-hardening.service
SELF_HOME=/home/phablet/gts9-audio-hardening

log() { echo "[gts9wifi-hardening] $*"; }
die() { echo "[gts9wifi-hardening] FATAL: $*" >&2; exit 1; }

UNINSTALL=0
for a in "$@"; do
  case "$a" in
    --uninstall) UNINSTALL=1 ;;
    *) echo "usage: $0 [--uninstall]"; exit 2 ;;
  esac
done

[ "$(id -u)" = 0 ] || die "must run as root (sudo)"

if [ "$UNINSTALL" = 1 ]; then
  touch /usr/local/sbin/.wtest 2>/dev/null || mount -o remount,rw / || true
  rm -f /usr/local/sbin/.wtest
  systemctl disable --now gts9-audio-hardening.service 2>/dev/null || true
  rm -f "$SCRIPT" "$UNIT"
  systemctl daemon-reload
  log "uninstalled."
  exit 0
fi

# --- preflight ---------------------------------------------------------------
err=()
command -v systemctl >/dev/null || err+=("no systemctl")
command -v getprop >/dev/null   || err+=("no getprop (not a halium image?)")
command -v setprop >/dev/null   || err+=("no setprop")
[ -d /home/phablet ]            || err+=("/home/phablet missing - userdata not mounted?")
if [ ${#err[@]} -gt 0 ]; then printf '%s\n' "${err[@]}" >&2; die "preflight failed"; fi

if ! touch /usr/local/sbin/.wtest 2>/dev/null; then
  log "rootfs read-only - remounting rw"
  mount -o remount,rw / || die "remount rw failed"
fi
rm -f /usr/local/sbin/.wtest

# --- the boot-time hardening script ------------------------------------------
cat > "$SCRIPT" <<'HARDEOF'
#!/bin/sh
# gts9-audio-hardening v1 - preventive subset of the gts9u bring-up chain
# for the 11" (fail-open: always exits 0; see the installer header).
LOGF=/var/log/gts9-audio-hardening.log
log(){ echo "gts9-audio-hardening: $*" > /dev/kmsg 2>/dev/null
       echo "$(date '+%F %T') $*" >> "$LOGF" 2>/dev/null; echo "$*"; }
MDIR=/android/vendor_dlkm/lib/modules
CS=/sys/kernel/snd_card/card_state
echo "---- boot $(date '+%F %T') ----" >> "$LOGF" 2>/dev/null

# 1) module walker (bug #1 belt) - the Ultra's proven logic, warn-only
c=0; while [ ! -f "$MDIR/modules.load" ] && [ $c -lt 120 ]; do sleep 1; c=$((c+1)); done
if [ -f "$MDIR/modules.load" ]; then
    BL=$(sed -n 's/^blocklist[[:space:]]*//p' "$MDIR/modules.blocklist" 2>/dev/null | sed 's/\.ko$//' | tr - _)
    loaded=0; present=0; failed=""
    for m in $(awk '!seen[$0]++' "$MDIR/modules.load"); do
        b=${m##*/}; n=${b%.ko}; p=$(echo "$n" | tr - _)
        echo "$BL" | grep -qx "$p" && continue
        grep -q "^$p " /proc/modules && { present=$((present+1)); continue; }
        if insmod "$MDIR/$b" 2>/dev/null; then
            loaded=$((loaded+1))
        else
            grep -q "^$p " /proc/modules && present=$((present+1)) || failed="$failed $n"
        fi
    done
    log "modules: +$loaded inserted, $present already live, failed:${failed:- none}"
else
    log "WARN: $MDIR/modules.load never appeared - walker skipped"
fi

# 2) card wait (bounded, warn-only - fail-open on this device)
c=0; while [ "$(cat $CS 2>/dev/null)" != "1" ] && [ $c -lt 90 ]; do sleep 1; c=$((c+1)); done
if [ "$(cat $CS 2>/dev/null)" = "1" ]; then
    log "card ONLINE after ${c}s"
else
    log "WARN: card not ONLINE after 90s - continuing (latch will still be cleared)"
fi

chmod 0666 "$CS" /sys/kernel/aud_dev/state 2>/dev/null

# 3) latch clear (bug #2) - unconditional; remember whether it was armed
WAS="$(getprop vendor.audio.use.primary.default 2>/dev/null)"
c=0
until setprop vendor.audio.use.primary.default false 2>/dev/null && \
      [ "$(getprop vendor.audio.use.primary.default)" = "false" ]; do
    [ $c -ge 15 ] && break
    sleep 1; c=$((c+1))
done
[ "$(getprop vendor.audio.use.primary.default)" = "false" ] \
    && log "latch clear ok (was: '${WAS:-unset}')" \
    || log "WARN: latch clear did not stick after 15s"

# 4) conditional HAL restart (bug #5a) - only when there is staleness evidence
SVC="$(getprop init.svc.vendor.audio-hal 2>/dev/null)"
if [ "$WAS" = "true" ] || [ "$SVC" != "running" ]; then
    log "restarting vendor.audio-hal (latch was '${WAS:-unset}', svc '$SVC')"
    setprop ctl.restart vendor.audio-hal 2>/dev/null
    c=0; until [ "$(getprop init.svc.vendor.audio-hal)" = "running" ] || [ $c -ge 30 ]; do
        sleep 1; c=$((c+1))
    done
    [ "$(getprop init.svc.vendor.audio-hal)" = "running" ] \
        && log "audio-hal running" || log "WARN: audio-hal did not return in 30s"
else
    log "healthy boot (latch unset, HAL running) - no restart"
fi
exit 0
HARDEOF
chmod 0755 "$SCRIPT"

cat > "$UNIT" <<'UNITEOF'
[Unit]
Description=gts9wifi audio hardening (module walker + latch clear, fail-open)
After=lxc-android-config.service
Wants=lxc-android-config.service

[Service]
Type=oneshot
TimeoutStartSec=360
ExecStart=/usr/local/sbin/gts9-audio-hardening
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable gts9-audio-hardening.service >/dev/null || die "enable failed"

# --- self-copy to userdata (survives rootfs replacement) ---------------------
mkdir -p "$SELF_HOME"
cp -f "$0" "$SELF_HOME/gts9wifi-audio-hardening-install.sh" 2>/dev/null || true
chown -R phablet:phablet "$SELF_HOME" 2>/dev/null || true

log "installed + enabled. Runs at next boot; start now with:"
log "  sudo systemctl start gts9-audio-hardening.service"
log "log: /var/log/gts9-audio-hardening.log (expect '+0 inserted' on healthy boots)"
