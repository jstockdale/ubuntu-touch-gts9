# gts9wifi — next-device-access checklist

Verification items that require the 11" in hand (queued 2026-08-30 by the
parity audit; work through top-to-bottom, tick and date).

1. **Archive the live audio-fix artifacts, then diff against the repo.**
   The repo installer is a documented *reconstruction*; the cold-boot-
   validated originals were never pulled off-device (and layout drift is
   documented: daemon path + gate filename differ between the Aug-29 notes
   and the repo script). The DEVICE copy wins any diff:
   ```
   tar czf ~/gts9wifi-audio-live-$(date +%F).tgz \
     /usr/local/bin/gts9-virtual-h2w /etc/systemd/system/gts9-virtual-h2w.service \
     /home/phablet/.config/systemd/user/pulseaudio.service.d \
     /home/phablet/gts9-audio-fix 2>/dev/null
   ```
   Pull the tarball off-device, diff, fold real deltas back into
   `fixes/audio/gts9-audio-fix-install.sh`.
2. **Pen state.** Does the pen track as a pointer right now, and does it
   survive a reboot? (`pen-cleanup.sh` default mode may never have been
   run after the last experiments.) If inert:
   `sudo fixes/input-pen/gts9wifi-pen-pointer-install.sh`, restart Lomiri.
3. **GLES state after the krita incident.** Confirm the reversal actually
   executed: `dpkg -l | grep -E 'libqt5(gui|quick)5'` shows ONLY `-gles`
   rows; `qtubuntu-android` installed; maliit running; check whether
   krita/xinput still linger (`apt remove --purge krita krita-data` if so).
4. **Apt pin.** `cat /etc/apt/preferences.d/no-desktop-qt5` — treat as
   absent until seen; install via the post-flash script if missing.
5. **modules.load measurement.** Re-confirm the 4x duplication figure and
   capture it for the upstream dedupe ask:
   `wc -l /android/vendor_dlkm/lib/modules/modules.load` vs
   `awk '!seen[$0]++' ... | wc -l` (was 457/357 on 2026-08-10).
6. **Install the hardening + post-flash kit** (one run of
   `fixes/post-flash/gts9wifi-post-flash.sh` covers 1-5's fixes) and copy
   the kit off-device.
7. **BT HAL crash-loop.** After a full power-off cold boot, capture:
   `lxc-attach -n android --clear-env -- logcat -d | grep -i bluetooth`
   plus `systemctl status bluebinder hciuart 2>/dev/null` — the ~62 s
   SIGKILL cycle's outcome was never recorded.
8. **aud_dev ownership oddity.** `ls -ln /sys/kernel/aud_dev/state` — the
   parked uid-1013 root-EACCES observation; the hardening service now
   chmods it, verify it sticks.
9. **Touchpad daemon (folio users).** Install + empirically validate the
   landscape label on this panel; record it in the port notes.
