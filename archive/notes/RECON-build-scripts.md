# RECON: build-gts9uwifi.sh / build-gts9pwifi.sh lineage

Reconciliation of the seven captured copies of the Ubuntu Touch build script under
`_capture/files/`. Date of analysis: 2026-08-30.

## Bottom line

There are only **four distinct versions** among the seven files (md5-verified).
The lineage is a **single, clean, linear chain with no forks or divergent edits**
for gts9uwifi, plus one device-fork (Tab S9+) at the end:

```
V1 (8,726 B)  porting-orig/outputs/build-gts9uwifi.sh          [Aug 4-5, porting thread]
   = ultra-main/uploads/build-gts9uwifi__7_.sh                 (user re-uploaded V1 as "(7)")
        |
        v  hardening pass (ultra-main thread)
V2 (10,573 B) ultra-main/outputs/gts9u-fixes/build-gts9uwifi.sh
   = audio-config/uploads/build-gts9uwifi.sh                   (user carried V2 into audio thread)
        |
        v  audio-overlay sanity gate added (audio-config thread, Aug 8-11)
V3 (11,970 B) audio-config/outputs/build-gts9uwifi.sh          <== CANONICAL / NEWEST gts9uwifi
   = tabS9plus-port/uploads/build-gts9uwifi__12_.sh            (user re-uploaded V3 as "(12)", Aug 27-29)
        |
        v  device fork: Tab S9 Ultra (SM-X910) -> Tab S9+ (SM-X810)
V4 (14,035 B) tabS9plus-port/outputs/build-gts9pwifi.sh        <== CANONICAL for gts9pwifi
```

### Checksums (identity proof)

| md5 | bytes | files |
|---|---|---|
| `92a44f52e161a27943630bb0b0284a75` | 8,726 | porting-orig/outputs/build-gts9uwifi.sh; ultra-main/uploads/build-gts9uwifi__7_.sh |
| `bc0224992710c43c2ce4076af0d466c9` | 10,573 | ultra-main/outputs/gts9u-fixes/build-gts9uwifi.sh; audio-config/uploads/build-gts9uwifi.sh |
| `26d72ee41dd650bc512ce80fe65c2872` | 11,970 | audio-config/outputs/build-gts9uwifi.sh; tabS9plus-port/uploads/build-gts9uwifi__12_.sh |
| `9d405d5fd6ebd2b737cac8df3a87f863` | 14,035 | tabS9plus-port/outputs/build-gts9pwifi.sh |

Key consequences:
- The user's copy "(7)" is **not** a newer version — it is byte-identical to the
  original porting-thread output (V1), fed into ultra-main as input.
- The user's copy "(12)" is byte-identical to the audio-config output (V3):
  **no gts9uwifi script changes happened between ~Aug 11 and Aug 29**. The
  Aug 27-29 Tab S9+ thread consumed V3 unmodified and only produced the
  gts9pwifi fork from it.
- **Canonical gts9uwifi script** = V3 (`audio-config/outputs/build-gts9uwifi.sh`,
  identical to `tabS9plus-port/uploads/build-gts9uwifi__12_.sh`).
- **Canonical gts9pwifi script** = V4 (`tabS9plus-port/outputs/build-gts9pwifi.sh`).

---

## V1 -> V2: hardening pass (ultra-main thread, output dir `gts9u-fixes/`)

No functional pipeline change (same clone/import/build/swap/super stages); this
is a robustness/correctness pass:

1. **`PARTS` renamed `SRC_PARTS`** (legacy `PARTS` still accepted via
   `SRC_PARTS="${SRC_PARTS:-${PARTS:-}}"`). Motivation is visible in stage 6:
   the script itself sets `PARTS=./partitions` when calling `scripts/super.sh`,
   so the input variable was renamed to avoid the collision/confusion.
2. **Preflight extended**: adds `zip` (make-flashable.sh), `file` (lpmake arch
   detection), `pahole` (kernel link with CONFIG_DEBUG_INFO_BTF=y on the
   kalama-gki base), `perl` (kernel build scripts); apt hint updated
   (`pahole = dwarves`).
3. **Missing-part error now goes to stderr** (`>&2` added).
4. **Atomic firmware-tar pack** (stage 3): packs to `$FWTAR.tmp` then `mv` —
   an interrupted `tar cJf` can no longer leave a truncated tar that passes the
   `[ ! -f "$FWTAR" ]` check on rerun.
5. **Module verification tiered** (stage 5): `goodix_ts_berlin.ko` missing is
   now FATAL (exit 1 — "a build without touch is unusable"); `wez01.ko`
   missing stays a warning (no pen). V1 warned for both and continued.
   Comment also notes swap-vendor-modules.sh "now audits leftovers" with
   `scripts/swap-allowlist.txt` (skeleton-side change made in the same thread).
6. **lpmake discovery rewritten** (stage 6):
   - a preset `LPMAKE` env is now respected as-is (skipping detection);
   - positive host-arch match (`uname -m` vs `file -b` output, `x86_64`->`x86-64`)
     instead of merely excluding `*aarch64*`;
   - exec probe by exit code (126/127 = not runnable) instead of the fragile
     V1 `--help`/output-sniff test;
   - null-delimited `find ... -print0 | while read -d ''` instead of V1's
     word-splitting `for cand in $(find ...)`.

## V2 -> V3: audio/hardware overlay gate (audio-config thread, Aug 8-11)

Exactly **one added block** (23 lines, between the existing sanity greps and
stage 3); everything else byte-identical. New "sanity: audio bring-up chain"
section verifies the staged skeleton (`overlay/system`) carries the
first-sound-session (2026-08-08) hardware overlay, and FATALs with a
`rm -rf $WORK/samsung-gts9u` re-stage hint if a stale pre-audio workdir copy
was used (staging is skipped when the dir exists). Checks:

- `usr/local/sbin/gts9u-audio-bringup` executable (completes modules.load
  "storm belt", gates PulseAudio via `/run/gts9u-audio-ready`) and contains
  "finit stage";
- `usr/local/lib/gts9u-virtual-h2w.py` (virtual h2w satisfies droid-extevdev's
  jack scan);
- both systemd `multi-user.target.wants` symlinks
  (`gts9u-audio-bringup.service`, `gts9u-virtual-h2w.service`);
- PA drop-in `zz-gts9u-audio.conf` references `gts9u-audio-ready`, and the
  **old** drop-in `50-gts9uwifi-wait-audiohal.conf` is absent (superseded
  approach must be gone);
- `scripts/swap-vendor-modules.sh` has the `seen[$0]` dedupe (fixes the
  quadruplicated modules.load at repack);
- pen reclass files: `etc/libinput/local-overrides.quirks` and
  `etc/udev/rules.d/61-gts9u-pen.rules`.

So V3 = V2 + a guard that the build is run against the post-audio-fix skeleton,
not a script-logic change. (The actual audio fixes live in the skeleton tarball
`gts9uwifi-skeleton-audio.tar.gz`, produced by the same thread.)

## V3 -> V4: the Tab S9+ (SM-X810) fork, `build-gts9pwifi.sh` (Aug 27-29)

Structure and all V2/V3 hardening retained verbatim (preflight, SRC_PARTS,
atomic tar, tiered module check, lpmake detection, overlay sanity gate).
Device-specific divergences:

| Aspect | gts9uwifi V3 (Tab S9 Ultra, SM-X910) | gts9pwifi V4 (Tab S9+, SM-X810) |
|---|---|---|
| Names/logs | `[gts9u-build]`, workdir `gts9u-build`, repo `samsung-gts9u` | `[gts9p-build]`, workdir `gts9p-build`, repo `samsung-gts9p` |
| Skeleton | `gts9uwifi-skeleton.tar.gz` | fork of the gts9u skeleton: `sed s/gts9u/gts9p/g` + file renames (audio-bringup, virtual-h2w.py, 2 systemd units + wants symlinks, `zz-gts9p-audio.conf`, `61-gts9p-pen.rules`) |
| Parts input | `out-x910/parts` (x910-extract.sh) | `out-x810/parts` (x810-extract.sh) |
| Firmware tar | `ubuntu-touch-kalama-firmware-x910.tar.xz` | `ubuntu-touch-kalama-firmware-x810.tar.xz` |
| Touch | goodix berlin, **imported** into kernel tree; module `goodix_ts_berlin.ko` (fatal if missing) | STM FTS1BA90A, **already in azkali tree** (no import); module `stm_ts_fts1b90a.ko` (fatal if missing); sanity greps `CONFIG_TOUCHSCREEN_STM_FTS1BA90A=m` in kalama-gki_defconfig |
| Pen | wacom wez01 via import (wacom wiring in gts9u-imports) | wez01 already in-tree (no import); sanity `CONFIG_EPEN_WACOM_WEZ01=m` + `drivers/input/wacom` dir |
| Kernel import scope | goodix + wacom wiring + gts9uwifi dts + halium.config append | **gts9pwifi dts only** (r00/r02/r04); no config-fragment append step |
| dts | `.../galaxytab/gts9uwifi/` | `.../galaxytab/gts9pwifi/`, sanity-checks `gts9pwifi_eur_open_w00_r04.dts` (thread also produced `gts9pwifi_eur_open_w00_r04_A13-AWG1.dts` and `_MIRROR.dts` variants in outputs/) |
| Panel / cmdline sed | `GTS9_...AMSA10FA01: + lcd_id args` -> `GTS9U_ANA38407_AMSA46AS02:` | same sed source -> `GTS9P_ANA38407_AMSA24VU05:`; lcd_id args dropped because GTS9P panel.c self-IDs via DDIC A1h (manufacture_id) reads, branching on 0x800004/0x800005 internally; note to cross-check stock `/proc/cmdline` once |
| Display import | GTS9U panel dir + `.dat` + merged Kbuild | GTS9P panel dir + `.dat` + AWH8 panel.c/h + merged Kbuild (via gts9p-imports) |
| wlan | kiwi_v2 IPA-off append (identical) | identical, plus comment: dts `qcom,cnss-qca6490` on gts9p AND gts9wifi is legacy node naming, both are actually WCN7850/kiwi |
| SUPER size | skeleton super.sh default `11744051200` (X910 PIT-verified), not exported | **`export SUPER=11714691072`** — X810 PIT `GTS9PWIFI_EUR_OPEN.pit`: 2,860,032 blocks x 4096 B; 28 MiB smaller than the X910 default, exported explicitly "so super.sh can never fall back to the wrong geometry" (PIT file captured in tabS9plus-port/outputs/) |
| Output zip | `ubuntu-touch-gts9uwifi-24.04-2.x.zip` | `ubuntu-touch-gts9pwifi-24.04-2.x.zip` |
| Flash notes | TWRP, stock dtbo left in place | same, plus: verify the gts9p TWRP build boots + backs up before trusting it; dtbo carries the 3 board-rev entries |
| Bring-up ladder | display -> touch (goodix) -> wifi -> audio -> pen | display -> touch (stm fts1ba90a) -> wifi -> audio -> pen |
| Overlay sanity gate | includes negative check that old `50-gts9uwifi-wait-audiohal.conf` is absent | gts9p-renamed checks; **drops** the stale-drop-in negative check (fork never had the old file); FATAL message also mentions "skeleton fork missed the gts9u->gts9p rename" as a cause |

Shared unchanged core across all four versions: clone kernel
(`kernel-samsung-gts9wifi`, branch `android13-5.15-halium`), display-drivers
and wlan from `gitlab.com/azkali-samsung/gts9/ubports/`; overlay imports;
`FIRMWARE=https://localhost/$FWTAR` basename trick to skip build.sh's wget;
`./build.sh`; module verify; `super.sh` + `make-flashable.sh`.

## File-by-file verdicts

| File | Version | Role |
|---|---|---|
| `files/porting-orig/outputs/build-gts9uwifi.sh` | V1 | original (Aug 4-5); superseded |
| `files/ultra-main/uploads/build-gts9uwifi__7_.sh` | V1 | user's re-upload of V1 into ultra-main; superseded |
| `files/ultra-main/outputs/gts9u-fixes/build-gts9uwifi.sh` | V2 | hardening pass output; superseded |
| `files/audio-config/uploads/build-gts9uwifi.sh` | V2 | V2 carried into audio thread; superseded |
| `files/audio-config/outputs/build-gts9uwifi.sh` | **V3** | **canonical/newest gts9uwifi** |
| `files/tabS9plus-port/uploads/build-gts9uwifi__12_.sh` | V3 | identical byte-for-byte to canonical (proof V3 was still current on Aug 27-29) |
| `files/tabS9plus-port/outputs/build-gts9pwifi.sh` | **V4** | **canonical gts9pwifi** (device fork of V3, not a replacement for it) |

Note: V4 is a *sibling* for different hardware, not a successor of V3 for
gts9uwifi. Any future gts9uwifi improvement discovered during the gts9p work
would need manual back-porting; as of the capture, none exists in script form —
the only V3->V4 deltas are device-specific (plus the two small overlay-gate
tweaks noted in the table, which are fork-appropriate, not fixes to port back).
