# E. Build-system parity audit (gts9uwifi V3 vs gts9pwifi V4 vs common/ v2 vs skeleton audio-era)

Audit date: 2026-08-30. All claims below are VERIFIED by reading the named file
unless marked REPORTED. Line numbers refer to the files as of this snapshot.

Files read in full:
- `/home/jstockdale/projects/ubuntu-touch-gts9/devices/gts9uwifi/build-gts9uwifi.sh` (V3, 239 lines)
- `/home/jstockdale/projects/ubuntu-touch-gts9/devices/gts9pwifi/build-gts9pwifi.sh` (V4, 268 lines)
- `/home/jstockdale/projects/ubuntu-touch-gts9/common/scripts/{super.sh,make-flashable.sh,swap-vendor-modules.sh,swap-allowlist.txt,README.md}` (v2 F-series)
- `/home/jstockdale/projects/ubuntu-touch-gts9/devices/gts9uwifi/skeleton/scripts/{super.sh,make-flashable.sh,swap-vendor-modules.sh}` (audio-era, the STAGED set)
- `/home/jstockdale/projects/ubuntu-touch-gts9/devices/gts9uwifi/skeleton/flashable/META-INF/com/google/android/update-binary` (v4)
- `/home/jstockdale/projects/ubuntu-touch-gts9/devices/gts9pwifi/docs/gts9pwifi-port-runbook.md`
- `/home/jstockdale/projects/claude-ubuntu-touch/_capture/notes/RECON-build-scripts.md` (verified against the above)
- PORT-STATE §4 (F1–F9), §5 (SUPER table), §6 (open issues)

A normalized diff (sed gts9p→gts9u, x810→x910 over V4, then diff against V3)
was run to confirm the delta set is complete.

---

## Q1. What V4 has that V3 lacks, beyond device constants

RECON-build-scripts.md's claim that "no back-portable script fix exists" is
essentially VERIFIED by the normalized diff. Only three deltas are even
candidates, and only the first is worth a backport:

1. **Explicit SUPER export (defense-in-depth pattern)** — V4 line 227
   `export SUPER=11714691072`, with rationale at lines 222–226 ("so super.sh
   can never fall back to the wrong geometry"). V3 (lines 197–200) deliberately
   relies on the skeleton super.sh default `11744051200`. Correct today, but
   the moment any skeleton is forked/edited (exactly what the gts9p work does),
   an implicit default becomes a cross-wiring hazard. Backport: add
   `export SUPER=11744051200  # X910 GTS9UWIFI_EUR_OPEN.pit` to V3 stage 6.
2. **Stale-skeleton FATAL extra diagnostic** — the FATAL itself is in BOTH
   scripts (V3 lines 141–147; V4 lines 164–171); V4 only adds one more cause
   line ("or the skeleton fork missed the gts9u->gts9p rename", line 167).
   Fork-specific; nothing to backport. (Correcting RECON emphasis: the
   task-prompt's "stale-skeleton FATAL" is NOT a V4-only feature.)
3. **Flash-note hardening** — V4 lines 261–265 add "verify TWRP boots + backs
   up BEFORE trusting it" and the dtbo/board-rev note. Informational,
   device-specific (the Ultra's TWRP is already trusted).

Everything else in the diff is device constants: STM vs goodix touch (V4
150–153, 206–219 vs V3 132–133, 183–195), panel strings/seds, dts paths, no
config-fragment append in V4 (goodix-only need), the cnss-qca6490 comment
(V4 128–129), import scope comments.

## Q2. Anything in V3 missing from V4

One real (minor) item:

- **Negative check for the superseded PA drop-in dropped** — V3 line 152:
  `[ ! -e "$AO/etc/systemd/user/pulseaudio.service.d/50-gts9uwifi-wait-audiohal.conf" ]`.
  V4 has no gts9p equivalent (verified: no `50-` check between lines 172–179).
  RECON calls this "fork-appropriate (fork never had the old file)", but that
  is only true if the fork was cut from a CLEAN skeleton tarball. The runbook's
  Phase-1 sed (`s/gts9u/gts9p/g`) would happily rename a stale
  `50-gts9uwifi-wait-audiohal.conf` into `50-gts9pwifi-wait-audiohal.conf`,
  which V4 would then not detect. Cheap insurance: restore the negative check
  with the gts9p name.
- V3's `halium.config.gts9u-append` step (lines 85–87) is absent from V4 —
  correct, not a gap (fragment carries goodix/wacom symbols the S9+ gets
  in-tree).

## Q3. Staged scripts: the v2 audit set is used by NEITHER build — CONFIRMED

**Confirmation chain (all VERIFIED):**
- V3 stages `$SKEL` (gts9uwifi-skeleton) at lines 64–67; V4 stages the forked
  gts9p skeleton at lines 78–81. `skeleton/build.sh` line 28 runs
  `./scripts/swap-vendor-modules.sh` — i.e. the STAGED copy.
- Staged copy `devices/gts9uwifi/skeleton/scripts/swap-vendor-modules.sh`
  (audio-era, 44 lines): HAS the modules.load dedupe (`awk '!seen[$0]++'`,
  line 25) + SELinux xattr restore on the rewritten lists (lines 26–27);
  has NO inventory, NO LEFTOVER/UNLANDED audit, NO allowlist logic, `set -e`
  only.
- `common/scripts/swap-vendor-modules.sh` (v2, 113 lines): HAS the audit
  (lines 36–75) + allowlist strict mode failing BEFORE repack (lines 77–107)
  + `set -euo pipefail`; has NO modules.load dedupe (verified: zero `seen[`
  or `awk` occurrences; the only `seen[$0]` in the repo's script copies is
  the skeleton's).
- The skeleton `scripts/` dir contains NO `swap-allowlist.txt` (verified by
  listing); the only allowlist lives at `common/scripts/swap-allowlist.txt` —
  and note it contains ZERO entries below the "triaged leftovers" line
  (line 20 is the last content), so the first strict run on any device will
  fail-and-list by design.
- Same fork for the other two scripts: staged `super.sh` is the original
  (no strict mode, no input checks, no lpmake probe); staged
  `make-flashable.sh` is `set -xe`, checks only super.img (line 9), and
  copies the static zstd only if present (line 20: `[ -f ... ] && cp`) —
  i.e. can silently ship a zip with no bundled zstd, which update-binary v4
  then aborts on at flash time (`abort "no zstd available"`, line 71) if
  TWRP's own zstd is missing. The v2 make-flashable hard-requires it at pack
  time (common/scripts/make-flashable.sh lines 12–14, 27).
- `common/scripts/README.md` lines 9–24 states the divergence explicitly and
  says the merge is "tracked in the open-issues ledger" — **it is NOT**:
  PORT-STATE §6 (items 1–18, read in full) contains no swap-script-merge
  item. Orphaned tracking claim; the merge task exists nowhere as an open
  item.

**Stale comments in BOTH build scripts (misleading):** V3 lines 179–181 and
V4 lines 201–203 say swap-vendor-modules.sh "audits leftovers - see its
report and scripts/swap-allowlist.txt". Against the staged skeleton scripts
this is FALSE — no audit runs, and the referenced allowlist path does not
exist in the skeleton. The comment describes the ultra-main v2 script that
never made it into the (audio-thread) skeleton line.

**Also:** V3 line 153 / V4 line 176 sanity-grep `seen[$0]` in the staged
swap script. The v2 script would FAIL this gate — so the common/ v2 script
cannot simply be dropped into a skeleton; only a merged script (which keeps
the awk dedupe literal) passes.

**Concrete risk (silent-dead-modules class), per device:**
- *gts9uwifi (Ultra)*: every build repacks vendor_dlkm with stock modules the
  halium kernel cannot load (stock vermagic) and nothing reports them. This is
  the exact class that cost the va_macro/machine_dlkm no-audio hunt
  (documented in the v2 script header, common/scripts/swap-vendor-modules.sh
  lines 4–7). The Ultra survives today because the leftover set was manually
  hunted once; any vintage bump or newly-needed stock module regresses
  silently.
- *gts9pwifi (S9+)*: WORSE — a brand-new device+vintage (X810/AWHA) whose
  leftover set has NEVER been triaged, built with the no-audit script. If any
  S9+-only subsystem (haptics, sensors, an STM-adjacent module) needs a stock
  vendor_dlkm module the halium tree doesn't rebuild, the first build ships
  it dead and mute. The audit exists precisely for this first-build scenario.
- *gts9wifi (11")*: out of scope of these scripts (Azkali upstream build; no
  swap step under our control) — noted for completeness.

**Merged script must combine (exact feature list):**
1. `set -euo pipefail` + named errors on every missing input (v2 lines 7,
   25–31).
2. Extraction into a subdir (`fsck.erofs --extract="$WORK/x"`, v2 line 29)
   rather than the mktemp root (audio-era line 12) — keeps the repack tree
   clean.
3. modules.load dedupe: `awk '!seen[$0]++'` over every `$MODS/modules.load*`
   (audio-era lines 22–29) — MUST keep the literal `seen[$0]` so V3/V4's
   sanity grep passes unchanged.
4. SELinux xattr + owner/mode restore on BOTH the swapped `.ko` files (both
   versions have this) AND the rewritten modules.load lists (audio-era only,
   lines 26–27 — v2 lacks it because v2 never rewrites the lists; after the
   merge the lists are rewritten, so without this the lists land labelless
   in the repacked erofs → vendor_modprobe/SELinux breakage risk).
5. CTX capture with fallback `u:object_r:vendor_file:s0` and the v2 `|| true`
   guard (v2 line 33; audio-era line 14 lacks `|| true` — safe today only
   because the pipeline's last command is `tr`).
6. Stock/built inventories + LEFTOVER/UNLANDED report (v2 lines 37–75).
7. Allowlist strict mode: default path `$(dirname $0)/swap-allowlist.txt`,
   `ALLOWLIST` env override, stale-entry note, FAIL BEFORE repack leaving the
   previous image intact, report-only when the file is absent (v2 lines
   78–107).
8. `vendor_dlkm.img.stock` preservation + `mkfs.erofs -zlz4 -T0
   --force-uid=0 --force-gid=0` repack (identical in both).
9. Staging: ship the merged script into BOTH skeletons' `scripts/` AND copy a
   PER-DEVICE `swap-allowlist.txt` beside it (X910 and X810 leftover sets
   will differ; the current common file is an empty template — each device
   needs its own triage pass on first strict run).
10. super.sh and make-flashable.sh: promote the v2 copies into both skeletons
    too (strict mode, input checks, lpmake probe, zstd hard-require) —
    optionally with per-device SUPER defaults (see Q5).

## Q4. update-binary

- **Ultra skeleton carries v4** — VERIFIED:
  `devices/gts9uwifi/skeleton/flashable/META-INF/com/google/android/update-binary`,
  header lines 4–13 ("v4 changes (F1)"): zstd `-t` integrity pre-pass before
  touching super (lines 127–131), marker-file pipeline-failure detection
  (lines 135–141), staged+size-verified small images (lines 80–108), vbmeta
  absent-vs-failed distinction (lines 110–117), device check v3
  (lines 38–64).
- **What the gts9p fork gets**: the runbook (Phase 1, lines 44–70) forks the
  ENTIRE skeleton tarball, so the fork inherits update-binary v4 mechanics —
  but the rename recipe is `sed -i 's/gts9u/gts9p/g'` and
  `'s/x910/x810/g'`, both LOWERCASE-only. Against the v4 script this
  produces a half-converted device check:
  - `EXPECTED_CODENAME="gts9uwifi"` → `"gts9pwifi"` (lowercase — converts).
  - Line 46 `grep -q "X916"` hard-reject: UPPERCASE — survives unchanged.
    Inert on an S9+ (rejects the Ultra 5G, not the S9+ 5G).
  - Line 49 `grep -q "X910"` verified-pass: survives unchanged — an X810
    can never take the verified path, and worse, the check is wrong-device.
  - Line 53 `*GTS9UWIFI*` and line 57 `*GTS9U*` case patterns: UPPERCASE —
    survive unchanged. **Cross-flash hazard**: an Ultra whose TWRP reports
    GTS9U* would match the forked package's `*GTS9U*` warn-and-proceed
    branch and flash X810 firmware onto an X910 with only a warning.
  - The runbook's own fork verification (line 75: `grep -rn gts9u .`) is
    case-sensitive and therefore reports "clean" despite all of the above.
- **What EXPECTED_CODENAME/device-check needs for gts9p**: codename
  `gts9pwifi`; hard-reject `X916` AND `X910` (both Ultras) AND `X816`
  (S9+ 5G); verified-pass `X810`; family patterns `*GTS9PWIFI*|*gts9pwifi*`
  then `*GTS9P*|*gts9p*` (note `*GTS9P*` must not be reachable by an Ultra —
  it isn't, GTS9U ≠ GTS9P); abort otherwise.
- **Does V4 build script or runbook mention update-binary?** NO — VERIFIED:
  `grep -rn update-binary devices/gts9pwifi/` returns nothing; the runbook
  covers skeleton fork, extraction, unit prep, build, flash, but never the
  flash-script device check. This is a loud gap: the one file where a
  lowercase-only sed is actively dangerous is the one file no doc mentions.
- Archived v1/v3 exist at `archive/superseded/update-binary-{v1,v3}`
  (superseded, fine).

## Q5. SUPER defaults and the Ultra post-resize lpmake budget

- Both super.sh copies default `SUPER=11744051200` (X910):
  `common/scripts/super.sh` line 11, `skeleton/scripts/super.sh` line 4.
- **Ultra (V3)**: no SUPER export anywhere in build-gts9uwifi.sh — relies on
  the skeleton default. Correct value, implicit mechanism (see Q1 item 1).
- **S9+ (V4)**: `export SUPER=11714691072` at build-gts9pwifi.sh line 227
  (X810 PIT: 2,860,032 blocks × 4096), overriding the default. Belt+braces:
  `x810-extract.sh` lines 36, 92–96 hard-fail unless the stock raw super is
  byte-exactly 11,714,691,072, and runbook §1.5 documents the override.
- **11" (gts9wifi)**: 11,643,387,904 per PORT-STATE line 348 (REPORTED; PIT
  not in this repo) — never passes through our super.sh (Azkali build).
- **Post-resize lpmake budget NOT in the pipeline — CONFIRMED.** PORT-STATE
  §6 item 5 (line 429) says "Bake the resized system-LP size + group budget
  into build-gts9uwifi.sh (lpmake stanza)" is still open, and line 327–328
  records the on-device state: product+system_ext LPs deleted via fastbootd,
  group ceiling bisected to 6,210,715,648, system grown online; "Pipeline
  lpmake fix (system→8e9, group→super capacity) still open." VERIFIED
  against the scripts: both super.sh copies size every partition to the
  image file size (`stat -c '%s'`, common lines 33–39) and set the group to
  the plain sum (`QTI=$((...))`, line 41) — no 8e9-class system budget, no
  group-to-super-capacity ceiling, anywhere. Consequence: rebuilding and
  reflashing the Ultra zip today REGRESSES the daily-driven device — rootfs
  shrinks back to the ~4.5 GB image size and the deleted One UI LPs return —
  then requires redoing the manual fastbootd surgery. The fix is a super.sh
  (or wrapper) knob: `--partition system:readonly:<budget≈8e9>:` with the
  image smaller than the partition, and `--group` set to super capacity
  minus metadata, per device.

---

## Loud flags (expected-but-absent)

1. **No build uses the module audit.** The v2 audit/allowlist swap script
   sits in common/, staged nowhere; both V3 and V4 comments claim it runs
   (V3:179–181, V4:201–203) — false against the staged scripts. Silent dead
   vendor_dlkm modules are unguarded on BOTH buildable devices; the
   unexecuted S9+ first build is the highest-risk consumer.
2. **The dedupe+audit merge is untracked.** common/scripts/README.md line 22
   claims it is "tracked in the open-issues ledger"; PORT-STATE §6 has no
   such item.
3. **update-binary fork hazard.** The runbook's lowercase seds leave the v4
   device check half-Ultra (X910 verify, X916 reject, GTS9U patterns) in the
   gts9p zip, the fork-verify grep can't see it, and no gts9p doc mentions
   update-binary at all. Includes a warn-and-proceed cross-flash path for
   X810 firmware onto an Ultra.
4. **Ultra rebuild would undo the rootfs grow** (PORT-STATE §6 #5 confirmed
   unimplemented) — do not reflash the Ultra from a fresh build until the
   lpmake budget is baked in.
5. **swap-allowlist.txt is an empty template** — even once staged, each
   device needs its own triaged entries; the "reviewed X910 allowlist" claim
   in common/scripts/README.md line 26 is not reflected by the file content.
6. Minor: staged make-flashable.sh can ship a zip without the bundled zstd
   (silent `[ -f ] && cp`); update-binary v4 then aborts at flash time on
   TWRPs lacking zstd. v2 catches this at pack time; promote it.
7. Minor: V4 dropped V3's negative check for the superseded
   `50-*-wait-audiohal.conf` PA drop-in; the runbook sed would rename a stale
   copy right past it.
