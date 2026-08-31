#!/bin/sh
# Copyright (c) 2026 John Stockdale and Off by One, Inc.
# BSD 3-Clause License - see LICENSE at the repository root.
# install.sh - install gts9u-tp-rotate on the tablet. Run as root from the
# extracted directory:  sudo ./install.sh
set -eu

fail() { echo "FATAL: $1" >&2; [ -n "${2:-}" ] && echo "  hint: $2" >&2; exit 1; }

# ---- prerequisites, all validated before anything is touched
[ "$(id -u)" = 0 ] || fail "must run as root" "sudo ./install.sh"
command -v python3 >/dev/null 2>&1 || fail "python3 not found" "apt install python3"
command -v systemctl >/dev/null 2>&1 || fail "systemctl not found - not a systemd image?"
DIR=$(dirname "$0")
for f in gts9u-tp-rotate gts9u-tp-orient gts9u-tp-rotate.service gts9u-tp-rotate.default; do
  [ -f "$DIR/$f" ] || fail "missing $f next to install.sh" "run from the extracted tarball directory"
done
python3 -m py_compile "$DIR/gts9u-tp-rotate" 2>/dev/null || fail "daemon fails to compile on this python3"
[ -e /dev/uinput ] || fail "/dev/uinput missing" "modprobe uinput"

# ---- writable rootfs
if ! touch /usr/local/sbin/.gts9u-wtest 2>/dev/null; then
  echo "rootfs read-only - remounting rw"
  mount -o remount,rw / || fail "remount rw failed"
  touch /usr/local/sbin/.gts9u-wtest 2>/dev/null || fail "/usr/local/sbin still not writable"
fi
rm -f /usr/local/sbin/.gts9u-wtest

# ---- install
install -m 0755 "$DIR/gts9u-tp-rotate"  /usr/local/sbin/gts9u-tp-rotate
install -m 0755 "$DIR/gts9u-tp-orient"  /usr/local/bin/gts9u-tp-orient
install -m 0644 "$DIR/gts9u-tp-rotate.service" /etc/systemd/system/gts9u-tp-rotate.service
if [ ! -f /etc/default/gts9u-tp-rotate ]; then
  install -m 0644 "$DIR/gts9u-tp-rotate.default" /etc/default/gts9u-tp-rotate
else
  echo "keeping existing /etc/default/gts9u-tp-rotate"
fi
systemctl daemon-reload
systemctl enable gts9u-tp-rotate.service >/dev/null 2>&1 || fail "systemctl enable failed"

# ---- end-to-end check (needs the folio attached)
echo "---- running gts9u-tp-rotate --check (folio must be attached) ----"
/usr/local/sbin/gts9u-tp-rotate --check || fail "self-check failed - see output above" \
  "if the device name differs on this unit, edit the unit's ExecStart with --device-name"

cat <<'EOF'
---- installed, service enabled but NOT started ----
Validation pass (foreground first):
  1. sudo gts9u-tp-rotate            # identity - pad should behave exactly as before
  2. rotate UI to landscape, then:  gts9u-tp-orient 90
     - cursor correct?  landscape label = 90
     - still wrong?     gts9u-tp-orient 270
  3. Ctrl-C the daemon, set the winning label in /etc/default/gts9u-tp-rotate
  4. sudo systemctl start gts9u-tp-rotate
EOF
