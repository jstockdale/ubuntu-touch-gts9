# gts9uwifi Audio Bring-Up — Audited Diagnosis

**Device:** Samsung Galaxy Tab S9 Ultra (SM-X910, gts9uwifi, kalama SoC)
**Stack:** Ubuntu Touch 24.04-2.x / halium / PulseAudio 16.1 + pulseaudio-modules-droid-30 (14.2.109) + modules-droid-hidl (1.5.1)
**Reference:** Azkali's working gts9wifi build (24.04-2.x, same SoC) — audio works there.
**Status:** Fully diagnosed, not solved. Blocker is one kernel-side link. PA-side config fully solved.

This document grades every link by evidence strength: **[CONFIRMED]** = direct log/binary evidence;
**[CORRECTED]** = a prior wrong claim, with the correcting evidence; **[OPEN]** = isolated but not root-caused.

---

## The working PA configuration (all CONFIRMED)

The correct `touch.pa` line (identical to Azkali's, extracted from his super.img):

```
load-module module-droid-card-30 module_id=hidl_compat config=/etc/pulse/gts9/audio_policy_configuration.xml voice_virtual_stream=true
```

Plus the environment his (and the stock UT) pulseaudio unit already provides:
- `HYBRIS_LD_LIBRARY_PATH=/system/lib64:/odm/lib64:/vendor/lib64`
- Note: his unit ALSO strips `HYBRIS_USE_VENDOR_NAMESPACE` with `-u` — so that flag is NOT a differentiator.

### PA-side chain, link by link

1. **[CONFIRMED]** `module_id=hidl_compat` requires the `config=` arg. `/etc/pulse/gts9/audio_policy_configuration.xml`
   declares `<module halVersion="3.0" name="hidl_compat">`. The vendor XML
   (`/vendor/etc/audio_policy_configuration.xml`) declares only `<module name="primary">`.
   Without `config=`, droid-util falls back to the vendor XML → "Couldn't find module with id hidl_compat".
   *Evidence: the config file contents; `thefix.txt` shows "Loaded hw module audio.hidl_compat" only when the arg is present.*

2. **[CORRECTED]** Early in the session the assistant changed `module_id=hidl_compat`→`primary`. That was the
   regression that caused the entire multi-round AGM / namespace / lib-closure detour. `primary` loads the *real*
   Samsung HAL in-process (`audio.primary.kalama.so`) instead of the shim.
   *Evidence: Azkali's touch.pa uses `hidl_compat`; `primary` produced the `-22` chain.*

3. **[CONFIRMED]** With the config arg, the shim `audio.hidl_compat.default.so` loads and **opens the HW device**.
   *Evidence: `thefix.txt`: "Loaded hw module audio.hidl_compat (generic)" + "Opened hw audio device version 2.0".*

4. **[CONFIRMED]** `vendor.audio.use.primary.default=false` is required so the real HAL's `adev_open` passes its
   guard at source line 2786 (`if (property_get_bool("vendor.audio.use.primary.default", false)) return -EINVAL`).
   *Evidence: disassembly of `audio.primary.kalama.so` @0xbf3c8; `thefix3.txt` shows "2786: sndcard is not active"
   when property is true; `both.txt` shows "2776: Enter" with NO 2786 line when false.*
   NOTE: Azkali's build does NOT set this property anywhere in his rootfs/build.prop — so on his build the default
   must already be false, OR his path never reaches this guard because his card is ONLINE (see below). This is the
   one PA-side item where his mechanism differs and is not fully pinned.

5. **[CONFIRMED]** When the guard is passed but the downstream open fails, the shim has a swallow-the-error bug:
   it logs the failure but falls through to fake-success, returning a null device, and droid-util then calls
   `adev_init_check` on null → SIGSEGV.
   *Evidence: `thefix3.txt` exit rc=139 (SIGSEGV); logcat shows `openDevice() error -19` then `adev_init_check`.*

---

## The real blocker (CONFIRMED)

6. **[CONFIRMED]** The downstream failure that the shim swallows originates in **AGM**. With the property false and
   the shim opening the device, the real HAL's `adev_open` calls into PAL → `pal_init` → AGM
   `wait_for_snd_card_to_online`, which fails: 60 retries of "wait SND_CARD_STATUS_ONLINE" + "Failed to open snd
   sysfs node", then "Not found any SND card online" → agm_init fails → `pal_init` returns −22 → `adev_open` returns
   −22 → shim null-deref SIGSEGV.
   *Evidence: `deep.txt`, `verdict.txt` — the full retry sequence captured.*

7. **[CONFIRMED]** AGM fails because the sound card is never marked **ONLINE**. The ASoC machine driver
   (`kalama-asoc-snd`, `machine_dlkm.ko`) has two callbacks:
   - `msm_asoc_machine_probe` → registers the card (this DOES run; card appears in `/proc/asound/cards`).
   - `msm_snd_card_late_probe` → calls `snd_card_notify_user` + `snd_card_set_card_status` → logs
     **"snd_card is ONLINE"** → populates the sysfs node AGM reads (`card_state` / `aud_dev` state).
   The late_probe **never runs** on this device. The card registers but is never notified ONLINE, so AGM's read of
   the online-state sysfs node fails ("Failed to open snd sysfs node") and it waits forever.
   *Evidence: the string "snd_card is ONLINE" appears in ZERO captures across the ENTIRE session (grep of all
   *.txt = 0 matches). `va-insmod.txt` shows `msm_asoc_machine_probe` completing ("Sound card ... registered",
   47 links, 4 cirrus amps) with NO late_probe / ONLINE afterward. Machine driver symbol table confirms
   `msm_snd_card_late_probe`, `snd_card_notify_user`, `snd_card_set_card_status` exist.*

This unifies AGM's two symptoms ("wait ONLINE" and "Failed to open snd sysfs node") into one cause: late_probe
never fired, so the online-state node was never populated.

---

## CORRECTED — the assistant's wrong root cause from the prior round

- **[CORRECTED]** The "-12 / multiple DAI registered with no name" error was NOT the boot failure. It was an
  **artifact**: the diagnostic re-ran `insmod lpass_cdc_va_macro_dlkm` while it was already loaded, causing a
  duplicate DAI registration. On a clean load the macros register fine (rc=0).
  *Evidence: `bootfail.txt` §4 insmod'd an already-present module; `va-insmod.txt` shows clean rc=0 loads and the
  −12 does not appear there.*

This correction matters: it would have sent a kernel-rebuild effort chasing a DAI-naming bug that does not exist.

---

## STILL OPEN — the one link isolated but not root-caused

**Why does `msm_snd_card_late_probe` never fire?** The card registers via `msm_asoc_machine_probe`, but ASoC never
calls the card's `late_probe`. Leading hypotheses (not yet distinguished by evidence):

- **Late macro load.** At boot, rx/tx macros load but va/wsa/wsa2 do not; they only register very late
  (t≈340s in `bootfail.txt`) or on manual insmod. `late_probe` runs once, right after `snd_soc_register_card`
  during the initial probe. If the card only fully assembles after ASoC has already passed the late_probe point
  (because it was waiting on the late macros via deferred probe), late_probe may be skipped.
  *Evidence: `va-insmod.txt` "before" state shows only rx/tx loaded at boot; card absent until va/wsa/wsa2 added.*

- **Deferred-probe ordering / DT difference** from Azkali's gts9wifi build. Same kernel source, but different DTB
  (Ultra vs S9) and possibly different kernel config controlling macro auto-load or late_probe invocation.

**Why don't va/wsa/wsa2 load at boot** (rx/tx do)? Related, and also open. Their `modules.dep` lists the same
prerequisites as rx/tx (swr_ctrl, lpass_cdc, spf_core, etc.), and `modules.load` lists them — yet only rx/tx come
up at boot. Azkali's `modules.load` ordering and machine_dlkm `modules.dep` are essentially identical to ours, so
the difference is likely in the kernel/DTB, not the module metadata.

---

## What was ruled OUT (each an assistant detour, corrected by evidence)

- **Missing vendor libs** (libaudioutils/libaudioroute): present via the VNDK apex + the vendor linker namespace;
  resolved once `HYBRIS_LD_LIBRARY_PATH` was set. NOT missing from the device.
- **`HYBRIS_USE_VENDOR_NAMESPACE` flag**: Azkali's build strips it with `-u` too. Not a differentiator.
- **`vendor.audio.use.primary.default` hardcoded true in build.prop**: it is NOT set in Azkali's build.prop, and on
  our device it is the default. Real for the 2786 guard, but not the ONLINE blocker.
- **`aud_dev/state` permissions**: chmod/chown had no effect; the node's readability is kernel-side, downstream of
  late_probe never populating it. Perms were a red herring.
- **PAL service collision** (container HAL vs PA passthrough): stopping the container HAL did not help; AGM fails
  identically in both contexts because the card is never ONLINE regardless of who runs the HAL.
- **`-12` DAI double-registration**: assistant artifact (see CORRECTED above).

---

## Fix direction (for a focused kernel session)

The blocker is kernel-side: get `msm_snd_card_late_probe` to fire so the card is notified ONLINE on a clean boot.
Concretely, the two coupled things to resolve:

1. Make va/wsa/wsa2 macros load at boot (before or together with the machine driver's probe completion), so the
   card fully assembles during the initial probe and `late_probe` runs — matching Azkali's working boot.
2. Confirm via `dmesg | grep "snd_card is ONLINE"` on a clean boot. If it appears, AGM will get past
   `wait_for_snd_card_to_online`, `pal_init` will succeed, `adev_open` returns 0, the shim gets a valid device (no
   SIGSEGV), and PA instantiates sinks.

**Decisive artifact still needed:** Azkali's kernel *source* (`kernel-samsung-gts9wifi`, esp.
`sound/soc/msm/` machine driver + `sound/soc/codecs/lpass-cdc/` and his `halium.config`) to diff against yours for
the macro-autoload / late_probe / deferred-probe difference. His working build is the ground truth; the delta is
there. A clean binary diff of his `machine_dlkm.ko` and the lpass macro `.ko`s vs yours would also localize it.

Once late_probe fires and ONLINE is signaled, the permanent userspace fix is already known and confirmed: the
Azkali `touch.pa` line (hidl_compat + config=) + the property setter, both of which are established above.
