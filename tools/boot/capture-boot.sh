#!/bin/bash
# Copyright (c) 2026 John Stockdale and Off by One, Inc.
# BSD 3-Clause License - see LICENSE at the repository root.
# capture-boot.sh - race the short adb window on a crash-looping halium boot.
# Run on the host, then (re)boot the tablet. Leave running across several
# crash cycles; each cycle lands in captures/session-N/. Ctrl-C when done.
set -u

command -v adb >/dev/null 2>&1 || { echo "missing adb (sudo apt install adb)"; exit 1; }

OUT="${OUT:-captures}"
mkdir -p "$OUT"
n=0

oneshot() {  # oneshot <name> <cmd...>
    local f="$1"; shift
    timeout 3 adb shell "$*" > "$D/$f" 2>&1 || true
}

echo "[capture] waiting for boot cycles - reboot the tablet now (Ctrl-C to stop)"
while :; do
    adb wait-for-device 2>/dev/null || { sleep 1; continue; }
    n=$((n+1)); D="$OUT/session-$(date +%H%M%S)-$n"; mkdir -p "$D"
    echo "[capture] === device up: session $n -> $D ==="

    # continuous kernel log until the connection dies (the money stream)
    ( adb shell 'dmesg -w' > "$D/dmesg-stream.log" 2>&1 || true ) &
    STREAM=$!

    # previous crash, if the initrd mounted pstore - grab FIRST, it's gold
    oneshot pstore-ls        'ls -la /sys/fs/pstore 2>/dev/null'
    oneshot pstore-console   'cat /sys/fs/pstore/console-ramoops* 2>/dev/null'
    oneshot pstore-dmesg     'cat /sys/fs/pstore/dmesg-ramoops* /sys/fs/pstore/dmesg-* 2>/dev/null'

    # identity: which DT actually applied on a NORMAL boot (TWRP lied; this won't)
    oneshot dt-model         "tr -d '\\0' < /proc/device-tree/model"
    oneshot cmdline          'cat /proc/cmdline'
    oneshot bootconfig       'cat /proc/bootconfig 2>/dev/null'
    oneshot uname            'uname -a'

    # state of the world
    oneshot lsmod            'lsmod'
    oneshot mounts           'cat /proc/mounts'
    oneshot mapper           'ls -la /dev/block/mapper 2>/dev/null'
    oneshot byname           'ls -la /dev/block/by-name 2>/dev/null'
    oneshot ps               'ps 2>/dev/null || ps -A'
    oneshot free             'free 2>/dev/null; cat /proc/meminfo | head -5'
    oneshot init-cmd         'cat /proc/1/cmdline | tr "\\0" " "'
    oneshot halium-log       'cat /dev/.halium* /run/halium* /init.log 2>/dev/null'

    # keep streaming until the device drops
    wait $STREAM 2>/dev/null
    echo "[capture] === device dropped: session $n complete ($(wc -l < "$D/dmesg-stream.log" 2>/dev/null || echo 0) dmesg lines) ==="
done
