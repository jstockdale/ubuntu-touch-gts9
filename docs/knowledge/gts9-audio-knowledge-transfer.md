# Ubuntu Touch audio on Samsung Galaxy Tab S9 – knowledge transfer
For troubleshooting the **11" Tab S9 (gts9wifi, SM-X710 / SM-X716B)**.
Derived from a full debugging campaign on the **Ultra (gts9uwifi, SM-X910)**,
UT 24.04 / Halium 13 / kalama platform, 2026-08. Hand this to a fresh Claude
session; it assumes no prior context.

────────────────────────────────────────────────────────────────────────
## 0. READ THIS FIRST – the 11" is the reference port

The Ultra port (where all findings below were derived) was built ON TOP OF
**Azkali's gts9wifi (11") port**. That means:

1. **Azkali's gts9wifi build may already have working audio.** Before
   debugging anything, establish: does a stock/current Azkali gts9wifi image
   produce sound? If yes, the job is likely *comparison* (what differs in the
   user's build/pipeline) not *first-principles bring-up*. If the user IS
   Azkali, or audio is broken in the reference too, the full playbook applies.
2. The two devices share the **entire audio architecture**: same SoC
   (SM8550/kalama), same Qualcomm audio DSP stack (lpass-cdc macros, AGM/PAL,
   Samsung AHAL), same Halium wrapper shim, same UT PulseAudio-droid stack.
   Every mechanism below transfers. What differs is DATA, not structure –
   see §7 for the device-specific deltas to verify on the 11".
3. Reference repos (Azkali, gitlab.com/azkali-samsung and git.codelinaro.org):
   - audio-kernel @ android13-5.15-halium
   - AGM @ LA.VENDOR.13.2.1.c25
   - device repo samsung-gts9 @ halium-13
   - kernel-samsung-gts9wifi (the 11" IS this tree; the Ultra borrows it)

The single most valuable first action: **diff the 11" against a known-good
gts9wifi boot**, not re-derive from scratch. We had no reference and paid for
it in ~23 debugging rounds.

────────────────────────────────────────────────────────────────────────
## 1. THE ARCHITECTURE (the signal path, and where each bug lives)

Sound on this stack traverses two worlds – the host (Ubuntu/glibc) and the
Android container (Halium/bionic):

```
  [HOST]  PulseAudio (phablet user)
            └─ module-droid-card / droid-util
                 └─ audio.hidl_compat.default.so   ← THE SHIM (bug #3)
                      │  (in-process, libhybris bionic linker)
                      ▼  hwbinder IPC
  [CONTAINER]  android.hardware.audio.service_64
                 └─ audio.primary.kalama.so  (Samsung AHAL)  ← latch guard (bug #2)
                      └─ PAL (libar-pal.so) → AGM (libagm.so)
                           └─ reads /sys/kernel/snd_card/card_state  ← perms (bug #5b)
  [KERNEL]  machine driver (kalama.c) registers the ASoC card
                 └─ needs lpass-cdc macros bound  ← va keystone (bug #1)
                 └─ card_state flips 1 when card registers
```

Plus a parallel host-side landmine in the UT PulseAudio module that has
nothing to do with the card: **droid-extevdev** aborting PA on jackless
hardware (bug #4).

Key files/paths (verify names on 11", but expect identical):
- `/sys/kernel/snd_card/card_state` – 0/1, the master readiness bit
- `/sys/kernel/aud_dev/state` – companion node
- `/proc/snd_debug_proc/sdp_boot_log` – Samsung's 64K boot log; the ONLY
  place "snd_card is ONLINE" is printed (NOT dmesg)
- `/android/vendor_dlkm/lib/modules/` – the DLKM .ko files + modules.load
- `/android/vendor/lib64/hw/audio.primary.kalama.so` – the AHAL
- `/android/system/lib64/hw/audio.hidl_compat.default.so` – the shim
- Container: `android.hardware.audio.service_64` (the vendor HAL service)
- Property: `vendor.audio.use.primary.default` – the latch (bug #2)

────────────────────────────────────────────────────────────────────────
## 2. THE FIVE-BUG CHAIN (each masks the next – this is why it's hard)

The defining property: fixing any one bug reveals the next, so partial fixes
look like failures. Symptoms overlap. Only a systematic layer-by-layer walk
(and, at the end, a core dump) untangles it. Below, each bug: SYMPTOM →
ROOT CAUSE → FIX → HOW TO CONFIRM on the 11".

### BUG #1 – Module load storm: sound card never appears

**Symptom:** `/proc/asound/cards` shows "no soundcards"; `card_state` reads
empty or 0; nondeterministic across boots (works ~1 boot in N, or comes up
minutes late). PulseAudio finds no droid sinks.

**Root cause:** Samsung's `/vendor/bin/vendor_modprobe.sh` (launched from
init.qti.kernel.rc) backgrounds EVERY modprobe in parallel and discards exit
codes. If the modules.load list is duplicated (ours was 4×, a build-pipeline
artifact – CHECK the 11"'s list), the spawn storm multiplies and modules drop
randomly. The critical dependency: **rx-macro and tx-macro probes DEFER until
va-macro is registered, BY DESIGN** –
`lpass_cdc_is_va_macro_registered()` in lpass-cdc-rx-macro.c (~line 4669) and
lpass-cdc-tx-macro.c (~2222) return -EPROBE_DEFER. So if
`lpass_cdc_va_macro_dlkm` loses the race, rx/tx defer forever, the machine
card never registers, card_state stays 0. On some boots `machine_dlkm` ITSELF
drops → the card_state node doesn't even exist.

**Fix:** (a) De-duplicate modules.load at build time (`awk '!seen[$0]++'`).
(b) A boot service that walks modules.load itself (deduped, blocklist-honored)
and inserts every hole. Healthy boot = no-op. On the Ultra, a single
`insmod .../lpass_cdc_va_macro_dlkm.ko` produced register-macro ×3 → card
registered → ONLINE in a 70ms cascade – proof the keystone is va.

**Confirm on 11":** `cat /proc/asound/cards`; if empty, check
`lsmod | grep lpass_cdc` for which macros loaded, and
`cat /sys/kernel/debug/devices_deferred` for rx/tx waiting. If the list is
`wc -l /android/vendor_dlkm/lib/modules/modules.load` and shows 4× the unique
count, that's the storm amplifier. NOTE: the 11" may have a DIFFERENT set of
enabled macros (§7) – but va is the SoC-level keystone regardless.

### BUG #2 – Samsung's fallback latch: adev_open refuses forever

**Symptom:** Card is ONLINE (card_state=1) but PulseAudio still can't open
audio; container logcat shows `AHAL: AudioDevice: adev_open: 2786: fail to
open audio device, sndcard is not active` and `Exit, status -22`, in ~1ms,
with no AGM retry. Survives service restarts. Comes back on every boot that
had the card down at the wrong moment.

**Root cause:** When AGM's card-wait times out (because bug #1 made the card
late), Samsung's failure handler sets the property
`vendor.audio.use.primary.default=true`. From then on the AHAL's adev_open
guard short-circuits, refusing regardless of actual card state. The property
name and the "sndcard is not active" string are both baked into
`audio.primary.kalama.so` (confirm: `strings` it). This ONE property explains
every "card is up but still no audio" symptom.

**Fix:** `setprop vendor.audio.use.primary.default false` – non-persistent, so
re-set on every boot AFTER the card is ONLINE. Whether the initial `true` is a
vendor build.prop default or purely runtime-set was never fully pinned; clear
it unconditionally to cover both.

**Confirm on 11":** `getprop vendor.audio.use.primary.default`. If `true` with
a live card, this is the wall. Set it false, then restart the container HAL
(bug #5) and retry.

### BUG #3 – Halium shim swallows errors → PulseAudio SIGSEGV

**Symptom:** With any upstream failure (e.g. the latch above), PulseAudio dies
with **SIGSEGV** – under systemd it's a crash-loop; foreground it's a hard
segfault. Logcat shows the factory returning `openDevice() error -19` but
droid-util prints "Opened hw audio device version 2.0" ANYWAY (the tell – a
success message over a failure). Last logcat line before death is
`adev_init_check`.

**Root cause:** `audio.hidl_compat.default.so` (Halium's wrapper HAL,
source: `android_vendor_halium_hardware/audio/audio_hw.cpp`). Its `adev_open`
logs the factory error then RETURNS 0 with `deviceIface` left null; the first
forwarded call – `adev_init_check` – dereferences the null sp<> and crashes.
Core-verified on Ultra: `signal=11 SEGV_MAPERR fault_addr=0x0`,
PC at shim+0x2280, LR=PC-8, x0=0. The bug is byte-identical across halium-12.0
through 16.0 and master.

**Fix:** This is upstream-patchable (early-return in adev_open on factory
failure – a patch was written: search for
`0001-audio_hw-fail-adev_open-when-the-devices-factory-can.patch`). BUT the
shim crash is a SYMPTOM – it only fires because something upstream failed.
Fix bugs #1/#2/#5 and the shim never gets a null. So: the shim patch is
hardening (converts future failures into log lines instead of core dumps),
not the primary fix. Don't chase the SEGV as the root cause – it's the messenger.

**Confirm on 11":** if PA segfaults at droid-card load, get a core dump
(`sysctl -w kernel.core_pattern=/home/phablet/core.%e.%p`, add
`LimitCORE=infinity`), and the faulting library naming the shim confirms it –
but the real question is what upstream failure fed it the null. Look at the
container logcat for the -19/-22 that preceded it.

### BUG #4 – droid-extevdev aborts PA on a jackless tablet

**Symptom:** PA reaches "Opened hw audio device" and even creates droid sinks,
then ABORTS (SIGABRT, rc=134) with:
`droid-extevdev.c: could not start input device detection` immediately
followed by `Assertion 'e' failed at ../src/pulse/mainloop.c: ...
mainloop_io_free()`. This is INDEPENDENT of bugs #1-3 – it fires even with a
perfectly working card.

**Root cause:** UT's jack-detection code (droid-extevdev, in
pulseaudio-modules-droid / module-droid-card) scans input devices for one with
`EV_SW` + `SW_HEADPHONE_INSERT`. A jackless tablet has none, the scan declares
detection impossible, and its error path calls `mainloop_io_free()` on an io
event that was never created → PA's own assert aborts the daemon. The extcon
path degrades gracefully; the evdev path treats no-jack as fatal.

**Fix:** Give it a jack. A ~20-line uinput daemon creates a virtual input
device advertising `SW_HEADPHONE_INSERT` (+ MIC/LINEOUT), state 0 (unplugged =
speaker route). The scan finds it, detection starts, no abort. This shipped on
the Ultra as `gts9u-virtual-h2w.service`. Upstream fix (make zero-jack
non-fatal + guard the null free) is also possible but not yet written.

**Confirm on 11":** does PA abort with the mainloop_io_free assert AFTER
creating sinks? Then it's this. `ls /sys/class/switch/` and check
`/proc/bus/input/devices` for any `SW_HEADPHONE_INSERT` device – if none, the
virtual-jack daemon is the fix. NOTE: if the 11" cover/config provides a real
headset switch, this bug may not fire – verify before assuming.

### BUG #5 – Stale container HAL + node permissions

**Symptom (5a):** Everything above fixed, card ONLINE, latch cleared, but
adev_open still fails – because the container's `vendor.audio-hal` service
started at boot when the card was DOWN, and its in-process AGM is permanently
in a failed state.

**Fix (5a):** `setprop ctl.restart vendor.audio-hal` AFTER card is ONLINE and
latch is cleared; wait for `init.svc.vendor.audio-hal` = running.

**Symptom (5b):** AGM inside the container can't read card_state even when it's
1 – because the node is `0660 root:audio` (host gid), and the container's AGM
opens it O_RDWR from the container's own uid space where host gid 29 is
meaningless.

**Fix (5b):** `chmod 0666 /sys/kernel/snd_card/card_state
/sys/kernel/aud_dev/state` (single-user-device tradeoff; 0666 on a one-byte
state node is acceptable for bring-up).

**Confirm on 11":** after clearing the latch, if adev_open still fails, restart
the HAL and re-check. If AGM logs sysfs-open failures, it's the perms.

────────────────────────────────────────────────────────────────────────
## 3. THE ORDER THAT ACTUALLY WORKS (bring-up sequence)

All five fixes must happen in dependency order. The Ultra's boot service does
exactly this; port it to the 11" (adjusting module/device names per §7):

1. Walk modules.load (deduped, blocklist-honored); insert every missing module
   via plain insmod. [bug #1]
2. Wait for card_state == 1 (poll, ~90s cap). [bug #1 result]
3. `chmod 0666` the two sysfs state nodes. [bug #5b]
4. `setprop vendor.audio.use.primary.default false` (poll until it sticks). [bug #2]
5. `setprop ctl.restart vendor.audio-hal`; wait init.svc = running; sleep ~2s. [bug #5a]
6. (If bug #4 applies) ensure the virtual jack device exists.
7. Touch a flag file (e.g. /run/audio-ready).
8. PulseAudio's systemd unit GATES on that flag – hard-fail if it never
   appears (a `-`-prefixed / non-gated start races into the crash loop and
   re-triggers the latch). [ties #2/#3 together]

Critical design note: **PA must gate on "bring-up complete", NOT on raw
card_state.** A live card behind a stale HAL still crashes PA. The flag file
means all of card+latch+HAL+jack are ready before PA starts.

────────────────────────────────────────────────────────────────────────
## 4. PULSEAUDIO UNIT CONFIG (the working drop-in)

The UT PulseAudio user unit needs a drop-in
(`~/.config` or `/etc/systemd/user/pulseaudio.service.d/`). The working one on
the Ultra:
- `ExecStartPre` gate: `until [ -e /run/<ready-flag> ]; do sleep 1; done`
  (timeout ~150s, NO `-` prefix – must fail if not ready)
- `ExecStart=` reset, then
  `ExecStart=/usr/bin/env -u HYBRIS_USE_VENDOR_NAMESPACE /usr/bin/pulseaudio
   --daemonize=no --log-target=journal` (the `-u` strips the namespace var; see
  exoneration note – with the container-HAL path this is the config that works)
- Sandbox relaxations were included during debugging
  (MemoryDenyWriteExecute=no, SystemCallFilter=, LockPersonality=no,
  RestrictNamespaces=no) but were NEVER PROVEN necessary – see §5. They may be
  removable; re-tighten one at a time if you care.

Stock UT ships a drop-in that sets HYBRIS_USE_VENDOR_NAMESPACE=1 and PULSE_SCRIPT.
Watch for drop-in merge order (later files override ExecStart). Consolidate to
ONE drop-in to avoid roulette.

────────────────────────────────────────────────────────────────────────
## 5. EXONERATED SUSPECTS – do NOT waste time here

We burned many rounds on these. All PROVEN irrelevant to the SEGV:

- **systemd sandbox hardening** (MemoryDenyWriteExecute, SystemCallFilter,
  LockPersonality, RestrictNamespaces, NoNewPrivileges, UMask, Slice,
  Type=notify): relaxing them did NOT fix; the crash reproduced foreground with
  NO sandbox. Not the cause.
- **HYBRIS_USE_VENDOR_NAMESPACE**: crash reproduced with it both set and unset.
  (Nuance: with it SET, the HAL loads in-process and fails CLEANLY – no sinks,
  no crash. The working config uses the container-service path with it stripped.)
- **LD_PRELOAD=libtls-padding.so**: exonerated for PA (crash without it). BUT it
  really does break `logcat` via lxc-attach – use `--clear-env` for logcat.
- **HYBRIS_LD_LIBRARY_PATH**: exonerated.
- **Host /dev/snd permissions**: fine (root:audio 0660, phablet in audio group,
  controlC0 opens rw). The perms problem that mattered was CONTAINER-side (5b).
- **Container HAL library health**: audio.primary.kalama.so dlopens fine – the
  AHAL log lines print from inside it. Not a missing-dependency problem.
- **socket activation / Type=notify / LISTEN_FDS**: not the cause (transient
  units without sockets crashed identically).

The unit-vs-foreground "context dependence" that seemed real early was an
ILLUSION: the working foreground runs happened BEFORE the latch flipped;
once time-matched, foreground crashed too. Beware this trap – always run a
time-matched control.

────────────────────────────────────────────────────────────────────────
## 6. THE DIAGNOSTIC TOOLKIT (techniques that worked)

Give these to the fresh session; they're how the truth got extracted:

**Reading Samsung's boot log** (ONLINE is not in dmesg):
`grep -c ONLINE /proc/snd_debug_proc/sdp_boot_log` – 0 = never came up, 1 =
came up once and stable, >1 = came up then TORE DOWN (a separate runtime bug).

**Container logcat, correctly** (the host/container split matters):
`lxc-attach -n android --clear-env -- logcat -b main,system,crash -d`
(--clear-env is REQUIRED or the libtls-padding preload breaks logcat). Filter
for `AHAL|AGM|adev_open|DevicesFactory|audio_hw|snd sysfs`. The pid columns
distinguish worlds: shim logs carry pid 0 (hybris liblog); the vendor service
logs carry its real pid. That split is how you tell host-side from
container-side failures.

**Which macros loaded / deferred:**
`lsmod | grep lpass_cdc`; `cat /sys/kernel/debug/devices_deferred`
(mount debugfs first if needed).

**Core dump triage** (when PA segfaults, to name the faulting library without
gdb): set `kernel.core_pattern`, add `LimitCORE=infinity` to the unit, catch
the core, parse the ELF note sections for NT_PRSTATUS (registers → PC) and
NT_FILE (memory map → which .so the PC is in). PC-in-shim + fault_addr=0 =
the null-deref. (A Python ELF-note parser was written for this; ~60 lines,
no gdb needed.)

**Time-matched controls:** ALWAYS reproduce foreground and via-unit in the
SAME time window. State (the latch) changes between attempts and creates
phantom "it works foreground but not as a service" conclusions.

**Capture rc correctly:** `cmd; rc=$?` BEFORE any pipe – piping to tee/tail
captures the pipeline's rc, not the command's. (This bit us twice – a false
"survived" reading.)

**evemu-record / libinput list-devices** for input-side questions (the jack
device, etc.) – more reliable than hand-rolled evdev readers.

**DANGER:** never `rmmod machine_dlkm` – it panics the box (no ramoops backend
on this config = unrecoverable). And pstore/ramoops is absent
(dump_sink=0x0), so kernel panics leave no post-mortem.

────────────────────────────────────────────────────────────────────────
## 7. DEVICE-SPECIFIC DELTAS TO VERIFY ON THE 11"

Everything structural transfers. These are the DATA points that WILL differ or
must be confirmed on gts9wifi (SM-X710) vs gts9uwifi (SM-X910):

1. **Codename / platform:** 11" = gts9wifi, kalama (same platform). Card name
   string was `kalama-mtp-snd-card` on Ultra – verify via
   `cat /proc/asound/cards` (machine driver kalama.c is shared, so likely same).

2. **Speaker amplifiers (WILL differ – most likely delta):** the Ultra's DT
   ext-dev-names had **4× cs35l45** (i2c 18-0030..0033) + btfmslim_slave. The
   11" is a smaller device and very likely has FEWER amps (perhaps 2×) or a
   different amp layout. Check the machine node's `ext-dev-names` and the
   `snd_soc_cirrus_amp` / cs35l45 instances in `lsmod` and dmesg. This affects
   which amp modules must load but NOT the card-bring-up logic.

3. **Which lpass-cdc macros are enabled:** Ultra DT had num-macros=3 with
   va/rx/tx okay and wsa/wsa2 DISABLED. The 11" may enable a different set
   (e.g. if it has different speaker routing). Check
   `/proc/device-tree/.../lpass-cdc/` or the DTS `num-macros` and per-macro
   `status`. va remains the keystone regardless.

4. **Module names:** the DLKM .ko names should be identical (same SoC), but
   confirm `ls /android/vendor_dlkm/lib/modules/ | grep -E "lpass|macro|machine"`.

5. **modules.load duplication:** CHECK whether the 11"'s list is duplicated.
   Ours was a 4× artifact of OUR extract/build pipeline – Azkali's original may
   be clean. `awk '{c[$0]++} END{for(k in c) if(c[k]>1) print c[k],k}'
   /android/vendor_dlkm/lib/modules/modules.load`.

6. **The latch property:** same name (`vendor.audio.use.primary.default`),
   same AHAL (audio.primary.kalama.so). Should behave identically.

7. **The shim, extevdev, AGM/PAL:** all UT/Halium-generation, not
   device-specific. Identical.

8. **Headset jack:** if the 11" or its cover exposes a real headset switch,
   bug #4 may not fire. Verify before shipping the virtual jack.

Because the 11" IS Azkali's tree, the fastest path for items 2/3/5 is to read
his DTS directly (kernel-samsung-gts9wifi,
arch/arm64/boot/dts/samsung/galaxytab/gts9wifi/) rather than probe the device.

────────────────────────────────────────────────────────────────────────
## 8. SECONDARY / UPSTREAM ITEMS (context, not blockers)

- **QC kernel accounting bug:** `lpass_cdc_unregister_macro` (lpass-cdc.c
  ~722-761) zeroes `macro_params[id].num_dais` BEFORE subtracting from
  `priv->num_dais`, so the count never decrements; re-registration then reads
  past the once-allocated DAI buffer and the probe hard-fails with no rollback.
  Means any macro UNBIND is unrecoverable without parent reload/reboot. Relevant
  if you hit runtime teardown (card goes from ONLINE to gone). Upstreamable.

- **Runtime teardown ghost:** on the Ultra, one early boot had the card come
  ONLINE then tear down; never reproduced (ONLINE count stayed 1 across days).
  `btfmslim_slave` (a card component tied to BT/FM slimbus) was the untested
  suspect – if the 11" shows card death on BT toggle, that's the lead.

- **Clock jump:** the container time service can jump the wall clock to ~1970
  mid-boot (corrected later by NTP). Harmless to audio (all waits are state
  polls / monotonic timeouts) but it scrambles `journalctl -b` time filtering
  and log timestamps. If logs look time-corrupted, this is why. Persistent
  logs should stamp with /proc/uptime, not wall clock.

- **journald kmsg:** Halium ships `ReadKMsg=no` (an lxc-android-config
  drop-in). If you need kernel logs in the journal for debugging, override with
  `ReadKMsg=yes` – but it's debug-only (journal volume cost) and accelerates
  rotation of early-boot entries.

────────────────────────────────────────────────────────────────────────
## 9. QUICK-START TRIAGE for the fresh session

1. Does a known-good Azkali gts9wifi image have sound? If yes → compare, don't
   re-derive. If no/unknown → continue.
2. `cat /proc/asound/cards` – no card? → bug #1 (macros/storm). Check
   `lsmod | grep lpass_cdc` and `devices_deferred`. Try
   `insmod .../lpass_cdc_va_macro_dlkm.ko` and watch for the cascade.
3. Card present but no sound? `getprop vendor.audio.use.primary.default` –
   `true`? → bug #2. Clear it, restart vendor.audio-hal (bug #5a),
   `chmod 0666` the state nodes (bug #5b), retry.
4. PA segfaults at droid-card? → bug #3 is the messenger; find the upstream
   -19/-22 in container logcat that fed it the null.
5. PA aborts (not segfaults) with a mainloop_io_free assert after making
   sinks? → bug #4, install the virtual jack.
6. Sequence all fixes in the §3 order behind a flag file, gate PA on it.
7. Verify device-specific deltas in §7 (esp. amp count and modules.load dupe).

The mental model that unlocks it: **there is no single "audio bug." There are
five, layered, each hiding the next. Fix them in dependency order, gate
PulseAudio on the whole chain being ready, and use container-side logcat +
the pid split to tell which layer is currently failing.**
