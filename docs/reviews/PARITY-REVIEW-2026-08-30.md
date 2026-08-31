> **HISTORICAL SNAPSHOT — pre-remediation audit.** This is the parity review
> exactly as produced on 2026-08-30, BEFORE the same-day five-tier
> remediation (commits ed6fd72, 0e9db09, 2b5b919, 7ef9ffc, 44a27dd + the
> verification-fix commit). Present-tense findings below (4500M deviceinfo,
> missing post-flash script, absent apt pin, tp default 0, divergent swap
> scripts, ...) were TRUE THEN and are FIXED NOW — current truth is
> `docs/knowledge/PORT-STATE.md` §6–§7. The pristine capture copy lives at
> `archive/notes/parity/PARITY-REVIEW.md`.

# Three-device parity review — gts9wifi / gts9pwifi / gts9uwifi

Synthesis of audit passes A–G (2026-08-30), files `A-` through `G-` in this directory.
Repo root `$R` = `/home/jstockdale/projects/ubuntu-touch-gts9`; skeleton `$SK` =
`$R/devices/gts9uwifi/skeleton`. Every claim is tagged **VERIFIED** (a file was read in
this audit — the loudest ones re-verified in this synthesis pass) or **REPORTED** (a
doc/notes file claims it; on-device state is inherently REPORTED — no device was attached).

---

## 1. Verdict

**Yes, all three devices are missing things — but the audio fix itself is in good shape
on the two devices that exist.** The Ultra has the full five-bug audio chain baked into
its skeleton, verified end-to-end on disk. The 11" has its one audio bug (#4, extevdev)
fixed, installed, and cold-boot validated. The S9+ has nothing yet (the port is
unexecuted) but its build script hard-gates the entire renamed audio chain, so it cannot
build without it.

The real findings are of three kinds:

1. **The 11" (daily driver) is one lost boot race from persistent audio death.** Its
   `modules.load` carries the same confirmed 4× duplication (457 lines / 357 unique,
   measured on-device — REPORTED `audio-cluster.notes.md:59`) that caused the Ultra's
   no-audio hunt, and it has **zero** latch-clear / HAL-restart protection. One lost
   va-macro race → AGM timeout → `vendor.audio.use.primary.default=true` latches
   persistently → audio dead on every subsequent boot with no installed recovery.
2. **A fresh Ultra rebuild+reflash would regress the device.** The skeleton is missing
   several device-live fixes (root-LP resize, touchpad rotation, WiFi modules-load,
   LimitNOFILE, apt pin), so the "canonical" build is behind the running device.
3. **The gts9p fork would inherit every skeleton gap plus a broken flash-script device
   check** (uppercase X910/GTS9U tokens survive the lowercase rename seds — including a
   warn-and-proceed path that could flash X810 firmware onto an Ultra).

### Top 5 actions

| # | Action | Why now |
|---|---|---|
| 1 | **Send the two upstream patches** — the pulseaudio-modules-droid ≥ 14.2.110 bump/dfda983 ask to Azkali/UBports, and the hidl_compat shim null-deref patch to Halium. Both sit finished with field reports in `$R/patches/upstream/` (both READMEs: "Status: UNSENT"). | The only path that retires audio bug #4 and defuses bug #3 on all three devices at once. Highest leverage per keystroke in the whole project. |
| 2 | **Do not reflash the Ultra from a fresh build until the root-LP resize is baked into `super.sh`** (system LP ~8e9 budget, group = super capacity). VERIFIED unbaked: `$SK/deviceinfo:34` still `4500M`; both `super.sh` copies stat-size + sum-group. A reflash today shrinks root back to ~4.5 GB/100 % full and resurrects the deleted One UI partitions. | PORT-STATE §6 #5, confirmed by audits E and G. |
| 3 | **Harden the 11" preventively**: at minimum the ~20-line latch-trap closure (dedupe/walker + unconditional `setprop vendor.audio.use.primary.default false` + conditional HAL restart), packaged into the existing self-copying installer. Justified by on-device measurement, not speculation (audit D §3). | Daily driver; failure mode is persistent and has no installed recovery. |
| 4 | **Close the gts9u skeleton gaps BEFORE executing the gts9p fork** (list in §4b) — otherwise the S9+ starts life with the full inherited orphan debt. | The fork is a blanket copy+sed; every gap propagates. |
| 5 | **Create the consolidated post-flash script** that CONTRIBUTING.md rule 1 names but which does not exist (VERIFIED: no post-flash artifact anywhere): audio installer + apt pin + LimitNOFILE + pen rule + touchpad daemon + journald, per device. Two of its items (apt pin, LimitNOFILE) currently have **no artifact file at all, anywhere**. | The 2026-08-29 flash + userdata wipe already destroyed the entire on-device fix set once. |

---

## 2. Parity matrix

Status legend: **SKEL** = baked in the Ultra skeleton overlay (survives reflash of a
repo-built image) · **INST** = repo installer, must be rerun after reflash/OTA ·
**DATA** = lives on userdata only (survives reflash, dies on wipe) · **VOLATILE** =
rootfs-on-device only, dies on every reflash · **PLAN** = planned/gated but nothing on
disk (gts9p has no skeleton — VERIFIED `devices/gts9pwifi/` has no `skeleton/`) ·
**MISSING** = expected but absent · **N/A** = not needed (reason given) ·
**⬆X** = a better version exists at X.

### 2a. Audio — the five-bug chain plus supporting pieces

| Fix | gts9wifi (11", Azkali image) | gts9pwifi (S9+, unexecuted) | gts9uwifi (Ultra) |
|---|---|---|---|
| **#1 storm: boot module-walk** | **MISSING** — amplifier CONFIRMED on device (457/357 lines, REPORTED); no walker, no guard | PLAN (fork; gated `build-gts9pwifi.sh:164–180`) | **SKEL** VERIFIED `$SK/overlay/system/usr/local/sbin/gts9u-audio-bringup:21–36` |
| **#1 storm: build-time modules.load dedupe** | N/A directly (Azkali builds the image) — the right shape is an upstream ask | PLAN (staged swap script, gate `:176`) | **SKEL** VERIFIED `$SK/scripts/swap-vendor-modules.sh:22–29`, invoked `build.sh:28`, gated `build-gts9uwifi.sh:153` |
| **#2 latch clear** (`vendor.audio.use.primary.default`) | **MISSING** — currently unset on device but no clearing mechanism exists; the trap is armed | PLAN (property name survives rename) | **SKEL** VERIFIED bringup `:79–83` (post-ONLINE, ≤60 s FATAL) |
| **#3 shim null-deref patch** | **MISSING everywhere** — patch VERIFIED at `$R/patches/upstream/halium-audio-hidl-compat/0001-…patch` but **UNSENT, deployed nowhere**; the only shim binary in the repo is the stock evidence copy (`archive/binaries/MANIFEST.md`). All three devices rely on prevention. | same | same |
| **#4 extevdev jackless abort (virtual-h2w)** | **INST+DATA hybrid** VERIFIED `$R/fixes/audio/gts9-audio-fix-install.sh` — version-gated (refuses ≥ 14.2.110), cold-boot validated 2026-08-29/30 (REPORTED). Daemon+unit rootfs (die on reflash), gate+self-copy userdata (died once in the 08-29 wipe). ⬆version-gating is the more polished pattern | PLAN (Ultra mechanism renamed; every filename asserted `build-gts9pwifi.sh:172–175`) | **SKEL** VERIFIED daemon+unit+wants-symlinks+bringup jack-wait `:97–100`. ⬆11" for the version gate; ⬆11" units for `ExecStartPre=-modprobe uinput` (Ultra unit lacks it) |
| **#5a stale-HAL restart post-ONLINE** | PARTIAL/N-A-today — Azkali's `50-gts9wifi-wait-audiohal.conf` waits but never restarts; likely near-fail-open (`$c` mangling + `-` prefix, mechanism doc) | PLAN | **SKEL** VERIFIED bringup `:85–91` |
| **#5b chmod 0666 card_state/aud_dev** | **MISSING** (probably latent-N/A on container path; but uid-1013 EACCES oddity parked, `audio-cluster.notes.md:115`) | PLAN | **SKEL** VERIFIED bringup `:77` |
| **PA hard gate** (`/run/*-audio-ready`, no `-`) | N/A by design — 11" philosophy is fail-open (its only bug is the abort itself) | PLAN (content gated `:175`) | **SKEL** VERIFIED `zz-gts9u-audio.conf:5` re-verified this pass: no `-` prefix |
| **touch.pa hidl_compat line** | ships in Azkali image | PLAN (path `etc/pulse/gts9/` is family-generic, no rename needed) | **SKEL** VERIFIED `touch.pa:47` (primary-edit regression reverted) |
| **Storm telemetry** (`+N inserted` log line) | **MISSING** — no storm sensor at all | PLAN | **SKEL** (bringup log line) |

### 2b. Input — pen, touch, touchpad

| Fix | gts9wifi | gts9pwifi | gts9uwifi |
|---|---|---|---|
| **Pen→touchscreen reclass** (udev rule + libinput quirk) | **VOLATILE + persistence UNCONFIRMED** — `72-gts9wifi-spen.rules` REPORTED installed 08-27/28, but `pen-cleanup.sh` (which persists it) never confirmed run; pen may be inert since. Rule text survives only in `archive/pen-investigation/`; `fixes/input-pen/README.md` VERIFIED "no standalone installer here" | PLAN (renamed `61-gts9p-pen.rules` gated `:178`) | **SKEL** VERIFIED `61-gts9u-pen.rules` + quirk with AttrEventCode strip |
| **Pen calibration** `74-gts9-wacom.rules` | in Azkali image? (rule header says "shared by gts9wifi/gts9uwifi") | PLAN (family-named, untouched by rename — correct) | **SKEL** VERIFIED |
| **Touch calibration matrix** `0 1 0 -1 0 1` | Azkali-native | PLAN — matrix is **family policy** (same panel mount, audit B), expected correct; confirm at bring-up rung 2 | **SKEL** VERIFIED `71-gts9uwifi-touch-calibration.rules` |
| **Touchpad rotation daemon** (gts9u-tp-rotate v0.1, name-generic) | **MISSING — never installed** though it transfers unchanged (`sec_touchpad_pogo` identical) | PLAN — runbook rung 6 "carries over" is **misleading**: it is a manual post-flash install | **INST only** — VERIFIED at `$R/fixes/input-touchpad/gts9u-tp-rotate/` but NOT in skeleton; **and the shipped default is wrong**: `gts9u-tp-rotate.default:6` = `GTS9U_TP_DEFAULT=0`, the silicon-proven value 270 lives only on-device |
| **DTS `touchpad,invert`** | n/a | stock values VERIFIED (`r04.dts:10424`) | **MISSING from repo** — imports r00/r03 VERIFIED stock `<0x00 0x01 0x01>`; the sed'd `<0x01 0x00 0x00>` exists only in the pika working tree → **repo and pika build different DTBOs** (deliberately deferred per peripherals notes, but PORT-STATE §6 #6 still lists it open — reconcile either way) |
| **Goodix berlin touch import** | fix for Goodix-rev 11" units sits **finished but stranded** in gts9u-imports — no delivery path, no ledger item (John's unit is STM-rev, unaffected) | N/A — S9+ is STM (goodix DT node is inert cruft, hw-findings); `stm_ts_fts1b90a.ko` missing = build-FATAL | **SKEL/imports** VERIFIED full source + Kconfig/Makefile wiring + config append, build-gated |
| **Wacom wez01 kernel wiring** (Kconfig/Makefile 2-file merge) | in CI build? (unverified — wez01.ko loads clean, REPORTED) | **MISSING from bundle** — gts9p-imports has NO drivers/input files; build checks (`:151,153`) were already true when the symbol "sat inert"; missing wez01.ko is **warn-only** (`:216`) → first S9+ build could silently ship no pen module | **imports** VERIFIED both merged files; ⬆donor for gts9p |

### 2c. Boot / power / container

| Fix | gts9wifi | gts9pwifi | gts9uwifi |
|---|---|---|---|
| Charger-mode bootconfig filter | N/A — Azkali's build boots cabled fine | PLAN | **SKEL** VERIFIED `start-android-container:20–48` + service drop-in |
| Stale `/dev/__properties__` clean | N/A — never exhibited the SEGV; keep as known remedy, don't port proactively | PLAN | **SKEL** VERIFIED `:14–18` ("family-portable") |
| UPower `CriticalPowerAction=Ignore` + sm5714 modules-load | MISSING (low priority — fuel gauge honest on this device) | PLAN | **SKEL** VERIFIED |
| repowerd battery/backlight waits, logind ignores | Azkali's own | PLAN | **SKEL** VERIFIED |
| Persistent journald tmpfiles.d | **MISSING** — 11" debugging repeatedly hit volatile early-boot logs | PLAN | **SKEL** VERIFIED `gts9uwifi-journal.conf` |
| **WiFi modules-load persistence** (cfg80211 + qca_cld3_kiwi_v2) | Azkali-native | inherits the gap | **MISSING from skeleton** — re-verified this pass: `modules-load.d/gts9uwifi.conf` carries ONLY the sm5714 pair; on-device `gts9u-wifi.conf` is orphaned. PORT-STATE §1's "persisted in modules-load.d" is **false for the skeleton**. Virgin-flash WiFi outage risk |
| **Root-LP resize** (system 4.5→6.2 GB) | N/A (Azkali sizes his super) | inherits — and must use SUPER=11,714,691,072 | **MISSING from pipeline** — re-verified: `deviceinfo:34` `4500M`; no lpmake budget anywhere. Lives on-device only; **reflash = regression** |
| BT HAL crash-loop / GPS AIDL mismatch / 2.x boot-hang | diagnosis-only, **zero remediation in repo**, outcomes uncaptured (11"-unique opens) | — | — |

### 2d. Hygiene / userland

| Fix | gts9wifi | gts9pwifi | gts9uwifi |
|---|---|---|---|
| **LimitNOFILE=65536 greeter drop-in** | **DATA only** (REPORTED created 08-30, `~/.config/systemd/user/...60-nofile.conf`); no repo artifact | inherits gap | **MISSING** — re-verified: no LimitNOFILE anywhere in skeleton |
| **Desktop-Qt5 apt pin** `no-desktop-qt5` | **MISSING — likely nowhere.** Re-verified: no artifact file in repo (prose only in docs); on-device creation never confirmed (lomiri-crash p2). The daily-driven, apt-tinkered 11" needs it most | inherits gap | **MISSING** |
| GLES-Qt state post-krita incident | REPORTED recovered manually, exact steps uncaptured; krita/xinput possibly still on rootfs — verify `dpkg -l` shows only `-gles` rows | n/a | n/a |
| `aud_pasthru_adsp` GROUP fix | n/a | inherits bug | **MISSING + bug still shipped** — re-verified `70-gts9uwifi.rules` `aud_pasthru_adsp ... GROUP="system"` (ueventd "system audio" mistranslated; should be GROUP="audio"); on-device `71-gts9u-audiofix.rules` never entered the repo; wider group-mistranslation sweep never done |
| Cosmetic identity | — | fork would self-describe as "Tab S9 Ultra" (deviceinfo_name/PrettyName contain no `gts9u` string); X910 PIT file rides along | **SM-X710 strings in Ultra skeleton** — `usb-moded.d/device-specific-config.conf:10` and `gts9-adb-gadget:45` say SM-X710 (Ultra is X910) |
| Stray artifacts | — | inherits all | `__pycache__/*.pyc` shipped in overlay; duplicate `qrng_dlkm.ko` in vendor-ramdisk `modules.load`; **F5 stale files still present** (re-verified: 2× `GTS9_ANA38407_AMSA10FA01.dat` + `tsp_stm/fts1ba90a_gts9.bin` — 11" panel data + STM touch fw in the Goodix Ultra's skeleton) |

### 2e. Build system & flashables

| Item | gts9wifi | gts9pwifi (V4) | gts9uwifi (V3) |
|---|---|---|---|
| Audio-chain FATAL build gates | n/a (Azkali) | VERIFIED `:158–180` — would loudly catch a pre-audio or mis-renamed fork | VERIFIED `:136–157` |
| `50-*-wait-audiohal` negative gate | n/a | **MISSING** (⬆V3 `:152` has it; the runbook sed would rename a stale copy right past V4) | VERIFIED |
| SUPER geometry | 11,643,387,904 (REPORTED, not our pipeline) | `export SUPER=11714691072` at `:227` (⬆pattern worth backporting) + x810-extract byte-exact check | implicit skeleton default 11744051200 — correct value, fragile mechanism |
| **Leftover-audit swap script (F2 v2)** | n/a | **NOT USED** — both builds stage the audio-era dedupe-only script; the v2 audit+allowlist sits unused in `common/scripts/` (re-verified: staged copy has `seen[$0]`, no LEFTOVER; common copy has audit, no dedupe — neither is a superset). **Both build scripts carry FALSE comments claiming the audit runs** (V3:179–181, V4:201–203). Worst for the S9+: its X810 module set has never been triaged | same |
| super.sh / make-flashable v2 (strict mode, zstd hard-require) | n/a | staged copies are the weaker originals; ⬆`common/scripts/` v2 both | same |
| lpmake system/group budget | n/a | absent | **absent — the reflash-regression trap** (§1 action 2) |
| **update-binary device check** | n/a (Azkali zip) | **BROKEN post-fork**: lowercase seds miss uppercase `X916`/`X910`/`*GTS9UWIFI*`/`*GTS9U*` (re-verified in `$SK/flashable/.../update-binary:46–58`) → no X810 verified-pass, **no X816 (5G S9+) rejection**, and a warn-and-proceed path that could flash X810 firmware onto an Ultra. No build gate touches `flashable/`; no gts9p doc mentions update-binary at all | v4 (F1) VERIFIED: zstd `-t` pre-pass, marker files, staged writes — device-neutral mechanics are the family best |
| kiwi_v2 IPA-offload-off patch | **not in Azkali's build** (as far as repo shows) | VERIFIED `:130–147` | VERIFIED `:108–129` |
| Panel Kbuild | Azkali-native GTS9 | GTS9+GTS9P — cleaner `_GTS9P`-suffixed merge style (⬆template) | GTS9+GTS9U (unsuffixed vars) — **the two bundles whole-file-overwrite `msm/Kbuild` and conflict on a shared tree** (moot today: fresh clones per build) |
| DTS board-rev coverage | 4 revs native | r00/r02/r04 present, r04 gated | r00/r03 present — parity OK |

### 2f. Docs / runbooks

| Item | Status |
|---|---|
| gts9pwifi runbook Phase 0.1/1 tarball name | **names the PRE-audio artifact** (`gts9uwifi-skeleton.tar.gz` = the file archived as `archive/superseded/gts9uwifi-skeleton-orig.tar.gz`); author demonstrably meant the audio-era skeleton (`devices/gts9uwifi/skeleton/`). Build gates catch the mistake, but only after Phase 1–3 effort |
| Runbook 1.3 leftover check | case-sensitive `grep -rn gts9u` — reports "clean" while uppercase tokens survive; should be `grep -rni 'gts9u\|x910'` |
| Runbook 1.4 display scaling | dead end — **no GRID_UNIT/scale knob exists anywhere in the skeleton** (VERIFIED empty grep); a knob must be *added*, not found |
| Post-flash script | prescribed by CONTRIBUTING.md rule 1, **does not exist** |

---

## 3. Contradictions and errors in the prior record (caught by the audits, re-verified where load-bearing)

1. **PORT-STATE §4 overstates two "landed" items.** F5 (stale-file prune) was never
   executed — all three stale files re-verified present in `$SK` this pass. The
   desktop-Qt5 apt pin is listed as a landed fix but exists nowhere as a file, and the
   underlying transcript records it as prescribed-not-confirmed-applied on-device.
2. **PORT-STATE §1 "WiFi persisted in modules-load.d" is false for the skeleton** — the
   skeleton `modules-load.d/gts9uwifi.conf` carries only the sm5714 pair (re-verified);
   the WiFi conf is an on-device orphan.
3. **Both build scripts' comments lie about the module audit** (`build-gts9uwifi.sh:179–181`,
   `build-gts9pwifi.sh:201–203` claim swap-vendor-modules.sh "audits leftovers … see
   scripts/swap-allowlist.txt") — the staged script has no audit and no allowlist exists
   in the skeleton. And `common/scripts/README.md:22` claims the dedupe+audit merge is
   "tracked in the open-issues ledger" — **PORT-STATE §6 has no such item** (orphaned
   tracking claim). Also its "reviewed X910 allowlist" is an empty template below line 20.
4. **The "Ultra's 4× modules.load duplication was our own pipeline artifact" hypothesis
   is falsified** — the 11" running Azkali's untouched image measured 457/357 on-device
   (REPORTED `audio-cluster.notes.md:59`). The amplifier is in the stock/vendor list.
5. **Runbook errors**: pre-audio tarball filename (§2f); "scaling knob" that doesn't
   exist; rung-6 "touchpad rotation quirk carries over" (it's a manual post-flash
   install); Phase-1.1 second sed (`x910→x810` in build.sh) is a no-op — `x910` appears
   nowhere in the skeleton (it lives in the Ultra's wrapper, outside the fork).
6. **Version-label drift**: on-disk bringup header says "v3" (re-verified line 2) but the
   content carries the v4 "finit stage" fingerprint (line 68); `fixes/audio/README.md`
   calls it v4. Content is v4; header comment is stale.
7. **Doc contradiction on the macro set**: `gts9u-audio-online-mechanism.md` names
   va/wsa/wsa2 as the card-gating macros; PORT-STATE §3 + the KT doc say va/rx/tx
   (wsa/wsa2 disabled in DT). Operationally moot (the bringup walks the whole list), but
   one doc is wrong; PORT-STATE is the later synthesis.
8. **Wrong-model strings**: `PRODUCT=SM-X710` in the Ultra skeleton's
   `usb-moded.d/device-specific-config.conf:10` and `gts9-adb-gadget:45` (cosmetic
   USB-identity; shows family copy-through, and would propagate to gts9p un-fixed).
9. **Obsolete TODOs in PORT-STATUS §13**: pen-battery udev hide and phantom power-key
   hunt — root cause was the sm5714 fuel gauge at 0 % (no pen power_supply exists on the
   Ultra); drop both.
10. **Repo installer vs device reality**: `fixes/audio/gts9-audio-fix-install.sh` is a
    documented *reconstruction* — the cold-boot-validated on-device originals were never
    archived or diffed (layout drift is documented: daemon path and gate filename differ
    between the Aug-29 notes and the repo script). The device copy should win the diff.

---

## 4. Prioritized recommendations

### 4a. Must-do before the next flash of each device

**gts9wifi (11", daily driver) — before the next reflash/OTA, and mostly doable now:**
1. Create and commit the **consolidated post-flash script** (audio installer + apt pin +
   LimitNOFILE drop-in + pen masquerade rule + touchpad daemon + journald tmpfiles.d +
   optional UPower seatbelt + RTL-SDR rule), self-copying to `/home/phablet` like the
   audio installer — and keep a copy off-device (the 08-29 wipe took everything once).
2. Actually create `/etc/apt/preferences.d/no-desktop-qt5` on the device (treat as
   absent until proven otherwise) and commit the pin file to `fixes/`.
3. Port the **bugs-1/2/5 minimal hardening** (audit D §3 gives the three required
   adaptations: jack-device name `gts9-` vs `gts9u-`; mask Azkali's `50-…wait-audiohal`
   drop-in to avoid double-ExecStart roulette; keep the fail-open gate philosophy).
4. On next device access: archive the live audio-fix artifacts and diff against the repo
   installer (device wins); verify pen survives a reboot (run `pen-cleanup.sh` default
   mode if not); confirm `dpkg -l` shows only `-gles` Qt rows and whether krita/xinput
   remain; capture the BT crash-loop state after a full power-off cold boot.
5. Install the touchpad rotation daemon (`fixes/input-touchpad/gts9u-tp-rotate/install.sh`,
   default 270) — folio pad is name-identical.

**gts9uwifi (Ultra) — before any rebuild+reflash:**
1. Bake the **root-LP resize** into the pipeline (system ~8e9 budget or drop
   product/system_ext + grow-to-fill; group = super capacity; per-device SUPER).
   Until then, treat Ultra rebuilds as regressive.
2. Add `cfg80211` + `qca_cld3_kiwi_v2` to `$SK/overlay/system/etc/modules-load.d/gts9uwifi.conf`.
3. Fold the three device-live fixes into the skeleton: touchpad rotation (daemon in
   overlay, or land the DTS `touchpad,invert` after reading the stm32_pogo parser —
   reconcile the pika-tree drift either way), LimitNOFILE=65536 greeter drop-in, apt pin.
4. Fix `70-gts9uwifi.rules` `aud_pasthru_adsp` to `GROUP="audio"` and sweep the file for
   other ueventd group mistranslations.
5. Set `gts9u-tp-rotate.default` to 270 with a provenance comment.
6. Housekeeping: F5 prune (3 stale files), `__pycache__` removal, SM-X710→SM-X910
   strings, dedupe the vendor-ramdisk modules.load, bump the bringup header v3→v4,
   `ExecStartPre=-modprobe uinput` on the h2w unit. One-time on-device debris sweep per
   G §3 (old logind/modules-load/audio units; keep `/var/log/journal` and the renamed LP
   metadata backup).

**gts9pwifi (S9+) — before executing the port:**
1. **Rewrite the forked update-binary device check** (verified-pass X810; hard-reject
   X916, X910, **X816**; `*GTS9PWIFI*`/`*gts9pwifi*` patterns) and add a build gate over
   `flashable/` (e.g. `grep -q X810` + `! grep -q GTS9UWIFI`) next to lines 163–179.
2. Fix the runbook: point Phase 0.1/1 at `devices/gts9uwifi/skeleton/` (the `-orig`
   tarball is a live foot-gun under exactly the name the runbook asks for); make the
   leftover check case-insensitive; rewrite 1.4 (add a grid-unit drop-in, don't hunt for
   one); reword rung 6 (touchpad daemon is a post-flash install).
3. Close the **pen-wiring hole**: add wacom-only merged `drivers/input/{Kconfig,Makefile}`
   to gts9p-imports (do NOT copy the touchscreen/Kconfig goodix `source` line without
   the goodix dir — parse error), or at minimum a fatal
   `grep -q 'wacom/Kconfig' $KDIR/drivers/input/Kconfig` gate; verify whether Azkali's
   current HEAD has since gained the wiring (the 11" CI image's clean wez01.ko load
   suggests it may have).
4. During the fork: fix identity strings ("Tab S9+ 12.4″"), replace/delete the X910 PIT,
   sed super.sh's default to 11714691072, source `fts1ba90a_gts9p.bin` for the recovery
   tsp_stm path (the sed cannot fix a binary's filename), add the
   `50-gts9pwifi-wait-audiohal.conf` negative gate, and run the L158–180 audio greps as
   the fork acceptance test.
5. Do all of §4a-Ultra items 2–6 in the gts9u skeleton **first** so the fork inherits a
   clean baseline.

### 4b. Merges / backports between builds

1. **Merge the two swap-vendor-modules.sh generations** (v2 audit+allowlist + audio-era
   dedupe+xattr; keep the literal `seen[$0]` so both build gates still pass — exact
   10-point feature list in audit E §Q3), stage into both skeletons with per-device
   allowlist files, and fix the false "audits leftovers" comments. Highest value before
   the S9+'s never-triaged first build. Add it as a real PORT-STATE §6 ledger item.
2. Promote `common/scripts/` v2 `super.sh` and `make-flashable.sh` into both skeletons
   (strict mode; zstd hard-require closes a flash-time abort path).
3. Backport `export SUPER=11744051200` into `build-gts9uwifi.sh` stage 6 (V4's explicit
   pattern).
4. Version-gate pattern (11" installer) and `modprobe uinput` belt → future skeletons;
   Ultra's storm-telemetry log line → any 11" ported bringup.
5. Eventually: a three-panel merged `msm/Kbuild` (GTS9 + GTS9P + GTS9U, all
   `_SUFFIXED` in the gts9p style) so the two import bundles stop being mutually
   exclusive whole-file overwrites; until then document loudly that they must never be
   applied to the same checkout.

### 4c. Upstream submissions (all deliverables already exist; the send is the missing step)

1. `pulseaudio-modules-droid-30` ≥ 14.2.110 bump / dfda983 cherry-pick → Azkali/UBports
   (`patches/upstream/pulseaudio-modules-droid/` + field report). Retires audio bug #4
   family-wide.
2. hidl_compat shim null-deref patch → Halium
   (`patches/upstream/halium-audio-hidl-compat/` + crash analysis). Defuses bug #3
   everywhere.
3. Goodix berlin import + touchscreen wiring + `CONFIG_TOUCHSCREEN_GOODIX_BRL=m` →
   Azkali's kernel tree (fully formed in gts9u-imports; currently **stranded with no
   ledger item** — add one). Gives Goodix-rev 11" units working touch.
4. kiwi_v2 IPA-offload-off defconfig patch → Azkali (present in both our build scripts,
   apparently absent upstream).
5. Modules.load dedupe ask + apt-pin image hardening → Azkali (one-liners, ride along
   with #1).

### 4d. Nice-to-have

- Regenerate the pulse policy XMLs from X910 vendor audio configs (PORT-README TODO —
  audio works with the family copies).
- Decide the recovery-touch question: whether TWRP touch matters enough to ship the
  right per-device firmware (Goodix for Ultra recovery, `fts1ba90a_gts9p.bin` for S9+)
  or document the IC-resident-fw reliance.
- Document the panel-`.dat` asymmetry (11" ships it at request_firmware paths; Ultra
  relies solely on the compiled-in `_PDF.h`).
- Mark the `gts9-virtual-h2w/` variant's hard-fail 55- gate as superseded to prevent a
  future double-install; reconcile the va/rx/tx vs va/wsa/wsa2 doc contradiction.
- GPS (AIDL gbinder client or gpsd discriminators) and BT crash-loop remediation —
  currently diagnosis-only with zero repo-side code; queue behind the items above.
- Watch item: `/userdata/vendor_dlkm.img` lives on userdata — confirm after the next
  flash which copy the Ultra actually mounts (`findmnt /android/vendor_dlkm`); a Format
  Data could silently revert the module set.
