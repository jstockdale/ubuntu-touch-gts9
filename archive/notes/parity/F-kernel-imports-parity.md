# F — Kernel/techpack import parity audit (gts9wifi / gts9pwifi / gts9uwifi)

Audit date: 2026-08-30. Method: direct file reads of both import bundles, both build
scripts, the Ultra skeleton, gts9p-hw-findings, PORT-STATUS §8–§12, PORT-STATE §5.
Tags: **VERIFIED** = I read the file; **REPORTED** = a doc claims it.

## 1. Display / msm Kbuild — CONFIRMED CONFLICT (two two-panel Kbuilds, no three-panel merge)

**VERIFIED** by reading and diffing:
- `devices/gts9uwifi/imports/display-drivers/msm/Kbuild` lines 261–287: GTS9 block
  (GTS9_ANA38407_AMSA10FA01) + GTS9U block (GTS9U_ANA38407_AMSA46AS02). No GTS9P.
- `devices/gts9pwifi/imports/display-drivers/msm/Kbuild` lines 261–287: GTS9 block +
  GTS9P block (GTS9P_ANA38407_AMSA24VU05, comment at 275–276). No GTS9U.
- diff of the two files: they differ ONLY in that one panel block (GTS9U vs GTS9P).

Each bundle ships the Kbuild as a **complete replacement** applied with `cp -rf`
(build-gts9uwifi.sh:104, build-gts9pwifi.sh:120). Applying both bundles to one
display-drivers checkout is last-write-wins: the second copy silently deletes the
first device's panel block. Today this never happens — each build script clones a
fresh tree into its own workdir — but any future family/shared-tree build needs a
three-panel merged Kbuild.

Merge hazards for that future three-panel Kbuild (**VERIFIED**):
- The GTS9U block reuses the **unsuffixed** shell vars `CLEAR_TMP/COPY_TO_HERE/
  DATA_TO_HEX/ADD_NULL_CHR` and re-defines `XXD:=`/`SED:=` (gts9u Kbuild 278–285),
  i.e. Samsung's verbatim style; the GTS9P block was hand-merged with `_GTS9P`
  suffixes and deduped XXD/SED (gts9p Kbuild 282–285, per MANIFEST.md line 13).
  Both styles happen to work (:= $(shell) executes per assignment at parse), but a
  three-panel merge should adopt the suffixed style for all non-base blocks.
- Panel CONFIG_PANEL_*=y symbols are exported by each panel's `.conf` include, so
  the merged Kbuild alone wires all compiled-in panels; ss_dsi picks the active
  panel at runtime from DT (REPORTED: IMPORT-GUIDE items 10; hw-findings addendum).

## 2. Touch — goodix berlin (Ultra) vs stm fts1ba90a (11"/S9+)

**VERIFIED** in gts9u-imports:
- Full sec_input-integrated goodix source at
  `devices/gts9uwifi/imports/kernel-samsung-gts9wifi/drivers/input/touchscreen/goodix/berlin/`
  (12 .c/.h + Kconfig + Makefile).
- Wiring: `drivers/input/touchscreen/Kconfig` last non-endif line sources
  `goodix/berlin/Kconfig`; `drivers/input/touchscreen/Makefile` last line
  `obj-$(CONFIG_TOUCHSCREEN_GOODIX_BRL) += goodix/berlin/`.
- Config: `arch/arm64/configs/halium.config.gts9u-append` = single symbol
  `CONFIG_TOUCHSCREEN_GOODIX_BRL=m`; build-gts9uwifi.sh:85–86 appends it to
  halium.config only if absent.

**Composition safety:** the Makefile hook is config-gated (GOODIX_BRL only ever set
by the gts9u append) and the driver is DT-probe-gated, so the import composes
safely into a family tree — EXCEPT the `source "…goodix/berlin/Kconfig"` line,
which is a **parse error if the goodix/berlin directory is absent**: the merged
touchscreen/Kconfig must never be applied without the driver directory.

**Claim chain for Goodix-rev 11" units** (REPORTED, consistent across sources):
PORT-STATUS §8 — S9 is dual-sourced (Goodix @0x5d or STM @0x49 by hw rev);
"Goodix-rev S9 units likely lack touch on the current port – the same import fixes
them." §9 corrects the source (Samsung OSRC goodix_ts_berlin, not the QC techpack)
and reconfirms "the import fixes Goodix-rev S9 units too."
**GAP:** nothing in our tree delivers this to gts9wifi builds. Azkali's upstream
build is not touched by either bundle, no gts9wifi build script exists here, and
the open-issues ledger (PORT-STATE §6) has **no item** for upstreaming the goodix
import + `CONFIG_TOUCHSCREEN_GOODIX_BRL=m` to Azkali. Goodix-rev 11" units remain
unfixed anywhere despite the fix sitting finished in gts9u-imports.

gts9p: correctly goodix-free. hw-findings line 17–18 (VERIFIED read): the
`goodix,gt9916` node in gts9p dts is inert kalama cruft; touch is STM FTS1BA90A
(azkali-native, proven on base S9). build-gts9pwifi.sh:150,152 sanity-checks the
defconfig symbol and `stm/fts1ba90a` dir; missing `stm_ts_fts1b90a.ko` is
build-FATAL (lines 206–213). Parity of F8 policy: on Ultra, goodix missing is
fatal, wez01 warn (build-gts9uwifi.sh:181–195). Consistent.

## 3. S-Pen / wacom wez01 — the one real asymmetry between the bundles

**VERIFIED** in gts9u-imports (the "gts9wifi backport included" claim of
PORT-STATUS §10 = these two merged files):
- `drivers/input/Kconfig` (merged): `source "drivers/input/wacom/Kconfig"` present.
- `drivers/input/Makefile` (merged): `obj-$(CONFIG_EPEN_WACOM_WEZ01) += wacom/`.
- No wacom driver source in the bundle — IMPORT-GUIDE line 61: `drivers/input/wacom/`
  already exists in the halium tree. No wacom config line in the append —
  `CONFIG_EPEN_WACOM_WEZ01=m` already in vendor/kalama-gki_defconfig (IMPORT-GUIDE
  29–34). So the 2-file wiring merge *is* the entire kernel-side pen enablement.
- Proof it works: PORT-STATUS §11 — wez01.ko (2.87 MB) compiled clean with the
  bundle applied (REPORTED).

**gts9p-imports has NO equivalent** (**VERIFIED**: the bundle's kernel tree contains
only `arch/arm64/boot/dts/samsung/galaxytab/gts9pwifi/` — no drivers/input files at
all). MANIFEST.md lines 15–19 deliberately exclude the wacom *driver* ("azkali
wins", 148-line drift) and note the *defconfig symbol* is present — but neither
addresses the **Kconfig/Makefile wiring**, which PORT-STATUS §9 VERIFIED missing
from the azkali tree ("drivers/input/Kconfig sources neither wacom/ nor
sec_input/"; Samsung's LEGO injects it at build time). build-gts9pwifi.sh checks
only `CONFIG_EPEN_WACOM_WEZ01=m` (line 151) and `[ -d drivers/input/wacom ]`
(line 153) — both of which were ALREADY true in the tree where the symbol "sat
inert" — and treats a missing wez01.ko as **warn-only** (line 216).

Mitigating evidence (REPORTED, unresolved): on the 11" running the UBports CI
24.04-2.x channel, `wez01.ko` loads cleanly at boot with no CRC force-load
(ultra-main.p5 notes lines 78–83), suggesting the wiring may since exist in
whatever azkali/CI builds. But that cannot be confirmed from this repo, and the
gts9p build clones `gitlab.com/azkali-samsung/.../kernel-samsung-gts9wifi` fresh.

**Risk:** if the azkali git tree still lacks the wiring, the first S9+ build
produces no pen module and the script only warns. Cheap fix: add the same two
merged `drivers/input/{Kconfig,Makefile}` files to gts9p-imports **minus the
goodix lines** (or wacom-only variants — the touchscreen/Kconfig `source` of
goodix/berlin must NOT be copied without the goodix directory, see §2), or at
minimum add `grep -q 'wacom/Kconfig' $KDIR/drivers/input/Kconfig` to the gts9p
sanity block so the outcome is explicit at build time instead of at evtest time.

## 4. DTS board-rev coverage — PARITY OK

**VERIFIED** (files present + Makefile dtb targets read):
- gts9u: `gts9uwifi_eur_open_w00_r00.dts` (17,547 lines) + `..._r03.dts` +
  Makefile with kalama/kalamap × v1/v2 dtb targets for r00 and r03. Matches the
  stock Ultra DTBO's 2 entries (board-id 00/03 — PORT-STATE §5, REPORTED).
- gts9p: `gts9pwifi_eur_open_w00_r00/r02/r04.dts` (r04 = 17,409 lines) + Makefile
  targets for all three. Matches the stock S9+ DTBO's 3 entries (hw-findings
  line 50, REPORTED from PIT/dtbo carve). build-gts9pwifi.sh:156 asserts r04
  present.
- gts9wifi: 4 revs, azkali-native (REPORTED, PORT-STATE §5); nothing needed here.
- Both ports boot via **stock dtbo partition** (`skip_dtbo_partition=true`), so the
  imported DTS matters only for rebuilt DTBOs — the bundles are consistent with
  each other on this (IMPORT-GUIDE item 6; PORT-STATE §5).
- hw-findings line 18–20 caveat (REPORTED): the r04 mirror dts drifts ~13% from the
  canonical A13 zip — bundle correctly built from the zips; `reference/dts/*_MIRROR.dts`
  is identity-reference only.

## 5. WLAN — kiwi_v2 everywhere; qca6490 is DT node cosmetics

- **VERIFIED**: `devices/gts9uwifi/skeleton/deviceinfo:25`
  `deviceinfo_kernel_wlan_chip="kiwi_v2"`; line 27 lists `wlan/platform
  wlan/qcacld-3.0` in `deviceinfo_kernel_vendor_modules`.
- gts9p: no skeleton exists yet (fork is open item #13); its kiwi_v2 selection is
  currently carried by (a) the skeleton-fork sed inheriting the Ultra deviceinfo
  and (b) build-gts9pwifi.sh:130–147 which patches
  `qcacld-3.0/configs/kiwi_v2_defconfig` (IPA offload off) exactly as the Ultra
  script does (build-gts9uwifi.sh:108–129). **VERIFIED** both scripts carry the
  identical kiwi IPA patch — parity OK.
- The gts9p dts names its nodes `bt_qca6490` / `qcom,cnss-qca6490`
  (**VERIFIED**: reference/dts/gts9pwifi_eur_open_w00_r04_MIRROR.dts:15087–15205)
  — build-gts9pwifi.sh:127–129 documents this is node *naming*, not chip identity;
  both are WCN7850/kiwi and the base-S9 port proves kiwi_v2 (REPORTED). Ultra is
  WCN785x kiwi, caught via stock module diff `qca_cld3_kiwi_v2.ko` (PORT-STATUS §10).
- gts9wifi (11", Azkali upstream): kiwi_v2_defconfig already in the X710 wlan
  import (IMPORT-GUIDE 52–54, REPORTED) — not different, same chip family. Note
  Azkali's upstream presumably does NOT carry our IPA-offload-off patch; that
  patch exists only in our two build scripts (delivery to the 11" would be via
  Azkali, untracked).

## 6. Stale / hazardous — F5 PRUNING WAS NOT DONE (loud flag)

PORT-STATE §4 lists F5 as a landed build-pipeline finding: "prune stale 11" panel
`.dat` + STM touch fw from the Ultra skeleton." **VERIFIED the canonical skeleton
still contains all three stale files:**
- `devices/gts9uwifi/skeleton/overlay/system/usr/lib/firmware/GTS9_ANA38407_AMSA10FA01.dat`
  (459,103 B — the 11" panel data file)
- `devices/gts9uwifi/skeleton/ramdisk-recovery-overlay/lib/firmware/GTS9_ANA38407_AMSA10FA01.dat`
- `devices/gts9uwifi/skeleton/ramdisk-recovery-overlay/vendor/firmware_mnt/image/tsp_stm/fts1ba90a_gts9.bin`
  (11" STM touch firmware; the Ultra is Goodix)

Impact: cosmetic-to-confusing on the Ultra (wrong-panel .dat shipped where
request_firmware can find it; wrong-device touch fw in recovery), and it
**propagates into the gts9p skeleton fork**, whose checklist is a blanket
`sed s/gts9u/gts9p/` + file renames (build-gts9pwifi.sh:18–23) that touches none
of these. Related asymmetry: no `GTS9U_ANA38407_AMSA46AS02.dat` exists anywhere in
the skeleton overlay/ramdisk firmware dirs (**VERIFIED** dir listings) — the Ultra
relies on the compiled-in `_PDF.h`; the 11" build is the only one shipping its
panel .dat at runtime firmware paths. For gts9p, note the recovery touch fw it
would actually want is `tsp_stm/fts1ba90a_gts9p.bin` (hw-findings line 12), not
the `_gts9.bin` the fork would inherit.

Also stale-adjacent (minor, VERIFIED): `skeleton/overlay/system/usr/lib/udev/rules.d/74-gts9-wacom.rules`
is family-named (gts9-) — likely intentional/harmless, listed for completeness.

## 7. Audio (scope-limited kernel/techpack view)

- Kernel side needs NO per-device import: audio-kernel Makefile.include family
  filter includes gts9uwifi; one shared `kalama_gts9.conf` covers all six boards
  (IMPORT-GUIDE 50–51 — REPORTED, techpack itself not in this repo).
- The audio *fix chain* is overlay/userspace and is enforced by both build
  scripts' fatal sanity gates (**VERIFIED**: build-gts9uwifi.sh:136–157,
  build-gts9pwifi.sh:158–180 — bringup script, virtual-h2w, systemd wants links,
  PA drop-in, modules.load dedupe, finit stage). Skeleton carries the payloads
  (**VERIFIED**: overlay/system/usr/local/sbin/gts9u-audio-bringup,
  usr/local/lib/gts9u-virtual-h2w.py). gts9p inherits via the skeleton fork.
- gts9wifi (11"): audio fix exists only as the on-device virtual-h2w workaround;
  every fresh cut from Azkali's 2026-07-28 snapshot re-breaks (PA-droid 14.2.109 —
  REPORTED, PORT-STATE §1). Upstream bump is open ledger item #1.

## Verdict summary

| Area | gts9wifi (11") | gts9pwifi (S9+) | gts9uwifi (Ultra) |
|---|---|---|---|
| Panel in Kbuild | azkali-native GTS9 | GTS9+GTS9P (bundle) | GTS9+GTS9U (bundle) — **conflicts with gts9p bundle on shared tree** |
| Touch | STM native; **Goodix-rev units unfixed, fix stranded in gts9u-imports** | STM native, fatal-checked | goodix import, fatal-checked |
| Pen wiring | in CI build? (unverified) | **NOT in bundle, warn-only check — gap** | wired + compile-proven |
| DTS revs | 4 native | r00/r02/r04 present | r00/r03 present |
| WLAN | kiwi_v2 (no IPA patch?) | kiwi_v2 + IPA patch (script) | kiwi_v2 + IPA patch (deviceinfo:25) |
| Audio chain | on-device workaround only | gated in script (needs skeleton fork) | gated + shipped |
| Stale files | — | inherits skeleton staleness | **F5 prune NOT done (3 files)** |
