# common/scripts — v2 "F-series" build-stage scripts

These are the hardened variants produced by the 2026-08-05/07 build review
(findings F1–F9): strict shell mode, named errors, host-lpmake probing, and —
in `swap-vendor-modules.sh` — the **LEFTOVER/UNLANDED module audit with
allowlist strict mode** (`swap-allowlist.txt`), the safeguard class that would
have prevented the va_macro audio hunt.

## ⚠ Divergence warning — read before using

The gts9uwifi skeleton (`devices/gts9uwifi/skeleton/scripts/`) carries its own
copies of these scripts. The two lines forked in parallel:

| Script | This dir (v2/F-series) | Skeleton copy (audio-era) |
|---|---|---|
| `swap-vendor-modules.sh` | audit + allowlist + strict mode | **modules.load dedupe** (audio bug #1 fix) + SELinux xattr on lists |
| `super.sh` | F6 strict mode, named errors, lpmake probe | original |
| `make-flashable.sh` | v2 strict, input checks, zstd hard-require | original |

Neither `swap-vendor-modules.sh` is a superset of the other. **A proven build
uses the skeleton copies** (that is what V3 `build-gts9uwifi.sh` stages). The
correct future state is a merge of dedupe + audit — tracked in the open-issues
ledger. Until merged, prefer the skeleton copies for building and use this
dir's audit as a manual post-check.

`swap-allowlist.txt` is the reviewed leftover allowlist for the X910 (stock
modules intentionally not replaced).
