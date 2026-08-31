# D — Audio parity audit: five-bug chain × three devices

Audit date: 2026-08-30. One pass of the three-device parity audit, audio deep-dive.
Legend: **VERIFIED** = I read the implementation file on disk in this pass;
**REPORTED** = a doc/notes file claims it (cited); **MISSING** = expected but absent.
Snapshot repo root: `/home/jstockdale/projects/ubuntu-touch-gts9` (abbreviated `REPO` below).
Mining notes root: `/home/jstockdale/projects/claude-ubuntu-touch/_capture/notes` (abbreviated `NOTES`).

---

## 0. Ground truth read for this audit (all VERIFIED read in full)

- `REPO/docs/knowledge/PORT-STATE.md` §3 (five-bug chain), §4, §6
- `REPO/docs/knowledge/gts9-audio-knowledge-transfer.md`
- `REPO/docs/knowledge/gts9u-audio-online-mechanism.md`
- `REPO/devices/gts9uwifi/skeleton/overlay/system/usr/local/sbin/gts9u-audio-bringup` (the v3/v4 script)
- `REPO/devices/gts9uwifi/skeleton/overlay/system/etc/systemd/system/gts9u-audio-bringup.service` (+wants symlink)
- `REPO/devices/gts9uwifi/skeleton/overlay/system/etc/systemd/system/gts9u-virtual-h2w.service` (+wants symlink)
- `REPO/devices/gts9uwifi/skeleton/overlay/system/usr/local/lib/gts9u-virtual-h2w.py`
- `REPO/devices/gts9uwifi/skeleton/overlay/system/etc/systemd/user/pulseaudio.service.d/zz-gts9u-audio.conf`
- `REPO/devices/gts9uwifi/skeleton/scripts/swap-vendor-modules.sh`
- `REPO/devices/gts9uwifi/skeleton/vendor-ramdisk-overlay/lib/modules/modules.load`
- `REPO/devices/gts9uwifi/build-gts9uwifi.sh` (audio sanity block, lines 136–157)
- `REPO/devices/gts9uwifi/docs/CHANGES-audio.md`
- `REPO/patches/upstream/halium-audio-hidl-compat/0001-audio_hw-fail-adev_open-when-the-devices-factory-can.patch` + `README.md`
- `REPO/patches/upstream/pulseaudio-modules-droid/0001-extevdev-Fix-startup-crash-when-no-input-device-is-f.patch` + `README.md`
- `REPO/fixes/audio/README.md`, `REPO/fixes/audio/gts9-audio-fix-install.sh`
- `REPO/fixes/audio/gts9-virtual-h2w/{install.sh,gts9-virtual-h2w.py,gts9-virtual-h2w.service,55-gts9wifi-wait-h2w.conf}`
- `REPO/devices/gts9pwifi/build-gts9pwifi.sh` (audio sanity block, lines 158–180), `REPO/devices/gts9pwifi/docs/gts9pwifi-port-runbook.md` (Phase 1 + bring-up ladder)
- `REPO/devices/gts9wifi/README.md`
- `NOTES/audio-cluster.notes.md` (full — 11" on-device evidence)

---

## 1. Bug-by-bug verification

### Bug 1 — module load storm / va-macro keystone

**Ultra (gts9uwifi) — VERIFIED, two-layer fix, skeleton-durable.**
- Boot-service module walk: `REPO/devices/gts9uwifi/skeleton/overlay/system/usr/local/sbin/gts9u-audio-bringup`
  lines 21–36: waits ≤120 s for `/android/vendor_dlkm/lib/modules/modules.load`, walks it with
  `awk '!seen[$0]++'` (line 26), honors `modules.blocklist` (line 24, name-normalized `tr - _`),
  skips already-loaded modules via `/proc/modules`, insmods every hole, logs
  `"modules: +N inserted, M already live, failed: ..."` (the storm-regression sensor —
  CHANGES-audio.md says expect `+0` on a deduped image).
- Build-time dedupe: `REPO/devices/gts9uwifi/skeleton/scripts/swap-vendor-modules.sh` lines 22–29:
  dedupes every `modules.load*` in the extracted stock vendor_dlkm with `awk '!seen[$0]++'`,
  restores mode/owner and the SELinux xattr (ctx harvested from `smcinvoke_dlkm.ko`, fallback
  `u:object_r:vendor_file:s0`), prints a `dedup N -> M` report line, then repacks erofs.
  Invoked by `REPO/devices/gts9uwifi/skeleton/build.sh:28`; presence of the dedupe is
  build-gated (`grep -q 'seen\[\$0\]'` at `build-gts9uwifi.sh:153`).
- Unit is enabled in the image: wants symlink VERIFIED at
  `overlay/system/etc/systemd/system/multi-user.target.wants/gts9u-audio-bringup.service`.
- Side check: the **vendor_boot ramdisk** `modules.load` in the skeleton
  (`vendor-ramdisk-overlay/lib/modules/modules.load`, 124 lines, zero audio modules — matches
  the mechanism doc) has **one duplicate line: `qrng_dlkm.ko`** (VERIFIED via `sort|uniq -d`).
  Harmless to audio, but it means the ramdisk list never went through the dedupe pass —
  trivial hygiene item.

**11" (gts9wifi) — MISSING, and the hazard is CONFIRMED PRESENT on-device.**
- No module-walk service and no dedupe exist for this device anywhere in the repo
  (`REPO/devices/gts9wifi/` contains only README.md; `fixes/audio/` carries only the bug-4 installer).
- REPORTED, strong: `NOTES/audio-cluster.notes.md:59` (2026-08-10 on-device diagnostic) —
  the 11"'s `/android/vendor_dlkm/lib/modules/modules.load` is **457 lines / 357 unique:
  "the same 4× audio-module duplication (storm amplifier present, this boot won the race)"**;
  consolidated open issue at `:114`. So the "Ultra's 4× was our own pipeline artifact,
  Azkali's may be clean" hypothesis (`CHANGES-audio.md` open items; audio-config p4 notes)
  is **falsified for the deployed 11" image**: the amplifier is in Azkali's image too.
  gts9wifi's card has come up on every observed boot (ONLINE ×1 at 13.16 s that boot), but that
  is a won race, not a guarantee — see §3.

**S9+ (gts9pwifi) — PLANNED via skeleton fork; nothing on disk yet.**
- The skeleton fork `samsung-gts9u → samsung-gts9p` has not been executed (no
  `REPO/devices/gts9pwifi/skeleton/` exists — VERIFIED by directory listing).
- The build script guards the outcome: `REPO/devices/gts9pwifi/build-gts9pwifi.sh:164–180`
  FATALs if `overlay/.../usr/local/sbin/gts9p-audio-bringup` is missing and asserts the
  renamed h2w py, both wants symlinks, `gts9p-audio-ready` in `zz-gts9p-audio.conf`,
  the dedupe in `swap-vendor-modules.sh`, and the `finit stage` string. The runbook
  (`docs/gts9pwifi-port-runbook.md` §1.2–1.3) gives the exact rename commands and a
  `grep -rn gts9u` leftover check. Since the S9+ vendor_dlkm will be its own stock X810
  extract run through the same swap script, the dedupe applies regardless of whether
  Samsung's X810 list is duplicated.

### Bug 2 — Samsung fallback latch (`vendor.audio.use.primary.default`)

**Ultra — VERIFIED.** `gts9u-audio-bringup` lines 79–83: after card ONLINE, retry-loop
`setprop vendor.audio.use.primary.default false` and verify via `getprop`, ≤60 s then
`FATAL: could not clear latch`. Correct position: after the card wait (73–75), before the HAL
restart (85). Unconditional clear (covers the never-pinned origin of the initial `true`).

**11" — MISSING (no preventive clear anywhere).** REPORTED evidence that it currently doesn't
need it: `NOTES/audio-cluster.notes.md:57` — latch verified **unset** on the diagnosed boot,
`vendor.audio-hal` demonstrably serving. But the latch is set by AGM's card-wait timeout, i.e.
exactly the event a lost bug-1 race produces, and once set it **survives reboots' service
restarts and poisons every subsequent open** until something clears it. The 11" has the
amplifier (above) and no clearing mechanism: one bad race away from persistent silent audio
with no installed recovery.

**S9+ — PLANNED** (inherits the bringup script via the fork; `build-gts9pwifi.sh` sanity block
checks the script exists, and the sed rename does not touch the property name — the latch
logic is device-name-free). Nothing on disk yet.

### Bug 3 — Halium shim null-deref (`audio.hidl_compat.default.so`)

**Patch — VERIFIED read.**
`REPO/patches/upstream/halium-audio-hidl-compat/0001-audio_hw-fail-adev_open-when-the-devices-factory-can.patch`:
3-line insertion in `adev_open` (`audio/audio_hw.cpp` @676) — on `openDevice()` failure,
`delete adev; *device = nullptr; return rc < 0 ? rc : -ENODEV;`. Applies to halium-12.0…16.0
per the commit message.

**Deployment status — the fix is currently the UNSENT PATCH ONLY, deployed NOWHERE.**
VERIFIED by exhaustive search: the only `audio.hidl_compat` binary in the repo is
`REPO/archive/binaries/audio_hidl_compat_default.so` — and per
`REPO/archive/binaries/MANIFEST.md` that is the **stock, unpatched** shim kept as the
crash-analysis evidence artifact (BuildID a60baea…, "crash PC = file offset 0x2280"), not a
patched build. No patched `.so` exists; no skeleton overlay (Ultra or planned S9+) carries a
shim replacement (`overlay/.../halium-overlay/` has no `system/lib64/hw/audio.*`); no device
runs a patched shim. `patches/.../README.md` line 7: **"Status: UNSENT"** (PORT-STATE §6
open item #2).
**All three devices therefore rely on never handing the shim a failed open:** the Ultra via
its bugs-1/2/5 prevention chain + the hard PA gate; the 11" via its card happening to come up
cleanly + the h2w fix preventing the unrelated abort; the S9+ prospectively via the forked
chain. This is by design (the SEGV is "the messenger, not the root cause" — patch README),
but it means bug 3 remains a live latent crash on every device until the patch lands upstream
and flows back through a Halium rebuild. It is not something an overlay can fix (the shim
lives in the halium system image), so "unsent patch + prevention" is the accurate and
currently-best-achievable state — the action item is the send.

### Bug 4 — droid-extevdev jackless abort

**(a) Ultra — VERIFIED, complete, skeleton-durable.**
- Daemon: `overlay/system/usr/local/lib/gts9u-virtual-h2w.py` — raw-ioctl uinput device
  named `gts9u-virtual-h2w`, EV_SW with SW_HEADPHONE/MICROPHONE/LINEOUT_INSERT, state 0,
  SIGTERM handler destroys the device.
- Unit: `overlay/system/etc/systemd/system/gts9u-virtual-h2w.service`
  (Restart=on-failure, WantedBy=multi-user.target) + VERIFIED wants symlink.
  Note: **no `ExecStartPre modprobe uinput`** (the 11" units have it) — presumably uinput is
  built-in/auto on the Ultra image; if a future image ships uinput as an unloaded module,
  the daemon fails and only the warn-path saves audio. One-line hardening candidate.
- PA wait: two layers. `gts9u-audio-bringup` lines 97–100 wait ≤15 s (warn-only) for
  `gts9u-virtual-h2w` in `/proc/bus/input/devices` **before** touching the ready flag;
  `zz-gts9u-audio.conf` then hard-gates PA (`ExecStartPre=/usr/bin/timeout 150 …
  until [ -e /run/gts9u-audio-ready ]`, **no `-` prefix**, ExecStart reset +
  `env -u HYBRIS_USE_VENDOR_NAMESPACE`). The superseded
  `50-gts9uwifi-wait-audiohal.conf` is asserted ABSENT at `build-gts9uwifi.sh:152`.
- No version gate (unconditional) — harmless even after upstream 14.2.110 lands, since the
  device just sits idle at state 0.

**(b) 11" — VERIFIED, two coexisting variants in `fixes/audio/` (both read in full):**
1. **`gts9-audio-fix-install.sh` — the CANONICAL installer** (per `fixes/audio/README.md`;
   cold-boot validated 2026-08-29/30 per README + `NOTES/audio-cluster.notes.md` §4
   "YUP FIXED AFTER A REBOOT").
   - Mechanism: python3-evdev `UInput` daemon written by the installer to
     `/usr/local/bin/gts9-virtual-h2w` (device name `gts9-virtual-h2w`, SW_HEADPHONE+MIC only,
     no LINEOUT — cosmetic delta vs Ultra); system unit `/etc/systemd/system/
     gts9-virtual-h2w.service` with `ExecStartPre=-/sbin/modprobe uinput`; PA gate written to
     `/home/phablet/.config/systemd/user/pulseaudio.service.d/50-gts9-h2w-gate.conf` —
     **fail-open** (`-` prefix, 30 s bound, always exits 0). Deliberate philosophy split vs
     the Ultra's hard gate: on the 11" the only bug is the abort itself, so a missing jack
     should merely delay PA, never wedge it.
   - **Version gate VERIFIED** (lines 30, 124–129): reads the droid-card module suffix from
     `/etc/pulse/touch.pa`, resolves the dpkg version of `pulseaudio-modules-droid-30`, and
     **refuses to install on ≥ 14.2.110** (`dpkg --compare-versions "$VER" ge "$FIXED_IN"`)
     unless `--force`; `--uninstall` supported; full preflight (python3-evdev, /dev/uinput,
     phablet user, rootfs-rw) validates everything before touching anything.
   - **Durability**: split. Gate drop-in (userdata) + self-copy of the installer to
     `/home/phablet/gts9-audio-fix/install.sh` (lines 227–233) survive a rootfs reflash;
     daemon + system unit live on rootfs and die on reflash → **installer must be rerun after
     every OTA/reflash** (stated in its own header, lines 17–19). Proven failure mode:
     the 2026-08-29 flash wiped userdata too and took even the self-copy
     (`NOTES/audio-cluster.notes.md:92`) — keep the installer off-device
     (open issue #5 there / PORT-STATE §6 persistence discipline).
2. **`gts9-virtual-h2w/` — the minimal-dependency variant** (raw-ioctl py, no python3-evdev;
   `install.sh` installs daemon+unit to rootfs and the **hard-fail** 60 s gate
   `55-gts9wifi-wait-h2w.conf` to `/etc/systemd/user/` — all rootfs, all die on reflash,
   **no version gate, no uninstall**). Kept per README for pip/apt-awkward images.
   - Divergence note: the repo's two variants gate at different paths with different
     semantics (50- fail-open on userdata vs 55- hard-fail on rootfs). Installing both is
     benign (two waits on the same device) but untidy; the README correctly crowns #1.

**(c) S9+ — via the fork:** gets the **Ultra mechanism renamed**, not the 11" installer:
`gts9p-virtual-h2w.py` + `gts9p-virtual-h2w.service` + wants symlink + the bringup's jack
wait + `zz-gts9p-audio.conf` flag gate — every one of these names is explicitly asserted in
`build-gts9pwifi.sh:172–175`, and the runbook bring-up ladder rung 4 checks
`systemctl status gts9p-audio-bringup` + `/run/gts9p-audio-ready`. The sed rename is
self-consistent (VERIFIED: the only occurrences of the h2w device name are the py `struct.pack`
string and the bringup grep, both `gts9u-*` → `gts9p-*` under `s/gts9u/gts9p/g`; the log path
`/var/log/gts9u-audio-bringup.log` renames too). No gts9p-specific naming exists on disk yet —
correct, since the skeleton fork is unexecuted.

### Bug 5a — stale container HAL restart after card ONLINE

**Ultra — VERIFIED.** `gts9u-audio-bringup` lines 85–91: `setprop ctl.restart vendor.audio-hal`
**after** card wait + latch clear, then poll `init.svc.vendor.audio-hal` = `running` ≤30 s
(FATAL), then `sleep 2`. Order matches the KT doc §3 exactly.

**11" — N/A-today / MISSING-as-hardening.** Azkali's image serializes PA behind
`init.svc.vendor.audio-hal == running` via his shipped
`50-gts9wifi-wait-audiohal.conf` (REPORTED: mechanism doc "What Azkali's build actually does";
`NOTES/audio-cluster.notes.md:60`) — which is *transitively* a card_state gate because the HAL
only reaches `running` after its in-process AGM passed the card wait. That protects PA from a
stale HAL **only when the card wins its race within AGM's 100 s window**; it does not restart
a HAL that went permanently stale. Same exposure logic as bug 2. (Side note from the mechanism
doc: Azkali's ExecStartPre uses a bare `$c` that systemd may mangle, and it carries a `-`
prefix — the gate is likely close to fail-open, masked by container ordering usually winning.)

**S9+ — PLANNED** via the forked bringup script; nothing on disk.

### Bug 5b — card_state/aud_dev chmod 0666

**Ultra — VERIFIED.** `gts9u-audio-bringup` line 77:
`chmod 0666 /sys/kernel/snd_card/card_state /sys/kernel/aud_dev/state` immediately after the
card wait, before latch/HAL steps. Correct order.

**11" — MISSING; probably latent-N/A on the current working path.** On the 11" the working
route is the container-service path, where AGM runs inside `vendor.audio-hal` (container root)
— it can open the node. The 0666 matters when AGM's open happens from a non-root uid (the
in-process/passthrough path, or the container uid-space mismatch seen on the Ultra). The
on-device diagnostic also logged a **root-EACCES oddity on `/sys/kernel/aud_dev/state`
(owner uid 1013)** on the 11" (`NOTES/audio-cluster.notes.md:59,115`) — parked, but it shows
node perms/ownership on the 11" are not pristine either. Zero-cost to include in any ported
bringup.

**S9+ — PLANNED** via fork.

### The ≤90 s FATAL wait — VERIFIED
`gts9u-audio-bringup` lines 73–75: `while [ "$(cat $CS)" != "1" ] && [ $c -lt 90 ]; do sleep 1`
→ `FATAL: card not ONLINE after 90s; exit 1` (which, with the no-dash PA gate, correctly keeps
PA down rather than letting it crash-loop and re-poison the latch). Unit `TimeoutStartSec=360`
(`gts9u-audio-bringup.service:9`) clears the worst-case wait chain (~330 s per CHANGES-audio),
fixing the v1-era 240 s truncation bug.

---

## 2. The 5×3 matrix

| Bug | gts9uwifi (Ultra) | gts9wifi (11") | gts9pwifi (S9+) |
|---|---|---|---|
| **1** storm / va keystone | **VERIFIED** · module-walk in `skeleton/overlay/.../sbin/gts9u-audio-bringup:21–36` + build dedupe `skeleton/scripts/swap-vendor-modules.sh:22–29` · **skeleton (survives reflash)** | **MISSING** · no walker, no dedupe; 4× dup CONFIRMED on device (457/357 lines, `audio-cluster.notes.md:59`) — latent, races won so far | **PLANNED** · fork of Ultra chain; guarded by `build-gts9pwifi.sh:164–180` FATAL sanity · **nothing on disk (skeleton fork unexecuted)** |
| **2** Samsung latch clear | **VERIFIED** · bringup `:79–83`, after ONLINE, retry ≤60 s FATAL · **skeleton** | **MISSING** (currently unset on device, but no clear mechanism = unrecoverable-without-manual-setprop if ever tripped) | **PLANNED** via fork (property name untouched by rename) |
| **3** shim null-deref | Patch **VERIFIED** (`patches/upstream/halium-audio-hidl-compat/0001-…patch`) but **UNSENT & DEPLOYED NOWHERE** — Ultra relies on bugs-1/2/5 prevention + hard PA gate | Same patch-only status — relies on healthy card + h2w fix | Same — prevention via forked chain (prospective) |
| **4** extevdev jackless abort | **VERIFIED** · `gts9u-virtual-h2w.py` + `.service` + wants symlink + bringup jack-wait `:97–100` + `zz-gts9u-audio.conf` hard flag-gate · **skeleton** · no version gate (harmless) | **VERIFIED** · `fixes/audio/gts9-audio-fix-install.sh` (canonical, version-gated <14.2.110, `--force/--uninstall`, fail-open 30 s gate) + `gts9-virtual-h2w/` minimal variant · **/data-installer hybrid: gate+self-copy on userdata, daemon+unit on rootfs → rerun per reflash; userdata wipe kills even the self-copy (proven 08-29)** | **PLANNED** · Ultra mechanism renamed gts9p-* — all names asserted in `build-gts9pwifi.sh:172–175` + runbook rung 4 |
| **5a** HAL restart post-ONLINE | **VERIFIED** · bringup `:85–91`, ordered after latch clear, wait `running` ≤30 s FATAL + 2 s settle · **skeleton** | **PARTIAL/N-A-today** · Azkali's `50-gts9wifi-wait-audiohal.conf` waits for HAL running (transitively card-up) but never restarts a stale HAL; gate itself likely near-fail-open (`$c` mangling + `-` prefix, mechanism doc) | **PLANNED** via fork |
| **5b** chmod 0666 nodes | **VERIFIED** · bringup `:77`, post-ONLINE pre-latch · **skeleton** | **MISSING** · likely N/A on container-service path, but aud_dev uid-1013 EACCES oddity parked (`audio-cluster.notes.md:115`) | **PLANNED** via fork |

Durability legend recap: Ultra = everything in skeleton overlay ⇒ survives reflash (rebuilt
into every image). 11" = installer model ⇒ must be rerun after every OTA/reflash and the
installer must be kept off-device. S9+ = will be skeleton-durable **once the fork is executed**;
today it has no build, so its column is entirely prospective.

---

## 3. The two questions asked

### Does gts9wifi need bugs 1/2/5 protections as preventive hardening?

**Yes — this is evidence-backed, not speculative.**
1. The bug-1 amplifier is CONFIRMED PRESENT on the 11" (457-line / 357-unique modules.load,
   `audio-cluster.notes.md:59` — a direct on-device measurement, not an inference). Its card
   has won the race on observed boots (ONLINE ×1 @13.16 s), but the Ultra showed the same
   loader losing `lpass_cdc_va_macro_dlkm` or `machine_dlkm` nondeterministically under 4×
   amplification. Nothing about the 11" removes the mechanism; it just has better odds
   (possibly fewer amp modules / different timing).
2. The failure mode is not "one bad boot": one lost race ⇒ AGM 100 s timeout ⇒ **bug-2 latch
   set persistently** ⇒ every later boot refuses `adev_open` in ~1 ms even with a healthy card
   ⇒ shim null-deref SEGV loop (bug 3, unpatched everywhere) ⇒ start-limit ⇒ session-permanent
   audio loss — on the user's **daily driver**, with no installed mechanism that would ever
   clear it. Recovery would require manual `setprop` + HAL restart knowledge.
3. Consolidated open issue #2 in `audio-cluster.notes.md:114` already recommends exactly this:
   "dedupe in image or port the Ultra's module-walker service."

### Would installing the Ultra bringup mechanism on the 11" be safe/beneficial?

**Beneficial: yes. Safe: yes with three small adaptations — do not drop the files in verbatim.**
- **Mechanically portable:** the bringup script is path- and data-driven
  (`/android/vendor_dlkm/lib/modules/modules.load` — same path on the 11", confirmed in
  `audio-cluster.notes.md:126`; latch property, HAL service name, sysfs nodes all identical
  per the KT doc §7). The walker no-ops modules already live; the finit allowlist
  (`muic_sm5714 pdic_sm5714 wez01`) is harmless on the 11" where those load cleanly
  (they'll report `=live`).
- **Adaptation 1 — jack-device name:** the bringup waits for the literal string
  `gts9u-virtual-h2w` in `/proc/bus/input/devices` (script lines 97–100). The 11"'s installed
  daemon is named `gts9-virtual-h2w`, so an unmodified script would burn the 15 s warn-wait
  every boot. Rename the grep (or the daemon) — or make the name a variable for a
  family-generic `gts9-audio-bringup`.
- **Adaptation 2 — PA drop-in collision:** Azkali's image ships
  `/etc/systemd/user/pulseaudio.service.d/50-gts9wifi-wait-audiohal.conf`. The Ultra's
  `zz-gts9u-audio.conf` resets ExecStart; two drop-ins double-resetting ExecStart is exactly
  the "merge-order roulette" the Ultra skeleton eliminated by deleting the 50- file
  (`CHANGES-audio.md`; asserted absent at `build-gts9uwifi.sh:152`). On the 11" the installer
  must mask/remove the shipped 50- conf (and restore it on uninstall) — or fold the flag-wait
  into a single consolidated drop-in.
- **Adaptation 3 — gate philosophy:** the Ultra gate is deliberately hard-fail (no `-`),
  correct where a half-ready stack means a SEGV loop. On the daily-driven 11" the established
  local philosophy is fail-open-after-bound (the canonical installer's 30 s gate). A ported
  bringup should hard-gate only while the bringup service itself is healthy — in practice the
  Ultra design already handles this (systemd retries + 150 s timeout per attempt), but pick
  one philosophy and document it; a wedged PA on the daily driver is a real usability cost.
- **Cheapest high-value subset if a full port feels heavy:** (a) dedupe the modules.load
  *inside the 11" image's vendor_dlkm* (or ship the walker service only), (b) add a boot-time
  unconditional `setprop vendor.audio.use.primary.default false` + conditional
  `ctl.restart vendor.audio-hal` after card ONLINE. That closes the latch trap with ~20 lines.
- **Durability caveat:** anything installed on the 11"'s rootfs dies on reflash (proven).
  A ported bringup should go into the same self-copying installer pattern as
  `gts9-audio-fix-install.sh` — ideally merged INTO it as one canonical
  "gts9wifi audio hardening" installer — and, longer-term, be offered upstream to Azkali as
  overlay material (it is his image; PORT-STATE §6 items 1–2 are the upstream sends).

---

## 4. Expected-but-absent / discrepancy flags (loud list)

1. **LOUD — Bug-3 shim patch deployed nowhere and UNSENT** (`patches/.../halium-audio-hidl-compat/README.md:7`).
   Every device carries the live null-deref; the only shim binary in the repo is the *stock*
   evidence copy (`archive/binaries/MANIFEST.md`). Highest-leverage open item #2; the extevdev
   packaging ask (#1) is likewise UNSENT (`patches/upstream/pulseaudio-modules-droid/README.md:8`).
2. **LOUD — 11" carries the confirmed 4× modules.load amplifier with zero bug-1/2/5 protection**
   (§3 above). Daily driver; latch trap is persistent-until-manual-fix.
3. **S9+ has nothing on disk** — its whole audio column exists only as build-script assertions
   and runbook text. Fine for an unexecuted port, but any parity statement for gts9pwifi is
   prospective until the skeleton fork + build happen (PORT-STATE §6 #13).
4. Version-label drift: the on-disk bringup script header says **v3**
   (`gts9u-audio-bringup:2`) while `fixes/audio/README.md:21` calls it **v4** and PORT-STATE §3
   says "v3/v4". Per `audio-config_09358316.p3.notes.md:33` the v4 fingerprint is the
   "finit stage" string — which the on-disk script HAS (line 47 region), so the content is v4
   and only the header comment is stale. Cosmetic, but it will confuse a future auditor.
5. Ultra `gts9u-virtual-h2w.service` lacks `ExecStartPre=-modprobe uinput` (both 11" unit
   variants have it). Works today; one-line belt if uinput ever ships modular.
6. Skeleton vendor-ramdisk `modules.load` has a duplicate `qrng_dlkm.ko` line (audio-irrelevant;
   shows the ramdisk list is un-deduped).
7. `swap-vendor-modules.sh` on disk is the dedupe revision but NOT the F2 "LEFTOVER/UNLANDED
   audit + allowlist strict mode" revision that `build-gts9uwifi.sh:179` comments reference —
   exactly the reconcile flagged in `CHANGES-audio.md` open items. Build-quality parity gap,
   not an audio-fix gap.
8. Doc inconsistency: `gts9u-audio-online-mechanism.md` (v2, items 7 & "do this first") names
   the macro set **va/wsa/wsa2**, while PORT-STATE §3 and the KT doc say the Ultra DT enables
   **va/rx/tx** (wsa/wsa2 disabled). Operationally moot (the bringup walks the whole list),
   but one of the two docs is wrong about which macros gate the card; PORT-STATE's version is
   the later synthesis.
9. 11" fix duplication: two h2w variants with different gate paths/semantics coexist in
   `fixes/audio/` (canonical installer's `50-gts9-h2w-gate.conf` fail-open vs the variant's
   `55-gts9wifi-wait-h2w.conf` hard-fail). README crowns the right one; consider marking the
   variant's hard-fail gate as superseded to prevent a future double-install.
10. Parked on-device oddity: `/sys/kernel/aud_dev/state` owner uid 1013 root-EACCES on the 11"
    (`audio-cluster.notes.md:115`) — would be auto-covered by a ported 5b chmod.

---

## 5. Bottom line

- **Ultra:** all five bugs covered, correctly ordered, skeleton-durable, build-gated. VERIFIED
  end to end on disk. Only bug 3 is "prevented, not fixed" — true everywhere until the patch ships.
- **11":** only the bug it has hit (#4) is fixed, via a well-engineered version-gated installer —
  but it demonstrably carries the bug-1 amplifier and has no latch/HAL-restart safety net, and
  its fix durability depends on rerunning an installer that has already been wiped once.
  Preventive port of bugs 1/2/5 (with the three adaptations) is justified by on-device evidence.
- **S9+:** the plan and guardrails are genuinely complete (build-script FATALs + runbook), and it
  will inherit the full Ultra chain — but nothing exists yet; execute the fork before trusting
  any parity claim.
- **Both upstream audio sends (extevdev bump, shim patch) remain unsent** — they are the only
  path to retiring the workarounds on every device at once.
