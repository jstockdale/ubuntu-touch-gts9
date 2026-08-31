#!/bin/bash
# ============================================================================
# xinput pen check - CONNECT TO XWAYLAND CORRECTLY (X710)
# Prior run failed with "Authorization required" because it ran as root and/or
# without the right XAUTHORITY. XWayland under Lomiri uses phablet's auth cookie.
# RUN AS phablet, NOT sudo:   bash /tmp/pen-x2.sh 2>&1 | tee /tmp/pen-x2.txt
# ============================================================================
OUT=/tmp/pen-x2.txt
{
sec(){ echo; echo "===== $* ====="; }
echo "=== xinput via Lomiri XWayland (as phablet) ==="; date -Is

if [ "$(id -un)" = "root" ]; then
  echo "!! You ran this as root. Re-run as phablet WITHOUT sudo:  bash /tmp/pen-x2.sh"
  echo "   (X authority belongs to phablet, not root.)"
  exit 1
fi

sec "1. find the XWayland DISPLAY + XAUTHORITY that Lomiri is using"
echo "--- Xwayland process + its args (shows :DISPLAY and -auth path):"
ps -o pid,args -C Xwayland 2>/dev/null || pgrep -a -f Xwayland 2>/dev/null
XWL_ARGS=$(pgrep -a -f Xwayland 2>/dev/null | head -1)
# extract :N display
XDISP=$(echo "$XWL_ARGS" | grep -oE ':[0-9]+' | head -1)
# extract -auth path
XAUTHP=$(echo "$XWL_ARGS" | grep -oE '\-auth[= ]?[^ ]+' | sed -E 's/-auth[= ]?//')
echo "detected DISPLAY=$XDISP  XAUTHORITY=$XAUTHP"

# fallbacks
[ -z "$XDISP" ] && XDISP=:0
# common UT xauth locations
for cand in "$XAUTHP" "$XDG_RUNTIME_DIR/.mutter-Xwaylandauth."* "$XDG_RUNTIME_DIR"/xauth* "$HOME/.Xauthority" /run/user/32011/.Xauthority; do
  [ -f "$cand" ] && XAUTHP="$cand" && break
done
echo "using DISPLAY=$XDISP  XAUTHORITY=${XAUTHP:-<none found>}"
export DISPLAY="$XDISP"
[ -n "$XAUTHP" ] && export XAUTHORITY="$XAUTHP"

sec "2. also look for any xauth files in the runtime dir (in case above missed)"
ls -la "$XDG_RUNTIME_DIR"/ 2>/dev/null | grep -iE 'xauth|xwayland|mutter' | head
echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"

sec "3. THE check: can we list X devices now, and does the pen have a Pressure axis?"
xinput list 2>&1
echo "---"
PID=$(xinput list --name-only 2>/dev/null | grep -iE 'e-pen|pen|stylus' | head -1)
echo "pen X device: [$PID]"
if [ -n "$PID" ]; then
  echo "--- valuators/axes for '$PID' (look for 'Abs Pressure'):"
  xinput list "$PID" 2>&1
  echo "--- props:"
  xinput list-props "$PID" 2>&1 | head -30
else
  echo "pen has no distinct X device name; full 'xinput list' above shows what X exposes."
  echo "(if only sec_touchscreen appears and no pen, X merged/dropped the pen.)"
fi

sec "4. if xinput STILL can't connect, try without auth via xhost-style"
if ! xinput list >/dev/null 2>&1; then
  echo "still no X connection. Trying DISPLAY variants:"
  for d in :0 :1 :2; do
    echo -n "  DISPLAY=$d : "
    DISPLAY=$d xinput list >/dev/null 2>&1 && echo "WORKS" || echo "no"
  done
fi
echo; echo "=== end ==="
} 2>&1 | tee "$OUT"
