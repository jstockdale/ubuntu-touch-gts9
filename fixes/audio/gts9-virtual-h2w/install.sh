#!/bin/sh -e
# Install gts9wifi virtual-jack workaround (rerun after any OTA).
D="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
REMOUNTED=0
if ! touch /etc/.rwtest 2>/dev/null; then mount -o remount,rw /; REMOUNTED=1; fi
rm -f /etc/.rwtest
install -D -m 755 "$D/gts9-virtual-h2w.py" /usr/local/bin/gts9-virtual-h2w.py
install -D -m 644 "$D/gts9-virtual-h2w.service" /etc/systemd/system/gts9-virtual-h2w.service
install -D -m 644 "$D/55-gts9wifi-wait-h2w.conf" /etc/systemd/user/pulseaudio.service.d/55-gts9wifi-wait-h2w.conf
systemctl daemon-reload
systemctl enable --now gts9-virtual-h2w.service
if [ "$REMOUNTED" = 1 ]; then mount -o remount,ro / 2>/dev/null || echo "note: could not remount / ro (busy)"; fi
echo "installed. Reboot, or reset-failed + start pulseaudio for the phablet user."
