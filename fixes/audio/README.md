# Audio fixes

Background: the family audio chain and the five-bug analysis live in
`docs/knowledge/gts9-audio-knowledge-transfer.md` (playbook) and
`docs/knowledge/PORT-STATE.md` §3 (authoritative summary).

## Live

- **`gts9-audio-fix-install.sh`** – CANONICAL installer for the 11"
  (gts9wifi) extevdev/jackless fix. Root-run, idempotent, `--force` /
  `--uninstall`, **version-gated**: refuses to install on
  pulseaudio-modules-droid-30 ≥ 14.2.110 (where upstream commit dfda983 makes
  it unnecessary). Installs the virtual-h2w jack + PA wait drop-in without
  requiring a reboot. Cold-boot validated 2026-08-29/30.
- **`gts9wifi-audio-hardening-install.sh`** – NEW (2026-08-30 parity
  remediation): preventive bugs-1/2/5 subset for the 11" – dedupe module
  walker, card_state/aud_dev chmod, unconditional latch clear, conditional
  HAL restart. Fail-open by design (no PA gate, Azkali's wait drop-in
  untouched, always exits 0). Closes the armed latch trap: the 11"
  measurably carries the 4× modules.load amplifier and previously had no
  recovery if a boot race ever latched `vendor.audio.use.primary.default`.
- **`gts9-virtual-h2w/`** – the minimal-dependency variant of the same
  workaround (no python3-evdev needed): uinput daemon advertising
  SW_HEADPHONE/MIC/LINEOUT state 0 + systemd unit + PA wait conf +
  `install.sh`. Keep: useful on images where pip/apt is awkward.
  ⚠ Its `55-gts9wifi-wait-h2w.conf` gate is HARD-FAIL on the rootfs –
  superseded semantics vs the canonical installer's fail-open userdata
  gate. Do not install both variants; the canonical installer wins.

The Ultra does **not** use these installers – its full five-bug bring-up
chain (`gts9u-audio-bringup` v4 + PA gate + virtual-h2w + modules dedupe)
ships inside `devices/gts9uwifi/skeleton/overlay/`.

## Superseded – do not install

- **`gts9u-audio-fix/`** – the v2-era standalone macro-loader
  (`gts9u-load-audio-macros` + unit + PA wait conf). Folded into and
  superseded by the skeleton's bringup service. Kept for reference.
- **`apply-string-patch.sh`** – the original `audio_hw_if`→`primary`
  libdroid-util string patch. **REVERTED in later analysis: it blocks the
  hidl_compat shim handshake.** The correct fix is the shim patch in
  `patches/upstream/halium-audio-hidl-compat/`. Kept only as history.
