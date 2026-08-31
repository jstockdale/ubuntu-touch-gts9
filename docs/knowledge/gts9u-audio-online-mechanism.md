# gts9uwifi Audio – The ONLINE Mechanism, Source-Verified (v2)

**Device:** Samsung Galaxy Tab S9 Ultra (SM-X910, gts9uwifi, kalama)
**Supersedes:** §6–§7 ("The real blocker" / late_probe), the "aud_dev/state permissions"
ruled-out item, and the "Fix direction" section of `gts9u-audio-diagnosis.md`.
The PA-side chain (§1–§5 of that doc: hidl_compat + config=, the 2786 property guard,
the shim null-deref hazard) stands unchanged.
**Method:** read the source Azkali's binaries are built from, plus the AGM userspace that
runs inside the HAL, instead of inferring kernel behavior from log absence.

Grading as before: **[CONFIRMED]** = direct source/log evidence; **[CORRECTED]** = a v1
claim overturned, with the correcting evidence; **[INFERRED]** = consistent but not
directly verified.

> **Editorial note (2026-08-30 parity audit):** this doc names **va/wsa/wsa2**
> as the macro set gating card registration; the later syntheses (PORT-STATE §3,
> the knowledge-transfer doc) say the Ultra DT enables **va/rx/tx** with
> wsa/wsa2 disabled (`num-macros=3`). The observations below (which .ko files
> were absent on the failed boot) stand as recorded; treat the *interpretation*
> of which macros gate the card per PORT-STATE. Operationally moot — the
> bringup walks the whole modules.load either way.

---

## Source provenance

| What | Repo @ ref | Commit |
|---|---|---|
| audio-kernel (machine driver, lpass-cdc macros) | gitlab.com/azkali-samsung/gts9/ubports/audio-kernel @ android13-5.15-halium | 43f74b4fee23 |
| AGM (vendor userspace, the wait loop) | git.codelinaro.org clo/la/platform/vendor/qcom/opensource/agm @ LA.VENDOR.13.2.1.c25 | bccf818efaca |
| kernel-samsung-gts9wifi (Samsung glue: snd_debug_proc) | same GitLab group @ android13-5.15-halium | file fetches |
| samsung-gts9 device repo (overlay, deviceinfo, scripts) | same group @ halium-13 | – |
| halium-generic-adaptation-build-tools (Azkali fork) | same group @ personal/azkali/gts9-integration | – |

Caveat: the on-device AGM/PAL libs are Samsung's builds of same-vintage CLO code. One
Samsung-only log string is inferred below and graded as such. All kernel-side claims are
against the exact source Azkali builds (and which the gts9u tree is derived from).

---

## The corrected mechanism, link by link

**1. [CONFIRMED] The sysfs node is created at module load, not at probe.**
`msm_asoc_machine_init()` (module_init) calls `snd_card_sysfs_init()` before it even
registers the platform driver – `asoc/kalama.c:3061–3066`. `snd_card_sysfs_init()`
creates kobject `snd_card` under `kernel_kobj` with attribute `card_state`, mode
**0660 root:root** – `asoc/msm_common.c:197–221`, attribute defs `:55–58`. Path:
`/sys/kernel/snd_card/card_state`. Initial value 0 (kcalloc'd pdata).
Consequence: the node exists on any boot where machine_dlkm loaded, even while the card
probe is still deferring.

**2. [CONFIRMED] Status flips to 1 at the END of `msm_asoc_machine_probe`, unconditionally.**
`kalama.c:2965–2966` logs `"%s: Sound card %s registered"`, then after non-fatal
housekeeping (fsa/dmic phandles, msm_common_snd_init, clk_get, ssr register – none of
which goto err), `:3019–3021` runs `snd_card_set_card_status(SND_CARD_STATUS_ONLINE)`.
`snd_card_set_card_status` just writes the integer (`msm_common.c:168–172`).
**Therefore: if dmesg shows "Sound card ... registered", card_state is 1.**
`va-insmod.txt` shows exactly that line, so on that boot, after the manual insmods, the
card WAS online. As far as the captures show, AGM was never re-run after that point – the
v1 causal chain was assembled across different boots/contexts.

**3. [CORRECTED] `late_probe` has nothing to do with ONLINE.**
`msm_snd_card_late_probe` (`kalama.c:2023–2066`) is WCD938x headset-jack MBHC setup and
nothing else. It is assigned only for the `"codec"` of_match entry (`:2228–2229`,
compatible `qcom,kalama-asoc-snd`), and returns 0 immediately when `pdata->wcd_disabled`
(`:2035`; DT-sourced at `:2845`). Samsung tabs have no WCD headset codec, so the early
return is by design. The v1 §7 blocker ("late_probe never runs → card never notified
ONLINE") does not exist: neither `snd_card_notify_user` nor `snd_card_set_card_status`
is called from late_probe.

**4. [CORRECTED] "snd_card is ONLINE" cannot appear in dmesg, ever.**
`kalama.c:3022` prints it via `sdp_boot_print`, which is Samsung's logger writing into a
64K in-kernel buffer exposed at **`/proc/snd_debug_proc/sdp_boot_log`**
(`sound/soc/samsung/snd_debug_proc.c:42–44` and `:227–228` in kernel-samsung-gts9wifi;
declaration in `include/sound/samsung/snd_debug_proc.h`, gated on
`CONFIG_SND_SOC_SAMSUNG_AUDIO`). The v1 evidence "the string appears in ZERO captures"
was structurally guaranteed and proves nothing. The correct probe-completion markers are
the "Sound card ... registered" dmesg line, or reading `sdp_boot_log` directly.

**5. [CONFIRMED] snd_event / `kalama_ssr_enable` is a separate, non-gating path.**
Registered at probe end via `msm_audio_ssr_register` (`kalama.c:2676–2694`) over the DT
phandle list `qcom,msm_audio_ssr_devs`; the framework fires `.enable` when all listed
client devices are up; that callback calls `snd_card_notify_user(ONLINE)` (`:2587`) =
set + `sysfs_notify` (a poll wakeup for readers), and OFFLINE on SSR-down (`:2650`).
This is the aDSP-restart machinery. It is not what gates AGM's boot wait; v1 conflated
the two ONLINE call sites. Residual note: an SSR-down event after boot flips card_state
back to 0 – worth remembering if audio ever dies mid-session.

**6. [CONFIRMED] What AGM actually does (`service/src/device.c` @ LA.VENDOR.13.2.1.c25).**
- `SNDCARD_PATH "/sys/kernel/snd_card/card_state"` (`:51`).
- `wait_for_snd_card_to_online()` (`:1037–1076`): opens the node **O_RDWR** (`:1048`),
  reads one char, sscanf's it, breaks only on value 1. `MAX_RETRY=100` at
  `RETRY_INTERVAL=1` s (`:53–54`), so a 100 s window. Enum `OFFLINE=0, ONLINE=1`
  (`:103–107`) mirrors kernel `msm_common.h:49–50` exactly.
- Per-retry `"Failed to open snd sysfs node, will retry ..."` means **open() itself
  failed**: ENOENT (machine_dlkm not loaded → no node) or EACCES (0660 root:root vs a
  non-root caller that needs read-write).
- The opened-but-reads-0 branch logs nothing per retry in CLO code. **[INFERRED]**
  Samsung's build adds the per-retry `"wait SND_CARD_STATUS_ONLINE"` line there – the
  string matches the kernel enum name and is absent from CLO source.
- On expiry: `"Failed to open snd sysfs node, exiting"` → `device_init` logs
  `"Not found any SND card online"` → agm_init fails → `pal_init` −22 → `adev_open` −22
  → the shim's swallow-and-SIGSEGV, exactly as v1 §5–§6 captured downstream.
- `/sys/kernel/aud_dev/state` (`:67`) is a **different node**: O_WRONLY bookkeeping
  writes with lazy open-retry (`:77–101`), explicitly tolerated to fail, and the in-code
  comment says android init chowns it during boot. The v1 "perms red herring" verdict
  was reached by chmodding this non-gating node; on the gating node (card_state), perms
  for the PA-as-phablet case are real, because AGM runs **inside pulseaudio's process**
  in the passthrough setup and opens O_RDWR as PA's uid.

**7. [CONFIRMED by construction + v1's own empirics] The entire boot condition is one line.**
card_state==1 ⇔ machine probe completed ⇔ all DAI-link components present ⇔ the
va/wsa/wsa2 macro components registered. Deferred probe re-runs the machine probe
automatically whenever a missing component appears (defer branch `kalama.c:2951–2959`,
including Samsung's defer_count / check_external_device logging – the `"cannot find the
%s"` sdp print at `:2765`). So LATE loading is fine: the moment the three macros load,
the card registers and card_state flips to 1. **No kernel code change, no DT change, no
late_probe work.** The two real work items:
(A) get the three macros loaded at boot, and
(B) make PA start after card_state==1 and be able to open it O_RDWR.

---

## Reinterpreting the existing captures

| Capture symptom | Meaning under the corrected model |
|---|---|
| per-retry "Failed to open snd sysfs node" | open() failing: machine_dlkm not yet loaded (ENOENT) or caller lacked rw on 0660 root:root (EACCES – e.g. PA as phablet). A one-line `exec 3<>` test distinguishes them in seconds (below). |
| per-retry "wait SND_CARD_STATUS_ONLINE" | node opened fine, value 0: machine probe still deferred because the macros were missing. Root/container contexts land here. |
| "Not found any SND card online" → pal_init −22 → adev_open −22 → rc=139 | the 100 s window expired; downstream chain exactly as v1 §5–§6. |
| va-insmod.txt: "Sound card ... registered", no "ONLINE" in dmesg | probe completed; card_state was 1 at that moment; the missing string is the logging artifact of item 4, not evidence of anything. |

Worth a 5-minute pass over `deep.txt` / `verdict.txt` / `thefix3.txt` to bucket which
variant each shows, and under which uid/context each test ran – that bucketing now
carries real signal (perms vs probe) instead of being noise.

---

## What Azkali's build actually does (device-repo facts)

- **PA is serialized behind container audio.** His overlay ships
  `system/etc/systemd/user/pulseaudio.service.d/50-gts9wifi-wait-audiohal.conf`:
  an `ExecStartPre=-/bin/sh -c '...'` loop polling
  `getprop init.svc.vendor.audio-hal` for `running` (≤90 s), then the known
  `ExecStart=/usr/bin/env -u HYBRIS_USE_VENDOR_NAMESPACE /usr/bin/pulseaudio ...`.
  The container HAL only reaches `running` after ITS in-process AGM passed the same
  card_state wait – i.e. his gate is transitively card_state==1. This is why his boots
  never race. (Side note, [INFERRED]: systemd expands bare `$c` in ExecStartPre lines,
  so his counter may actually be mangled and the loop close to a no-op – masked by the
  leading `-` and by container ordering usually winning. The replacement drop-in below
  avoids `$` entirely via `timeout` + backtick substitution.)
- **No audio modules load early.** His vendor_boot ramdisk `modules.load` has 124
  entries, zero audio. All audio DLKMs load inside the container from vendor_dlkm via
  stock Samsung mechanisms.
- **His vendor_dlkm is stock-plus-swap.** `scripts/swap-vendor-modules.sh` extracts the
  STOCK image, overwrites only same-named `.ko` files with his builds (SELinux context
  preserved from a stock module), repacks erofs. `modules.load` / `modules.dep` /
  `modules.blocklist` and every init rc stay stock. So on gts9wifi the stock in-container
  loader demonstrably loads machine_dlkm and all five lpass macros.
- **vendor_dlkm is loop-mounted** from `/userdata/vendor_dlkm.img` and symlinked to
  `/vendor_dlkm` (`mount-android-partitions:96–98` in his overlay).
- Kernel config deltas are minimal: `halium.config` is 43 lines, audio-relevant content
  none beyond `CONFIG_MODULE_SIG=n`, `CONFIG_MODULE_FORCE_LOAD/UNLOAD=y`.
  `CONFIG_SND_SOC_SAMSUNG_AUDIO` comes from the stock `vendor/kalama-gki_defconfig`.

---

## The one remaining unknown, and how to pin it

Same-named modules, same modules.load – yet on gts9uwifi the container loads the audio
stack MINUS exactly va/wsa/wsa2 (until ~t≈340 s in `bootfail.txt`, or manual insmod).
Ranked hypotheses and the on-device commands that discriminate them:

1. **Samsung's loader is staged/conditional and a later stage doesn't run under halium.**
   Pixel-style `init.insmod.sh` + cfg, or explicit rc insmod lines gated on properties.
   ```
   grep -rn -iE "insmod|modprobe" /android/vendor/etc/init/ | grep -v "^Binary"
   ls /android/vendor/bin | grep -iE "insmod|modprobe|kmod"
   ls /android/vendor/etc | grep -i insmod
   # if a cfg exists:
   grep -niE "lpass|macro|setprop" /android/vendor/etc/init.insmod*.cfg
   ```
   A cfg showing the macros in a property-gated stage = hypothesis confirmed; the gate
   property tells you the fix.
2. **The three insmods are attempted and fail at that moment.** android init logs every
   module event to kmsg:
   ```
   sudo dmesg | grep -c "Loaded kernel module"
   sudo dmesg | grep "Loaded kernel module" | grep -iE "lpass|macro"
   sudo dmesg | grep -iE "init:.*(insmod|module).*(fail|error)"
   ```
   Failures present = hypothesis 2; macros simply never attempted = hypothesis 1 or 3.
3. **Pipeline divergence on the gts9u side** (vendor_dlkm handling in the rewritten
   six-script pipeline vs Azkali's stock-plus-swap + loop-mount). Compare: is gts9u
   flashing a self-built vendor_dlkm with regenerated metadata, or stock-plus-swap?
   `diff` the gts9u `modules.blocklist` against stock, not just modules.load:
   ```
   grep -iE "lpass|macro" /android/vendor_dlkm/lib/modules/modules.blocklist
   ```
4. **Attribute the t≈340 s event** – whoever loads them late is the loader that should
   have run early:
   ```
   sudo journalctl -k -b -o short-monotonic | grep -iE "va_macro|wsa2?_macro|lpass_cdc|Sound card"
   ```

Whichever of these lands, the systemd loader service below makes boots correct in the
meantime and is harmless to keep afterwards as belt-and-braces.

---

## Do this first – 10-minute manual test, no new code

The corrected model predicts audio can work TODAY on a booted device:

```
# 1. load the macros (skip any already in lsmod)
sudo insmod /android/vendor_dlkm/lib/modules/lpass_cdc_va_macro_dlkm.ko
sudo insmod /android/vendor_dlkm/lib/modules/lpass_cdc_wsa_macro_dlkm.ko
sudo insmod /android/vendor_dlkm/lib/modules/lpass_cdc_wsa2_macro_dlkm.ko

# 2. probe re-runs and completes
sudo dmesg | grep "Sound card"          # expect: Sound card kalama-...-snd-card registered

# 3. the gate AGM reads
cat /sys/kernel/snd_card/card_state      # expect: 1

# 4. Samsung's boot log confirms (the string v1 grepped dmesg for lives HERE)
grep ONLINE /proc/snd_debug_proc/sdp_boot_log   # expect: msm_asoc_machine_probe: snd_card is ONLINE

# 5. can PA's uid open it O_RDWR? (this is exactly AGM's open)
ls -l /sys/kernel/snd_card/card_state
sh -c 'exec 3<>/sys/kernel/snd_card/card_state && echo rw-ok'   # run as phablet
# on EACCES:
sudo chgrp audio /sys/kernel/snd_card/card_state /sys/kernel/aud_dev/state
sudo chmod 0660  /sys/kernel/snd_card/card_state /sys/kernel/aud_dev/state
id -nG phablet | grep -w audio           # must list audio

# 6. restart PA (as phablet) with the v1-confirmed touch.pa + property in place
systemctl --user restart pulseaudio

# 7. observe
pactl list short sinks                   # expect a droid sink
journalctl --user -u pulseaudio -b | tail -50
# expect: "Loaded hw module audio.hidl_compat", "Opened hw audio device",
# NO 100-retry AGM wall, NO -22, NO SIGSEGV

# 8. noise
paplay /usr/share/sounds/alsa/Front_Center.wav
```

If step 7 still shows the AGM wall, note WHICH per-retry string appears – open-fail vs
wait-0 – that now discriminates perms vs probe cleanly (see the mapping table).

---

## Permanent fix – files in this folder

| File | Install to | Mode |
|---|---|---|
| `gts9u-load-audio-macros` | `/usr/libexec/gts9u-load-audio-macros` | 0755 |
| `gts9u-load-audio-macros.service` | `/etc/systemd/system/` | 0644 |
| `50-gts9u-audio-wait.conf` | `/etc/systemd/user/pulseaudio.service.d/` | 0644 |

```
sudo mount -o remount,rw /
sudo install -m0755 gts9u-load-audio-macros /usr/libexec/
sudo install -m0644 gts9u-load-audio-macros.service /etc/systemd/system/
sudo mkdir -p /etc/systemd/user/pulseaudio.service.d
sudo install -m0644 50-gts9u-audio-wait.conf /etc/systemd/user/pulseaudio.service.d/
sudo systemctl daemon-reload
sudo systemctl enable --now gts9u-load-audio-macros.service
# as phablet:
systemctl --user daemon-reload && systemctl --user restart pulseaudio
```

Notes:
- Keep the existing HYBRIS_LD_LIBRARY_PATH env drop-ins untouched; the ExecStart
  override here reproduces Azkali's `-u HYBRIS_USE_VENDOR_NAMESPACE` semantics.
- The `-` on ExecStartPre keeps PA non-fatal if the wait times out; AGM's own 100 s
  retry loop is the backstop.
- The loader script is idempotent, bounded-wait at every stage, and fails loudly with a
  concrete hint at the first unmet precondition. Re-running it after boot is safe.
- Once the real loader gap (previous section) is identified and fixed at the source,
  the service can be retired – or kept; it no-ops in seconds on a healthy boot.

---

## Retired from v1 / still standing

Retired: the §6–§7 late_probe blocker and its "get late_probe to fire" fix direction;
kernel-source diffing as the critical path for audio (still mildly useful for the loader
question, useless for ONLINE); the aud_dev-perms ruling (tested on the non-gating node);
the request for Azkali's machine_dlkm binary diff.

Still standing from v1: the entire PA-side chain (§1–§5) – `hidl_compat` + `config=`,
`vendor.audio.use.primary.default=false` for the 2786 guard, and the shim's
swallow-the-error null-deref. That last one becomes moot on the success path but remains
a real latent bug in `audio.hidl_compat.default.so` worth an eventual upstream patch.
