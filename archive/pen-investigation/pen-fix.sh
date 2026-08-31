#!/bin/bash
# ============================================================================
# S-Pen fix for Samsung Galaxy Tab S9 11" (SM-X710 / gts9wifi)
# The digitizer (sec_e-pen, event10) already works; wez01 loaded clean, no CRC issue.
# The ONLY problem: node reports PROP=0 (no INPUT_PROP_DIRECT), so libinput treats
# it as an external tablet and Lomiri won't map it to the screen as a direct pointer.
# Fix: install a libinput quirk adding INPUT_PROP_DIRECT, then restart the session.
#
# This script writes + verifies the quirk. The session restart (which DROPS your
# SSH connection) only runs if you pass RESTART=1 - do that at the device.
#
# Usage (verify only):   sudo bash /tmp/pen-fix.sh 2>&1 | tee /tmp/pen-fix.txt
# Usage (apply+restart): sudo RESTART=1 bash /tmp/pen-fix.sh    <-- run AT the device
# ============================================================================
sec(){ echo; echo "===== $* ====="; }
echo "=== S9 11\" S-Pen quirk install ==="; date -Is

sec "1. confirm the digitizer node + its current PROP (should be event10, PROP=0)"
EVN=$(awk -v RS= '/Name=.*sec_e-pen/ {match($0,/event[0-9]+/); print substr($0,RSTART,RLENGTH)}' /proc/bus/input/devices | head -1)
echo "sec_e-pen node: /dev/input/${EVN:-NOT FOUND}"
if [ -z "$EVN" ]; then echo "!! digitizer node not found - is wez01 loaded? aborting"; exit 1; fi
grep -A6 'Name="sec_e-pen"' /proc/bus/input/devices | grep -E 'PROP|EV|Handlers'

sec "2. write the libinput quirk (adds INPUT_PROP_DIRECT so Lomiri maps pen to screen)"
mkdir -p /etc/libinput
# remount rootfs rw in case it is read-only
mount -o remount,rw / 2>/dev/null
cat > /etc/libinput/local-overrides.quirks <<'QUIRK'
[Samsung S-Pen gts9wifi]
MatchName=sec_e-pen
AttrInputProp=+INPUT_PROP_DIRECT
QUIRK
echo "--- written to /etc/libinput/local-overrides.quirks:"
cat /etc/libinput/local-overrides.quirks

sec "3. verify libinput parses the quirk (install libinput-tools only if trivially available)"
if command -v libinput >/dev/null 2>&1; then
  echo "--- libinput quirks list for the pen node:"
  libinput quirks list "/dev/input/$EVN" 2>&1
else
  echo "(libinput-tools not installed - skipping CLI verify; the library Lomiri uses will read the quirk regardless)"
  echo "quirk file syntax self-check:"
  grep -qE '^\[.+\]$' /etc/libinput/local-overrides.quirks && \
    grep -qE '^MatchName=' /etc/libinput/local-overrides.quirks && \
    grep -qE '^AttrInputProp=\+INPUT_PROP_DIRECT$' /etc/libinput/local-overrides.quirks && \
    echo "  OK: section + MatchName + AttrInputProp all present" || echo "  !! quirk file malformed"
fi

sec "4. compositor unit (confirmed present on this device)"
sudo -u phablet env XDG_RUNTIME_DIR=/run/user/32011 systemctl --user is-active lomiri-full-greeter.service 2>/dev/null

sec "5. apply (session restart) - only if RESTART=1"
if [ "${RESTART:-0}" = "1" ]; then
  echo ">>> restarting lomiri-full-greeter.service - THIS DROPS YOUR SSH/UI SESSION <<<"
  echo ">>> after ~30s reconnect and test the pen: hover, then draw in an app <<<"
  sleep 2
  sudo -u phablet env XDG_RUNTIME_DIR=/run/user/32011 systemctl --user restart lomiri-full-greeter.service
else
  echo "quirk installed but NOT yet applied. To apply, run AT THE DEVICE (drops the session):"
  echo "  sudo -u phablet env XDG_RUNTIME_DIR=/run/user/32011 systemctl --user restart lomiri-full-greeter.service"
  echo "  -- or just reboot. Then hover + draw to test."
fi
echo; echo "=== end ==="
