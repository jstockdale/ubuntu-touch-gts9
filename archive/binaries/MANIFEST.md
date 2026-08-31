# archive/binaries – manifest

These files exist on local disk but are **excluded from git**
(Samsung/Qualcomm proprietary binaries). Verify with `sha256sum -c` against
the hashes below after any copy.

| File | Bytes | SHA-256 | What it is |
|---|---|---|---|
| `oracle-bundle.tgz` | 146,889,524 | `880028e3ee56459bfaa0f55ac4172894cac68948b194d22e6945a2555f42856d` | `halbins2/`: the complete gts9uwifi vendor audio-HAL binary set (AGM/PAL/sndcardparser + Samsung/arcsoft libs) + `hal.strace` + symbol-string dumps, captured for the audio RE work. Not reproducible without the device. |
| `halbins.tgz` | 3,155,294 | `df91390c9ce72005149ed082742ce0e5f84b40c7d9419102997fcee6cbb338a1` | First, smaller HAL binary capture (oracle-bundle's `halbins2/` is the fuller second pass). |
| `audio_hidl_compat_default.so` | 24,608 | `c8e62402369e96b57f45a442da7ff907121369228c8903a711946a8f91fa723d` | The Halium `audio.hidl_compat.default.so` shim binary analyzed in `patches/upstream/halium-audio-hidl-compat/shim-crash-analysis.md` (BuildID `a60baea45ee9f1e2b1a3b8d5da069832`; crash PC = file offset 0x2280). |
| `gts9u-compile-validation.tar.gz` | 2,199,200 | `3bad4d68c44690fda36c283a3dece53f11076b9f1f2997981df34e7358f8b4da` | Session-6 proof-of-compile: `wez01.ko`, `goodix_ts_berlin.ko`, gts9u r00 dtbo, `.config`, VALIDATION.md. Historical. |

# archive/osrc (also git-ignored)

| File | SHA-256 | Source |
|---|---|---|
| `SM-X810_13_Opensource_dts.zip` | `7607e5bc622b289527dbf1f8edeaca43e9fa1e67e309572375b977e922e3977c` | opensource.samsung.com (gts9pwifi dts overlay, X810XXU1AWG1) |
| `SM-X818U_13_Opensource_X818USQU1AWH8_….zip` | `79dd507a3501b9410d0f989d3c986f4d8ecff42159daf9936a0815bf27ddb246` | opensource.samsung.com (AWH8 delta; the full **base** `SM-X818U_13_Opensource.zip` was too large to retain – re-download) |
