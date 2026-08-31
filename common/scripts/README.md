# common/scripts – canonical build-stage scripts (v3, merged)

As of the 2026-08-30 parity remediation the historical fork is RESOLVED.
These files are byte-identical with the copies staged in
`devices/gts9uwifi/skeleton/scripts/` (which is what the builds actually
run); this directory is the canonical reference copy. Keep them in sync –
edit here, then re-install into the skeleton(s).

- **`swap-vendor-modules.sh` (v3)** – the merge of the two v2-era branches:
  modules.load dedupe + SELinux xattr restore on rewritten lists (audio
  branch, bug #1) AND the LEFTOVER/UNLANDED audit with allowlist strict
  mode (F2 branch – the class of check that would have caught the va_macro
  hunt). With no `swap-allowlist.txt` beside it the audit is REPORT-ONLY:
  read the LEFTOVER list in the build log, triage per
  `swap-allowlist.txt.template`, then create the per-device allowlist to
  enforce. No triaged allowlist exists yet for any device – X910 and X810
  each need their own pass on the next build.
- **`super.sh` (v3)** – strict mode (F6) + the LP group ceiling at super
  capacity minus an 8 MiB reserve, with a named-error capacity check. Root
  size comes from `deviceinfo_system_partition_size` (7600M on gts9u).
  `SUPER` must be exported per device (both wrappers do).
- **`make-flashable.sh` (v2)** – strict mode, boot-chain input checks,
  static-zstd hard-require at pack time (a zip without bundled zstd would
  otherwise only fail at flash time on TWRPs lacking their own).
- **`swap-allowlist.txt.template`** – the strict-mode triage template.
  Renamed from `swap-allowlist.txt` on purpose: an empty allowlist file
  would fail every leftover; the template form makes report-only the
  explicit default.
