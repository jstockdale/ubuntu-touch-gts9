# post-flash — run after every reflash

Rootfs changes die on every reflash; these scripts restore the fix set and
verify the result. Keep a copy off-device (a userdata wipe takes the
on-device kit with it).

- **`gts9wifi-post-flash.sh`** (11", Azkali's image) — run as root after any
  reflash/OTA. Seven steps: audio fix (version-gated), audio hardening,
  S-Pen pointer rule, apt pin, greeter LimitNOFILE, persistent journald,
  touchpad-daemon pointer. Reports real failures loudly (exit 1) and
  self-copies the whole kit to `/home/phablet/gts9-postflash-kit/`.
- **`gts9uwifi-post-flash.sh <sweep|check>`** (Ultra, repo-built image) —
  the image already bakes everything, so this only offers:
  - `sweep` — one-time cleanup of pre-repo on-device debris (old drop-ins,
    superseded units). Interlocked: refuses to run on an image that doesn't
    bake the replacements.
  - `check` — read-only acceptance: audio ONLINE count, bringup log,
    WiFi persistence, touchpad default, root size, vendor_dlkm mount source,
    udev group fix. Default mode.
