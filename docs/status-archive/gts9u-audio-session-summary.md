# gts9uwifi audio bring-up – session summary, findings, and todos
Ubuntu Touch 24.04 / Samsung Galaxy Tab S9 Ultra (SM-X910) – 2026-08-08 session
Companion docs: CHANGES-audio.md (ship notes), shim-crash-analysis.md (crash evidence chain),
gts9u-audio-fix/gts9u-audio-online-mechanism.md (v2 kernel-side mechanism, pre-compaction).

## Executive summary

Started with a tablet whose audio worked never-or-at-t≈340s depending on boot luck, and
whose PulseAudio died by SIGSEGV under systemd in a way that resisted a full night of
environment, sandbox, and context bisection. Root cause was five stacked bugs, each
masking the next. All five are now named, evidenced, and either fixed or worked around;
the boot chain is deterministic (~20.5s kernel-start to PA release, bring-up itself
8.49s measured monotonically); the skeleton and build script ship the whole fix set;
the tablet is byte-identical to the skeleton; first sound, warm recovery, warm restart,
and one unattended cold boot are all demonstrated. A virgin sideload of a fresh build
remains the final undemonstrated certificate.

## The five-bug causal chain

1. MODULE LOAD STORM (boot lottery). `vendor_modprobe.sh` backgrounds every modprobe in
   parallel and discards exit codes; the image's `modules.load` was duplicated 4x,
   multiplying the storm. Modules drop nondeterministically per boot – observed: only
   va-macro missing (probe6), va late at t≈340s (first "good" boot), machine_dlkm itself
   missing (cold boot of 12:42). Kernel design makes va the keystone: rx-macro
   (lpass-cdc-rx-macro.c:4669) and tx-macro (:2222) both defer until
   `lpass_cdc_is_va_macro_registered()` – so one dropped module means the card never
   registers. Proof of mechanism: a single `insmod lpass_cdc_va_macro_dlkm.ko` produced
   register-macro x3, card registration, and `snd_card is ONLINE` in a 70ms cascade
   (probe7). Fix: build-time dedupe in swap-vendor-modules.sh (with selinux xattr
   restore) + runtime belt (bringup v3 walks modules.load itself, deduped and
   blocklist-honored, inserting every hole).

2. SAMSUNG'S FALLBACK LATCH (the wall that survived everything). One boot with the card
   offline makes AGM's failure handler set `vendor.audio.use.primary.default=true`.
   From then on the vendor AHAL's adev_open guard (AudioDevice.cpp:2786,
   "fail to open audio device, sndcard is not active", Exit status -22) refuses in ~1ms
   regardless of actual card state – surviving audio-hal restarts, and reaching the
   client as factory EINVAL / openDevice -19. Confirmed by strings in
   audio.primary.kalama.so (property name + message co-resident) and by the logcat
   sequence at 01:12 ("sound card err, vendor.audio.use.primary.default as true").
   This one property explains every post-card-ONLINE failure of the first night.
   Whether the initial `true` is a vendor build.prop default or purely runtime-set was
   never pinned down – the bringup clears it unconditionally, covering both. Cleared by
   `setprop vendor.audio.use.primary.default false` (non-persistent; re-cleared every
   boot by the service).

3. HALIUM SHIM ERROR SWALLOW (the lie that made everything look like a PA bug).
   `audio.hidl_compat.default.so` adev_open logs the factory error then returns 0 with
   `deviceIface` null; droid-util prints "Opened hw audio device version 2.0" (the
   lie's origin); the first forwarded call – adev_init_check, always the last logcat
   line before death – dereferences the null sp<> and SIGSEGVs. Core-proven:
   signal 11 SEGV_MAPERR, fault_addr 0x0, PC = shim+0x2280, LR = PC-8 (return from the
   ALOGV), x0 = 0; disassembly matched to source exactly (deviceIface at wrapper+0x150,
   vtable slot +0x38 = initCheck; sibling trampolines confirm ops ordering). The bug is
   byte-identical on halium-12.0, 13.0, 14.0, 16.0, and master. Patch cut and committed:
   0001-audio_hw-fail-adev_open-when-the-devices-factory-can.patch (early return,
   delete wrapper, null the out param). Reviewer aside included: adev_open opens
   AUDIO_HARDWARE_MODULE_ID_PRIMARY regardless of the requested name, which makes
   client logs ("audio_hw_if") disagree with server logs ("audio.primary").

4. DROID-EXTEVDEV JACKLESS ABORT (the crash after the crash). UT's jack-detection scans
   input devices for EV_SW + SW_HEADPHONE_INSERT; on a jackless tablet it finds zero,
   declares "could not start input device detection", and its error path calls
   `mainloop_io_free(NULL)` – PA assert, SIGABRT (rc=134). Observed module:
   module-droid-card-28.so under /usr/lib/pulse-16.1+dfsg1/modules. The extcon path
   right above it degrades gracefully ("Cannot open /sys/class/switch/h2w/state.
   Skipping."); the evdev path does not. Shipped workaround: gts9u-virtual-h2w.service
   creates a uinput device advertising SW_HEADPHONE_INSERT/MIC/LINEOUT, state 0
   (speaker route); bringup waits for it before releasing PA. Upstream patch still to
   draft (make zero jack devices non-fatal + guard the null free).

5. STALE CONTAINER HAL (the fix that undid itself). The container's
   android.hardware.audio.service_64 that starts before the card is up keeps a
   permanently failed in-process AGM; adev_open fails forever even after the card comes
   ONLINE and the latch is cleared. Every manual success included a
   `setprop ctl.restart vendor.audio-hal` after card-up; v2's omission of it is why PA
   died at 13:03 with a perfect card. v3's step 5 restarts it after card ONLINE + latch
   clear, then waits for init.svc = running. Related container fact: the AGM inside the
   service opens /sys/kernel/snd_card/card_state O_RDWR from the container's uid space
   – host-group 0660 (root:audio) locks it out, hence the 0666 on the two nodes
   (documented single-user-device tradeoff).

## Exonerated suspects and corrected errors (negative findings that mattered)

- systemd sandbox hardening (MemoryDenyWriteExecute, SystemCallFilter, LockPersonality,
  RestrictNamespaces, NoNewPrivileges, UMask, Slice, Type=notify, socket-activation
  fds): not the cause. Relaxation didn't fix (probe11, knobs verified applied in
  probe12 §0); the crash reproduced foreground with no sandbox at all (probe16,
  rc=139). Note: the shipped drop-in still carries the relaxations from the debugged
  working configuration; they were never individually re-tested with touch.pa, so
  re-tightening is a queued experiment, not a known-safe change.
- HYBRIS_USE_VENDOR_NAMESPACE: not the SEGV cause (resolved ExecStart carried the -u
  during a SEGV, probe10 §1; foreground without it also died, probe16). Nuance kept:
  with the var SET, PA loads the vendor HAL in-process and fails cleanly (probe10's
  graceful 25s run) – no droid sinks, no crash. The shipped config strips it (Azkali
  parity, container-service path), which is the path that works end-to-end.
- LD_PRELOAD=libtls-padding.so: exonerated for PA (probe14 x2 died without it). Still
  real elsewhere: it breaks logcat via lxc-attach unless --clear-env is used.
- HYBRIS_LD_LIBRARY_PATH: exonerated (probe15 x3).
- Environment in general: exact-foreground-env replication inside a unit still died
  (probe15 x5, env -i). The unit-vs-foreground "context dependence" was an illusion
  created by the missing time-matched control – by the time transients were tested,
  the latch had flipped; the 01:43 foreground "successes" predated it. Probe16's
  same-window control (foreground rc=139) collapsed the whole axis.
- Host-side permissions: /dev/snd root:audio 0660 with phablet in audio is fine
  (probe8 §1 controlC0 rw-ok). The permission problem that mattered was
  container-side (finding 5).
- Container HAL library health: audio.primary.kalama.so dlopens fine – the AHAL log
  lines are printed from inside it (probe18). sound_trigger.primary's EINVAL at
  service start is separate and cosmetic for audio. My "shared broken dependency"
  prediction was wrong.
- pstore/ramoops: absent on this boot config (dump_sink=0x0) – kernel panics are
  unrecoverable. Corollary: never rmmod machine_dlkm (it panics the box, probe4).
- Azkali gts9wifi "same unit works" puzzle: dissolved – the unit was never the
  variable. His port works because his boots get the card up and never latch.
- My own process errors, owned: pipeline exit-status bug twice (probe8 §5 "rc=0",
  probe12 harness) – judge by content, capture rc before pipes; probe12/13 bisections
  vacuous (PULSE_SCRIPT not carried into transients, so the droid path never loaded);
  filtered greps hid tag-HAL/AHAL lines for several probes – the unfiltered logcat
  (probe18) broke the case; celebration discipline ("droid sink or it doesn't count")
  added only after the auto_null false positive (probe13 §1).

## Secondary findings

- QC kernel bug (upstreamable): `lpass_cdc_unregister_macro` (lpass-cdc.c:722-761)
  zeroes macro_params[id].num_dais BEFORE subtracting from priv->num_dais, so the
  count never decrements; re-registration then calls snd_soc_register_component with
  an inflated num_dais over the once-allocated DAI buffer – probe fails hard, no
  rollback. Any macro unbind is unrecoverable without parent reload/reboot. Explains
  the first night's post-teardown state (rx/tx bound, va dead, empty deferred list).
- Runtime teardown ghost: the first chaotic boot's card death (ONLINE then torn down)
  never recurred – ONLINE count has read exactly 1 across a full day. btfmslim_slave
  (in the card's ext-dev-names) remains the untested suspect; passive watch = ONLINE
  count, directed test = BT toggle + paplay (still pending, low priority).
- DT truth (gts9u): num-macros=3; wsa-macro and wsa2-macro status=disabled – all wsa
  work permanently retired; ext-dev-names = 4x cs35l45 (18-0030..33) + btfmslim_slave.
- Silent va non-attach after rmmod/insmod (probe4): driver re-registration produced no
  probe attempt, no deferred entry, no kernel output. Unexplained; parked as a
  recovery-path oddity, moot under the current design.
- Clock jump: wall clock fell to 1970-01-19 mid-bring-up (container time service
  settling), corrected later by NTP – hence ExecMainExitTimestamp/flag mtime reading
  1970 while start reads 13:23:48, and the empty `journalctl -b` greps. The audio
  chain is immune by construction (state polls + monotonic systemd timeouts).
  Monotonic truth: bring-up ran 12,056,484us to 20,544,692us = 8.49s; PA released at
  t≈20.5s after kernel start. Stock comparison: t≈340s on lucky boots, never on
  unlucky ones.
- journald: halium ships ReadKMsg=no (lxc-android-config drop-in); fixed on the tablet
  (zz-gts9u-kmsg.conf: ReadKMsg=yes, SystemMaxUse=500M). Deliberately NOT in the
  skeleton (journal-volume cost); side effect: kmsg flood accelerates rotation and ate
  the cold-boot bringup lines – which motivated the persistent
  /var/log/gts9u-audio-bringup.log sensor (active from next boot).
- Architecture map (for the writeup): PA (host, phablet) -> module-droid-card ->
  audio.hidl_compat shim in-process -> hwbinder -> container
  android.hardware.audio.service_64 -> audio.primary.kalama.so (AHAL) -> PAL/AGM ->
  kernel card. Shim logs carry pid 0 via hybris liblog; service logs carry its real
  pid – the pid split in logcat is how the two worlds were finally told apart.
- vendor_modprobe.sh quadruplication origin (stock Samsung image vs x910-extract
  pipeline) unconfirmed; dedupe at repack covers both.
- Expected-failure modules in the bringup walk (not defects): ipam/rmnet offload
  stack, dataipa-dependent wlan bits, snd-soc-cs35l43/hdmi-codec, and wez01 (needs
  finit_module IGNORE_MODVERSIONS – see todos). Health = card ONLINE + latch cleared +
  bring-up complete, not an empty failed list.

## Current state

Tablet: audio working; proven across warm recovery, warm restart under the real unit,
and one unattended cold boot (NRestarts=0, ONLINE count 1, still singing hours later).
Scripts/units byte-identical to the skeleton (identity rule adopted for the reference
device). Debug era archived: /home/phablet/gts9u-debug-archive-20260808 (36 files,
28M); cores removed. Recovery command for any future mid-session audio death:
`systemctl restart gts9u-audio-bringup` then a user-side PA restart – the script is
idempotent across all five legs, and its journal/log names whichever leg broke.

Shipped chain (fresh flash, by construction): deduped modules.load ->
gts9u-audio-bringup (fill holes -> card ONLINE -> nodes 0666 -> latch clear ->
audio-hal restart -> h2w present -> /run/gts9u-audio-ready) -> PA hard-gated on the
flag -> droid sinks. Every named failure mode has an owner in that chain.

Deliverables in /mnt/user-data/outputs/:
- gts9uwifi-skeleton-audio.tar.gz – patched skeleton (overlay: bringup v3 script+unit+
  wants symlink, virtual-h2w py+unit+symlink, zz-gts9u-audio.conf; old 50- drop-in
  removed; swap-vendor-modules.sh dedupe; 231 entries).
- build-gts9uwifi.sh – audio sanity block + stale-workdir guard (rerun builds must
  `rm -rf $WORK/samsung-gts9u` so the new skeleton stages; the guard says so).
- CHANGES-audio.md – ship notes incl. fresh-flash boot sequence; porters-writeup spine.
- 0001-audio_hw-...patch + shim-crash-analysis.md – Halium shim fix + evidence chain.
- gts9u-audio-fix/ (pre-compaction, partially superseded): the v2 kernel mechanism doc
  remains a valid deep reference; gts9u-load-audio-macros(+.service) and
  50-gts9u-audio-wait.conf are SUPERSEDED by bringup v3 / zz conf – do not install.

## Todos

Proof and upstream:
1. Final certificate: fresh build from the patched skeleton (refresh workdir first),
   virgin sideload, expect first-boot audio and `+0 inserted` in the persistent log.
   Until then the answer to "fully fixed" is by-construction, not by-demonstration.
2. Submit the shim patch to Halium/android_vendor_halium_hardware (PR against master,
   cherry-picks 12.0-16.0; attach shim-crash-analysis.md). Check author attribution
   in the patch file before sending (currently set to John).
3. Draft + submit the extevdev patch to UBports pulseaudio-modules-droid: zero jack
   devices non-fatal + null-guard the io_free error path. Draftable on request.
4. Draft + submit the lpass_cdc_unregister_macro accounting patch (audio-kernel
   android13-5.15-halium; also upstreamable toward CLO). Draftable on request.
5. Porters writeup for 24.04 Samsung/kalama ports: the five-bug chain, the
   exonerations (so others skip the sandbox/env rabbit holes), the architecture map,
   the clock-jump note. CHANGES-audio.md + this file are the spine.

Hardening and follow-ups (low priority):
6. Add /proc/uptime stamps to the bringup persistent log (clock-jump-proof sensor);
   batch with the next skeleton touch – keep tablet/skeleton identity when applied.
7. Sandbox re-tightening experiment: restore stock hardening knobs one per boot with
   touch.pa actually loading; drop the relaxations that prove innocent.
8. Decide whether to ship the kmsg journald drop-in in the skeleton (debug value vs
   journal volume; interacts with rotation of early-boot evidence).
9. Check x910-extract output to pin the modules.load quadruplication origin.
10. Reconcile skeleton lineage: the uploaded skeleton predates the swap-allowlist
    leftover audit referenced in build-gts9uwifi.sh comments.
11. BT on/off toggle + paplay spot check (btfmslim teardown suspect); passive alarm
    remains ONLINE count > 1.
12. bringup's `sleep 2` post-HAL-restart: trim only with evidence.

Next subsystem:
13. S-Pen (wez01): plain insmod fails (modversions); needs a small loader using the
    finit_module IGNORE_MODVERSIONS path proven in the earlier session (digitizer
    streaming confirmed, libinput quirk written, Lomiri session restart still
    unexecuted). Natural next bring-up target now that audio is closed.

## Addendum (post-summary): charging rescue + stage-2 finit

- Finding: muic_sm5714/pdic_sm5714 modversion-locked (insmod EINVAL);
  finit_module flags=3 loads both; cable detection restored; SM5714 fuel
  gauge revived as a side effect (ta_exist=1, SOC live, cycle=1) - the FG
  fault was downstream of the dead notifier chain, not independent.
- Shipped: bringup stage-2 curated finit loader (muic_sm5714 pdic_sm5714
  wez01), before the card wait; unit Description updated. Todo 13's loader
  half is now shipped; remaining pen work = Lomiri session verification.
- New todos: (15) FG capacity/profile check - charge_full_design 9800mAh vs
  ~11200mAh pack spec, investigate above 3.7V only; (16) confirm boot-time
  attach detection with cable pre-inserted (probe-time state read expected;
  replug is the fallback).
- Probe defect owned: the charge probe's "failed at bringup" grep read the
  persistent log, which did not exist yet on that boot (born next reboot) -
  false negative; probe22's list was the truth.
- GPU: verdict healthy (Adreno740v2, EGL 1.5 full Android extension suite,
  zero llvmpipe) - my gpubusy read-reset semantics and renderer-grep were
  probe defects, not device defects.

## Addendum 2 (2026-08-10): pen closed, stage-2 certified, charging-at-boot

- Stage 2 first-boot certificate: finit stage muic/pdic/wez01 all =ok,
  card ONLINE 0s, audio boot #3 clean (NRestarts=0). Clock jump photographed
  in-log (sane boot header, 1970 body) - todo 6 evidence.
- Todo 16 CLOSED: charging engages at boot with cable pre-inserted. Caveat ->
  new todo 17: boot negotiation lands plain USB/rp(2) (PD attempt likely
  predates pdic load at t~12s); one replug renegotiates. Investigate early
  pdic load or accept documented replug.
- Todo 13 CLOSED: pen functional as precise touch (quirk v2 + udev rule,
  shipped in overlay; ID_INPUT_TABLET residue inert - quirk strips pen codes
  first). Digitizer verified end-to-end: hover, tilt, distance, BTN_TOUCH,
  pressure 655-1251 at evdev.
- New todo 18 (platform-gated): toolkit pressure awaits UT's Mir 2 / Wayland
  transition. Evidence bundle for upstream note: Mir 1.x zero-zwp strings
  table, mirclient QPA app path, Qt tablet-v2 client + QTabletEvent present.
- Probe defects owned: linkA block ran unprivileged (mount/apt/capture void);
  wire-truth #1 captured mirclient not Wayland (two strings, no registry) -
  itself the finding that apps bypass the Wayland client entirely.
