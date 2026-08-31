# archive — provenance, evidence, and superseded material

Nothing in here is needed to build. It is the paper trail behind everything
in the live tree.

- **Kept out of this repository (private):** the lossless transcripts of
  the 28 source working conversations, the raw diagnostic log uploads
  (dmesg/journal/straces — device logs can embed identifiers), and the
  per-thread conversation-summary notes. They live only in the local
  capture workspace (`.../claude-ubuntu-touch/_capture/`). Citations in
  the retained docs of the form `[thread.pN]` / `transcripts/<file>:line`
  refer to that private capture.
- `notes/` — the retained engineering analyses: RECON (build-script
  lineage, skeleton diffs, fixes catalog), the two synthesis documents
  (`SYNTHESIS-port-state.md` is the original source of
  `docs/knowledge/PORT-STATE.md`, which has since been corrected and
  extended — the live copy wins), and `parity/` (the 2026-08-30
  three-device parity audit).
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
