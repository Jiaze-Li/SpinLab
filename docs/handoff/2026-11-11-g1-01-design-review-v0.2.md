# SpinLab G1-01 — DESIGN Gate v0.2 review handoff

**Purpose:** Temporary read-only cross-context handoff; not an additional source of product authority. Single active handoff for this task. Consume from an immutable Git commit, not floating `main`.

- Original task: `SPINLAB-G1-01-SAFETY v1.0` — AC1–AC6 and S1–S6 unchanged.
- Frozen policy SHA: `2304f2e93185fca3b50fb1f076b2e1801797492d`.
- G0 v1.4: historical DESIGN PASS; original bytes SHA-256 `d3709d05a17d5414e18d54fee3658e61fded40432ea6543b58765b7e3ed00eb8`.
- Worker v1.0 frozen contract SHA-256: `24521827f5fe06712f37430ed42d7aeecdd0337df705f12581bb84e8fdbbb1d9`.
- Candidate v0.2 design SHA-256 / `design_ref`: `bc4e4e39598144630e48c056e89a80647507da67806a7380eaf7554b21ad6c7a` (33,467 bytes, UTF-8/LF, trailing LF). Status: **DESIGN PENDING**, not PASS.
- v0.1 DESIGN REWORK findings to verify: D-01 coordination protocol; D-02 deletion snapshot and recursive delete boundary; D-03 index field authority and unknown fields; D-04 conditional rollback and crash recovery; D-05 adversarial concurrency tests.

## Immutable materials for reviewer

The following three files are **verbatim**, not rewritten; inspect each at the fixed commit SHA of this documentation branch:

1. [v0.2 candidate design](../architecture/library/contracts/spinlab-g1-01-shared-write-delete-design-v0.2.md)
2. [G0 v1.4 frozen design](../architecture/library/contracts/spinlab-g0-identity-association-v1.4.md)
3. [G1-01 v1.0 frozen Worker contract](../architecture/library/contracts/spinlab-g1-01-frozen-worker-v1.0.txt)

## Implementation context (read-only)

- Repository: `Jiaze-Li/SpinLab`.
- PR #195: `G1-01` stacked on `T01`. Code baseline: `01e19d823829fbf5f6bf6b224fd95e861e0ceaea`, PR bot state at handoff: REWORK, F001 P2 OPEN; recheck live state before any action.
- PR #194 / T01 acceptance remains **PAUSED**, not part of this design review.
- Reproduced with **synthetic** Library by Worker: (A) cross-Batch index lost update; (B) recursive delete absorbs concurrently created Sample + measurement. Do not claim production data corruption was observed.
- Scope of reviewer: independent Tier 3 DESIGN Gate for v0.2 only, using `engineering-reviewer/skill.md` at frozen `policy_sha`; compare exact bytes and original G0/G1 invariants. Return DESIGN PASS / REWORK / BLOCKED, independently. Do not edit repo or assert code PASS.
- Authorization: only this documentation branch, commit/push and draft documentation PR approved. No source changes, test/data edits, merge, permissions, destructive actions or actual G1 code implementation authorized in this handoff.

**Only next action:** Independent Reviewer reads this document and the three files from a fixed commit SHA, validates hashes, and reviews v0.2. If the current DESIGN is REWORK, send consolidated findings to Engineering Lead. Remove temporary handoff only under `docs/handoff/README.md` cleanup policy with separate authorization.
