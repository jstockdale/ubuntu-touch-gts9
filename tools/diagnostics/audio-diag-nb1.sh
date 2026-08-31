#!/bin/bash
# Copyright (c) 2026 John Stockdale and Off by One, Inc.
# BSD 3-Clause License - see LICENSE at the repository root.
# audio-diag-nb1.sh -- Ubuntu Touch audio diagnostics, stage NB1
# (first pass on Azkali's S-Pen build)
#
# Target : Samsung Galaxy Tab S9 11" (gts9wifi / SM-X710), UT 24.04, Halium 13
# Mode   : STRICTLY READ-ONLY. Captures state, changes nothing.
# Run as : phablet, from an INTERACTIVE shell (adb shell or terminal app),
#          because sudo will prompt once for your passcode.
# Output : /home/phablet/audio-diag-nb1.log
#
# History context this stage discriminates between:
#   H1  orphaned wait-h2w drop-in survived on userdata, system unit wiped
#       by new rootfs -> PA gated forever in ExecStartPre
#   H2  build still ships pulseaudio-modules-droid 14.2.107-109, workaround
#       wiped -> extevdev NULL-io abort storm -> StartLimitBurst -> socket dead
#   H3  build carries >=14.2.110 (Azkali's dfda983 fix) -> failure is elsewhere
#       (HAL race, config, routing/mute, new regression)

set -u

LOG=/home/phablet/audio-diag-nb1.log
T=12   # per-command timeout, seconds

# ---------------------------------------------------------------------------
# Prechecks -- validate every prerequisite up front, fail fast with hints.
# Nothing below this block is allowed to abort the run.
# ---------------------------------------------------------------------------
missing=()
for c in date id uname timeout md5sum wc grep sed awk tee ls cat printf \
         systemctl journalctl pgrep dpkg dpkg-query sudo; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c (coreutils/systemd/procps -- should be preinstalled on UT)")
done
command -v pactl   >/dev/null 2>&1 || missing+=("pactl   -- install: sudo apt install pulseaudio-utils")
command -v getprop >/dev/null 2>&1 || missing+=("getprop -- expected on Halium-based UT (check /usr/bin/getprop)")

if [ ${#missing[@]} -gt 0 ]; then
  echo "FATAL: missing prerequisites:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

if [ "$(id -un)" != "phablet" ]; then
  echo "FATAL: run as phablet (user-session probes need phablet's session bus)." >&2
  echo "       From a root shell: sudo -iu phablet bash $0" >&2
  exit 1
fi

# User session bus -- required for systemctl --user / journalctl --user / pactl
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
if [ ! -S "$XDG_RUNTIME_DIR/bus" ]; then
  echo "FATAL: no user session bus at $XDG_RUNTIME_DIR/bus." >&2
  echo "       Is the session up? Unlock the device, or check loginctl." >&2
  exit 1
fi

# Log destination must be writable
if ! : > "$LOG" 2>/dev/null; then
  echo "FATAL: cannot write $LOG" >&2
  exit 1
fi

# Root capability -- needed for dmesg and system journal of the h2w unit.
# Prompt at most once, up front, never mid-run.
if ! sudo -n true 2>/dev/null; then
  echo "sudo validation (you may be prompted for your passcode once):"
  if ! sudo -v; then
    echo "FATAL: sudo required (dmesg, system journal). Configure sudo or run" >&2
    echo "       from a session where the phablet passcode works." >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Helpers. run() never propagates failure; rc captured directly (no pipeline).
# Pass the command string SINGLE-QUOTED at the call site.
# ---------------------------------------------------------------------------
log() { printf '%s\n' "$*" >>"$LOG"; }
hdr() {
  { echo; echo "==================================================================="
    echo "== $*"
    echo "==================================================================="
  } >>"$LOG"
  echo ">> $*"
}
run() {
  local desc="$1"; shift
  local cmd="$*"
  { echo; echo "----- $desc"; echo "\$ $cmd"; } >>"$LOG"
  timeout "$T" bash -c "$cmd" >>"$LOG" 2>&1
  local rc=$?
  if [ "$rc" -eq 124 ]; then log "[rc=124 TIMEOUT after ${T}s]"; else log "[rc=$rc]"; fi
  return 0
}

log "audio-diag-nb1  --  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
log "device: gts9wifi expected -- verify in S0"

# ---------------------------------------------------------------------------
hdr "S0  identity: build, kernel, uptime"
# ---------------------------------------------------------------------------
run "date/uptime"        'date; uptime'
run "kernel"             'uname -a'
run "who am i"           'id'
run "os-release"         'cat /etc/os-release'
run "UT channel (may not exist on 24.04)"  'cat /etc/system-image/channel.ini'
run "lsb-release"        'cat /etc/lsb-release'
run "vendor fingerprint" 'getprop ro.vendor.build.fingerprint; getprop ro.build.fingerprint'
run "vendor build date"  'getprop ro.build.date; getprop ro.build.id; getprop ro.build.version.release'

# ---------------------------------------------------------------------------
hdr "S1  package versions -- THE key fact: droid modules >= 14.2.110 or not"
# ---------------------------------------------------------------------------
run "droid/pulse packages (dpkg -l)" 'dpkg -l | grep -iE "pulse|droid|hybris" '
run "exact droid module version"     'dpkg-query -W -f="\${Package} \${Version} [\${Status}]\n" pulseaudio-modules-droid pulseaudio-modules-droid-common pulseaudio-modules-droid-hidl pulseaudio libhybris0'

# ---------------------------------------------------------------------------
hdr "S2  workaround remnants -- which pieces survived the reflash?"
# ---------------------------------------------------------------------------
run "fix dir on userdata"       'ls -la /home/phablet/gts9-audio-fix/'
run "install.sh (reveals canonical install paths)" 'sed -n "1,120p" /home/phablet/gts9-audio-fix/install.sh'
run "system unit file locations" 'ls -la /etc/systemd/system/gts9-virtual-h2w.service /lib/systemd/system/gts9-virtual-h2w.service /usr/lib/systemd/system/gts9-virtual-h2w.service'
run "system unit status"         'systemctl status gts9-virtual-h2w.service --no-pager -l -n 20'
run "system unit journal (this boot)" 'sudo journalctl -u gts9-virtual-h2w -b --no-pager -n 80'
run "h2w daemon process"         'pgrep -af "h2w|gts9-virtual"'
run "PA user drop-in dir: /etc/systemd/user"        'ls -la /etc/systemd/user/pulseaudio.service.d/ ; grep -RHn . /etc/systemd/user/pulseaudio.service.d/'
run "PA user drop-in dir: /usr/lib/systemd/user"    'ls -la /usr/lib/systemd/user/pulseaudio.service.d/ ; grep -RHn . /usr/lib/systemd/user/pulseaudio.service.d/'
run "PA user drop-in dir: ~/.config/systemd/user"   'ls -la /home/phablet/.config/systemd/user/pulseaudio.service.d/ ; grep -RHn . /home/phablet/.config/systemd/user/pulseaudio.service.d/'
run "EFFECTIVE pulseaudio.service (unit + all drop-ins -- the money shot)" 'systemctl --user cat pulseaudio.service --no-pager'
run "EFFECTIVE pulseaudio.socket"  'systemctl --user cat pulseaudio.socket --no-pager'

# ---------------------------------------------------------------------------
hdr "S3  input devices -- does anything jack-like exist for extevdev to find?"
# ---------------------------------------------------------------------------
run "full input device list"   'cat /proc/bus/input/devices'
run "jack-like names"          'grep -iE "h2w|head|jack|gts9" /proc/bus/input/devices'
run "uinput node"              'ls -la /dev/uinput'
run "uinput dmesg"             'sudo dmesg | grep -i uinput | tail -n 20'
run "legacy switch class"      'ls -la /sys/class/switch/'

# ---------------------------------------------------------------------------
hdr "S4  PulseAudio unit state"
# ---------------------------------------------------------------------------
run "enabled?"        'systemctl --user is-enabled pulseaudio.service pulseaudio.socket'
run "service status"  'systemctl --user status pulseaudio.service --no-pager -l -n 0'
run "socket status"   'systemctl --user status pulseaudio.socket  --no-pager -l -n 0'
run "service props"   'systemctl --user show pulseaudio.service -p ActiveState,SubState,Result,NRestarts,ExecMainCode,ExecMainStatus,StatusText,StatusErrno'
run "socket props"    'systemctl --user show pulseaudio.socket  -p ActiveState,SubState,Result'
run "failed user units" 'systemctl --user list-units --failed --no-pager'

# ---------------------------------------------------------------------------
hdr "S5  PulseAudio journal (current boot)"
# ---------------------------------------------------------------------------
run "PA service journal, last 400"  'journalctl --user -u pulseaudio.service -b --no-pager -n 400'
run "targeted greps (assert/extevdev/droid/fail)" 'journalctl --user -u pulseaudio.service -b --no-pager | grep -inE "assert|abort|extevdev|droid|failed|error|start-limit|timed out" | tail -n 80'
run "PA socket journal"             'journalctl --user -u pulseaudio.socket -b --no-pager -n 40'
run "PA journal previous boot (if persistent)" 'journalctl --user -u pulseaudio.service -b -1 --no-pager -n 60'

# ---------------------------------------------------------------------------
hdr "S6  container + Android HAL side"
# ---------------------------------------------------------------------------
run "container active?"      'systemctl is-active lxc-android-config'
run "audio-ish processes"    'pgrep -af audio | head -n 12'
run "audio HAL svc props"    'getprop | grep -iE "init\.svc\..*audio|vendor\.audio|audio.*hal"'
run "explicit vendor audio-hal" 'getprop init.svc.vendor.audio-hal'
run "host ALSA cards (NOTE: --no soundcards-- is NORMAL on halium; audio flows via container HAL)" 'cat /proc/asound/cards'

# ---------------------------------------------------------------------------
hdr "S7  /etc/pulse config integrity (Gemini-mangling precedent, Aug 5)"
# ---------------------------------------------------------------------------
run "tree"                 'ls -laR /etc/pulse | head -n 80'
run "line counts"          'wc -l /etc/pulse/touch.pa /etc/pulse/gts9/*.xml'
run "checksums (diff vs shipped overlay later)" 'md5sum /etc/pulse/touch.pa /etc/pulse/gts9/*.xml'
run "voice_virtual_stream" 'grep -n voice_virtual_stream /etc/pulse/touch.pa'
run "droid lines in touch.pa" 'grep -n droid /etc/pulse/touch.pa'
run "hybris env in this shell (unit env is in S2 output)" 'env | grep -i hybris'

# ---------------------------------------------------------------------------
hdr "S8  live PA probe (only if service is active)"
# ---------------------------------------------------------------------------
if systemctl --user is-active --quiet pulseaudio.service; then
  run "pactl info"           'pactl info'
  run "cards"                'pactl list cards short'
  run "sinks short"          'pactl list sinks short'
  run "sources short"        'pactl list sources short'
  run "droid modules loaded" 'pactl list modules short | grep -i droid'
  run "sinks FULL (mute/volume/active port)" 'pactl list sinks'
else
  log ""
  log "----- PA service INACTIVE -- skipping all pactl probes (expected under H1/H2)"
fi

# ---------------------------------------------------------------------------
hdr "S9  kernel log, audio-adjacent"
# ---------------------------------------------------------------------------
run "dmesg filtered" 'sudo dmesg | grep -iE "snd|audio|adsp|h2w|uinput" | tail -n 150'

# ---------------------------------------------------------------------------
hdr "S10  AUTO-TRIAGE (computed fresh, also echoed to stdout)"
# ---------------------------------------------------------------------------
t() { echo "  $*"; log "  $*"; }
echo; echo "===== TRIAGE ====="
log ""

droidver="$(dpkg-query -W -f='${Version}' pulseaudio-modules-droid 2>/dev/null || true)"
if [ -n "$droidver" ]; then
  if dpkg --compare-versions "$droidver" ge 14.2.110 2>/dev/null; then
    t "droid modules: $droidver  (>= 14.2.110: upstream extevdev fix PRESENT -> workaround unnecessary -> leans H3)"
  else
    t "droid modules: $droidver  (< 14.2.110: extevdev bug PRESENT in this build -> workaround required -> leans H1/H2)"
  fi
else
  t "droid modules: NOT FOUND via dpkg-query -- check S1 raw output"
fi

asserts="$(journalctl --user -u pulseaudio.service -b --no-pager 2>/dev/null | grep -cE "Assertion .e. failed" || true)"
t "extevdev assertion lines this boot: ${asserts:-0}  (>0 -> H2 confirmed-shape)"

nres="$(systemctl --user show pulseaudio.service -p NRestarts --value 2>/dev/null || true)"
pasvc="$(systemctl --user is-active pulseaudio.service 2>/dev/null || true)"
pasock="$(systemctl --user is-active pulseaudio.socket 2>/dev/null || true)"
t "PA service=$pasvc socket=$pasock NRestarts=${nres:-?}  (service activating + no asserts -> H1 gate; failed + NRestarts=5 -> H2 storm)"

if [ -f /etc/systemd/system/gts9-virtual-h2w.service ]; then
  t "h2w system unit: PRESENT in /etc (survived or reinstalled)"
else
  t "h2w system unit: ABSENT from /etc (wiped by reflash, as expected for H1/H2)"
fi

if pgrep -f "gts9-virtual-h2w" >/dev/null 2>&1; then
  t "h2w daemon: RUNNING"
else
  t "h2w daemon: not running"
fi

dropin="$(ls /etc/systemd/user/pulseaudio.service.d/*wait-h2w* /usr/lib/systemd/user/pulseaudio.service.d/*wait-h2w* /home/phablet/.config/systemd/user/pulseaudio.service.d/*wait-h2w* 2>/dev/null || true)"
if [ -n "$dropin" ]; then
  t "wait-h2w drop-in: PRESENT at: $dropin  (if daemon absent -> H1 orphaned gate)"
else
  t "wait-h2w drop-in: none found in the three candidate dirs"
fi

if grep -qiE "h2w|gts9" /proc/bus/input/devices 2>/dev/null; then
  t "jack-like input device: something matches h2w/gts9 in /proc/bus/input/devices (see S3 for which)"
else
  t "jack-like input device: NONE matching h2w/gts9 (extevdev finds nothing on <14.2.110)"
fi

echo "=================="
log ""
log "=== end of capture ==="
echo
echo "Done. Log written to: $LOG"
echo "Pull it with:  adb pull $LOG"
