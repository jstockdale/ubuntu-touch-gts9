#!/bin/bash
# Copyright (c) 2026 John Stockdale and Off by One, Inc.
# BSD 3-Clause License - see LICENSE at the repository root.
# gts9-audio-fix installer
# ------------------------
# Workaround for the droid-extevdev "jackless abort" in
# pulseaudio-modules-droid 14.2.107 – 14.2.109 on jackless Samsung
# Galaxy Tab S9 family devices running Ubuntu Touch 24.04.
#
# Mechanism: publishes a persistent uinput switch device
# ("gts9-virtual-h2w", EV_SW: SW_HEADPHONE_INSERT + SW_MICROPHONE_INSERT,
# state never toggled) so droid-extevdev finds a jack to watch instead of
# aborting, plus a bounded 30 s ExecStartPre gate on the PulseAudio user
# unit so PA cannot race the device's creation. Fail-open on both ends.
#
# Upstream fix: 14.2.110 (commit dfda983). This installer detects a fixed
# package and refuses to install (see --force).
#
# Idempotent. Rerun after every OTA/reflash: the rootfs pieces
# (/usr/local/bin daemon + /etc/systemd/system unit) do not survive them;
# the gate drop-in and this installer's self-copy live on userdata.
#
# Usage: sudo ./gts9-audio-fix-install.sh [--force|--uninstall]

set -u -o pipefail

FIX_HOME=/home/phablet/gts9-audio-fix
DAEMON=/usr/local/bin/gts9-virtual-h2w
UNIT=/etc/systemd/system/gts9-virtual-h2w.service
GATE_DIR=/home/phablet/.config/systemd/user/pulseaudio.service.d
GATE="$GATE_DIR/50-gts9-h2w-gate.conf"
FIXED_IN=14.2.110

FORCE=0
UNINSTALL=0
for a in "$@"; do
  case "$a" in
    --force)     FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    *) echo "usage: $0 [--force|--uninstall]"; exit 2 ;;
  esac
done

log() { printf '[gts9-audio-fix] %s\n' "$*"; }

# --- run as root (re-exec via sudo if needed) --------------------------------
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -- "$0" "$@"
  fi
  echo "[gts9-audio-fix] must run as root and sudo is missing" >&2
  exit 1
fi

phablet_userctl() {
  # best-effort systemctl --user as phablet; returns nonzero if unreachable
  local puid
  puid=$(id -u phablet 2>/dev/null) || return 1
  runuser -u phablet -- env "XDG_RUNTIME_DIR=/run/user/$puid" \
    systemctl --user "$@" 2>/dev/null
}

# --- uninstall ---------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
  log "uninstalling workaround (keeping $FIX_HOME)"
  # rootfs is ro by default on UT - the rootfs removals below need rw
  touch /usr/local/bin/.wtest 2>/dev/null || mount -o remount,rw / || true
  rm -f /usr/local/bin/.wtest
  systemctl disable --now gts9-virtual-h2w.service 2>/dev/null || true
  rm -f "$UNIT" "$DAEMON"
  systemctl daemon-reload
  rm -f "$GATE"
  rmdir "$GATE_DIR" 2>/dev/null || true
  phablet_userctl daemon-reload \
    && log "user manager reloaded" \
    || log "user manager unreachable - gate removal applies after next boot"
  log "done"
  exit 0
fi

# --- preflight: validate EVERYTHING before touching ANYTHING -----------------
err=()

command -v python3 >/dev/null 2>&1 \
  || err+=("python3 missing - sudo apt install python3")

python3 -c 'import evdev' 2>/dev/null \
  || err+=("python3-evdev missing - sudo apt install python3-evdev")

if [ ! -e /dev/uinput ]; then
  modprobe uinput 2>/dev/null || true
fi
[ -e /dev/uinput ] \
  || err+=("/dev/uinput absent and 'modprobe uinput' failed - kernel lacks CONFIG_UINPUT?")

id phablet >/dev/null 2>&1 \
  || err+=("user 'phablet' missing - is this an Ubuntu Touch system?")

[ -d /home/phablet ] \
  || err+=("/home/phablet missing - userdata not mounted?")

for d in /usr/local/bin /etc/systemd/system; do
  t="$d/.gts9-audio-fix.wtest.$$"
  if touch "$t" 2>/dev/null; then
    rm -f "$t"
  else
    err+=("$d not writable - remount rootfs rw: sudo mount -o remount,rw /")
  fi
done

# Which droid-card module does this image load, and is its package affected?
card=$(grep -rho 'module-droid-card-[0-9]\+' /etc/pulse/touch.pa 2>/dev/null | head -1)
if [ -n "${card:-}" ]; then
  PKG="pulseaudio-modules-droid-${card##*-}"
else
  PKG="pulseaudio-modules-droid-30"
  log "warning: could not read droid-card module from /etc/pulse/touch.pa, assuming $PKG"
fi
VER=$(dpkg-query -W -f '${Version}' "$PKG" 2>/dev/null || true)
[ -n "$VER" ] \
  || err+=("$PKG not installed - not a droid-audio image? (touch.pa ref: ${card:-none})")

if [ ${#err[@]} -gt 0 ]; then
  log "preflight failed - NOTHING was changed:"
  for e in "${err[@]}"; do printf '  - %s\n' "$e"; done
  exit 1
fi

if dpkg --compare-versions "$VER" ge "$FIXED_IN" && [ "$FORCE" -eq 0 ]; then
  log "$PKG $VER already carries the upstream fix (>= $FIXED_IN, dfda983)."
  log "Workaround unnecessary - not installing. Use --force to override."
  exit 0
fi
log "$PKG $VER is in the affected window (< $FIXED_IN) - installing workaround."

APPLY_ERRS=0

# --- daemon ------------------------------------------------------------------
cat > "$DAEMON" <<'PYEOF'
#!/usr/bin/env python3
"""gts9-virtual-h2w - persistent virtual headset-jack switch.

droid-extevdev (pulseaudio-modules-droid 14.2.107-14.2.109) aborts on
jackless devices. This daemon publishes an EV_SW input device advertising
SW_HEADPHONE_INSERT / SW_MICROPHONE_INSERT (state: unplugged, never
toggled) so extevdev finds a jack to watch and droid card setup proceeds.
Fixed upstream in 14.2.110 (dfda983); retire this once the image ships it.
"""
import signal
import sys

try:
    from evdev import UInput, ecodes as e
except ImportError:
    sys.exit("gts9-virtual-h2w: python3-evdev missing "
             "(sudo apt install python3-evdev)")

CAPS = {e.EV_SW: [e.SW_HEADPHONE_INSERT, e.SW_MICROPHONE_INSERT]}


def main():
    try:
        ui = UInput(CAPS, name="gts9-virtual-h2w")
    except Exception as exc:
        sys.exit(f"gts9-virtual-h2w: uinput device creation failed: {exc}")
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: sys.exit(0))
    print(f"gts9-virtual-h2w: created {ui.device.path}", flush=True)
    while True:          # hold the device node open forever
        signal.pause()


if __name__ == "__main__":
    main()
PYEOF
chmod 755 "$DAEMON" || APPLY_ERRS=$((APPLY_ERRS+1))

# --- system unit -------------------------------------------------------------
cat > "$UNIT" <<'UNITEOF'
[Unit]
Description=Virtual h2w jack switch for droid-extevdev (gts9 audio workaround)

[Service]
Type=simple
ExecStartPre=-/sbin/modprobe uinput
ExecStart=/usr/local/bin/gts9-virtual-h2w
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable --now gts9-virtual-h2w.service || {
  log "ERROR: failed to enable/start gts9-virtual-h2w.service"
  APPLY_ERRS=$((APPLY_ERRS+1))
}

# verify the virtual device appears (<= 10 s)
seen=0
for _ in $(seq 1 10); do
  if cat /sys/class/input/input*/name 2>/dev/null | grep -qx gts9-virtual-h2w; then
    seen=1; break
  fi
  sleep 1
done
if [ "$seen" -eq 1 ]; then
  log "virtual jack device present"
else
  log "ERROR: gts9-virtual-h2w not visible in /sys/class/input after 10 s"
  log "       check: systemctl status gts9-virtual-h2w"
  APPLY_ERRS=$((APPLY_ERRS+1))
fi

# --- PulseAudio gate (user drop-in, lives on userdata) -----------------------
install -d -m 755 "$GATE_DIR"
cat > "$GATE" <<'GATEEOF'
# gts9 audio workaround: do not let PulseAudio (droid-extevdev) start before
# the virtual h2w jack exists. Bounded at 30 s, fail-open ('-' prefix +
# unconditional fallthrough) so a daemon failure can never wedge PA startup.
[Service]
# NOTE: $$ everywhere - systemd expands bare $n to empty before the shell
# runs (found 2026-08-31: the old gate never actually waited).
ExecStartPre=-/bin/sh -c 'n=0; while [ $$n -lt 30 ]; do cat /sys/class/input/input*/name 2>/dev/null | grep -qx gts9-virtual-h2w && exit 0; n=$$((n+1)); sleep 1; done; echo "gts9-h2w gate: virtual jack absent after 30s - proceeding (extevdev may abort)" >&2'
GATEEOF
chown -R phablet:phablet /home/phablet/.config/systemd 2>/dev/null || true

phablet_userctl daemon-reload \
  && log "user manager reloaded - gate active for the next PulseAudio start" \
  || log "user manager unreachable (no session yet?) - gate applies from next boot"

# --- self-copy to userdata so the fix survives rootfs replacement ------------
install -d -m 755 "$FIX_HOME"
SRC=$(readlink -f "$0")
if [ "$SRC" != "$FIX_HOME/install.sh" ]; then
  cp -f "$SRC" "$FIX_HOME/install.sh"
  chmod 755 "$FIX_HOME/install.sh"
fi
chown -R phablet:phablet "$FIX_HOME"

# --- summary -----------------------------------------------------------------
log "installer self-copied to $FIX_HOME/install.sh (rerun after every OTA/reflash)"
if [ "$APPLY_ERRS" -gt 0 ]; then
  log "finished WITH $APPLY_ERRS error(s) - see messages above"
  exit 1
fi
log "install complete. Acceptance:"
log "  1. cat /sys/class/input/input*/name | grep -x gts9-virtual-h2w"
log "  2. as phablet: systemctl --user restart pulseaudio   (or just reboot)"
log "  3. as phablet: pactl list short modules | grep droid"
log "  4. cold-boot test: reboot, then confirm audio output works"
exit 0
