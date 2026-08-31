# Parity audit pass B — what the future gts9pwifi (Tab S9+) build inherits, and what it misses

2026-08-30. Evidence-based; every claim tagged VERIFIED (file read in this pass) or
REPORTED (a doc claims it). Repo root: `/home/jstockdale/projects/ubuntu-touch-gts9`
(abbreviated `$R` below). Skeleton = `$R/devices/gts9uwifi/skeleton/` (abbreviated `$SK`).

---

## 1. build-gts9pwifi.sh — complete sanity-gate inventory (VERIFIED, file read in full)

File: `$R/devices/gts9pwifi/build-gts9pwifi.sh` (269 lines, `set -euo pipefail` L33 —
every bare `[ ... ]` / `grep -q` below is a hard abort on failure).

| Lines | Gate |
|---|---|
| 42–58 | Host-tool preflight: 25 tools (incl. zip, file, pahole, perl) + libssl-dev/libelf-dev headers; prints apt line and exits |
| 61–64 | `SKEL`, `IMPORTS` required; `SRC_PARTS` (legacy `PARTS`) required |
| 70–72 | All six X810 partition images present in `$SRC_PARTS` |
| 97–100 | chmod u+w on OSRC-mode-0444 dts dirs before/after `cp -rf` (rerun safety) |
| 107–109 | Panel cmdline sed in `halium.config` (GTS9_ANA38407_AMSA10FA01 + lcd_id args → bare `GTS9P_ANA38407_AMSA24VU05:`), then **grep-assert** the GTS9P string landed (L109) |
| 137–146 | kiwi_v2 IPA offload forced off (append once), **grep-assert** `CONFIG_IPA_OPT_WIFI_DP := n` (L146) |
| 150–151 | `CONFIG_TOUCHSCREEN_STM_FTS1BA90A=m` and `CONFIG_EPEN_WACOM_WEZ01=m` present in cloned `vendor/kalama-gki_defconfig` |
| 152–153 | Driver dirs exist in-tree: `drivers/input/touchscreen/stm/fts1ba90a`, `drivers/input/wacom` |
| 155 | `GTS9P_ANA38407_AMSA24VU05` wired in merged `$DDIR/msm/Kbuild` |
| 156 | `gts9pwifi_eur_open_w00_r04.dts` present in kernel tree |
| 163–171 | **FATAL block**: `overlay/system/usr/local/sbin/gts9p-audio-bringup` must exist and be executable — explicitly written to catch a **pre-audio skeleton** or a missed gts9u→gts9p rename; tells you to `rm -rf $WORK/samsung-gts9p` and re-stage |
| 172 | `usr/local/lib/gts9p-virtual-h2w.py` exists |
| 173–174 | Both systemd **wants symlinks** (`-L`): `multi-user.target.wants/gts9p-audio-bringup.service`, `.../gts9p-virtual-h2w.service` (catches the "sed doesn't rename symlinks" failure mode) |
| 175 | `zz-gts9p-audio.conf` PA drop-in greps for `gts9p-audio-ready` (catches un-sed'ed content) |
| 176 | `scripts/swap-vendor-modules.sh` greps for `seen[$0]` — asserts the **audio-era dedupe revision** of the swap script, not the pre-audio one |
| 177 | `etc/libinput/local-overrides.quirks` exists (pen reclass quirk) |
| 178 | `etc/udev/rules.d/61-gts9p-pen.rules` exists (renamed pen rule) |
| 179 | `gts9p-audio-bringup` greps for `"finit stage"` — asserts the **v3 bringup with finit stage-2** (charging muic/pdic + wez01 force-load), catching even an early-audio-era skeleton |
| 185–193 | Firmware tar staged atomically (`.tmp` + `mv`); `FIRMWARE=https://localhost/$FWTAR` basename trick skips build.sh's wget |
| 206–219 | Post-build module audit: **`stm_ts_fts1b90a.ko` missing = FATAL** (L210–214, exit L219); `wez01.ko` missing = warn only (L216) |
| 227 | `export SUPER=11714691072` (X810 PIT) **before** super.sh — skeleton default can never apply in the scripted path |
| 228–256 | Host-arch lpmake probe (skeleton prebuilt is aarch64); errors out if none runnable |
| 257–258 | super + flashable zip via skeleton scripts |

Gate present on the Ultra side but **absent here**: `build-gts9uwifi.sh:152` has a
negative gate `[ ! -e .../50-gts9uwifi-wait-audiohal.conf ]` (stale pre-v3 audio drop-in
must NOT exist). build-gts9pwifi.sh has no `[ ! -e .../50-gts9pwifi-wait-audiohal.conf ]`
equivalent (VERIFIED absent from L163–180). Harmless against the canonical skeleton
(file isn't there), but it is a lost defense if an older tarball is ever used.

---

## 2. The skeleton-tarball question: which tarball does the runbook point at?

Runbook: `$R/devices/gts9pwifi/docs/gts9pwifi-port-runbook.md`, Phase 0.1 (input table)
and Phase 1 L47: `tar xzf gts9uwifi-skeleton.tar.gz  # -> samsung-gts9u/`.

**The name literally matches the PRE-AUDIO artifact.** Evidence:

- The pre-audio original exists as `$R/archive/superseded/gts9uwifi-skeleton-orig.tar.gz`
  (7,809,633 bytes — matches the "7.8 MB, root dir samsung-gts9u" description of
  `gts9uwifi-skeleton.tar.gz` in `archive/notes/porting-orig_993a1f88.p1.notes.md:232`). VERIFIED size / REPORTED provenance.
- The audio-era tarball was produced 2026-08-24 under a DIFFERENT name:
  `gts9uwifi-skeleton-audio.tar.gz` (231 entries; transcript
  `archive/transcripts/2026-08-24_...touchpad-troubleshooting_b08114aa.md:204,600`;
  `archive/notes/audio-config_09358316.p2.notes.md:71`). REPORTED.
- The repo's canonical `$SK` was unpacked from the **-audio** tarball
  (`archive/notes/SYNTHESIS-repo-proposal.md:90`). REPORTED — and consistent with what
  I read: `$SK` contains `gts9u-audio-bringup` (v3 with finit stage), `gts9u-virtual-h2w.py`,
  both units + wants symlinks, `zz-gts9u-audio.conf`, dedupe swap script. VERIFIED audio-era.

**Which did the author mean?** The audio-era one. The runbook (2026-08-27, three days
after the -audio tarball existed) Phase 1.2 renames the audio files by name and Phase 1.3
verifies `gts9p-audio-bringup` + `61-gts9p-pen.rules` — instructions that only make sense
against the audio-era skeleton. The author simply used the ambiguous short name.

**Would the gates catch a fork from the pre-audio tarball?** YES, loudly and early
(before the kernel build): build-gts9pwifi.sh L164–171 FATALs on missing
`gts9p-audio-bringup`, and L172–179 assert every other audio/pen artifact. L176
(`seen[$0]` in the swap script) and L179 (`finit stage` in the bringup) additionally
catch a fork from an *early* audio-era skeleton (pre-dedupe swap script, v1/v2 bringup
without finit). The exact audio assertions, at post-rename paths, are the L163–179 rows
in the table above.

**Residual risk / recommendation:** the pre-audio tarball still exists under exactly the
name the runbook asks for — a Downloads-folder grab is a live foot-gun (caught at build
time, but after Phase 1–3 effort). Repoint runbook Phase 0.1 + Phase 1 at the repo
canonical `devices/gts9uwifi/skeleton/` (or explicitly name `gts9uwifi-skeleton-audio.tar.gz`).

---

## 3. What the rename-fork gives gts9p automatically (VERIFIED in `$SK`)

The fork = `cp -r` + `sed s/gts9u/gts9p/g` on content + file/symlink renames (runbook 1.1–1.2).

- **Full audio bring-up chain (the audio fix)** — `usr/local/sbin/gts9u-audio-bringup`
  v3: storm-belt walk of vendor `modules.load` (dedup + blocklist-honored insmod), card
  ONLINE wait, 0666 nodes, Samsung fallback-latch clear, container-HAL restart, and the
  `/run/gts9u-audio-ready` flag; **finit stage-2** force-loads `muic_sm5714 pdic_sm5714 wez01`
  via finit_module flags=3 (curated allowlist only). sm5714 is also the S9+ charger family
  (`gts9p-hw-findings.md` OSRC section: sm5714/sm5440 battery dtsi in the X810 dts overlay
  zip), so the finit list carries over *correctly*, not just harmlessly.
  Plus: `gts9u-virtual-h2w.py` (uinput EV_SW jack), both systemd units + wants symlinks,
  `zz-gts9u-audio.conf` (PA hard-gated on the ready flag, no `-` prefix),
  `etc/pulse/touch.pa` L47 `module-droid-card-30 module_id=hidl_compat config=/etc/pulse/gts9/...`
  (the canonical post-regression line), `etc/pulse/gts9/` policy XMLs (path is
  family-generic, no rename needed), and the dedupe `scripts/swap-vendor-modules.sh`
  (modules.load 4x-duplication fix — audio bug #1 — applied at repack, vintage-agnostic).
- **Pen** — `61-gts9u-pen.rules` (pen→touchscreen reclass), `local-overrides.quirks`
  (`+INPUT_PROP_DIRECT`, strip BTN_TOOL_PEN/RUBBER/STYLUS/STYLUS2), and
  `usr/lib/udev/rules.d/74-gts9-wacom.rules` — name is family-generic ("gts9", untouched
  by the rename, correctly so; its header says "shared by gts9wifi/gts9uwifi").
- **Touch calibration matrix** — `71-gts9uwifi-touch-calibration.rules`:
  `ATTRS{name}=="sec_touchscreen" ... LIBINPUT_CALIBRATION_MATRIX="0 1 0 -1 0 1"` (90°).
  **Is it Ultra-specific? No — it is family policy.** `74-gts9-wacom.rules` applies the
  *same* matrix to the pen on both gts9wifi and gts9uwifi with the comment "Same panel
  mount as the touchscreen" (VERIFIED text). All three panels share the portrait-native
  mount; the STM driver also names its device `sec_touchscreen`, so the match will hit
  on gts9p. Expected correct for the S9+ — REPORTED-by-analogy, confirm on device at
  bring-up rung 2.
- **Recovery touch/pen modules** — `vendor-ramdisk-overlay/lib/modules/modules.load.recovery`
  already lists `stm_ts_fts1b90a.ko` (L360), `stm32_pogo_v3.ko` (L368), `wez01.ko` (L369):
  the S9+ recovery loads its own touch driver with zero edits (family-shared list). VERIFIED.
- **update-binary v4 hardening (F1)** — `$SK/flashable/META-INF/.../update-binary` header
  L4 "v4 changes (F1)": staged small-image writes, zstd `-t` super integrity pre-pass,
  marker-file pipeline-failure detection. Device-neutral; carries over intact. VERIFIED.
- **Per-device firmware blob names are a non-issue for main boot** — the kernel cmdline
  (`deviceinfo_kernel_cmdline`) sets `firmware_class.path=/vendor/firmware_mnt/image`, and
  the build stages the **X810 stock vendor image**, which inherently contains
  `tsp_stm/fts1ba90a_gts9p.bin`, `wez01_gts9p.bin`, `stm32_gts9family.bin` under their
  correct names. The skeleton overlay ships no touch/pen fw for main boot (VERIFIED grep:
  only a PORT-README mention). Nothing to sed.
- Plus the whole hardened plumbing: EFS read-only + mountpoint services, gts9-adb
  recover, usb-moded/MTP stack, waydroid binder, repowerd backlight/battery waits,
  greeter/shell 600 s timeouts, apparmor/gbinder/sensors overlays, hwc2 lsc-wrapper.

## 4. What the fork does NOT give (gaps — loud ones first)

1. **update-binary device check breaks on case.** The seds (`s/gts9u/gts9p/g`,
   `s/x910/x810/g`) are lowercase; the runbook's leftover check `grep -rn gts9u .` (1.3)
   is also case-sensitive. The update-binary's **uppercase** tokens survive untouched:
   `X916` reject (L46), `X910` verified-pass (L49), case patterns `*GTS9UWIFI*` (L53) and
   `*GTS9U*` (L56). Post-fork on an S9+: no verified-pass path (bootinfo says X810), **no
   rejection of the 5G S9+ (X816)**, and pass/abort hinges on whether the gts9p TWRP
   reports a lowercase `gts9pwifi` prop — a spurious abort (or a silent wrong-device pass
   on an X816) is possible. **No build gate covers the flashable/ dir at all.** Fix:
   rewrite the check for X810/X816/GTS9P tokens during the fork; change the runbook 1.3
   check to `grep -rni gts9u .`. VERIFIED (file read in full).
2. **Stale base-S9 blobs ride along (PORT-STATE F5, never executed).**
   `ramdisk-recovery-overlay/vendor/firmware_mnt/image/tsp_stm/fts1ba90a_gts9.bin` is the
   11" touch fw; name contains `gts9` (not `gts9u`) so both seds and the rename loop miss
   it. S9+ recovery's STM driver wants `fts1ba90a_gts9p.bin` → recovery touch runs on
   IC-resident fw at best. Same for `GTS9_ANA38407_AMSA10FA01.dat` +
   `ss_dsi_panel_PBA_BOOTING_FHD.dat` in `overlay/.../usr/lib/firmware/` and the recovery
   overlay — 11" panel data; no `GTS9P_...dat` is shipped in the rootfs (panel data is
   compiled in via the Kbuild xxd→`_PDF.h` path, which is how the Ultra works too, so
   likely harmless — but the S9+ fork inherits the wrong-device litter and F5 says prune).
   VERIFIED paths; F5 REPORTED at `docs/knowledge/PORT-STATE.md:338`.
3. **Identity cosmetics survive:** `deviceinfo_name="Tab S9 Ultra 14.6'"` and yaml
   `PrettyName: Tab S9 Ultra` contain no `gts9u` → the S9+ will self-describe as an
   Ultra in Settings/About. `GTS9UWIFI_EUR_OPEN.pit` (uppercase name, X910 geometry)
   stays in the fork as a misleading reference (not consumed by any script — VERIFIED
   no pit refs in build.sh/super.sh/make-flashable.sh). Not gated anywhere.
4. **super.sh default stays X910** (`scripts/super.sh:4` `SUPER=${SUPER:-"11744051200"}`).
   Safe in the scripted path (wrapper exports 11714691072 at L227), **unsafe for any
   manual `scripts/super.sh` run in the fork** — 28 MiB oversized super for the X810.
   Runbook 1.5 knows; the F6 strict-mode super.sh (in `common/scripts/`) that would
   refuse to run without an explicit SUPER was never landed in the skeleton. VERIFIED.
5. **Display scaling: the knob doesn't exist.** `grep -rn 'GRID_UNIT\|grid'` over the
   entire skeleton returns nothing (VERIFIED). Runbook 1.4 ("locate the scaling knob …
   bump ~11%") will find nothing to bump — the Ultra runs default scaling and the S9+
   (~266 vs ~239 ppi) will inherit it. Non-blocking, but the runbook step as written is
   a dead end; a GRID_UNIT_PX drop-in has to be *added*, not edited.
6. **Folio touchpad rotation is NOT in the skeleton.** The daemon lives only in
   `$R/fixes/input-touchpad/gts9u-tp-rotate/` (post-flash /data install), and the Ultra's
   DTS fix `touchpad,invert <0x01 0x00 0x00>` is **not landed in any imports**: Ultra
   imports dts r00/r03 still carry stock `<0x00 0x01 0x01>` (VERIFIED
   `gts9uwifi_eur_open_w00_r03.dts:10407`), and the gts9p stock dts has the identical
   value (VERIFIED `gts9pwifi/.../gts9pwifi_eur_open_w00_r04.dts:10424`). The runbook
   rung-6 phrase "your touchpad rotation quirk carries over" is misleading — nothing
   carries in the image; it's a manual install after first boot (the daemon *is*
   name-generic, so the same tarball works). Open ledger #6 (flip after v5) applies
   family-wide.
7. **Swap-script comment oversells what's inherited.** build-gts9pwifi.sh L202–203 says
   the swap script "audits leftovers – see its report and scripts/swap-allowlist.txt".
   FALSE for the inherited skeleton copy: it is the 43-line dedupe+SELinux revision with
   **no LEFTOVER/UNLANDED audit and no allowlist** (VERIFIED read; `common/scripts/README.md`
   documents the fork: "Neither swap-vendor-modules.sh is a superset of the other").
   The F2 v2 audit script + `swap-allowlist.txt` exist only in `$R/common/scripts/`, and
   that allowlist is X910-triaged — the X810 would need its own triage pass anyway.
   The L206–219 two-module check partially compensates (touch fatal, pen warn) but
   nothing would catch an X810 va_macro-class leftover.
8. **Missing negative gate** for a stale `50-gts9pwifi-wait-audiohal.conf` (Ultra has it
   at build-gts9uwifi.sh:152). Defense-in-depth only.
9. **Post-flash /data survivors aren't baked in** (family-wide, incl. future S9+):
   LimitNOFILE greeter drop-in and the no-desktop-qt5 apt pin are in the PORT-STATE
   post-flash checklist, not the overlay (VERIFIED absent from `$SK`). The S9+'s first
   image will lack them until the checklist is run.
10. **vendor_dtb/dtbo/bootconfig provenance is X910's** — but the prebuilt `vendor_dtb`
    is the generic `"Qualcomm Technologies, Inc. Kalama v2 SoC"` base DTB (VERIFIED model
    string) and bootconfig is generic qcom; the device-specific DT comes from the
    **stock on-device dtbo** (left in place at flash; X810's own carries r00/r02/r04).
    Family-common by design — REPORTED assumption; if the S9+ misbehaves at first boot,
    extracting the X810 vendor_boot dtb for a diff is the check (hw-findings already
    notes where to get it).
11. **Runbook nit:** the Phase 1.1 second sed (`x910→x810`, "firmware tar name in
    build.sh") is a no-op against the canonical skeleton — `x910` appears nowhere in it
    (VERIFIED grep); the x910 string lives in the *Ultra's wrapper*
    (`build-gts9uwifi.sh:163`), which isn't part of the fork. `grep -rl x910 . | xargs sed -i`
    on empty input makes GNU sed print "no input files" and continue — cosmetic.

---

## 5. Q4 — the merged display Kbuild and the family-tree question

- `$R/devices/gts9pwifi/imports/display-drivers/msm/Kbuild`: base **GTS9** block
  (L261–273, the 11" panel — azkali-native) + **GTS9P** block (L275–287, shell vars
  suffixed `_GTS9P`). **GTS9U count: 0** (VERIFIED `grep -c GTS9U` = 0).
- `$R/devices/gts9uwifi/imports/display-drivers/msm/Kbuild`: base GTS9 block + **GTS9U**
  block (L275–287, unsuffixed shell vars — the older, sloppier merge pattern). No GTS9P.
- Both bundles are applied with `cp -rf <imports>/display-drivers/. "$DDIR"/` — a
  **whole-file overwrite of msm/Kbuild**. Family-tree implication: applying gts9p imports
  over a tree that already had gts9u imports (or vice versa) **conflicts, not composes** —
  the last-applied bundle silently drops the other device's panel block. Today this is
  moot: each wrapper clones its own fresh `$DDIR` in its own `$WORK` (build-gts9pwifi.sh
  L112–121), and each build only needs its own panel. But a future unified family tree
  needs a tri-panel merged Kbuild (adopt the `_GTS9P`-style var suffixing for the GTS9U
  block too; the panel dirs and `.dat` files themselves are disjoint paths and compose fine).
- Each device's own gate keeps this honest per-build: gts9p asserts its panel in the
  merged Kbuild at L155; the Ultra asserts GTS9U at build-gts9uwifi.sh:134.

## 6. Answers to the specific questions, compressed

- **Runbook Phase-1 tarball**: names the pre-audio artifact's filename, but means (and
  its own steps require) the audio-era skeleton; the archive keeps the pre-audio one
  under `-orig`. Gates **would** catch a pre-audio (and even early-audio) fork before
  the kernel build: FATAL L164–171 plus asserts L172–179 (exact files/paths in §1).
- **Audio fix on gts9p**: inherited in full by the rename and *enforced* by eight
  separate build-time asserts. The mechanism is vintage-agnostic (completes whatever
  vendor `modules.load` X810 ships). Open variance (ledger #14) is only whether the
  X810 audio stack has surprises the Ultra's didn't.
- **Calibration matrix `0 1 0 -1 0 1`**: family policy (same panel-mount comment covers
  gts9wifi + gts9uwifi + pen), not Ultra-specific; expected right for the S9+, verify at
  bring-up.
- **update-binary**: v4 (F1) hardening inherited; EXPECTED_CODENAME sed-renames cleanly;
  the *uppercase* device-check tokens do not — rewrite for X810/X816/GTS9P (gap #1).
- **Firmware names**: correct by construction for main boot (loaded from staged X810
  vendor); wrong-name stale blob only in the recovery overlay (gap #2).
- **SUPER**: wrapper-exported correctly; skeleton default remains an X910 trap for
  manual runs (gap #4).
- **GridUnit**: no knob exists anywhere to inherit or sed (gap #5).
