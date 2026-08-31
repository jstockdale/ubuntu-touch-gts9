# gts9pwifi (Tab S9+ / SM-X810) Ubuntu Touch port – full runbook

2026-08-27. End-to-end procedure from the assembled artifacts to a booted port.
Companion docs: `gts9p-hw-findings.md` (evidence and rationale), MANIFEST.md
inside the imports bundle (per-file provenance).

---

## Phase 0 – inputs and build box

### 0.1 Collect inputs

| Item | Source | Verify |
|---|---|---|
| gts9p imports: `devices/gts9pwifi/imports/` **from this repo, current HEAD** | ubuntu-touch-gts9.git | do NOT use any archived `gts9p-imports.tar.gz` (sha256 bce7f412... predates the 2026-08-30 wacom `drivers/input/{Kconfig,Makefile}` wiring addition — a tarball with that hash makes the build's wacom gates die FATAL) |
| `build-gts9pwifi.sh`, `x810-extract.sh` | this session | `bash -n` passes; `chmod +x` both |
| `SAMFW.COM_SM-X810_XAR_X810XXU1AWHA_fac.zip` (exact vintage — see repo FIRMWARE.md) | your s10.ooo link | exactly 9,225,074,787 bytes; `unzip -T` OK. Token links expire – if it 403s, regenerate from the samfw SM-X810 / XAR / AWHA page |
| OSRC set: `SM-X818U_13_Opensource.zip` (base) + `SM-X810_13_Opensource_dts.zip` + AWHA-named delta zip | already downloaded | keep all three together |
| gts9u skeleton: `devices/gts9uwifi/skeleton/` **from this repo, current HEAD** | ubuntu-touch-gts9.git | do NOT use any `gts9uwifi-skeleton*.tar.gz` — the pre-audio original survives under exactly that name (`archive/superseded/gts9uwifi-skeleton-orig.tar.gz`) and is a foot-gun; the repo dir is the canonical audio-era skeleton **plus the 2026-08-30 parity fixes** (WiFi persistence, tp-rotate, sed-safe flasher, merged swap script, LP budget) |
| TWRP gts9p build + your vbmeta-disabled file | same XDA thread as the Ultra | treat as unverified until Phase 3.5 |

### 0.2 Archive the rescue path

Old builds rot off mirrors and rev-1 is this unit's permanent way back to
factory state. Before anything else, copy the AWHA firmware zip and the three
OSRC zips to durable storage (NAS + offsite, your call).

### 0.3 Host dependencies (build box)

```
sudo apt install git curl wget tar xz-utils zstd lz4 xxd bc bison flex make gcc \
     python3 rsync cpio attr erofs-utils android-sdk-libsparse-utils \
     device-tree-compiler fakeroot zip file dwarves perl unzip gawk \
     libssl-dev libelf-dev
pip install lpunpack        # or use lpunpack from AOSP otatools
```

Disk: ~35 GB transient for extraction, ~50 GB for the build (they overlap fine
on one 100 GB volume). Both scripts preflight their own deps and fail fast, so
a missed package surfaces immediately, not mid-run.

---

## Phase 1 – fork the skeleton (samsung-gts9p)

```
cp -r /path/to/ubuntu-touch-gts9/devices/gts9uwifi/skeleton samsung-gts9p
cd samsung-gts9p
```

### 1.1 Content rename (gts9u -> gts9p everywhere)

```
grep -rl gts9u . | xargs sed -i 's/gts9u/gts9p/g'
grep -rl x910 .  | xargs sed -i 's/x910/x810/g'     # incl. the flasher's MODEL_WIFI token
```

Note `gts9uwifi` becomes `gts9pwifi` via the first sed automatically, and the
update-binary device check converts COMPLETELY via these two seds (v5 keeps
all its model/codename tokens in lowercase variables for exactly this reason;
the 5G sibling x816 is derived, not spelled out).

### 1.1b Uppercase/identity pass (the lowercase seds cannot see these)

```
# USB identity strings (gadget + usb-moded)
sed -i 's/SM-X910/SM-X810/g' overlay/system/usr/libexec/gts9-adb-gadget \
    overlay/system/etc/default/usb-moded.d/device-specific-config.conf
# super.sh manual-run default (the wrapper's export wins in the scripted
# path, but a manual scripts/super.sh run must not get X910 geometry)
sed -i 's/11744051200/11714691072/' scripts/super.sh
```
(The touchpad env-var rename moved to 1.2b — its target files only get their
gts9p names in step 1.2.)

Also fix identity by hand (no sed can guess these; note the deviceinfo yaml
is still NAMED `gts9uwifi.yaml` until step 1.2 renames it):
- `deviceinfo`: `deviceinfo_name="Tab S9+ 12.4'"`
- `overlay/system/etc/deviceinfo/devices/gts9uwifi.yaml` (→ `gts9pwifi.yaml`
  after 1.2): `PrettyName: Tab S9+`
- Replace `GTS9UWIFI_EUR_OPEN.pit` with `GTS9PWIFI_EUR_OPEN.pit` (from
  `devices/gts9pwifi/reference/`); delete the X910 one.
- `PORT-README.md` describes the X910 — rewrite or delete it.
- `kernel-additions/halium.config.append` carries Ultra-only goodix notes;
  the gts9p wrapper never appends it — DELETE it (keeping it means permanent
  X910-comment noise in every 1.3 sweep).

### 1.2 File and symlink renames (sed does not rename files)

```
# regular files
for f in $(find . -name '*gts9u*' ! -type l); do mv "$f" "${f//gts9u/gts9p}"; done
# systemd wants/ symlinks: recreate so targets point at the new names
cd overlay/system/etc/systemd/system/multi-user.target.wants
for l in *gts9u*; do t=$(readlink "$l"); rm "$l"; ln -s "${t//gts9u/gts9p}" "${l//gts9u/gts9p}"; done
cd -
```

### 1.2b Touchpad env-var tidiness (must run AFTER 1.2's renames)

```
sed -i 's/GTS9U_TP_/GTS9P_TP_/g' \
    overlay/system/usr/local/bin/gts9p-tp-orient \
    overlay/system/etc/default/gts9p-tp-rotate \
    overlay/system/etc/systemd/system/gts9p-tp-rotate.service
```

Optional: skipping it leaves GTS9U_TP_FIFO/GTS9U_TP_DEFAULT names that stay
internally consistent (the daemon still works) but show up in 1.3's sweep.

### 1.3 Verify the fork (case-insensitive — uppercase leftovers bite)

```
grep -rniE 'gts9u|x910' . | grep -vE 'PORT-README|swap-vendor-modules.sh|super.sh:.*#|deviceinfo:.*#' \
  && echo "LEFTOVERS - triage each before building" || echo "clean"
ls -la overlay/system/usr/local/sbin/gts9p-audio-bringup \
       overlay/system/etc/udev/rules.d/61-gts9p-pen.rules
sh -n flashable/META-INF/com/google/android/update-binary
```

Benign residue (comments/provenance only): historical notes in
`swap-vendor-modules.sh`/`super.sh`/`deviceinfo` comments. Anything else —
especially in `flashable/`, `overlay/`, or executable scripts — must be fixed.
`build-gts9pwifi.sh`'s sanity block re-checks every audio/pen/wifi/touchpad
overlay file AND greps the flasher for Ultra tokens at build time, so a missed
rename dies loudly there rather than on-device.

### 1.4 Display scaling — a knob must be ADDED, not found

There is no GRID_UNIT/scale knob anywhere in the skeleton (verified: the grep
comes back empty — the Ultra runs default scaling). The S9+ is ~266 ppi vs the
Ultra's ~239 (~11% difference). To pre-compensate, ADD a `GridUnit` entry to
`overlay/system/etc/deviceinfo/devices/gts9pwifi.yaml` (deviceinfo yaml is the
UT mechanism for it; the Ultra yaml simply omits it). Non-blocking: wrong
scaling renders, just slightly off-size — tuning after first boot is fine.

### 1.5 SUPER default

Covered by 1.1b's sed (X810 PIT: 11,714,691,072). `build-gts9pwifi.sh` also
exports `SUPER=11714691072` before super.sh — belt and braces — and super.sh
v3 fail-fasts with a named error if the images cannot fit the geometry.

---

## Phase 2 – firmware extraction (build box)

```
curl -C - -o SAMFW.COM_SM-X810_XAR_X810XXU1AWHA_fac.zip '<s10.ooo link>'
stat -c%s SAMFW.COM_SM-X810_XAR_X810XXU1AWHA_fac.zip   # must be 9225074787
FW=$PWD/SAMFW.COM_SM-X810_XAR_X810XXU1AWHA_fac.zip ./x810-extract.sh
```

The script streams `super.img.lz4` out of the AP tar, unsparsers it, and
**hard-fails unless raw super is byte-exactly 11,714,691,072** (the
GTS9PWIFI_EUR_OPEN.pit value) – a wrong package cannot silently poison the
geometry. Output: `out-x810/parts/{vendor,odm,product,system_ext,system_dlkm,vendor_dlkm}.img`.

---

## Phase 3 – unit prep (the tablet)

Standing rule for this entire phase: **no OTA, ever**. Current fleet builds
are binary 6 – past the last unlockable rev 5. One accepted update ends this
unit's usefulness for the project permanently.

### 3.1 First boot, offline

Skip Wi-Fi entirely in the setup wizard. Enable Developer options
(Settings > About > Software information > tap Build number x7). Record
`Build number` – you need to know whether the unit shipped on AWHA or an
earlier AWG/AWF build (decision point in 3.6).

### 3.2 OEM unlocking toggle

Developer options > OEM unlocking. If hidden or greyed: set date/time
manually first; if it still demands a network check, disable auto-update
(Settings > Software update > toggle off), connect briefly, get the toggle,
disconnect. Decline anything that offers to update.

### 3.3 Download-mode readout (sourcing-rules check)

Power off. Hold Vol Up + Vol Down and insert the USB cable from the PC.
On the download screen, photograph and record: the **fuse/bit line**, the
current **binary (expect 1)**, and the **KG state**. Proceed only if the
readout matches a pre-fuse-bit-6, binary-1 unit. Vol Down to reboot out.

### 3.4 Stock ground-truth capture (while still stock, still locked)

Enable USB debugging, then:

```
adb shell cat /proc/cmdline | tee gts9p-stock-cmdline.txt
adb shell getprop ro.boot.hw_rev        # which board rev this unit is (r00/r02/r04)
adb shell getprop ro.bootloader
adb shell getprop ro.build.id
```

In the cmdline, confirm `msm_drm.dsi_display0=GTS9P_ANA38407_AMSA24VU05`
appears and **note whether any `lcd_id` args accompany it**. Our halium
cmdline uses the bare panel string (panel.c self-IDs via DDIC reads); if stock
carries lcd_id args, file them – they are the pre-planned first fix should the
display not attach in Phase 6.

### 3.5 Unlock

Download mode > long-press Vol Up > confirm. The device wipes. Redo 3.1/3.2
offline, verify OEM unlocking now shows greyed-on, and check KG state on the
download screen again per your Ultra procedure (a brief network check-in
clears prenormal if needed – same no-OTA discipline).

### 3.6 TWRP + pristine backup (order matters)

1. Odin/heimdall-flash the **gts9p** TWRP + your vbmeta-verification-disabled
   file, exactly as on the Ultra. Boot straight into recovery from the flash –
   do not let stock boot first and restore recovery.
2. **Verification gate**: this TWRP build was posted untested initially. Before
   trusting it: does it boot, does touch work in recovery, does Backup see the
   partition list? If any of that fails, stop and resolve recovery first.
3. **Pristine FULL backup, before anything else touches the device**: TWRP
   Backup with everything selectable ticked (EFS especially), then raw-dump the
   small unit-unique partitions to the host:

```
for p in efs sec_efs persist optics prism up_param; do
  adb shell "test -e /dev/block/by-name/$p && dd if=/dev/block/by-name/$p" > pristine_$p.img 2>/dev/null
done
adb pull /sdcard/TWRP ./twrp-pristine-backup
```

4. **Baseline alignment**: if 3.4 showed the unit shipped on a pre-AWHA build,
   Odin-flash the AWHA package now (BL + AP + CSC – CSC, not HOME_CSC; the
   unlock already wiped) so on-device BL/dtbo/vendor match the extracted
   parts – one vintage, no skew. This restores stock recovery: re-flash TWRP
   after. Boot stock once and repeat the 3.4 capture so your archived
   cmdline is AWHA's. If the unit already shipped on AWHA, skip this step.

---

## Phase 4 – build

```
SKEL=~/samsung-gts9p IMPORTS=/path/to/ubuntu-touch-gts9/devices/gts9pwifi/imports \
  SRC_PARTS=~/out-x810/parts  ./build-gts9pwifi.sh
```

What the script enforces on your behalf (all fail-fast, before the hours-long
kernel build where possible):

- host tool preflight; the six parts present
- gts9pwifi dts imported; cmdline retargeted to the bare GTS9P panel string
- kiwi_v2 IPA offload forced off (same as base/Ultra)
- `CONFIG_TOUCHSCREEN_STM_FTS1BA90A=m` + `CONFIG_EPEN_WACOM_WEZ01=m` present
  in the cloned tree; `stm/fts1ba90a/` and `wacom/` dirs exist
- GTS9P wired in the merged display Kbuild
- every renamed audio/pen overlay file from Phase 1
- post-build: **`stm_ts_fts1b90a.ko` AND `wez01.ko` in the module set are
  both FATAL if missing** (yes, Samsung spells it fts1b90a – do not "fix"
  it; wez01 became fatal 2026-08-30 once the wacom wiring shipped in the
  imports)
- `SUPER=11714691072` exported before super.sh

Watchpoints: first techpack failure point is the msm_drm link with the GTS9P
panel objects; if the build dies there, suspect the Kbuild merge or a
read-only-file copy issue (rerun after `chmod -R u+w` on the display dirs).
Stale-skeleton FATAL means: `rm -rf gts9p-build/samsung-gts9p` and rerun so the
updated fork stages.

Output: `gts9p-build/samsung-gts9p/out/ubuntu-touch-gts9pwifi-24.04-2.x.zip`.

---

## Phase 5 – flash

```
adb push gts9p-build/samsung-gts9p/out/ubuntu-touch-gts9pwifi-24.04-2.x.zip /data/
# TWRP: Install -> /data -> the zip     (leaves stock dtbo in place - correct:
#                                        it carries the 3 board-rev entries and
#                                        selects per ro.boot.hw_rev)
adb shell twrp reboot system
```

---

## Phase 6 – bring-up ladder

First contact is your usual halium initrd flow: USB rndis comes up, ssh in.
Then climb, one rung at a time, confirming each before the next:

1. **Display** – panel should attach via DDIC self-ID.
   `dmesg | grep -iE 'ss_dsi|GTS9P|manufacture'` – look for a sane
   manufacture_id read and the GTS9P panel probe. *If black screen*: apply the
   pre-planned fix – add the lcd_id args exactly as captured in 3.4 to
   halium.config's CONFIG_CMDLINE, rebuild boot, reflash. That is the only
   known-unknown in the display path.
2. **Touch** – `dmesg | grep -i fts` (expect fts1ba90a probe +
   `tsp_stm/fts1ba90a_gts9p.bin` firmware load from vendor), then `evtest`.
   *If dead*: confirm the fw blob exists in the mounted vendor partition;
   after that, the documented azkali-vs-base driver drift (fts_ts.c: 14 lines)
   is suspect #1 – diff and cherry-pick.
3. **Wi-Fi** – kiwi_v2 loads, interface up, scan. Same config as the working
   base port; the dts `cnss-qca6490` node name is legacy naming, ignore it.
4. **Audio** – `systemctl status gts9p-audio-bringup`, `/run/gts9p-audio-ready`
   present, PA sinks listed. The mechanism is vintage-agnostic (modules.load is
   completed from whatever vendor_dlkm is present), so this should port clean.
5. **Pen** – `evtest` on the wez01 device; fw `wez01_gts9p.bin` from vendor.
   *If dead*: wacom_i2c.c drift (148 lines) is suspect #1.
6. **Extras** – folio keyboard/touchpad (same stm32 pogo family,
   `stm32_gts9family.bin`). The rotation daemon IS baked into the forked
   skeleton (gts9p-tp-rotate, enabled, default 270 — the Ultra-proven
   landscape label; the pad name `sec_touchpad_pogo` is family-generic).
   Validate the orientation empirically on this panel: if the cursor is
   wrong in landscape, run the `gts9p-tp-orient 90` / `270` ladder from the
   daemon README and set the winning label in `/etc/default/gts9p-tp-rotate`.
   Then rotation, brightness, battery reporting.

Log each rung's dmesg to the port notes – the diffs against the Ultra's
bring-up log are the interesting artifacts for upstreaming.

---

## Rescue paths

- **Soft**: TWRP restore of the pristine backup from 3.6.
- **Full factory**: Odin the archived AWHA package (BL/AP/CSC) – possible
  forever *because* the unit stays on binary 1. Re-flash TWRP after if
  continuing.
- **Never**: accept an OTA. Binary 6 is in the wild; it is a one-way door out
  of unlockability.
