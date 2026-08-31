#!/bin/bash
# ============================================================================
# S-Pen: Mir/Lomiri enumeration + udev tagging check (X710)
# Digitizer CONFIRMED working; quirk installed; pen still not tracking.
# This decides the fork WITHOUT needing libinput-tools:
#   - Does Mir enumerate event10 and how does it classify it?
#   - How does the pen's udev tagging differ from the WORKING touchscreen (event8)?
# READ ONLY. Prints to terminal AND writes /tmp/pen-mir.txt.
# Usage: sudo bash /tmp/pen-mir.sh
# Then:  adb pull /tmp/pen-mir.txt   (or just copy the terminal output)
# ============================================================================
OUT=/tmp/pen-mir.txt
{
sec(){ echo; echo "===== $* ====="; }
echo "=== pen: Mir enumeration + udev tagging fork ==="; date -Is

PEN=/dev/input/event10   # sec_e-pen (confirmed)
TS=/dev/input/event8     # sec_touchscreen (works - reference)

sec "1. phablet groups + input node ownership (perm cross-check vs working touchscreen)"
id phablet 2>/dev/null || groups phablet 2>/dev/null
echo "--- pen node vs working touchscreen node:"
ls -l "$PEN" "$TS" 2>/dev/null

sec "2. udev tags: PEN vs WORKING TOUCHSCREEN (the decisive comparison)"
echo "--- PEN ($PEN):"
udevadm info --query=all --name="$PEN" 2>/dev/null | grep -iE 'ID_INPUT|TAGS|CURRENT_TAGS|SEAT|LIBINPUT|WL_|E:.*INPUT'
echo
echo "--- WORKING TOUCHSCREEN ($TS):"
udevadm info --query=all --name="$TS" 2>/dev/null | grep -iE 'ID_INPUT|TAGS|CURRENT_TAGS|SEAT|LIBINPUT|WL_|E:.*INPUT'
echo
echo "--- (looking for: does pen have ID_INPUT_TABLET while touchscreen has"
echo "     ID_INPUT_TOUCHSCREEN? is pen MISSING a seat/tag the touchscreen has?)"

sec "3. does Mir/Lomiri enumerate the pen at all? (its input log this boot)"
sudo -u phablet journalctl --user -b 2>/dev/null | grep -iE 'mir|libinput|input.*device|sec_e-pen|tablet|stylus|pointer|event10|Pen|added device|seat' | tail -50
echo "--- if empty, try the system journal for the greeter:"
journalctl -b 2>/dev/null | grep -iE 'sec_e-pen|event10|libinput.*tablet|mir.*input.*(pen|tablet)' | tail -20

sec "4. full udev record for the pen (so we can craft a tagging rule if needed)"
udevadm info --query=all --name="$PEN" 2>/dev/null | head -40

sec "5. existing udev rules touching input tagging (where a fix would go)"
ls /usr/lib/udev/rules.d/ /etc/udev/rules.d/ 2>/dev/null | grep -iE 'input|libinput|touch|60-|70-' | head
grep -rl 'ID_INPUT\|sec_e-pen\|sec_touch' /usr/lib/udev/rules.d/ /etc/udev/rules.d/ 2>/dev/null | head

echo; echo "=== end ==="
} 2>&1 | tee "$OUT"
