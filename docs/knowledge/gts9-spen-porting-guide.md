# S-Pen on Ubuntu Touch 24.04 – gts9uwifi implementation notes
For porting to gts9 (11") / gts9+ and other Samsung EMR devices.
Verified working 2026-08-10 on SM-X910 (Tab S9 Ultra, kalama, UT 24.04-2.x,
Halium 13). Written for the gts9 family where the kernel, Mir stack, and
vendor layout are shared – expect a near-clone port with two device-specific
checks (module name, input device name).

## TL;DR

Three pieces, all config/loader – no kernel or compositor patches:

1. Load the Wacom digitizer module (`wez01.ko` on gts9u) with
   `finit_module(..., IGNORE_MODVERSIONS|IGNORE_VERMAGIC)` – plain insmod
   fails EINVAL against the halium kernel.
2. A libinput quirk that adds `INPUT_PROP_DIRECT` and STRIPS the pen button
   codes so libinput cannot classify the device as a tablet.
3. A udev rule asserting `ID_INPUT_TOUCHSCREEN`.

Result: the pen drives the UI as a precise single-touch input. Full digitizer
data (4096-level pressure, tilt, hover distance) is present at evdev; app
pressure is platform-gated (section 8) – the Wayland client stack for it is
already on the image, the compositor generation is the only missing link.

## 1. Loading the module

Stock `wez01.ko` lives in vendor_dlkm and is modversion-locked against the
stock kernel; on the halium kernel plain insmod fails:

    insmod: ERROR: could not insert module .../wez01.ko: Invalid parameters

EINVAL here = vermagic/modversion rejection. (If you instead see
"Unknown symbol", stop – that is a missing dependency, a different problem.)

Load it with finit_module, flags = MODULE_INIT_IGNORE_MODVERSIONS |
MODULE_INIT_IGNORE_VERMAGIC = 3 (`__NR_finit_module` = 273 on arm64):

    python3 -c "
    import ctypes, os
    libc = ctypes.CDLL(None, use_errno=True)
    fd = os.open('/android/vendor_dlkm/lib/modules/wez01.ko', os.O_RDONLY)
    r = libc.syscall(273, fd, b'', 3)
    print('rc=%d' % r + ('' if r==0 else ' errno=%d' % ctypes.get_errno()))
    os.close(fd)"

Risk framing, honestly: the module was built from the same android13-5.15
kalama source family as the halium kernel; ABI drift is theoretically
possible, empirically it has been stable across days of uptime and many
reboots on gts9u (as have muic_sm5714/pdic_sm5714, loaded the same way for
charging). Do NOT blanket-force every module that fails plain insmod – the
typical failed list contains other-variant codecs, dataipa-dependent wlan,
and ipam/rmnet pieces that must stay dead. Curated allowlist only.

Boot integration – either fold into an existing bring-up service (we run it
as "stage 2" of ours, before any long waits), or as a minimal standalone
oneshot:

    # /usr/local/sbin/gts9-pen-load
    #!/bin/sh
    grep -q "^wez01 " /proc/modules && exit 0
    exec python3 - <<'EOF'
    import ctypes, os
    libc = ctypes.CDLL(None, use_errno=True)
    fd = os.open('/android/vendor_dlkm/lib/modules/wez01.ko', os.O_RDONLY)
    raise SystemExit(0 if libc.syscall(273, fd, b'', 3) == 0 else 1)
    EOF

    # /etc/systemd/system/gts9-pen-load.service
    [Unit]
    Description=Load S-Pen digitizer module (finit, ignore modversions)
    After=local-fs.target
    [Service]
    Type=oneshot
    ExecStart=/usr/local/sbin/gts9-pen-load
    RemainAfterExit=yes
    [Install]
    WantedBy=multi-user.target

(Plus the wants symlink if shipping via overlay. The script must tolerate
/android appearing late – poll for the .ko if your mount ordering is loose.)

## 2. What a healthy digitizer looks like

/proc/bus/input/devices on gts9u after load:

    N: Name="sec_e-pen"
    S: Sysfs=/devices/platform/soc/.../i2c-60/60-0056/input/inputN
    B: EV=2b
    B: KEY=c03 0 2000000000000000 100000000000 0 0
    B: ABS=f000003

Decoded: ABS_X/Y + ABS_PRESSURE(0x18) + ABS_DISTANCE(0x19) +
ABS_TILT_X/Y(0x1a/0x1b); KEY includes BTN_TOOL_PEN, BTN_TOOL_RUBBER,
BTN_TOUCH, BTN_STYLUS/2. i2c address is informational (60-0056 on X910;
yours may differ).

Raw-event proof (no evtest needed):

    EV=$(awk '/^N:.*sec_e-pen/{f=1} f&&/^H:/{match($0,/event[0-9]+/);
         print substr($0,RSTART,RLENGTH); exit}' /proc/bus/input/devices)
    timeout 10 python3 -c "
    import struct
    f=open('/dev/input/$EV','rb')
    for _ in range(60):
        d=f.read(24)
        if not d: break
        _,_,t,c,v=struct.unpack('llHHi',d)
        if t: print(f'type={t:#04x} code={c:#04x} val={v}')"

Hover: X/Y stream + ABS_DISTANCE ticking + BTN_TOOL_PEN=1.
Contact: BTN_TOUCH=1 + ABS_PRESSURE ramp (we observed 655→1251 mid-press;
range is 0–4095).

Bonus device you will also see: `hall_wacom` – the pen-garage/cover hall
switch, a plain EV_SW device Lomiri already classifies as Switch. Free
attach-detection hook for later; needs nothing now.

## 3. Why it does NOT drive the UI natively

- udev's input_id sees BTN_TOOL_PEN → tags `ID_INPUT_TABLET` → libinput
  initializes its tablet-tool interface for the device.
- The UT 24.04 compositor is UBports' Mir 1.x fork (libmir1server.so.53,
  libmir1wayland.so.0, session runs with MIR_SERVER_ENABLE_MIRCLIENT=1).
  Its Wayland frontend contains ZERO `zwp_*` interface strings – there is
  no `zwp_tablet_manager_v2` to enable; `MIR_SERVER_WAYLAND_EXTENSIONS` is
  a Mir 2 / miral facility and does not apply.
- Apps additionally ride the mirclient QPA
  (`QT_QPA_PLATFORM=ubuntumirclient;wayland-egl;xcb`), so even the Wayland
  client path is bypassed today.

Net: native tablet events have no consumer anywhere in the current stack.
The pen produces perfect events into a void.

## 4. The fix – two files

/etc/libinput/local-overrides.quirks:

    [Samsung S-Pen gts9u]
    MatchName=sec_e-pen
    AttrInputProp=+INPUT_PROP_DIRECT
    AttrEventCode=-BTN_TOOL_PEN;-BTN_TOOL_RUBBER;-BTN_STYLUS;-BTN_STYLUS2

/etc/udev/rules.d/61-gts9u-pen.rules:

    SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="sec_e-pen", \
      ENV{ID_INPUT}="1", ENV{ID_INPUT_TABLET}="", ENV{ID_INPUT_TOUCHSCREEN}="1"

Mechanism – this is the part worth understanding rather than cargo-culting:
the quirk's AttrEventCode removes the pen/stylus button capabilities BEFORE
libinput classifies the device, so the tablet backend cannot claim it (a
tablet with no pen tools is not a tablet); INPUT_PROP_DIRECT plus BTN_TOUCH
plus ABS_X/Y then satisfies the touchscreen path, which the udev tag also
asserts. Expect `ID_INPUT_TABLET=1` to REMAIN visible in udevadm output –
input_id's tag survives the ENV clear on this udev version. It is inert
(the capability strip decides the outcome); do not spend time chasing it.

Apply: write both files, `udevadm control --reload-rules`, then bounce the
module (rmmod + finit as above) so the device re-enumerates – no session
restart needed – or just reboot with the loader unit in place. Rename the
rule file to match your codename; adjust `MatchName`/`ATTRS{name}` if your
device name differs (likely also `sec_e-pen` on gts9 – verify, section 6).

## 5. Verification ladder

1. Module: `lsmod | grep wez01` (or your name).
2. Device: `grep -A7 sec_e-pen /proc/bus/input/devices`.
3. Session saw it: `journalctl -b | grep "Input device added"` →
   expect `"sec_e-pen" ... (Button|TouchScreen|Switch)`.
4. Events: the python reader above – hover stream, then BTN_TOUCH +
   pressure on contact.
5. Human: tap icons, drag lists with the tip. This is the verdict; nothing
   in 1–4 substitutes for it.

If 4 passes and 5 fails, re-check the quirk actually matched (`libinput
quirks list /dev/input/eventN` if libinput-tools installed) and that both
files survived your read-only rootfs (`mount -o remount,rw /` first – a
silent EROFS write cost us one full debugging round).

## 6. Adapting to gts9 (11") / gts9+

Two things to verify, everything else transplants:

1. Module name: `ls /android/vendor_dlkm/lib/modules/ | grep -iE
   "wez|wacom|pen"` – gts9u uses wez01; same-generation boards usually
   share it, but confirm, and confirm the failure mode is EINVAL (not
   Unknown symbol) before reaching for finit.
2. Input device name after load: `grep -B1 -A7 -i pen
   /proc/bus/input/devices` – set MatchName and ATTRS{name} to exactly
   what you see.

Same kernel family, same Mir 1.x stack, same udev/libinput versions – the
classification story and the fix are identical by construction.

## 7. Known limitations (deliberate and honest)

- No hover cursor: touch semantics – fingers do not hover. Hover data
  exists at evdev only.
- No pressure/tilt in apps; pen side-button and eraser are inert (their
  codes are stripped by design). Bespoke apps CAN read /dev/input directly
  and get the full 4096-level stream today.
- Palm rejection: untested and likely absent. Pen and finger are now two
  independent touchscreens; stock Android suppresses touch during pen
  proximity across drivers, and nothing does that here. Future option: a
  small daemon gating the touchscreen on BTN_TOOL_PEN proximity (or
  hall_wacom) – design sketch available on request, not needed for basic
  use.
- Simultaneous pen + finger produces two independent touch streams; most
  UI copes, drawing apps may not.

## 8. Pressure: the platform path (for when it opens)

The missing link is solely the compositor+QPA generation, and the evidence
says pressure lights up with NO port-side work once UT lands the Mir 2 /
Wayland transition:

- Qt5WaylandClient 5.15.13 on the 24.04 image contains the complete
  zwp_tablet_v2 client (manager/seat/tool/pad symbols AND the runtime
  handler string "Ignoring zwp_tablet_tool_v2_proximity_v2 with no
  surface" – it processes, not just declares).
- Qt5Gui carries QTabletEvent (apps can receive pressure).
- Mir 1.x server: zero zwp strings; mirclient QPA is the live app path.

Revisit checklist when the session goes Wayland/Mir 2: delete the udev
rule, reduce the quirk to MatchName + INPUT_PROP_DIRECT only (or delete
it), let the device classify as a tablet, and test with any
QTabletEvent-aware app. Until then, pen-as-touch is the supported mode.

## 9. Where this lives in the gts9uwifi tree

Overlay: `overlay/system/etc/libinput/local-overrides.quirks`,
`overlay/system/etc/udev/rules.d/61-gts9u-pen.rules`; module loading is
stage 2 of `overlay/system/usr/local/sbin/gts9u-audio-bringup` (curated
finit allowlist `muic_sm5714 pdic_sm5714 wez01` – the first two fix
charging, same EINVAL/finit story, take them too if your charging is on
SM5714). Build sanity checks in build-gts9uwifi.sh verify all of it before
a build starts. Ask John for the current skeleton tarball; everything above
is self-contained enough to cherry-pick without it.
