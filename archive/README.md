# archive — provenance, evidence, and superseded material

Nothing in here is needed to build. It is the paper trail behind everything
in the live tree.

- `transcripts/` — lossless captures of the 28 claude.ai working
  conversations (Jul–Aug 2026), named `<date>_<slug>_<conv-uuid8>.md`. Full
  message text plus every pasted log and text attachment (bodies of
  duplicate attachments deduplicated in place). This is the canonical source
  the whole repo was reconstructed from on 2026-08-30.
- `notes/` — the reconstruction working notes: per-thread mining notes,
  RECON analyses (build-script lineage, skeleton diffs, fixes catalog), and
  the two synthesis documents. `SYNTHESIS-port-state.md` here is the source
  of `docs/knowledge/PORT-STATE.md`.
- `logs/<thread>/` — raw diagnostic uploads (dmesg, journal, straces,
  probe outputs) that back specific findings in the docs.
- `session8-audio/` — the session-8 audio bisection one-off scripts. Their
  conclusions shipped; the scripts are methodology/evidence.
- `pen-investigation/` — the S-Pen/Krita investigation ladder (pen-*.sh,
  krita-*.sh, mir-tablet.sh). Outcome: the Mir 1.8 tablet-protocol ceiling.
- `superseded/` — earlier versions kept for diffing: build-gts9uwifi V1/V2
  (+ re-uploads), update-binary v1/v3, tp-rotate v0, the pre-audio original
  skeleton tarball, the reverted-analysis audio diagnosis v1, the phablet-run
  audio-fix installer variant.
- `binaries/` — **git-ignored** (Samsung/Qualcomm proprietary): see
  `binaries/MANIFEST.md` for what belongs here and the SHA-256 of each file
  held on local disk.
- `osrc/` — **git-ignored**: Samsung Open Source Release zips (redistribution
  is Samsung's; re-download from opensource.samsung.com — exact package names
  in `devices/gts9pwifi/docs/gts9p-hw-findings.md`).
