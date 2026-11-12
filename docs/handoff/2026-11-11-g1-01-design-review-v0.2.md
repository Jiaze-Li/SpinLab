# SpinLab G1-01 — v0.4 Independent DESIGN Gate review handoff

**Only active candidate: v0.4 — DESIGN PENDING.** This is the single temporary handoff for the original `SPINLAB-G1-01-SAFETY v1.0`. The filename retains an older v0.2 suffix for compatibility with existing links, but **v0.4 is the only candidate**. Read all documents at the same fixed Git commit SHA, never floating `main`.

## Immutable materials

- Current candidate: [G1-01 shared-write/delete supplemental design v0.4](../architecture/library/contracts/spinlab-g1-01-shared-write-delete-design-v0.4.md). **design_ref: `sha256:d186e372ab74badb1d873ab510fe555253096626a163557b3c4359ba44250f51`**, exact size 55794 UTF-8/LF bytes including terminal LF.
- Historical G0 v1.4: [unaltered source](../architecture/library/contracts/spinlab-g0-identity-association-v1.4.md). SHA-256 `d3709d05a17d5414e18d54fee3658e61fded40432ea6543b58765b7e3ed00eb8`; 46,620 bytes. Original DESIGN PASS remains historical.
- Original frozen G1-01 Worker contract v1.0: [unaltered source](../architecture/library/contracts/spinlab-g1-01-frozen-worker-v1.0.txt). SHA-256 `24521827f5fe06712f37430ed42d7aeecdd0337df705f12581bb84e8fdbbb1d9`; 12,397 bytes. AC1–AC6/S1–S6 unchanged.
- Historical DESIGN REWORK drafts: [v0.3](../architecture/library/contracts/spinlab-g1-01-shared-write-delete-design-v0.3.md), [v0.2](../architecture/library/contracts/spinlab-g1-01-shared-write-delete-design-v0.2.md); do not confuse them with current candidate.

Policy frozen at `Jiaze-Li/personal-skills@2304f2e93185fca3b50fb1f076b2e1801797492d`; Reviewer must read `engineering-reviewer/skill.md` at that commit.

## Reviewer focus

Independent v0.3 DESIGN REWORK (F3-01 P1, F3-02 P1). v0.4 adds: (1) separate session `lockScopeKey` from durable `rootUUID`, with first registration, restart, symlink, move/copy and conflict behavior; (2) global Root-wide recovery fence for any unresolved R2/R3/R4 pending before any K write, including `ensureRoot` migration, index sync, direct Store writes and change logs. Confirm F3-01/F3-02 are closed without contradicting prior R2-01–R2-03, D-01–D-05, G0 and frozen G1. Verify V5/V7/V9 include successful legacy Root registration, device-ID change across reboot and two-process crash/recovery with other-Batch writer blocked until A is finalized, but not for a valid completed+stale pending.

Code evidence: `Jiaze-Li/SpinLab` PR #195 frozen audit HEAD `01e19d823829fbf5f6bf6b224fd95e861e0ceaea`, stacked on T01 `d29d914b7a19824d822361ed67ea67b322705786`. Bot was REWORK F001 P2; this design review does not imply code PASS. Original Worker reproduced A lost index update and B recursive deletion of concurrently added Sample + measurement in **isolated synthetic Library only**; real production data damage not claimed. PR #194/T01 paused. Docs Draft PR #197 is only a transport artifact.

**Only next action:** independent Tier 3 DESIGN Review, **strictly read-only**, first verify exact raw UTF-8 bytes/hashes of the three primary contracts and frozen Reviewer skill. Return DESIGN PASS / DESIGN REWORK / DESIGN BLOCKED **bound to the v0.4 design_ref**, with consolidated findings. No code edits, document changes, repository/PR mutations, real data, access changes, merge, or claims of code PASS. This handoff is not an implementation license and may be removed only under `docs/handoff/README.md` with appropriate authorization.
