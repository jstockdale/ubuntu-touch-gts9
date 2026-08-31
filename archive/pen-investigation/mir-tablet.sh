#!/bin/bash
# ============================================================================
# Find the REAL Mir/qtmir libraries and check for tablet-tool (zwp_tablet)
# support. The prior script's globs missed them - this locates them properly.
# READ ONLY. Usage: sudo bash /tmp/mir-tablet.sh 2>&1 | tee /tmp/mir-tablet.txt
# ============================================================================
OUT=/tmp/mir-tablet.txt
{
sec(){ echo; echo "===== $* ====="; }
echo "=== locate Mir + check tablet-tool support ==="; date -Is

sec "1. what Mir/qtmir/lomiri packages are actually installed (correct filter)"
dpkg -l 2>/dev/null | awk '/^ii/ && ($2 ~ /mir/ || $2 ~ /qtmir/ || $2 ~ /lomiri-system-compositor/ || $2 ~ /wlcs/) {print $2, $3}'
echo "--- (also anything providing the compositor):"
dpkg -l 2>/dev/null | awk '/^ii/ && $2 ~ /compositor/ {print $2,$3}'

sec "2. locate the actual Mir/qtmir shared objects on disk"
echo "--- libmir* / libmiral / qtmir platform + server libs:"
find /usr/lib -iname 'libmir*.so*' -o -iname 'libmiral*.so*' -o -iname '*qtmir*' 2>/dev/null | head -30
echo "--- the qtmir Qt platform plugin (this is what maps input to Qt):"
find /usr/lib -path '*platforms*mirserver*' -o -iname 'libqpa-mirserver*' -o -iname '*mirserver*.so*' 2>/dev/null | head
echo "--- what does the running lomiri process actually have mapped? (definitive):"
LPID=$(pgrep -x lomiri | head -1); echo "lomiri pid: $LPID"
if [ -n "$LPID" ]; then
  grep -oiE '/usr/lib[^ ]*(mir|qtmir)[^ ]*\.so[^ ]*' /proc/$LPID/maps 2>/dev/null | sort -u | head -30
fi

sec "3. THE check: tablet-tool / zwp_tablet protocol symbols in those libs"
FOUND=0
for so in $(find /usr/lib -iname 'libmir*.so*' -o -iname 'libmiral*.so*' -o -iname '*mirserver*.so*' 2>/dev/null); do
  HITS=$(strings "$so" 2>/dev/null | grep -iE 'zwp_tablet|tablet_tool|tablet_manager|tablet_seat|tablet_pad' | sort -u)
  if [ -n "$HITS" ]; then
    echo "--- $so:"; echo "$HITS" | head -8; FOUND=1
  fi
done
# also scan whatever the live process mapped
if [ -n "$LPID" ]; then
  for so in $(grep -oiE '/usr/lib[^ ]*\.so[^ ]*' /proc/$LPID/maps 2>/dev/null | sort -u); do
    HITS=$(strings "$so" 2>/dev/null | grep -iE 'zwp_tablet|tablet_tool' | sort -u)
    [ -n "$HITS" ] && { echo "--- (mapped) $so:"; echo "$HITS" | head -5; FOUND=1; }
  done
fi
echo
[ "$FOUND" = "1" ] && echo ">>> TABLET-TOOL SYMBOLS PRESENT - Mir likely can route pen w/ pressure" \
                    || echo ">>> no tablet-tool symbols found in Mir libs - likely the ceiling"

sec "4. does qtmir map tablet events? check the qtmir input plugin specifically"
QTMIR=$(find /usr/lib -iname '*qtmir*.so*' -o -path '*mirserver*' -name '*.so' 2>/dev/null | head -3)
for q in $QTMIR; do
  echo "--- $q : tablet/pointer/touch symbols:"
  strings "$q" 2>/dev/null | grep -iE 'tablet|TabletStylus|QTabletEvent|InputType' | sort -u | head -10
done

sec "5. Mir version string (decides whether it's >= the tablet-support release)"
for so in $(find /usr/lib -iname 'libmirserver.so*' -o -iname 'libmircommon.so*' 2>/dev/null | head -2); do
  echo "--- $so:"; strings "$so" 2>/dev/null | grep -iE '^[0-9]+\.[0-9]+\.[0-9]+$|Mir [0-9]|version [0-9]' | sort -u | head
done
echo; echo "=== end ==="
} 2>&1 | tee "$OUT"
