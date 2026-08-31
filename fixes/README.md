# fixes — who installs what

Two consumption models, by device:

- **Tab S9 Ultra (gts9uwifi), repo-built image:** nothing to install — every
  fix here is already **baked into the skeleton** and ships in the image
  (audio bring-up chain, virtual headphone jack, S-Pen pointer rules,
  touchpad rotation @270, apt pin, greeter fd-limit). After a flash, run
  `post-flash/gts9uwifi-post-flash.sh check` (and `sweep` once, if the unit
  previously ran pre-repo builds).
- **Tab S9 11" (gts9wifi), Azkali's image:** the fixes are **installers you
  run on the device** — and they die on every reflash/OTA, so run
  `post-flash/gts9wifi-post-flash.sh` after each one. It applies everything
  below in order and self-copies a kit to userdata.

Directory map:

- `audio/` — the extevdev/jackless fix (version-gated installer + minimal
  variant) and the preventive audio hardening for the 11"; superseded
  pieces are clearly marked. See its README.
- `input-pen/` — S-Pen pointer (touchscreen masquerade) installer for the
  11"; the Ultra's equivalent is skeleton-baked.
- `input-touchpad/` — the folio touchpad rotation daemon (name-generic,
  works family-wide; skeleton-baked on the Ultra).
- `hygiene/` — the desktop-GL apt pin and the greeter LimitNOFILE drop-in
  as standalone artifacts.
- `post-flash/` — the per-device restore-everything scripts. Start there.
