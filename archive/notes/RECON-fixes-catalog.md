# RECON: catalog of fix / tool / doc artifacts in `_capture/files/`

Date: 2026-08-30. Scope: everything under `_capture/files/` **except** the
skeleton/import tarballs (`gts9uwifi-skeleton*.tar.gz`, `gts9u-imports.tar.gz`,
`gts9u-compile-validation.tar.gz`, `gts9p-imports.tar.gz`, `oracle-bundle.tgz`,
`halbins.tgz`) and the large diagnostic logs in `uploads/` (dmesg, journal,
audio probes, pen-*.output, etc.). Both bundled tarballs named in the task
(`gts9-virtual-h2w-workaround.tar.gz`, `gts9u-tp-rotate-v0.1.tar.gz`) were
extracted and read in full.

Devices:
- **gts9wifi** = Tab S9 11" (SM-X710) — Azkali's reference port.
- **gts9pwifi** = Tab S9+ (SM-X810) — planned third port.
- **gts9uwifi** = Tab S9 Ultra (SM-X910) — the main port this project built.

Status legend: **FIX** = finished, shippable fix/workaround; **TOOL** = reusable
build/extract/inspect tool; **DOC** = knowledge/status document; **DIAG** =
diagnostic script (read-only or probe); **ONE-OFF** = session-specific
experiment/bisection script, historical value only.

Suggested repo layout referenced below:

```
repo/
  devices/gts9uwifi/   devices/gts9pwifi/   devices/gts9wifi/
  fixes/audio/  fixes/input-pen/  fixes/input-touchpad/
  patches/upstream/
  tools/{extract,boot,lp,flash}/
  docs/{knowledge,status-archive,postmortems}/
  contrib-scripts/diagnostics/   (or attic/)
```

---

## Master table

| Artifact (path under `_capture/files/`) | What it is | Device | Status | Repo home |
|---|---|---|---|---|
| `audio-config/outputs/0001-audio_hw-fail-adev_open-when-the-devices-factory-can.patch` | Upstream Halium patch: `adev_open()` in `audio.hidl_compat.default` must fail (free wrapper, return -ENODEV) instead of returning success with a null `deviceIface`, which crashed PulseAudio (SEGV at shim+0x2280). Applies halium-12.0..16.0/master. | all (Halium generic) | FIX (pending upstream) | `patches/upstream/halium-audio-hidl-compat/` |
| `audio-trouble/outputs/0001-extevdev-Fix-startup-crash-when-no-input-device-is-f.patch` | Azkali's upstream mer-hybris pulseaudio-modules-droid patch (`dfda983`, in 14.2.110): don't `io_free(NULL)` when no jack input device exists. Kept locally as the reference fix the h2w workaround stands in for. | all jackless devices | FIX (already upstream) | `patches/upstream/pulseaudio-modules-droid/` (reference copy) |
| `audio-config/outputs/gts9u-audio-fix/50-gts9u-audio-wait.conf` | systemd user drop-in gating PulseAudio start on `/sys/kernel/snd_card/card_state == 1` (the exact condition AGM polls), with careful `$`-avoidance notes. Superseded on-device by the `zz-gts9u-audio.conf` `/run/gts9u-audio-ready` gate baked into the skeleton, but is the standalone-install variant. | gts9uwifi | FIX (v2-era, superseded by skeleton gate) | `fixes/audio/gts9u-audio-fix/` (mark superseded in README) |
| `audio-config/outputs/gts9u-audio-fix/gts9u-load-audio-macros` | POSIX-sh boot script: bounded waits for the android container's `vendor_dlkm` module dir + base audio stack, insmods the three `lpass_cdc_{va,wsa,wsa2}_macro_dlkm` modules dropped by the parallel modprobe storm, waits for card ONLINE, fixes sysfs node perms for PA. Idempotent, fails loudly with hints. Precursor of the skeleton's `gts9u-audio-bringup` v3. | gts9uwifi | FIX (v2-era standalone; skeleton's bringup v3 is the shipped evolution) | `fixes/audio/gts9u-audio-fix/` |
| `audio-config/outputs/gts9u-audio-fix/gts9u-load-audio-macros.service` | systemd system unit for the above (oneshot, TimeoutStartSec=600). | gts9uwifi | FIX (v2-era) | `fixes/audio/gts9u-audio-fix/` |
| `audio-config/outputs/gts9u-audio-fix/gts9u-audio-online-mechanism.md` | "The ONLINE Mechanism, Source-Verified (v2)": link-by-link, source-cited model of how card_state goes 0→1 (msm_asoc machine driver, AGM `wait_for_snd_card_to_online()`), 10-minute manual test, provenance table. The definitive kernel-side audio explainer. | gts9uwifi | DOC (keystone) | `docs/knowledge/` |
| `audio-config/outputs/CHANGES-audio.md` | Ship notes for the 2026-08-08 "first sound" skeleton patchset: everything in the overlay (bringup v3, virtual h2w, PA zz drop-in, dedupe in swap script), fresh-flash boot sequence, the five-bug chain, addenda for charging (stage-2 finit: muic/pdic_sm5714, wez01) and S-Pen ship. | gts9uwifi | DOC (release notes; canonical description of what the skeleton contains) | `docs/knowledge/` or `devices/gts9uwifi/CHANGES-audio.md` |
| `audio-config/outputs/gts9-audio-knowledge-transfer.md` | Knowledge-transfer doc: full audio architecture + five-bug chain + working bring-up order + exonerated suspects + triage playbook, written for debugging the 11" using Ultra findings. (Duplicated verbatim in `audio-trouble/uploads/` and `Ubuntu Touch audio troubleshoo/uploads/` — those are re-uploads of this file into later sessions.) | gts9wifi (audience), derived on gts9uwifi | DOC (keystone) | `docs/knowledge/` |
| `audio-config/outputs/gts9-spen-porting-guide.md` | S-Pen porting guide: finit_module IGNORE_MODVERSIONS load of `wez01.ko`, libinput quirk (INPUT_PROP_DIRECT + strip pen buttons), udev ID_INPUT_TOUCHSCREEN rule; verification ladder; gts9/gts9+ adaptation notes; Mir-2/Wayland pressure outlook. | gts9uwifi (portable to family) | DOC (keystone) | `docs/knowledge/` |
| `audio-config/outputs/gts9u-audio-session-summary.md` | 2026-08-08 session summary: exec summary of the five-bug chain, exonerated suspects, current state, todos, charging + pen addenda. Overlaps CHANGES-audio but adds negative findings and timeline. | gts9uwifi | DOC (session record) | `docs/status-archive/` |
| `audio-config/outputs/shim-crash-analysis.md` | Full evidence chain for the shim null-deref: coredump registers, disassembly of offset 0x2280, source correspondence — the justification document for the 0001-audio_hw patch. | gts9uwifi (bug is generic Halium) | DOC (evidence for the upstream patch) | `patches/upstream/halium-audio-hidl-compat/` (next to the patch) |
| `audio-config/outputs/build-gts9uwifi.sh` | **Newest** Ultra build driver: end-to-end kernel+image build with panel-cmdline bake, module swap, plus the audio/pen overlay sanity block (fails fast if bringup/h2w/quirk files missing from staged skeleton). Identical to `tabS9plus-port/uploads/build-gts9uwifi__12_.sh`. Supersedes `ultra-main/outputs/gts9u-fixes/build-gts9uwifi.sh` and `porting-orig/outputs/build-gts9uwifi.sh`. | gts9uwifi | TOOL (canonical) | `devices/gts9uwifi/build-gts9uwifi.sh` |
| `audio-trouble/outputs/extevdev-crash-field-report.md` | Field report for upstream/UBports: confirms shipping UT 24.04 images carry the extevdev abort (14.2.107–109), version-range pin, impact, asks, interim workaround. Companion to the dfda983 patch copy. | gts9wifi (observed), all jackless | DOC (upstream communication) | `patches/upstream/pulseaudio-modules-droid/` or `docs/postmortems/` |
| `audio-trouble/outputs/gts9-virtual-h2w-workaround.tar.gz` → `gts9-virtual-h2w/{gts9-virtual-h2w.py, .service, 55-gts9wifi-wait-h2w.conf, install.sh}` | Minimal virtual headset-jack workaround bundle: raw-ioctl uinput daemon advertising SW_HEADPHONE/MIC/LINEOUT (state 0), system unit, hard-fail PA ExecStartPre gate, root installer with ro-rootfs handling. Validated on gts9wifi 2026-08-10. | gts9wifi (works family-wide) | FIX (finished, installable bundle) | `fixes/audio/gts9-virtual-h2w/` (unpacked, not as tarball) |
| `lomiri-crash/outputs/gts9-audio-fix-install.sh` | **Newest** single-file installer for the extevdev workaround: root-run, `--force`/`--uninstall`, preflight-everything-first, detects fixed package (>=14.2.110) and refuses, python3-evdev daemon in /usr/local/bin, fail-open 30 s gate, self-copy to userdata. Supersedes the sound-script variant. | gts9 family (jackless Tab S9s) | FIX (finished, polished) | `fixes/audio/gts9-audio-fix-install.sh` |
| `sound-script/outputs/gts9-audio-fix-install.sh` | Earlier phablet-run variant of the same installer (userdata payloads, 440 Hz tone validation, step/rollback log). Superseded by the lomiri-crash version but its acceptance-test tail (tone playback) is worth salvaging. | gts9wifi | FIX (superseded variant) | `attic/` or keep beside canonical with a note |
| `sound-script/outputs/audio-diag-nb1.sh` | Read-only audio diagnostics stage NB1 for Azkali's S-Pen build: discriminates H1 (orphaned wait-h2w gate) / H2 (14.2.107–109 extevdev abort) / H3 (fixed package, failure elsewhere); writes `~/audio-diag-nb1.log`. (Upload copy identical; `audio-diag-nb1.log` uploads are its captured output.) | gts9wifi | DIAG (reusable triage tool) | `contrib-scripts/diagnostics/` |
| `porting-orig/outputs/AUDIO-DIAGNOSIS-gts9uwifi.md` | Session-8 audio diagnosis: crash chain proven, hypotheses eliminated, two fix paths. Historically important; superseded by postmortem + v2 mechanism doc. | gts9uwifi | DOC (session record) | `docs/status-archive/` |
| `porting-orig/outputs/AUDIO-POSTMORTEM-gts9uwifi.md` | Polished postmortem of the PA init crash diagnosis (method, eliminated hypotheses, root cause `audio_hw_if` vs `primary`, lessons). Written to be reusable. | gts9uwifi | DOC (keep) | `docs/postmortems/` |
| `porting-orig/outputs/AUDIO-STATE-session8-final.md` | "Read first next session" state file: string-patch crash fix proven, version-gate (EINVAL) still open. | gts9uwifi | DOC (session record) | `docs/status-archive/` |
| `porting-orig/outputs/BUILD-AUDIT-session8.md` | Audit that the build tree already carries every live-discovered fix; rebuild+reflash promotes all. | gts9uwifi | DOC (session record) | `docs/status-archive/` |
| `porting-orig/outputs/PORT-STATUS-gts9uwifi.md` | Rolling port status/plan (sessions 1–6+): architecture of Azkali's port, constraints, addenda for firmware analysis, PIT, OSRC, compile validation. | gts9uwifi | DOC (session record, rich provenance) | `docs/status-archive/` |
| `porting-orig/outputs/SPEN-PLAN.md` | S-Pen enablement plan: hardware map read from stock DTBOs for both boards, kernel/module/input-stack pieces, backport checklist to gts9wifi. Largely realized by the spen-porting-guide. | gts9uwifi + gts9wifi | DOC (planning; superseded by guide) | `docs/status-archive/` |
| `porting-orig/outputs/VERIFICATION-REPORT.md` | Item-by-item verification of build pipeline, patchers, flasher, skeleton overlay, imports; flags on-device-only checks. | gts9uwifi | DOC (QA record) | `docs/status-archive/` |
| `porting-orig/outputs/apply-string-patch.sh` (+ identical copy `porting-orig/outputs/audio-fix/apply-string-patch.sh`) | Proven partial fix: binary-patches `libdroid-util-*.so` string `audio_hw_if` → `primary` (NUL-padded) so Samsung's HAL accepts adev_open. Delivered permanently via halium-overlay in the build; this is the on-device patcher. | gts9uwifi (any Samsung HAL rejecting `audio_hw_if`) | FIX (on-device patcher; overlay is the permanent vehicle) | `fixes/audio/apply-string-patch.sh` (dedupe the two copies) |
| `porting-orig/outputs/audio_droid_patch.sh` | Session-8 experiment: locate/patch the `audio_hw_if` string in libdroid-util via bind-mounted copy, verify. | gts9uwifi | ONE-OFF | `attic/session8-audio/` |
| `porting-orig/outputs/audio_next.sh` | Session-8 follow-on: re-apply bind patch, capture full PA init log past the open. | gts9uwifi | ONE-OFF | `attic/session8-audio/` |
| `porting-orig/outputs/audio_shim_patch.sh` | Session-8 experiment: same string patch attempted on the Android-side shim. | gts9uwifi | ONE-OFF | `attic/session8-audio/` |
| `porting-orig/outputs/audio_stage2.sh` / `audio_stage3.sh` | Session-8 staged bisection: log-context capture around the failure; patch+bind all three libdroid-util generations. | gts9uwifi | ONE-OFF | `attic/session8-audio/` |
| `porting-orig/outputs/audio_verify_block.sh` | Session-8 "Path A" verification: disassembles the shim, checks which openDevice variant libaudiohal resolves. | gts9uwifi | DIAG / ONE-OFF | `attic/session8-audio/` |
| `porting-orig/outputs/capture-boot.sh` | Host-side tool: races the short adb window across crash-loop boot cycles, snapshotting state each cycle into `captures/session-N/`. Genuinely reusable for any halium bring-up. | device-agnostic | TOOL | `tools/boot/capture-boot.sh` |
| `porting-orig/outputs/fix-boot-cmdline.py` | Padded in-place retarget of the baked CONFIG_CMDLINE panel selection (11" AMSA10FA01 → Ultra AMSA46AS02) inside a built boot.img. Was a bridge before the panel sed moved into the build script; still handy for image surgery. | gts9uwifi | TOOL (build script now bakes this; keep as image-surgery utility) | `tools/boot/` |
| `porting-orig/outputs/fix-vendor-boot-mode.py` | Padded in-place flip of `androidboot.mode = "charger"` → `"normal"` in vendor_boot bootconfig (size-preserving) so init does a full boot. | gts9uwifi (generic technique) | TOOL | `tools/boot/` |
| `porting-orig/outputs/x910-extract.sh` | Self-contained stock-firmware extractor for SM-X910 (embedded sparse + LP parsing, no lpunpack/simg2img): produces stockimgs/, parts/, PIT, LP geometry info. | gts9uwifi | TOOL (canonical for X910) | `tools/extract/x910-extract.sh` |
| `porting-orig/outputs/update-binary` | TWRP updater script for the gts9uwifi flashable zip (X910 verify, X916 hard-reject). Earlier revision; the v4 in ultra-main's gts9u-fixes tree supersedes it. (Upload copy in `porting-first/uploads/` is yet another, older revision.) | gts9uwifi | FIX (superseded by v4) | `attic/` (v4 goes in the skeleton's `flashable/`) |
| `porting-first/outputs/ut-gts9uwifi-port-plan.md` | The original port plan (2026-08-03): verdict, verified findings on the gts9wifi bundle, hardware delta, full change-surface inventory, phase plan, feature matrix, risks. | gts9uwifi | DOC (founding document) | `docs/status-archive/` (or `docs/` root as the origin story) |
| `root-expand/outputs/lp_inspect.py` | Read-only Android LP (super) metadata inspector: parses geometry/header/partition/extent/group tables directly, verifies checksums, supports `--target/--grow` what-if. High-quality standalone tool. | device-agnostic (used on Tab S9 family) | TOOL | `tools/lp/lp_inspect.py` |
| `root-expand/outputs/probe-lp-ceiling.ps1` | Windows/fastbootd bisection probe: finds the largest size fastbootd will grant a logical partition (`resize-logical-partition`), grow-only commits, guards (fastbootd check, userspace check). | device-agnostic (Tab S9 in fastbootd) | TOOL (NOT read-only — commits sizes) | `tools/lp/probe-lp-ceiling.ps1` |
| `ultra-main/outputs/gts9u-audio-diagnosis.md` | "Audited Diagnosis" (v1): graded PA-side chain (all confirmed) + kernel-side blocker; explicitly superseded in parts by the v2 online-mechanism doc (which names the superseded sections). | gts9uwifi | DOC (session record; keep for the grading trail) | `docs/status-archive/` |
| `ultra-main/outputs/gts9u-fixes/build-gts9uwifi.sh` | v2 build driver (audited, pre-audio-sanity-block). Superseded by audio-config's copy. | gts9uwifi | TOOL (superseded) | `attic/` |
| `ultra-main/outputs/gts9u-fixes/samsung-gts9u/flashable/META-INF/.../update-binary` | v4 TWRP flash script: staged+size-verified dd, zstd integrity test of super before writing, vbmeta absent-vs-failed distinction. The best flasher revision captured. | gts9uwifi | FIX (canonical flasher) | `devices/gts9uwifi/flashable/META-INF/...` |
| `ultra-main/outputs/gts9u-fixes/samsung-gts9u/scripts/make-flashable.sh` | v2 packager for the TWRP zip (strict mode, named input errors, static zstd). | gts9uwifi | TOOL | `devices/gts9uwifi/scripts/` |
| `ultra-main/outputs/gts9u-fixes/samsung-gts9u/scripts/super.sh` | v2 super.img assembler (lpmake wrapper; strict mode, exec-format probe, named errors). | gts9uwifi | TOOL | `devices/gts9uwifi/scripts/` |
| `ultra-main/outputs/gts9u-fixes/samsung-gts9u/scripts/swap-vendor-modules.sh` | v2 module swapper with LEFTOVER/UNLANDED audit and allowlist strict mode ("the class that cost us the va_macro hunt"). Note: CHANGES-audio.md says the audio-config-era skeleton's copy also dedupes modules.load — that newer copy lives inside the excluded skeleton tarball; this is the newest loose copy. | gts9uwifi | TOOL (near-canonical; skeleton tarball has the +dedupe revision) | `devices/gts9uwifi/scripts/` |
| `ultra-main/outputs/gts9u-fixes/samsung-gts9u/scripts/swap-allowlist.txt` | Strict-mode allowlist for the swapper (template, workflow documented in comments, list empty). | gts9uwifi | TOOL (config template) | `devices/gts9uwifi/scripts/` |
| `ultra-main/outputs/spen-gts9wifi-notes.md` | S-Pen findings on the 11": hardware fully working, pointer via touchscreen-masquerade, pressure blocked by Mir 1.8 (confirmed), krita-into-rootfs hazard warning, cleanup state. | gts9wifi | DOC (session findings) | `docs/status-archive/` |
| `ultra-main/outputs/pen-recon.sh, pen-diag.sh, pen-mir.sh, pen-li.sh, pen-min.sh, pen-x2.sh, pen-xinput.sh, pen-why-touch.sh, mir-tablet.sh` | The pen investigation ladder on the 11": read-only recon → libinput/Mir/udev classification checks → XWayland/xinput probes → "why touchscreen not stylus" → Mir zwp_tablet capability check. Each documents its findings-so-far in the header; collectively they are the evidence trail behind the spen guide. Matching `pen-*.output` files in `Ubuntu Touch on Galaxy Tab S9 /uploads/` are their captured results. | gts9wifi | DIAG / ONE-OFF (methodology value) | `contrib-scripts/diagnostics/pen/` or `attic/pen-investigation/` |
| `ultra-main/outputs/pen-fix.sh, pen-udev.sh, pen-interim.sh, pen-tablet.sh, pen-cleanup.sh` | The pen fix attempts: quirk install, udev touchscreen tag, interim masquerade (the approach that shipped), pressure-preserving tablet path (blocked by Mir 1.8), and the unwind script restoring a known state. | gts9wifi | ONE-OFF (superseded by the shipped quirk+udev files in the skeleton and the spen guide) | `attic/pen-investigation/` |
| `ultra-main/outputs/krita-pen.sh, krita-diag.sh, krita-fix-attempts.sh, krita-xcb.sh` | Krita pressure experiments on the 11": evdevtablet plugin, diagnosis (ubuntumirclient QPA eats tablet events), xcb/XWayland launch attempt. Concluded pressure is platform-gated until Mir 2.x. | gts9wifi | ONE-OFF | `attic/pen-investigation/` |
| `touchpad/outputs/gts9u-tp-rotate-v0.1.tar.gz` → `gts9u-tp-rotate/{gts9u-tp-rotate, gts9u-tp-orient, .service, .default, install.sh, README.md}` | Folio touchpad orientation shim v0.1: python daemon EVIOCGRABs `sec_touchpad_pogo`, re-emits via a capability-mirroring uinput clone with quarter-turn transform; recreate-on-rotate with contact replay; FIFO control tool; systemd unit; env-file boot default; validating installer; honest README (manual orientation switching — auto-tracking deferred to v1). v0.1 adds release-flush before clone teardown and SYN_DROPPED resync over v0. | gts9uwifi (any `sec_touchpad_pogo` device via `--device-name`) | FIX (finished v0.1, validation pass on device pending) | `fixes/input-touchpad/gts9u-tp-rotate/` (unpacked) |
| `touchpad/outputs/gts9u-tp-rotate-v0.tar.gz` | v0 of the same bundle (pre flush/resync). | gts9uwifi | FIX (superseded by v0.1) | drop, or `attic/` (git history covers it) |
| `touchpad/outputs/gts9u-tp-rotate.py` | Loose copy of the daemon, byte-identical to the v0.1 tarball's `gts9u-tp-rotate`. | gts9uwifi | duplicate | drop after unpacking v0.1 |
| `tabS9plus-port/outputs/gts9p-hw-findings.md` | Canonical A13-vintage hardware confirmation for the Tab S9+: panel/touch/pen/folio/WLAN table, OSRC base+overlay structure correction, stock-firmware surgical sampling, assembly-complete addendum. | gts9pwifi | DOC (keystone for the S9+ port) | `devices/gts9pwifi/docs/` |
| `tabS9plus-port/outputs/gts9pwifi-port-runbook.md` | End-to-end S9+ port runbook: inputs with hashes, skeleton fork procedure (gts9u→gts9p rename list), extraction, unit prep, build, TWRP flash, bring-up ladder, rescue paths. | gts9pwifi | DOC (runbook, actionable) | `devices/gts9pwifi/docs/` |
| `tabS9plus-port/outputs/build-gts9pwifi.sh` | S9+ build driver forked from the Ultra script: family-split notes (STM touch + wez01 already in tree, GTS9P panel import, smaller SUPER from X810 PIT). | gts9pwifi | TOOL (canonical for S9+, unexecuted as of capture) | `devices/gts9pwifi/build-gts9pwifi.sh` |
| `tabS9plus-port/outputs/x810-extract.sh` | S9+ firmware extractor. Note: NOT self-contained like x910-extract.sh — depends on `simg2img`/`lpunpack`; narrower output contract (parts/ only). | gts9pwifi | TOOL (canonical for X810) | `tools/extract/x810-extract.sh` |
| `tabS9plus-port/outputs/GTS9PWIFI_EUR_OPEN.pit` | Stock Samsung PIT (partition table) for SM-X810 — source of the SUPER size constant in build-gts9pwifi.sh. | gts9pwifi | reference data | `devices/gts9pwifi/reference/` |
| `tabS9plus-port/outputs/gts9pwifi_eur_open_w00_r04_A13-AWG1.dts` | Canonical decompiled board DTS (r04) from the A13 OSRC zips — the authoritative one to build imports from. | gts9pwifi | reference data | `devices/gts9pwifi/reference/dts/` |
| `tabS9plus-port/outputs/gts9pwifi_eur_open_w00_r04_MIRROR.dts` | Same board DTS from a mirror tree; ~13% line drift vs canonical; kept as identity-reference only (per hw-findings). | gts9pwifi | reference data (secondary) | `devices/gts9pwifi/reference/dts/` (or drop, with a note) |

## Uploads worth remembering (not cataloged as artifacts)

- `audio-config/uploads/audio_hidl_compat_default.so` — the actual stripped
  24 KB shim binary (BuildID a60baea…) that `shim-crash-analysis.md` disassembles;
  keep next to the analysis if binary redistribution is acceptable, else record
  BuildID only.
- `audio-config/uploads/build-gts9uwifi.sh`, `ultra-main/uploads/build-gts9uwifi__7_.sh`,
  `tabS9plus-port/uploads/build-gts9uwifi__12_.sh` — intermediate/newest revisions of the
  Ultra build script fed between sessions; `__12_` == the canonical audio-config output.
- `porting-first/uploads/update-binary` — oldest flasher revision.
- Everything else in `uploads/` is diagnostic captures (dmesg/journal/lsmod/audio
  probes/pen outputs/strace) or excluded source/firmware bundles.

---

## Commentary

### Lineage: three generations of the same audio fix

The audio work left artifacts from three eras, and a future repo should be
explicit about which is current:

1. **Session-8 era (`porting-orig/`)** — the `audio_hw_if`→`primary` string
   patch (`apply-string-patch.sh`) plus the bisection one-offs
   (`audio_*.sh`). The crash was solved here; the version gate was not.
2. **v2 era (`audio-config/outputs/gts9u-audio-fix/`)** — the source-verified
   ONLINE mechanism plus the standalone `gts9u-load-audio-macros` service and
   the card_state PA gate. Correct model, standalone install form.
3. **Shipped era (skeleton overlay, described by `CHANGES-audio.md`)** — the
   bringup v3 script (`gts9u-audio-bringup`), virtual h2w, `zz-gts9u-audio.conf`
   flag-file gate, modules.load dedupe, stage-2 finit loader (charging + pen).
   The actual shipped files live **inside the excluded
   `gts9uwifi-skeleton-audio.tar.gz`** — the loose `gts9u-audio-fix/` folder is
   one generation behind it. When building the repo, unpack the skeleton
   tarball for the canonical overlay content and use `CHANGES-audio.md` as its
   changelog.

Similarly for the extevdev workaround there are three forms: the raw-ioctl
bundle (`gts9-virtual-h2w-workaround.tar.gz`, validated on gts9wifi), the
phablet-run installer (`sound-script/`), and the polished root-run installer
with version detection (`lomiri-crash/`). The **lomiri-crash installer is the
one to keep as the entry point**; the tarball bundle is the minimal-dependency
variant (no python3-evdev needed) and worth keeping too.

### Build script and flasher: pick the newest

`build-gts9uwifi.sh` exists in four copies. Canonical =
`audio-config/outputs/` (== `tabS9plus-port/uploads/__12_`), which carries the
audio/pen overlay sanity block. The TWRP `update-binary` exists in three
revisions; canonical = the v4 in `ultra-main/outputs/gts9u-fixes/.../flashable/`.
The `scripts/` trio (super.sh, make-flashable.sh, swap-vendor-modules.sh +
allowlist) under `gts9u-fixes/samsung-gts9u/` are the newest loose copies, but
CHANGES-audio.md documents a later swap-vendor-modules revision (modules.load
dedupe + selinux xattr restore) that lives in the excluded skeleton tarball —
reconcile against it when assembling the repo.

### The two upstream patches are the highest-leverage artifacts

Both `0001-*.patch` files fix bugs that affect every Halium/UT device of their
class, not just this port: the hidl_compat swallow-error (with
`shim-crash-analysis.md` as its evidence dossier) targets Halium; the extevdev
NULL-free is already upstream (Azkali dfda983, 14.2.110) and is kept with the
field report that pins the affected packaged range. Give them a `patches/
upstream/` home with their companion docs so submission status stays tracked.

### Docs split cleanly into keystone vs archive

Keep-forever, still-true reference docs: `gts9-audio-knowledge-transfer.md`,
`gts9u-audio-online-mechanism.md`, `gts9-spen-porting-guide.md`,
`CHANGES-audio.md`, `AUDIO-POSTMORTEM-gts9uwifi.md`, and both gts9p docs
(hw-findings, runbook). Everything else (`PORT-STATUS`, `AUDIO-DIAGNOSIS`,
`AUDIO-STATE`, `BUILD-AUDIT`, `VERIFICATION-REPORT`, `SPEN-PLAN`,
session summaries, spen-gts9wifi notes, gts9u-audio-diagnosis v1) is a dated
session record — valuable provenance, but several contain claims explicitly
corrected by later docs (v1 audio diagnosis §6–7 is superseded by the v2
mechanism doc, which says so by name). Put them in `docs/status-archive/`
with dates in filenames so nobody mistakes them for current truth.

### Genuinely reusable tools beyond this port

`lp_inspect.py` (LP metadata parser with checksum verification),
`capture-boot.sh` (crash-loop adb snapshotter), the padded in-place image
patchers (`fix-boot-cmdline.py`, `fix-vendor-boot-mode.py`), and
`x910-extract.sh` (self-contained sparse+LP extraction in pure
python3/bash) are device-independent techniques worth a `tools/` directory
with their own READMEs. `probe-lp-ceiling.ps1` belongs with them but needs a
loud warning: it commits every successful probe to LP metadata (grow-only).

### Duplicates to collapse when importing

- `apply-string-patch.sh` == `audio-fix/apply-string-patch.sh` (porting-orig).
- `touchpad/outputs/gts9u-tp-rotate.py` == the daemon inside the v0.1 tarball;
  v0 tarball is strictly older.
- `gts9-audio-knowledge-transfer.md` appears three times (one output, two
  session uploads).
- `sound-script/outputs/audio-diag-nb1.sh` == its upload copy.

### Device targeting at a glance

- **gts9uwifi (Ultra)** owns the bulk: audio bringup chain, both build/flash
  toolchains, tp-rotate, boot patchers, x910 extractor, most docs.
- **gts9wifi (11")** owns the extevdev workaround deployments, the audio-diag
  triage script, and the entire pen/krita investigation suite (whose
  conclusions then shipped on the Ultra via the spen guide).
- **gts9pwifi (S9+)** has a complete but so-far-unexecuted port kit: findings
  doc, runbook, build script, extractor, PIT, canonical DTS.
- The two upstream patches and the lp/boot/capture tools are device-agnostic.
