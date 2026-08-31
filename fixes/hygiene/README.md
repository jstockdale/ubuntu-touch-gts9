# Hygiene drop-ins (family-wide)

Two small guards that previously existed only as prose (or on-device, or
nowhere). Both are baked into the gts9uwifi skeleton overlay as of
2026-08-30; on the 11" (Azkali's image) they must be installed per-device —
`fixes/post-flash/gts9wifi-post-flash.sh` does it.

- **`no-desktop-qt5`** → `/etc/apt/preferences.d/no-desktop-qt5` (rootfs —
  dies on every reflash/OTA, reapply). Pins desktop-GL `libqt5gui5`/
  `libqt5quick5` to -1 so an `apt install krita`-class command can no longer
  remove the -gles Qt stack and crash-loop Lomiri (the 2026-08-27/30 11"
  incident — PORT-STATE.md §4). Desktop apps go in Libertine/Waydroid.
- **`60-limitnofile-greeter.conf`** → for the 11":
  `/home/phablet/.config/systemd/user/lomiri-full-greeter.service.d/`
  (userdata — survives reflash, dies on a userdata wipe). Raises the
  greeter's fd limit to 65536 so client churn cannot SIGTRAP it via fd
  exhaustion. The Ultra ships it in the skeleton at the system path
  (`/etc/systemd/user/lomiri-full-greeter.service.d/60-gts9uwifi-nofile.conf`).
