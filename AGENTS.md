# Agent Instructions

Purpose: make repository-wide engineering constraints automatically discoverable for Claude, Codex, and other agents working in this repository.

## Testing

Before fixing tests or changing test expectations:

- Read `docs/architecture/TESTING_STRATEGY.md`.
- Classify the failure before editing code.
- Identify the failure category, owner module, and test tier.
- Prefer targeted tests before full `swift test`.
- Do not turn test failures into broad architecture work.
- For Rules-dependent tests, prefer `RulesTestHarness` helpers:
  - `withBundledRules`
  - `withTempRulesBook`
  - `withTempRulesDirectory`
  - `withUnconfiguredRules`
- Treat full `swift test` as closeout, not first diagnostics, unless explicitly requested.

## Technical debt governance

- `docs/TASK_BOARD.md` is the repository entry point to the shared `SpinLab-shared/TASK_BOARD.md`, and that shared board is the **only lifecycle source of truth** for technical debt.
- Before acting on a recorded debt, verify that the debt still exists against the current `HEAD`. Stale debt records must be closed or corrected rather than mechanically implemented.
- Architecture, audit, roadmap, ADR, and handoff documents may record current architecture, invariants, rationale, historical findings, and references to a debt ID. They must **not** independently maintain debt lifecycle state such as Open, Deferred, priority, planned migration, or Resolved.
- Do not create a second technical-debt tracker in repository docs, source comments, or handoffs. Persistent source `TODO` comments are implementation-local notes only; when they represent tracked debt, reference the canonical debt entry instead of becoming another status record.
- Accepted or deferred debt must have an explicit trigger for reconsideration (for example: a third consumer appears, or a shared behavioral change requires synchronized edits).
- When code resolves, supersedes, or invalidates a debt, update the canonical task-board entry in the same change and repair any architecture/audit prose that has become factually stale.
- If the shared board is unavailable from the current tool/environment, do **not** create a substitute tracker. Record the exact required board mutation in the handoff/final report so an agent with local access can apply it.

## Change closeout

After any code change:

- Always run `./scripts/check_required_actions.sh`.
- If the output contains `Required: ./scripts/build_desktop_app.sh debug`, run `./scripts/build_desktop_app.sh debug`.
- Final reports must include:
  - exact `check_required_actions.sh` output
  - whether a desktop rebuild was required
  - whether `build_desktop_app.sh debug` was run
  - `/Applications/SpinLab.app` version
  - `CFBundleVersion`
  - whether `~/Desktop/SpinLab.app` exists
