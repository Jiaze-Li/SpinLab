# Agent Instructions

Purpose: make repository-wide engineering constraints automatically discoverable for Claude, Codex, and other agents working in this repository.

This is the maintained common engineering instruction entry. `CLAUDE.md` points here instead of duplicating repository-wide rules. Product and data requirements belong to the owning specs or task briefs.

## Workbench controls

- Any change to Workbench controls (Common / Plot / Workflow Specific, responsive layout, adding a workflow or Plot Mode) must follow `specs/06_WORKBENCH_CONTROLS_UI.md`. Run `./scripts/check_controls_contract.sh`; do not re-implement Common/Plot controls inside a workflow.

## Feature and architecture work

- For **Sample-centred new-model work**, start with `docs/architecture/spinlab/execution/README.md`, its `SKELETON.md` and the relevant task brief. For unrelated fixes, use `docs/architecture/INDEX.md` and the owning region instead; do not force the Sample execution pack onto all work.
- New-model rules describe an approved target, not proof of current Swift implementation. Check existing behavior before changing legacy storage or compatibility.
- Sample-centred task order and status live in the 5.6.x segment of `docs/V5_ROADMAP.md`. Do not start a task whose prerequisites are not checked off.
- When a task merges, check it off in `docs/V5_ROADMAP.md` in the same PR. If the work changes a rule in `SKELETON.md`, change `SKELETON.md` in the same PR.
- Older design documents (`docs/architecture/spinlab/planning/`, `contracts/`, `docs/architecture/library/contracts/`) are reference only. Where they disagree with the execution folder, the execution folder wins. Do not implement the G1-01 supplemental designs v0.1-v0.4.

## Adding Swift code

1. Find the owning area with `docs/architecture/INDEX.md`; update its Code Map where that area maintains one. Do not decide ownership from physical directory alone.
2. When adding/removing/renaming `Sources/SpinLabApp/Features/Workbench/**/*.swift`, update `docs/architecture/workbench/SHELL_BLOCKS.md` under `## Code Map`: one backticked source path and one short stable responsibility per entry.
3. Run `./scripts/verify_architecture_code_coverage.sh`; the current verifier covers **Workbench Feature files only**, not all Swift files. For local pre-commit integration use `./scripts/install_git_hooks.sh`.

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

## Versioning

- The app version lives in one place: `Sources/SpinLabApp/App/AppVersion.swift`. `build_desktop_app.sh` reads it; branch names never carry version meaning.
- Bump it on every PR merged into `main` (CI `Version Guard` fails otherwise; docs/CI-only PRs use the `no-release` label). After merge, CI tags `main` with the same `vX.Y.Z`.
- Which digit: patch = fixes only; minor = a new user-visible capability (reset patch to 0); major = UI/workflow overhaul or Library data-format change that needs migration. Mixed PR → highest level, bump once.
- Versions before v5.6.0 are historical and inconsistent; do not rewrite them.
