#!/bin/bash
# verify-flasher-fork.sh - behavioral test of the update-binary device check,
# for BOTH the Ultra original and the runbook-forked gts9p variant.
#
# Tests the ACTUAL script text (not a hand-copied emulation - the 2026-08-30
# parity verification caught exactly that mistake): the device-check block is
# extracted between its EXPECTED_CODENAME= line and the end-marker comment,
# the three runtime reads are replaced with injected scenario values, and the
# block is executed under stubbed ui_print/abort.
#
# Run from anywhere: tools/dev/verify-flasher-fork.sh [path-to-update-binary]
# Exit 0 = full expected matrix; nonzero = at least one mismatch (printed).
set -u -o pipefail

UB="${1:-$(dirname "$0")/../../devices/gts9uwifi/skeleton/flashable/META-INF/com/google/android/update-binary}"
[ -f "$UB" ] || { echo "no update-binary at $UB"; exit 1; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# the forked variant, exactly per runbook Phase 1.1
sed -e 's/gts9u/gts9p/g' -e 's/x910/x810/g' "$UB" > "$WORK/ub.gts9p"
cp "$UB" "$WORK/ub.gts9u"

extract() { # $1=file -> extracted check block with runtime reads removed
    sed -n '/^EXPECTED_CODENAME=/,/end device check/p' "$1" \
      | grep -vE '^DT_MODEL=|^DEVICE_CODENAME=|^BOOTINFO=|^BOOTINFO_LC=|^ID_LC='
}

run_check() { # $1=block-file $2=bootinfo $3=identity -> verdict string
    local out rc
    out=$(sh -c '
        ui_print() { echo "UI:$1"; }
        abort()    { echo "ABORT:$1"; exit 9; }
        BOOTINFO_LC="$(printf %s "$SIM_BOOTINFO" | tr "A-Z" "a-z")"
        ID_LC="$(printf %s "$SIM_ID" | tr "A-Z" "a-z")"
        DT_MODEL="$SIM_ID"; DEVICE_CODENAME=""
        . "$1"
    ' sh "$1" 2>&1 <<<"" ; )
    rc=$?
    case "$out" in
        *ABORT*)              echo "ABORT" ;;
        *"Device verified"*)  echo "VERIFIED" ;;
        *WARNING*)            echo "WARN-PROCEED" ;;
        *"UI:Device:"*)       echo "ID-PROCEED" ;;
        *)                    echo "UNEXPECTED(rc=$rc:$out)" ;;
    esac
}

fails=0
check() { # $1=variant $2=bootinfo $3=identity $4=expected
    local blk="$WORK/blk.$1"
    SIM_BOOTINFO="$2" SIM_ID="$3" ; export SIM_BOOTINFO SIM_ID
    got=$(run_check "$blk")
    if [ "$got" = "$4" ]; then
        printf 'ok   %-6s boot=%-12s id=%-12s -> %s\n' "$1" "${2:-∅}" "${3:-∅}" "$got"
    else
        printf 'FAIL %-6s boot=%-12s id=%-12s -> %s (expected %s)\n' "$1" "${2:-∅}" "${3:-∅}" "$got" "$4"
        fails=$((fails+1))
    fi
}

extract "$WORK/ub.gts9u" > "$WORK/blk.gts9u"
extract "$WORK/ub.gts9p" > "$WORK/blk.gts9p"
for v in gts9u gts9p; do
    grep -q 'for p in x71 x81 x91' "$WORK/blk.$v" || { echo "FATAL: sibling generator missing in $v block"; exit 1; }
    sh -n "$WORK/blk.$v" || { echo "FATAL: $v block does not parse"; exit 1; }
done

echo "== Ultra package (gts9u, MODEL_WIFI=x910) =="
check gts9u "SM-X910" ""            VERIFIED
check gts9u "SM-X916" ""            ABORT          # own 5G
check gts9u "SM-X810" ""            ABORT          # sibling wifi
check gts9u "SM-X816" ""            ABORT          # sibling 5G
check gts9u "SM-X710" ""            ABORT
check gts9u "SM-X716" ""            ABORT
check gts9u ""        "GTS9UWIFI"   ID-PROCEED     # no bootinfo, own codename
check gts9u ""        "GTS9U"       WARN-PROCEED   # family only
check gts9u ""        "GTS9PWIFI"   ABORT          # other device identity
check gts9u ""        ""            ABORT

echo "== Forked S9+ package (gts9p, MODEL_WIFI=x810) =="
check gts9p "SM-X810" ""            VERIFIED
check gts9p "SM-X816" ""            ABORT          # own 5G
check gts9p "SM-X910" ""            ABORT          # ULTRA on gts9p pkg - the regression the generator fixes
check gts9p "SM-X916" ""            ABORT
check gts9p "SM-X710" ""            ABORT
check gts9p "SM-X716" ""            ABORT
check gts9p "SM-X910" "GTS9PWIFI"   ABORT          # untrustworthy recovery id must NOT override bootinfo
check gts9p ""        "GTS9PWIFI"   ID-PROCEED
check gts9p ""        "GTS9P"       WARN-PROCEED
check gts9p ""        "GTS9UWIFI"   ABORT          # Ultra identity on gts9p pkg
check gts9p ""        ""            ABORT

echo
if [ "$fails" -eq 0 ]; then echo "ALL SCENARIOS PASS"; else echo "$fails FAILURES"; exit 1; fi
