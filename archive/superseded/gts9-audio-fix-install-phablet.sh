#!/bin/bash
# gts9-audio-fix-install.sh -- rebuild + install the droid-extevdev crash
# workaround on gts9wifi (Samsung Galaxy Tab S9 11", UT 24.04 / Halium 13)
#
# Root cause this works around:
#   pulseaudio-modules-droid-30 14.2.109 (packaged 2026-07-28) contains the
#   extevdev bug (14.2.107-14.2.109): with no jack-capable input device,
#   find_input_device() fails and mainloop_io_free() is called on a NULL io
#   event -> PA aborts -> StartLimitBurst kills pulseaudio.socket.
#   Upstream fix: mer-hybris dfda983, first in tag 14.2.110 (missed this
#   packaging cut by three days).
#
# What this installs:
#   /home/phablet/gts9-audio-fix/gts9-virtual-h2w.py   uinput daemon (state-0
#       virtual jack advertising SW_HEADPHONE/MICROPHONE/LINEOUT_INSERT)
#   /home/phablet/gts9-audio-fix/wait-h2w.sh           bounded 30 s PA gate
#   /home/phablet/gts9-audio-fix/install.sh            copy of this installer
#   /etc/systemd/system/gts9-virtual-h2w.service       (rootfs -- redo per OTA)
#   ~/.config/systemd/user/pulseaudio.service.d/55-gts9wifi-wait-h2w.conf
#                                                      (userdata -- survives OTA)
# Then: reset-failed + restart PA, restart audiosystem-passthrough-af,
# validate with a 440 Hz tone.
#
# Run as phablet from an interactive shell (sudo prompts once, up front):
#   bash gts9-audio-fix-install.sh

set -u

FIXDIR=/home/phablet/gts9-audio-fix
DROPDIR=/home/phablet/.config/systemd/user/pulseaudio.service.d
UNIT=/etc/systemd/system/gts9-virtual-h2w.service
DEVNAME=gts9-virtual-h2w

done_steps=()
die() {
  echo
  echo "FATAL: $*" >&2
  if [ ${#done_steps[@]} -gt 0 ]; then
    echo "State changed so far (for manual cleanup/debug):" >&2
    printf '  - %s\n' "${done_steps[@]}" >&2
  else
    echo "No state was changed." >&2
  fi
  exit 1
}
step() { done_steps+=("$*"); echo "[ok] $*"; }

# ---------------------------------------------------------------------------
# Prechecks -- validate everything up front, fail fast with install hints.
# ---------------------------------------------------------------------------
missing=()
for c in id readlink install mkdir grep sed sleep tee findmnt systemctl \
         journalctl chmod cp; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c (coreutils/systemd -- should be preinstalled)")
done
command -v python3 >/dev/null 2>&1 || missing+=("python3 -- install: sudo apt install python3")
command -v pactl   >/dev/null 2>&1 || missing+=("pactl   -- install: sudo apt install pulseaudio-utils")
command -v paplay  >/dev/null 2>&1 || missing+=("paplay  -- install: sudo apt install pulseaudio-utils")
command -v sudo    >/dev/null 2>&1 || missing+=("sudo")
if [ ${#missing[@]} -gt 0 ]; then
  echo "FATAL: missing prerequisites:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

[ "$(id -un)" = "phablet" ] || { echo "FATAL: run as phablet." >&2; exit 1; }

SRC="$(readlink -f "$0" 2>/dev/null || true)"
[ -n "$SRC" ] && [ -f "$SRC" ] || { echo "FATAL: run this as a file (bash gts9-audio-fix-install.sh), not via a pipe." >&2; exit 1; }

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
[ -S "$XDG_RUNTIME_DIR/bus" ] || { echo "FATAL: no user session bus at $XDG_RUNTIME_DIR/bus (unlock the device / session up?)." >&2; exit 1; }

[ -e /dev/uinput ] || { echo "FATAL: /dev/uinput missing -- try: sudo modprobe uinput" >&2; exit 1; }

if ! sudo -n true 2>/dev/null; then
  echo "sudo validation (you may be prompted for your passcode once):"
  sudo -v || { echo "FATAL: sudo required (writes /etc, runs the daemon as root)." >&2; exit 1; }
fi

echo "Prechecks passed."

# ---------------------------------------------------------------------------
# 1. Payloads onto userdata
# ---------------------------------------------------------------------------
mkdir -p "$FIXDIR" || die "mkdir $FIXDIR"

cat > "$FIXDIR/gts9-virtual-h2w.py" <<'PYEOF'
#!/usr/bin/env python3
# gts9-virtual-h2w -- state-0 virtual headset jack for gts9wifi.
# Gives droid-extevdev (pulseaudio-modules-droid 14.2.107-109) a qualifying
# input device so find_input_device() succeeds and PA does not abort.
# Advertises the jack switches but never reports anything inserted.
import fcntl, os, signal, struct, sys, time

UINPUT_PATH = "/dev/uinput"
# arm64/LE ioctl numbers, computed from <linux/uinput.h>
UI_SET_EVBIT   = 0x40045564          # _IOW('U', 100, int)
UI_SET_SWBIT   = 0x4004556D          # _IOW('U', 109, int)
UI_DEV_SETUP   = 0x405C5503          # _IOW('U', 3, struct uinput_setup[92])
UI_DEV_CREATE  = 0x00005501          # _IO('U', 1)
UI_DEV_DESTROY = 0x00005502          # _IO('U', 2)
EV_SW = 0x05
SWITCHES = (0x02, 0x04, 0x06)        # SW_HEADPHONE, SW_MICROPHONE, SW_LINEOUT _INSERT
BUS_VIRTUAL = 0x06
NAME = b"gts9-virtual-h2w"

def main():
    fd = None
    for attempt in range(10):        # tolerate early-boot udev races
        try:
            fd = os.open(UINPUT_PATH, os.O_WRONLY | os.O_NONBLOCK)
            break
        except OSError as e:
            if attempt == 9:
                print(f"open {UINPUT_PATH} failed: {e}", flush=True)
                sys.exit(1)
            time.sleep(0.5)

    fcntl.ioctl(fd, UI_SET_EVBIT, EV_SW)
    for sw in SWITCHES:
        fcntl.ioctl(fd, UI_SET_SWBIT, sw)
    # struct uinput_setup: input_id{bustype,vendor,product,version}, name[80], ff_effects_max
    setup = struct.pack("<HHHH80sI", BUS_VIRTUAL, 0, 0, 0, NAME, 0)
    fcntl.ioctl(fd, UI_DEV_SETUP, setup)
    fcntl.ioctl(fd, UI_DEV_CREATE)

    def bail(signum, frame):
        try:
            fcntl.ioctl(fd, UI_DEV_DESTROY)
        finally:
            os.close(fd)
        sys.exit(0)
    signal.signal(signal.SIGTERM, bail)
    signal.signal(signal.SIGINT, bail)

    time.sleep(0.3)
    try:
        with open("/proc/bus/input/devices", "rb") as f:
            present = NAME in f.read()
    except OSError:
        present = False
    print(f"virtual jack created (visible in /proc/bus/input/devices: {present}); "
          f"switch state 0, holding device open", flush=True)
    while True:
        time.sleep(3600)

if __name__ == "__main__":
    main()
PYEOF
[ $? -eq 0 ] || die "write gts9-virtual-h2w.py"
chmod 0755 "$FIXDIR/gts9-virtual-h2w.py" || die "chmod daemon"
step "wrote $FIXDIR/gts9-virtual-h2w.py"

cat > "$FIXDIR/wait-h2w.sh" <<'SHEOF'
#!/bin/sh
# Bounded gate: give the virtual jack up to 30 s to appear before PA starts.
# Deliberately exits 0 either way, so a missing daemon delays PA by 30 s at
# worst -- it can never wedge PA (avoids the orphaned-gate failure mode).
c=0
while ! grep -q "gts9-virtual-h2w" /proc/bus/input/devices 2>/dev/null && [ "$c" -lt 30 ]; do
  sleep 1
  c=$((c+1))
done
exit 0
SHEOF
[ $? -eq 0 ] || die "write wait-h2w.sh"
chmod 0755 "$FIXDIR/wait-h2w.sh" || die "chmod wait-h2w.sh"
step "wrote $FIXDIR/wait-h2w.sh (bounded 30 s gate)"

install -m 0755 "$SRC" "$FIXDIR/install.sh" || die "self-copy to $FIXDIR/install.sh"
step "kept installer at $FIXDIR/install.sh (rerun after every OTA/reflash)"

# ---------------------------------------------------------------------------
# 2. System unit onto rootfs (remount rw only if needed, restore after)
# ---------------------------------------------------------------------------
WAS_RO=0
if findmnt -no OPTIONS / | tr ',' '\n' | grep -qx ro; then
  WAS_RO=1
  sudo mount -o remount,rw / || die "remount / rw"
  step "remounted / rw (was ro; will restore)"
fi

sudo tee "$UNIT" >/dev/null <<'UNITEOF'
[Unit]
Description=gts9wifi virtual headset jack (droid-extevdev 14.2.107-109 crash workaround)
RequiresMountsFor=/home/phablet/gts9-audio-fix

[Service]
Type=simple
ExecStart=/usr/bin/python3 /home/phablet/gts9-audio-fix/gts9-virtual-h2w.py
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNITEOF
[ $? -eq 0 ] || die "write $UNIT"
step "wrote $UNIT"

sudo systemctl daemon-reload || die "systemctl daemon-reload (system)"
sudo systemctl enable --now gts9-virtual-h2w.service || die "enable/start gts9-virtual-h2w.service"
step "enabled + started gts9-virtual-h2w.service"

ok=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  grep -q "$DEVNAME" /proc/bus/input/devices && { ok=1; break; }
  sleep 1
done
if [ "$ok" -ne 1 ]; then
  sudo journalctl -u gts9-virtual-h2w -b --no-pager -n 30 >&2 || true
  die "virtual jack never appeared in /proc/bus/input/devices (daemon journal above)"
fi
step "virtual jack visible in /proc/bus/input/devices"

if [ "$WAS_RO" -eq 1 ]; then
  if sudo mount -o remount,ro /; then
    step "restored / to ro"
  else
    echo "[warn] could not remount / ro (busy?) -- restore manually: sudo mount -o remount,ro /"
  fi
fi

# ---------------------------------------------------------------------------
# 3. PA gate drop-in onto userdata (survives rootfs reflash)
# ---------------------------------------------------------------------------
mkdir -p "$DROPDIR" || die "mkdir $DROPDIR"
cat > "$DROPDIR/55-gts9wifi-wait-h2w.conf" <<'DROPEOF'
[Service]
ExecStartPre=-/home/phablet/gts9-audio-fix/wait-h2w.sh
DROPEOF
[ $? -eq 0 ] || die "write 55-gts9wifi-wait-h2w.conf"
systemctl --user daemon-reload || die "systemctl --user daemon-reload"
step "installed PA gate drop-in in ~/.config (userdata)"

# ---------------------------------------------------------------------------
# 4. Recover PA from the start-limit lockout (no reboot needed)
# ---------------------------------------------------------------------------
systemctl --user reset-failed pulseaudio.socket pulseaudio.service audiosystem-passthrough-af.service 2>/dev/null
systemctl --user start pulseaudio.socket  || die "start pulseaudio.socket"
systemctl --user start pulseaudio.service || die "start pulseaudio.service (check: journalctl --user -u pulseaudio -b -n 30)"
sleep 3
if ! systemctl --user is-active --quiet pulseaudio.service; then
  journalctl --user -u pulseaudio.service -b --no-pager -n 30 >&2 || true
  die "PA started but did not stay up (journal above)"
fi
step "pulseaudio.socket + pulseaudio.service active and holding"

systemctl --user restart audiosystem-passthrough-af.service 2>/dev/null
sleep 1
AF_STATE="$(systemctl --user is-active audiosystem-passthrough-af.service 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# 5. Validate: droid card loaded, sinks present, audible 440 Hz tone
# ---------------------------------------------------------------------------
echo
echo "--- pactl info"
pactl info | sed -n '1,8p'
echo "--- sinks"
pactl list sinks short
echo "--- droid modules"
pactl list modules short | grep -i droid || echo "(no droid modules listed -- investigate)"

TONE=/tmp/gts9-tone440.wav
python3 - "$TONE" <<'PYT'
import math, struct, sys, wave
path = sys.argv[1]; rate = 44100; dur = 1.0; amp = 0.3; f = 440.0
w = wave.open(path, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
w.writeframes(b"".join(struct.pack("<h", int(amp * 32767 * math.sin(2*math.pi*f*i/rate)))
                       for i in range(int(rate*dur))))
w.close()
PYT
[ $? -eq 0 ] || die "tone generation"
echo
echo "Playing 1 s 440 Hz test tone..."
paplay "$TONE" || die "paplay failed (PA is up but playback path failed -- capture journal)"
step "440 Hz tone played without error"

echo
echo "==================== RESULT ===================="
echo "  daemon:            $(systemctl is-active gts9-virtual-h2w.service 2>/dev/null)"
echo "  pulseaudio.socket: $(systemctl --user is-active pulseaudio.socket 2>/dev/null)"
echo "  pulseaudio:        $(systemctl --user is-active pulseaudio.service 2>/dev/null)"
echo "  passthrough-af:    ${AF_STATE:-unknown}   (if 'failed', that's a separate thread -- flag it)"
echo "================================================"
echo
echo "Did you HEAR the tone? If yes, audio is back."
echo
echo "Persistence notes:"
echo "  - Survives reboots (unit enabled) and, on the userdata side, rootfs reflashes."
echo "  - After the next OTA/reflash: rerun $FIXDIR/install.sh (restores the /etc unit)."
echo "  - If a flash wipes userdata again, re-push this installer first."
echo "  - Real fix: pulseaudio-modules-droid-30 >= 14.2.110 (dfda983) in the packaging."
