# SYNTHESIS: git repo proposal — Ubuntu Touch on Galaxy Tab S9 family

Goal: a single durable home for the whole three-device UT port (gts9wifi/SM-X710,
gts9pwifi/SM-X810, gts9uwifi/SM-X910) with room for the 5G variants (X716/X816/X916),
mapping every artifact currently under `_capture/files/`. Based on the 28-thread synthesis
(`SYNTHESIS-port-state.md`) and the three RECON passes (`RECON-build-scripts.md`,
`RECON-skeletons.md`, `RECON-fixes-catalog.md`).

---

## 1. One repo, not many — argued from the evidence

**Decision: a single monorepo `ubuntu-touch-gts9`.**

The evidence is overwhelmingly on the side of shared lineage over per-device divergence:

- **One kernel binary, one build lineage.** All three tablets are SM8550/kalama; Azkali's
  `kernel-samsung-gts9wifi` @ `android13-5.15-halium` builds for the whole family, and NinjaSU
  proves an X710-source kernel runs on X910 and X916C. `[SYNTHESIS §0]`
- **The build scripts are a single linear chain, not forks.** `RECON-build-scripts.md` proves
  `build-gts9uwifi.sh` has only 4 distinct versions across 7 captured copies, a clean V1→V2→V3
  chain, and `build-gts9pwifi.sh` (V4) is a *device fork of V3*, not a competing tree. The
  gts9pwifi script retains all V2/V3 hardening verbatim; the only diffs are device-specific
  (names, touch IC, panel string, SUPER size). A monorepo lets a fix in the shared core propagate
  to all three; separate repos would force manual back-porting (which `RECON` notes has *already*
  become a hazard — "any future gts9uwifi improvement discovered during gts9p work would need
  manual back-porting").
- **The device skeletons are near-identical.** The gts9p skeleton is literally
  `sed s/gts9u/gts9p/g` + file renames of the gts9u skeleton. `[RECON-build-scripts]`
- **Fixes are overwhelmingly device-agnostic or family-shared.** The five-bug audio chain, the
  two upstream patches, the S-Pen finit/quirk/udev approach, the touchpad daemon (name-generic —
  works on any `sec_touchpad_pogo` device), the boot patchers, the LP/extract tools, the whole
  knowledge-transfer corpus — all cross devices. Only the panel/touch/DTS/SUPER-size constants
  are per-device. `[RECON-fixes-catalog "Device targeting at a glance"]`
- **The docs are already written as family knowledge.** `gts9-audio-knowledge-transfer.md` was
  authored on the Ultra explicitly to hand findings to the 11"; `gts9-spen-porting-guide.md`
  targets "the family". Splitting them across repos would strand the shared playbooks.

Per-device isolation is confined to a thin `devices/<codename>/` layer (panel string, touch IC,
DTS, PIT, SUPER constant, skeleton overrides). That is exactly the axis a monorepo's `devices/`
subtree expresses cleanly. A polyrepo would duplicate the shared 90% three ways.

**Room for 5G variants:** add `devices/gts9-5g/{gts9,gts9p,gts9u}5g/` when the time comes — same
kernel, new PIT/DTS/firmware-code, and the update-binary already knows to reject X916 on the WiFi
flashers (so the guard logic is already family-aware). No structural change needed.

---

## 2. Full directory layout (every captured artifact mapped)

```
ubuntu-touch-gts9/
├── README.md                      # project overview, device matrix, quick-start, status badges
├── CONTRIBUTING.md                # persistence discipline, /data rules, "no desktop-GL in rootfs"
│
├── common/                        # everything shared across all three (+future 5G) devices
│   ├── build/
│   │   └── build-gts9.sh          # (future) parameterized core the per-device wrappers call;
│   │                              #   for now the per-device wrappers live in devices/ (see note)
│   ├── scripts/                   # the shared build-stage scripts (currently duplicated per skeleton)
│   │   ├── super.sh               #  <- ultra-main/outputs/gts9u-fixes/.../scripts/super.sh (v2)
│   │   ├── make-flashable.sh       #  <- ultra-main/.../scripts/make-flashable.sh (v2)
│   │   ├── swap-vendor-modules.sh  #  <- CANONICAL = the +dedupe copy inside the audio skeleton
│   │   │                          #     tarball; the loose gts9u-fixes copy is one gen behind
│   │   └── swap-allowlist.txt      #  <- ultra-main/.../scripts/swap-allowlist.txt
│   └── overlay-template/          # device-agnostic overlay pieces the skeletons share
│
├── devices/
│   ├── gts9wifi/                  # Tab S9 11" / SM-X710  (Azkali's reference; user daily-drives)
│   │   ├── README.md              # what's Azkali's vs ours; audio = only bug #4; GPS/BT open
│   │   └── reference/             # (identity data only — Azkali owns the device tree upstream)
│   │
│   ├── gts9pwifi/                 # Tab S9+ / SM-X810  (port kit complete, UNEXECUTED)
│   │   ├── README.md
│   │   ├── build-gts9pwifi.sh     #  <- tabS9plus-port/outputs/build-gts9pwifi.sh  (V4, canonical)
│   │   ├── imports/               #  <- unpack tabS9plus-port/outputs/gts9p-imports.tar.gz (26 files)
│   │   ├── docs/
│   │   │   ├── gts9p-hw-findings.md        #  <- tabS9plus-port/outputs/
│   │   │   └── gts9pwifi-port-runbook.md   #  <- tabS9plus-port/outputs/
│   │   └── reference/
│   │       ├── GTS9PWIFI_EUR_OPEN.pit                       #  <- tabS9plus-port/outputs/
│   │       └── dts/
│   │           ├── gts9pwifi_eur_open_w00_r04_A13-AWG1.dts  #  canonical
│   │           └── gts9pwifi_eur_open_w00_r04_MIRROR.dts    #  identity-ref only (~13% drift)
│   │
│   └── gts9uwifi/                 # Tab S9 Ultra / SM-X910  (lead port, ~fully working)
│       ├── README.md
│       ├── build-gts9uwifi.sh     #  <- CANONICAL = audio-config/outputs/build-gts9uwifi.sh (V3)
│       │                          #     (== tabS9plus-port/uploads/build-gts9uwifi__12_.sh)
│       ├── skeleton/              #  <- unpack audio-config/outputs/gts9uwifi-skeleton-audio.tar.gz
│       │                          #     (CANONICAL superset: samsung-gts9u/, 236 entries)
│       │   ├── deviceinfo, build.sh, .gitlab-ci.yml, GTS9UWIFI_EUR_OPEN.pit, vbmeta.img
│       │   ├── kernel-additions/halium.config.append
│       │   ├── overlay/system/...          # incl. the audio bringup + h2w + pen + PA-gate overlay
│       │   ├── scripts/                     # (or symlink to common/scripts once reconciled)
│       │   ├── vendorboot/, ramdisk-*-overlay/, vendor-ramdisk-overlay/
│       │   └── flashable/META-INF/.../update-binary   #  <- CANONICAL v4 from ultra-main/gts9u-fixes
│       ├── imports/               #  <- unpack porting-orig/outputs/gts9u-imports.tar.gz (50 files)
│       ├── docs/
│       │   ├── CHANGES-audio.md            #  <- audio-config/outputs/  (skeleton changelog)
│       │   └── gts9u-audio-online-mechanism.md  #  <- audio-config/.../gts9u-audio-fix/ (keystone)
│       └── reference/
│           └── (X910 PIT lives in skeleton/; keep OSRC provenance notes here)
│
├── fixes/                         # standalone, installable fixes (device-tagged in each README)
│   ├── audio/
│   │   ├── gts9-virtual-h2w/      #  <- unpack audio-trouble/outputs/gts9-virtual-h2w-workaround.tar.gz
│   │   │                          #     {gts9-virtual-h2w.py, .service, 55-*.conf, install.sh}
│   │   ├── gts9-audio-fix-install.sh   #  CANONICAL <- lomiri-crash/outputs/ (root-run, version-gated)
│   │   ├── gts9u-audio-fix/       #  v2-era standalone (mark SUPERSEDED by skeleton bringup)
│   │   │   ├── gts9u-load-audio-macros           #  <- audio-config/.../gts9u-audio-fix/
│   │   │   ├── gts9u-load-audio-macros.service
│   │   │   └── 50-gts9u-audio-wait.conf
│   │   └── apply-string-patch.sh  #  <- porting-orig/outputs/ (dedupe the audio-fix/ twin)
│   ├── input-pen/                 # the shipped S-Pen files (from the skeleton) + guide pointer
│   └── input-touchpad/
│       └── gts9u-tp-rotate/       #  <- unpack touchpad/outputs/gts9u-tp-rotate-v0.1.tar.gz
│                                  #     {gts9u-tp-rotate, gts9u-tp-orient, .service, .default,
│                                  #      install.sh, README.md}  (drop v0 tarball + loose .py)
│
├── patches/upstream/             # the highest-leverage artifacts — track submission status
│   ├── halium-audio-hidl-compat/
│   │   ├── 0001-audio_hw-fail-adev_open-when-the-devices-factory-can.patch  #  <- audio-config/outputs/
│   │   └── shim-crash-analysis.md          #  <- audio-config/outputs/ (evidence dossier)
│   └── pulseaudio-modules-droid/
│       ├── 0001-extevdev-Fix-startup-crash-when-no-input-device-is-f.patch  #  <- audio-trouble/outputs/ (dfda983 ref)
│       └── extevdev-crash-field-report.md  #  <- audio-trouble/outputs/
│
├── tools/                        # device-agnostic build/extract/inspect utilities (each +README)
│   ├── extract/
│   │   ├── x910-extract.sh        #  <- porting-orig/outputs/ (self-contained, canonical X910)
│   │   └── x810-extract.sh        #  <- tabS9plus-port/outputs/ (needs simg2img/lpunpack)
│   ├── boot/
│   │   ├── capture-boot.sh        #  <- porting-orig/outputs/ (crash-loop adb snapshotter)
│   │   ├── fix-boot-cmdline.py    #  <- porting-orig/outputs/ (padded boot.img panel-cmdline patch)
│   │   └── fix-vendor-boot-mode.py #  <- porting-orig/outputs/ (charger→normal bootconfig patch)
│   ├── lp/
│   │   ├── lp_inspect.py          #  <- root-expand/outputs/ (read-only LP metadata inspector)
│   │   └── probe-lp-ceiling.ps1   #  <- root-expand/outputs/ (WARNING: commits sizes, not read-only)
│   └── diagnostics/
│       └── audio-diag-nb1.sh      #  <- sound-script/outputs/ (read-only triage, H1/H2/H3)
│
├── docs/
│   ├── knowledge/                 # keep-forever, still-true reference
│   │   ├── gts9-audio-knowledge-transfer.md   #  <- audio-config/outputs/ (the five-bug playbook)
│   │   ├── gts9-spen-porting-guide.md         #  <- audio-config/outputs/
│   │   └── (gts9u-audio-online-mechanism.md — or leave in devices/gts9uwifi/docs/)
│   ├── postmortems/
│   │   └── AUDIO-POSTMORTEM-gts9uwifi.md       #  <- porting-orig/outputs/
│   └── status-archive/            # dated session records (SOME CONTAIN CORRECTED CLAIMS — date them)
│       ├── ut-gts9uwifi-port-plan.md          #  <- porting-first/outputs/ (founding doc)
│       ├── PORT-STATUS-gts9uwifi.md            #  <- porting-orig/outputs/
│       ├── AUDIO-DIAGNOSIS-gts9uwifi.md, AUDIO-STATE-session8-final.md
│       ├── BUILD-AUDIT-session8.md, VERIFICATION-REPORT.md, SPEN-PLAN.md
│       ├── gts9u-audio-session-summary.md      #  <- audio-config/outputs/
│       ├── gts9u-audio-diagnosis.md            #  <- ultra-main/outputs/ (v1, superseded by v2)
│       └── spen-gts9wifi-notes.md              #  <- ultra-main/outputs/
│
└── archive/                      # NOT in the live tree — transcripts, logs, one-offs, superseded
    ├── transcripts/               #  the 28 source .md conversations (or keep under _capture/)
    ├── notes/                     #  this synthesis + the per-thread mining notes
    ├── logs/                      #  ALL uploads/*.txt|.log|.strace, dmesg/journal/lsmod, probes
    ├── session8-audio/            #  porting-orig one-offs: audio_droid_patch/next/shim/stage2/
    │                              #   stage3/verify_block.sh
    ├── pen-investigation/         #  ultra-main pen-*.sh (recon/diag/mir/li/min/x2/xinput/why-touch/
    │                              #   fix/udev/interim/tablet/cleanup) + mir-tablet.sh + krita-*.sh
    ├── superseded/                #  V1/V2 build scripts, older update-binary revisions, v0 tp tarball
    └── binaries/                  #  audio_hidl_compat_default.so, halbins.tgz, oracle-bundle.tgz,
                                   #   gts9u-compile-validation.tar.gz, the OSRC zips (see §5)
```

Note on `common/build`: today each device ships its own full wrapper (V3 for gts9u, V4 for gts9p).
`RECON-build-scripts.md` shows they are 95% identical. Keep the per-device wrappers as the source
of truth initially (they are proven and self-contained), and file a follow-up to factor the shared
core into `common/build/build-gts9.sh` once a third device (gts9wifi own-build, or a 5G variant)
makes the duplication painful. Do NOT parameterize prematurely — the user deliberately chose
fail-fast device forks over parameterization.

---

## 3. Canonical-version rules (which copy wins)

From the RECON passes — critical to get right, because the capture has many superseded copies:

- **Build script (gts9u):** `audio-config/outputs/build-gts9uwifi.sh` (V3, md5 `26d72ee4…`).
  Identical to `tabS9plus-port/uploads/build-gts9uwifi__12_.sh`. Supersedes the `porting-orig`
  (V1) and `ultra-main/gts9u-fixes` (V2) copies and both re-uploads. `[RECON-build-scripts]`
- **Build script (gts9p):** `tabS9plus-port/outputs/build-gts9pwifi.sh` (V4). A *sibling*, not a
  successor of V3.
- **Skeleton:** `audio-config/outputs/gts9uwifi-skeleton-audio.tar.gz` (md5 `9ff0bf6e…`) — a strict
  superset of the original (`porting-orig/outputs/gts9uwifi-skeleton.tar.gz`, md5 `abbf0590…`, also
  the two `__2__` re-uploads). It carries the audio bringup + virtual-h2w + PA-gate + pen-reclass
  overlay and the modules.load-dedupe swap script. **Unpack the audio tarball for the canonical
  overlay; the loose `gts9u-audio-fix/` folder is one generation behind it.** `[RECON-skeletons]`
- **update-binary (TWRP flasher):** the **v4** at
  `ultra-main/outputs/gts9u-fixes/samsung-gts9u/flashable/.../update-binary` (zstd integrity
  pre-pass + marker-file failure detection). Supersedes `porting-orig/outputs/update-binary` and the
  older `porting-first/uploads/update-binary`. `[RECON-fixes-catalog]`
- **swap-vendor-modules.sh:** the copy *inside the audio skeleton tarball* (adds modules.load dedupe
  + SELinux-xattr restore on top of the LEFTOVER/UNLANDED audit) beats the loose
  `gts9u-fixes/.../swap-vendor-modules.sh`. Reconcile when unpacking. `[RECON-skeletons]`
- **Extevdev installer:** `lomiri-crash/outputs/gts9-audio-fix-install.sh` (root-run, version-gated,
  `--force`/`--uninstall`) is the entry point; the `gts9-virtual-h2w-workaround.tar.gz` bundle is
  the minimal-dependency (no python3-evdev) variant, worth keeping; `sound-script/outputs/`'s copy is
  a superseded phablet-run variant (salvage only its tone-playback acceptance tail). `[RECON-fixes-catalog]`
- **apply-string-patch.sh:** `porting-orig/outputs/apply-string-patch.sh` ==
  `porting-orig/outputs/audio-fix/apply-string-patch.sh` — dedupe. NOTE this fix (audio_hw_if→primary)
  was **reverted** in later analysis (it blocks the shim handshake); keep it in `fixes/audio/` with a
  loud "SUPERSEDED — do not install" banner, since the correct fix is the shim patch. `[ultra-main.p1]`
- **tp-rotate:** unpack `gts9u-tp-rotate-v0.1.tar.gz`; drop the v0 tarball and the loose
  `gts9u-tp-rotate.py` (byte-identical to the v0.1 daemon). `[RECON-fixes-catalog]`
- **Knowledge-transfer doc:** appears 3× (one output, two re-uploads) — keep one copy in `docs/knowledge/`.

---

## 4. What each README should cover

- **Root `README.md`** — the device matrix table (from `SYNTHESIS-port-state §0`); one-paragraph
  status per device (Ultra ~working, 11" daily-driven on Azkali's build, S9+ kit-ready-unexecuted);
  the "one kernel, three DTBs" architecture; quick-start pointing at `devices/<codename>/`; a link
  to `docs/knowledge/`; the persistence rule up front.
- **`CONTRIBUTING.md`** — the recurring hard-won discipline: (1) every rootfs change dies on reflash,
  every /home change dies on userdata wipe → durable fixes go in the skeleton overlay or on /data;
  (2) never `apt upgrade` the UT rootfs; never install desktop-GL apps (krita/gimp/blender) in the
  rootfs — use Libertine/Waydroid; (3) never `rmmod machine_dlkm` (panic, no ramoops); (4) read
  bootloader lock state in Download Mode only; (5) keep the S9+ unit offline (rev-1, past-cliff fleet);
  (6) test binary/overlay changes reversibly (reboot is the oracle), install only when proven.
- **`devices/gts9uwifi/README.md`** — status (from `SYNTHESIS §1`), the build command
  (`SKEL=…/skeleton IMPORTS=…/imports SRC_PARTS=…/out-x910/parts ./build-gts9uwifi.sh`), the flash
  procedure (TWRP full backup incl. EFS first; sideload; `twrp reboot system`; never touch dtbo),
  and the open list (sensors HAL, lpmake budget, touchpad DTS bake, USB-C host).
- **`devices/gts9pwifi/README.md`** — "unexecuted; follow `docs/gts9pwifi-port-runbook.md`"; the
  rev-1/offline rule; the SUPER-size and touch-IC deltas from the Ultra; first-boot unknown = panel
  attach.
- **`devices/gts9wifi/README.md`** — this is Azkali's upstream device tree; our contribution is the
  fixes/patches we file back (extevdev bump, shim patch, S-Pen guide) plus the on-device workarounds;
  the GPS/BT/pressure open items.
- **`fixes/*/README.md`** — per-fix: what it does, which devices, install command, and whether it's
  superseded or platform-gated.
- **`patches/upstream/*/`** — each patch's target project/branch, what it fixes, and **submission
  status** (both are currently unsent — track it here so it doesn't get lost again).
- **`tools/*/README.md`** — usage + the loud warning on `probe-lp-ceiling.ps1` (commits sizes).
- **`docs/status-archive/README.md`** — "dated session records; several contain claims corrected by
  later docs (e.g. v1 audio diagnosis §6-7 superseded by the v2 mechanism doc). Do not treat as
  current truth — see `docs/knowledge/` and `SYNTHESIS-port-state.md`."

---

## 5. Live tree vs archive (what stays out of the working tree)

**`archive/` (or keep under `_capture/`, out of the buildable tree):**
- **Transcripts** — the 28 source conversation .md files. Provenance, not code.
- **Diagnostic logs** — everything in the capture's `uploads/`: `dmesg*.txt`, `journal.log`,
  `lsmod.txt`, `audio2.txt`, `round2.txt`, `gts9u-audio-probe{5,8}.log`, `audio-diag-*.log`,
  `hal.strace`, `hal-restart.txt`, all `pen-*.output`, `mir-tablet.output`. These are captured
  outputs, valuable only as evidence behind specific findings — link them from the relevant doc,
  don't put them in the live tree.
- **Session one-offs** — `porting-orig/outputs/audio_{droid_patch,next,shim_patch,stage2,stage3,
  verify_block}.sh` (session-8 audio bisection) and the entire `ultra-main` pen/krita investigation
  ladder (`pen-*.sh`, `mir-tablet.sh`, `krita-*.sh`). Their *conclusions* shipped (the S-Pen guide,
  the touchscreen-masquerade rule); the scripts are methodology/evidence only.
- **Superseded copies** — V1/V2 `build-gts9uwifi.sh`, the older `update-binary` revisions, the v0
  tp-rotate tarball, the loose `gts9u-tp-rotate.py`, the byte-identical re-uploaded skeletons/scripts.
- **Large binaries** — `audio_hidl_compat_default.so` (24 KB shim, keep next to `shim-crash-analysis.md`
  only if binary redistribution is acceptable — otherwise record BuildID `a60baea45ee9f1e2b1a3b8d5da069832`
  and drop it); `halbins.tgz`, `oracle-bundle.tgz` (vendor HAL .so bundles for RE — do NOT commit,
  these are Samsung/Qualcomm proprietary blobs); `gts9u-compile-validation.tar.gz` (proof-of-compile,
  historical).
- **OSRC / firmware zips** — `Ubuntu touch port for Samsung/uploads/SM-X810_13_Opensource_dts.zip`
  and `SM-X818U_..._AWH8_....zip` are **Samsung source drops — do NOT commit to a public repo** (large,
  and licensing/redistribution is Samsung's). Keep them out-of-tree; `devices/gts9pwifi/docs/` records
  where to get them (opensource.samsung.com, and the Google Drive links noted in the runbook).

**Live tree (buildable / installable / reference):** everything in §2's `common/`, `devices/`,
`fixes/`, `patches/`, `tools/`, `docs/knowledge/`, `docs/postmortems/`. The `devices/*/reference/`
DTS and PIT files are small text/binary reference data and belong in-tree.

**Firmware donor partitions** (the carved `out-x910/parts/`, `out-x810/parts/`, and
`ubuntu-touch-kalama-firmware-*.tar.xz`) are Samsung vendor blobs — **never commit**; they are
regenerated by `tools/extract/x9{1,0}0-extract.sh` from the user's own firmware. `.gitignore` must
exclude `out-*/`, `*.img`, `super.img*`, `*.tar.xz`, `workdir/`, `partitions/`.

---

## 6. Migration checklist (concrete first commits)

1. `git init ubuntu-touch-gts9`; write root `README.md` + `CONTRIBUTING.md` + `.gitignore`
   (exclude firmware/blobs/build-output per §5).
2. Unpack `gts9uwifi-skeleton-audio.tar.gz` → `devices/gts9uwifi/skeleton/`; drop in the v4
   `update-binary`; reconcile `scripts/` against the loose gts9u-fixes copies (skeleton's
   swap-vendor-modules wins).
3. Unpack `gts9u-imports.tar.gz` → `devices/gts9uwifi/imports/`; `gts9p-imports.tar.gz` →
   `devices/gts9pwifi/imports/`.
4. Place canonical build scripts (V3→gts9u, V4→gts9p); place the gts9p reference data (PIT, DTS).
5. Unpack the fix bundles (`gts9-virtual-h2w-workaround.tar.gz`, `gts9u-tp-rotate-v0.1.tar.gz`) into
   `fixes/`; place the canonical installers; dedupe `apply-string-patch.sh` with a superseded banner.
6. Place the two upstream patches + companion docs under `patches/upstream/` and open two tracking
   issues (Halium shim PR; UBports/Azkali extevdev bump) — these are the highest-leverage, still-unsent.
7. Place `tools/` (extract/boot/lp/diagnostics) with per-directory READMEs.
8. Place `docs/knowledge/` (3 keystone docs), `docs/postmortems/` (audio postmortem), and everything
   else dated into `docs/status-archive/` with a "corrected by later docs" README.
9. Copy `SYNTHESIS-port-state.md` in as `docs/knowledge/PORT-STATE.md` (the current-truth index).
10. Move transcripts, logs, one-offs, superseded copies, and blobs to `archive/` (or leave under
    `_capture/`, out of the buildable tree).
