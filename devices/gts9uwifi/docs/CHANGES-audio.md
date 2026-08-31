# gts9uwifi skeleton – audio bring-up patchset (2026-08-08 first-sound session)

## What ships

Overlay (all under `overlay/system/`):
- `usr/local/sbin/gts9u-audio-bringup` – v3 boot service. Walks vendor_dlkm
  `modules.load` (deduped, blocklist-honored) and inserts every module the
  parallel modprobe storm dropped; waits for `card_state=1`; sets the two
  audio sysfs nodes 0666 (container AGM opens card_state O_RDWR from its own
  uid space – host-group 0660 locks it out); clears Samsung's fallback latch
  `vendor.audio.use.primary.default`; restarts `vendor.audio-hal` so its
  in-process AGM re-inits against a live card; touches `/run/gts9u-audio-ready`.
- `etc/systemd/system/gts9u-audio-bringup.service` + `multi-user.target.wants`
  symlink. TimeoutStartSec=360 (worst-case wait chain is ~330s; the 240 in the
  hand-installed v1 unit could kill the script mid-wait).
- `usr/local/lib/gts9u-virtual-h2w.py` +
  `etc/systemd/system/gts9u-virtual-h2w.service` + wants symlink. Creates a
  virtual EV_SW input device advertising SW_HEADPHONE_INSERT/MIC/LINEOUT,
  state 0. UT's droid-extevdev treats "no jack switch device on the system"
  as fatal and then aborts PA via a null `mainloop_io_free()`; giving the
  scan a device sidesteps both until the module is patched upstream.
- `etc/systemd/user/pulseaudio.service.d/zz-gts9u-audio.conf` – PA gates on
  the `/run/gts9u-audio-ready` flag (not on raw card_state: a live card
  fronted by a stale HAL still yields adev_open -19 → shim null-deref SEGV).
  No `-` prefix: if bring-up never completes, PA must not start. Also strips
  HYBRIS_USE_VENDOR_NAMESPACE (Azkali parity) and carries the sandbox
  relaxations from the debugged, working configuration.
- REMOVED: `pulseaudio.service.d/50-gts9uwifi-wait-audiohal.conf` (superseded;
  two drop-ins double-resetting ExecStart is merge-order roulette).

Scripts:
- `scripts/swap-vendor-modules.sh` – now dedupes `modules.load*` at repack
  (with a before→after line report) and restores the selinux xattr on the
  rewritten list. The stock-extracted list ships 4x duplicated;
  vendor_modprobe.sh backgrounds every line in parallel with exit codes
  discarded, so duplication multiplies the storm and the odds of any module
  silently losing (observed dropped across boots: lpass_cdc_va_macro_dlkm,
  machine_dlkm → no sound card).

Build driver (`build-gts9uwifi.sh`, alongside this tarball):
- Sanity block verifying all overlay artifacts + the dedupe are present
  before the multi-hour build starts.

## Fresh-flash boot sequence (what a virgin sideload does)

1. vendor_dlkm ships a deduplicated modules.load (build-time fix); the
   parallel modprobe storm still runs but at 1x. Whether 1x still drops
   modules is unproven - the bringup service is the belt either way, and
   its "+N inserted" log line is the storm-regression sensor (expect +0).
2. gts9u-audio-bringup: fills any holes, waits card ONLINE, chmods nodes,
   clears the latch (covers both runtime-latched and any build.prop-default
   true - origin of the initial 'true' was never pinned down), restarts
   vendor.audio-hal, waits for the virtual h2w jack, then drops
   /run/gts9u-audio-ready.
3. PulseAudio's gate holds until the flag (hard-fail, 150s/attempt,
   systemd retries) - so PA can never race a half-ready stack, and the
   latch never gets a trigger.

## Live-device delta

The tablet already runs v3 script + zz drop-in (probe23). One fixup remains:
    sed -i 's/TimeoutStartSec=240/TimeoutStartSec=360/' /etc/systemd/system/gts9u-audio-bringup.service && systemctl daemon-reload

## Reading the bringup log

`modules: +N inserted, M already live, failed: ...` – the failed list is NOT
a defect signal: it contains modules that legitimately cannot load on halium
(ipam/rmnet offload stack, dataipa-dependent wlan bits) plus known cases:
wez01 (S-Pen) needs the finit_module IGNORE_MODVERSIONS path – separate pen
loader, later. Health = `card ONLINE after Ns` (single digits) +
`latch cleared` + `bring-up complete`. On a deduped image expect `+0` on
healthy boots; a nonzero N is the cheapest storm-regression alarm we have.

## The five-bug chain this closes (for the porters writeup)

1. Parallel modprobe storm (quadruplicated list, exit codes discarded) drops
   modules nondeterministically; rx/tx macros serialize behind va BY DESIGN
   (`lpass_cdc_is_va_macro_registered` defer), so one dropped module = card
   never ONLINE.
2. One bad boot latches `vendor.audio.use.primary.default=true` (Samsung AGM
   failure handler); from then on adev_open refuses in 1ms forever – survives
   service restarts, cleared only by setprop or reboot-into-good-bringup.
3. audio.hidl_compat shim swallows factory errors, logs "Opened hw audio
   device" over a -19, hands PA null → SEGV at shim+0x2280 (core-verified,
   fault_addr=0, PC=LR+8). Upstream patch pending.
4. droid-extevdev aborts PA on jackless hardware (assert in mainloop_io_free
   error path). Upstream patch pending; virtual h2w is the shipped workaround.
5. Container audio-hal that started before the card was up keeps a stale AGM
   forever; must be restarted after card ONLINE + latch clear (bring-up step 5).

## Open items

- Quadruplication origin (stock Samsung image vs x910-extract pipeline)
  unconfirmed – dedupe at repack covers both; check the extract output when
  convenient.
- This skeleton predates the swap-allowlist leftover audit referenced in
  build-gts9uwifi.sh comments – reconcile if a newer skeleton exists.
- Upstream: extevdev no-jack + null-free fix (UBports), shim swallow-error
  (Halium – needs the 24KB .so for exact offset), lpass_cdc_unregister_macro
  num_dais accounting (Azkali/CLO kernel tree).

## Addendum 2026-08-08 (late) - charging + finit stage 2

Charging on the tablet was dead: muic_sm5714 and pdic_sm5714 are
modversion-locked against the halium kernel (plain insmod = EINVAL), so cable
detection never fired - Cable(NONE), Imax 100mA, HV/PD power 0 - and the
SM5714 fuel gauge degraded alongside it (SOC stuck 0, cycle -1, CISD I2C
complaints). Loading both via finit_module(IGNORE_MODVERSIONS|IGNORE_VERMAGIC)
restored detection AND revived the fuel gauge (ta_exist=1, live SOC/cycle).

The bringup script now carries a stage-2 curated finit loader
(muic_sm5714 pdic_sm5714 wez01) placed before the card wait. Allowlist only -
never blanket-finit the failed list. wez01 merges the S-Pen loader here
(digitizer proven in an earlier session; Lomiri session test still pending).
Open: charge_full_design reads 9800mAh vs ~11200mAh pack spec (FG profile
question, low priority); boot-time attach detection with cable pre-inserted
is expected from MUIC probe-time state reads but not yet demonstrated - if a
fresh boot on charger shows no attach, replug once and file it.

## Addendum 2026-08-10 - S-Pen ships (touch mode)

Pen path closed. Ships in overlay: etc/libinput/local-overrides.quirks
(MatchName=sec_e-pen, +INPUT_PROP_DIRECT, AttrEventCode strips
BTN_TOOL_PEN/RUBBER/STYLUS/STYLUS2) + etc/udev/rules.d/61-gts9u-pen.rules
(asserts ID_INPUT_TOUCHSCREEN). Mechanism: quirk removes pen capabilities
before classification, so libinput's tablet path cannot claim the device and
the touch path wins; ID_INPUT_TABLET may remain set (input_id) and is inert.
wez01 loads via bringup stage 2. Result: pen drives the UI as a precise
single-touch input, full 4096-level pressure visible at evdev.

Pressure through the toolkit is PLATFORM-GATED, evidence-backed: the UT 24.04
compositor is UBports Mir 1.x (libmir1server.so.53) with zero zwp_* interface
strings - no tablet global exists to enable - and apps ride the mirclient QPA
(QT_QPA_PLATFORM=ubuntumirclient;...), not Wayland. Meanwhile
Qt5WaylandClient 5.15.13 carries the complete zwp_tablet_v2 client and
Qt5Gui carries QTabletEvent: when UT lands the Mir 2 / Wayland transition,
pressure should light up on this device with no port-side work. Bonus device:
"hall_wacom" is the pen-garage hall switch, already classified by Lomiri.
