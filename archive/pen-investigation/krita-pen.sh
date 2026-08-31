#!/bin/bash
# ============================================================================
# Krita + S-Pen pressure setup (X710, native ARM64 Krita from apt)
#
# GOAL: get Krita to read the pen's evdev pressure via Qt's native tablet path.
# This needs the pen tagged as a TABLET (not the touchscreen-masquerade we set for
# Lomiri pointer tracking) - Qt's native tablet reader looks for ID_INPUT_TABLET=1.
#
# So this script REVERTS to direct-tablet tagging (undoing the interim touchscreen
# rule), checks Krita/Qt tablet support, and preps the launch environment.
#
# NOTE: this trades away the Lomiri pointer-tracking we set earlier - the pen will
# again NOT track the desktop cursor, but Krita (if its tablet path works) reads the
# pen directly. You can't have both at once on this stack. The undo is at the end.
#
# READ-heavy; the only writes are swapping the udev rule. No session restart here.
# Usage: sudo bash /tmp/krita-pen.sh 2>&1 | tee /tmp/krita-pen.txt
# ============================================================================
OUT=/tmp/krita-pen.txt
{
sec(){ echo; echo "===== $* ====="; }
echo "=== Krita + S-Pen pressure setup ==="; date -Is
PEN=/dev/input/event10

sec "1. what did apt install? (krita version + Qt it links against)"
dpkg -l 2>/dev/null | awk '/^ii/ && $2 ~ /krita/ {print $2, $3}'
which krita 2>/dev/null
echo "--- Qt version krita links (Qt5 vs Qt6 decides tablet path support):"
KBIN=$(which krita 2>/dev/null); [ -z "$KBIN" ] && KBIN=/usr/bin/krita
ldd "$KBIN" 2>/dev/null | grep -iE 'Qt5Gui|Qt6Gui|Qt5Core|Qt6Core|QtGui' | head
echo "--- does the Qt build have the evdev/libinput tablet plugin?"
find /usr/lib -path '*qt5*generic*' -name '*tablet*' 2>/dev/null | head
find /usr/lib -path '*plugins*' -name 'libqevdevtablet*' -o -name '*evdevtablet*' 2>/dev/null | head
ls /usr/lib/*/qt5/plugins/generic/ 2>/dev/null

sec "2. REVERT pen to direct-tablet (Qt native tablet path needs ID_INPUT_TABLET=1)"
mount -o remount,rw / 2>/dev/null
# remove the touchscreen-masquerade rule
if [ -f /etc/udev/rules.d/72-gts9wifi-spen.rules ]; then
  echo "removing touchscreen-masquerade rule (was for Lomiri pointer tracking)..."
  rm -f /etc/udev/rules.d/72-gts9wifi-spen.rules
fi
# keep the INPUT_PROP_DIRECT quirk (helps Qt treat it as a direct/screen tablet)
mkdir -p /etc/libinput
cat > /etc/libinput/local-overrides.quirks <<'QUIRK'
[Samsung S-Pen gts9wifi]
MatchName=sec_e-pen
AttrInputProp=+INPUT_PROP_DIRECT
QUIRK
udevadm control --reload-rules 2>&1
udevadm trigger --name-match="$PEN" 2>&1
sleep 1
echo "--- pen tags now (want ID_INPUT_TABLET=1, NOT touchscreen):"
udevadm info --query=all --name="$PEN" 2>/dev/null | grep -iE 'ID_INPUT|CALIBRATION|PROP'

sec "3. can Krita's Qt see the tablet via evdev? check env + permissions"
echo "--- phablet access to the pen node:"
ls -l "$PEN"
id phablet 2>/dev/null | tr ' ' '\n' | grep -iE 'input|android_input'
echo "--- Qt platform + tablet env that Krita will use:"
echo "QT_QPA_PLATFORM (UT default): would be 'mirserver' or 'wayland'"
echo "--- KEY: Qt evdev tablet needs either the qevdevtablet plugin OR libinput w/ tablet."

sec "4. how to LAUNCH Krita and test pressure (instructions - run as phablet)"
cat <<'LAUNCH'
Run these AS phablet (not root), from the device terminal or SSH:

  # Try launching Krita. Under UT the default platform is mirserver; tablet input
  # through mirserver/Mir 1.8 likely WON'T carry pressure. So try forcing Qt to read
  # the tablet via evdev directly, bypassing the compositor's input:

  # Option A - let Krita use the default (mirserver) platform:
  krita

  # Option B - force Qt to add the evdev tablet device directly (pressure via evdev):
  QT_QPA_GENERIC_PLUGINS=evdevtablet:/dev/input/event10 krita

  # Option C - if a qevdevtablet plugin exists, point it explicitly:
  QT_QPA_EVDEV_TABLET_PARAMETERS=/dev/input/event10 krita

Once Krita opens:
  - Settings > Configure Krita > Tablet Settings
  - Select "Linux native tablet support" if offered
  - Open the "Tablet Tester" (Settings > Configure Krita > Tablet Settings > there is
    a tablet test widget) and press the pen with varying force.
  - If the test line varies with pressure -> IT WORKS. If flat -> pressure not reaching Krita.
LAUNCH

sec "5. UNDO (restore Lomiri pointer tracking if Krita pressure doesn't pan out)"
echo "  sudo bash /tmp/pen-interim.sh   # re-installs the touchscreen-masquerade rule"
echo "  (you can't have Lomiri-pointer AND Krita-tablet simultaneously on this stack)"
echo; echo "=== end ==="
} 2>&1 | tee "$OUT"
