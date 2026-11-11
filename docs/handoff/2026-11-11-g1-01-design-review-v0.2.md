# SpinLab G1-01 — v0.3 Independent DESIGN Gate review handoff

**Active candidate: v0.3, DESIGN PENDING.** This is the one active handoff for the original `SPINLAB-G1-01-SAFETY v1.0`. The filename retains its original v0.2 suffix for continuity with already-shared GitHub links; **do not review v0.2 as the current candidate**. Review all materials at the **same immutable Git commit SHA**.

- Frozen policy: `2304f2e93185fca3b50fb1f076b2e1801797492d`; read `Jiaze-Li/personal-skills/engineering-reviewer/skill.md` at this SHA.
- G0 v1.4: historical DESIGN PASS. Original SHA-256 `d3709d05a17d5414e18d54fee3658e61fded40432ea6543b58765b7e3ed00eb8` (46,620 UTF-8/LF bytes).
- Original G1-01 Worker v1.0: frozen AC1–AC6, S1–S6. SHA-256 `24521827f5fe06712f37430ed42d7aeecdd0337df705f12581bb84e8fdbbb1d9` (12,397 bytes).
- **Candidate v0.3 design_ref:** `sha256:b5772dfa84c7678340113c50d613d599997d785c0d03b4fbd297922f9fe8c81e` (45058 bytes, exact UTF-8/LF including trailing LF). `DESIGN PENDING`, not PASS.
- Previous v0.1: DESIGN REWORK (D-01–D-05); previous v0.2: DESIGN REWORK (R2-01, R2-02, R2-03). The v0.3 limited revision adds durable completed idempotency receipts, complete file/index/receipt sync order, and pre-write protection of unknown JSON fields in authoritative source files. Independently check that these are consistent and actually close all three blockers.

## Immutable primary materials

1. [**v0.3 candidate design**](../architecture/library/contracts/spinlab-g1-01-shared-write-delete-design-v0.3.md)
2. [G0 v1.4 exact original](../architecture/library/contracts/spinlab-g0-identity-association-v1.4.md)
3. [Frozen G1-01 Worker v1.0 exact original](../architecture/library/contracts/spinlab-g1-01-frozen-worker-v1.0.txt)
4. [Historical v0.2 design — DESIGN REWORK, not the current candidate](../architecture/library/contracts/spinlab-g1-01-shared-write-delete-design-v0.2.md)

## Code and review baseline

- Repository: `Jiaze-Li/SpinLab`; PR #195 code baseline `01e19d823829fbf5f6bf6b224fd95e861e0ceaea`, base `T01` `d29d914b7a19824d822361ed67ea67b322705786`.
- PR #195 bot last reported REWORK (F001 P2), and review was PARTIAL; this DESIGN Gate cannot change code-review status. Recheck actual HEAD when code work is later considered.
- Original Worker reproduced two races on **isolated synthetic data** only: A, stale index overwrites another Batch update; B, recursive Batch deletion removes newly created Sample and measurement. No production data damage was observed.
- PR #194/T01 remains paused; G2 is not authorized by this review.

## Strict permissions / next action

Perform **Tier 3 Independent DESIGN review, read only**, using the frozen Reviewer skill. First verify the exact bytes of the three primary contracts and hashes, then assess R2-01, R2-02, R2-03, prior D-01–D-05, the original frozen invariants, and positive/negative recovery evidence requirements. Return independent DESIGN PASS / DESIGN REWORK / DESIGN BLOCKED **bound to v0.3 design_ref**. No repo edits, source code, tests on actual Library, PR mutations, permissions, merge or claims of code PASS.

The docs-only PR #197 is just a transfer vehicle; its title may still mention v0.2. This file and SHA-256 specify the **sole current candidate**. The provisional v0.3 design does not authorize implementation or merge. Temporary handoff cleanup requires separate approval under `docs/handoff/README.md`.
