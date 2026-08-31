# audio.hidl_compat.default.so null-deref: full evidence chain

Target: Halium audio wrapper HAL (`android_vendor_halium_hardware/audio/audio_hw.cpp`),
binary from Ubuntu Touch 24.04 gts9uwifi port (halium-13.0), BuildID
a60baea45ee9f1e2b1a3b8d5da069832, stripped, 24 KB.
Patch: `0001-audio_hw-fail-adev_open-when-the-devices-factory-can.patch`
(applies to halium-12.0/13.0/14.0/16.0/master – block is identical on all).

## Crash signature (systemd-coredump, PulseAudio 16.1, arm64)

    signal=11 si_code=1 (SEGV_MAPERR) fault_addr=0x0
    PC = 0x7fad8a7280 -> audio.hidl_compat.default.so (file offset 0x2280)
    LR = 0x7fad8a7278 (= PC-8)
    x0 = 0  x1 = 0  x2 = 0x50

## Disassembly of the faulting function (file offset = vaddr; .text @ 0x2000)

    2250: stp  x29, x30, [sp,#-0x20]!
    2254: str  x19, [sp,#0x10]
    2258: mov  x29, sp
    225c: adrp x1, #0
    2260: adrp x2, #0
    2264: mov  x19, x0            ; x19 = struct audio_hw_device *dev
    2268: add  x1, x1, #0xd92     ; "audio_hw_primary"          (log tag)
    226c: add  x2, x2, #0xe07     ; "adev_init_check"           (format)
    2270: mov  w0, #2             ; ANDROID_LOG_VERBOSE
    2274: bl   0x3f00             ; __android_log_print PLT
    2278: ldr  x0, [x19, #0x150]  ; x0 = wrapper->deviceIface   <- LR points here
    227c: ldr  x19, [sp,#0x10]
    2280: ldr  x8, [x0]           ; <<< FAULT: deviceIface == null
    2284: ldr  x1, [x8, #0x38]    ; vtable slot: initCheck()
    2288: ldp  x29, x30, [sp],#0x20
    228c: br   x1                 ; tail-call into the interface

Sibling trampolines at 0x2290 (slot +0x40, "adev_set_voice_volume: %f") and
0x22e4 (slot +0x48, "adev_set_master_volume: %f") confirm the pattern: every
audio_hw_device op logs, loads `deviceIface` from wrapper+0x150, and forwards.
`x1=0` at the fault is scratch from the log call; `x2=0x50` is leftover.

## Source correspondence (halium-13.0, audio/audio_hw.cpp)

    struct wrapper_audio_device {
        struct audio_hw_device hw_device;      // 0x150 bytes on arm64
        sp<DeviceHalInterface> deviceIface;    // -> wrapper+0x150
    };

    static int adev_init_check(const struct audio_hw_device *dev) {
        ALOGV("adev_init_check");
        struct wrapper_audio_device *adev = (struct wrapper_audio_device *)dev;
        return adev->deviceIface->initCheck();   // <- 0x2278..0x228c
    }

    static int adev_open(...) {
        ...
        int rc = devicesFactoryHal->openDevice(AUDIO_HARDWARE_MODULE_ID_PRIMARY,
                                               &adev->deviceIface);
        if (rc) {
            ALOGE("devicesFactoryHal->openDevice() error %d loading module %s",
                  rc, name);
        }                       // <- error swallowed: falls through,
        ...populates ops...     //    returns 0 with deviceIface == null
        return 0;
    }

## Failure narrative as observed

1. Vendor HAL refuses the open. On gts9uwifi: Samsung AGM's failure handler
   had latched `vendor.audio.use.primary.default=true` after one boot with
   the sound card offline; from then on the container-side factory returns
   ENODEV in ~1 ms (`AHAL: adev_open: 2786: fail to open audio device,
   sndcard is not active`).
2. Shim logs `devicesFactoryHal->openDevice() error -19 loading module
   audio_hw_if`, then returns 0 anyway.
3. pulseaudio-modules-droid logs "Opened hw audio device version 2.0"
   (the lie's origin), then calls init_check().
4. Trampoline logs `adev_init_check` (always the last logcat line before
   death), dereferences the null sp<>, SIGSEGV.
5. systemd restarts PA; loop; on Ubuntu Touch this crash-loop itself keeps
   re-triggering the vendor-side failure path - the error swallow converted
   a config problem into a persistent, misattributed crash that resisted a
   full session of environment/sandbox bisection until a core dump named it.

## Fix

Early-return in adev_open on factory failure (delete wrapper, null the out
param, propagate rc). Clients then see a failed hw-module open and fall
back gracefully - PulseAudio keeps running with fake sinks and one E-line
names the real problem.

## Aside for reviewers

`adev_open` receives `name` (on UT: "audio_hw_if" from the policy XML) but
opens `AUDIO_HARDWARE_MODULE_ID_PRIMARY` unconditionally - harmless today,
but it makes client logs ("loading module audio_hw_if") disagree with
server logs ("in audio.primary"), which cost real time during triage.
Possibly worth a comment or passing `name` through where supported.
