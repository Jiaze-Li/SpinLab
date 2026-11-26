# Agent Instructions

Purpose: make repository-wide engineering constraints automatically discoverable for Claude, Codex, and other agents working in this repository.

This is the maintained common engineering instruction entry. `CLAUDE.md` points here instead of duplicating repository-wide rules. Product and data requirements belong to the owning specs or task briefs.

## Workbench controls

- Any change to Workbench controls (Common / Plot / Workflow Specific, responsive layout, adding a workflow or Plot Mode) must follow `specs/06_WORKBENCH_CONTROLS_UI.md`. Run `./scripts/check_controls_contract.sh`; do not re-implement Common/Plot controls inside a workflow.

## UI changes

- Before adding or changing any screen, sheet, dialog or control, read `specs/04_UI_RULES.md` (spacing scale, text roles, sheet sizing). Use `AppSpacing` tokens and `WorkbenchUIStyle`/`AppFontScale` text roles; reuse `AdaptiveSheet` for form sheets and `CollapsibleSectionHeader` for section disclosures instead of writing new height logic or `DisclosureGroup`; never bare numeric spacing, `.caption`/`.footnote`/`.subheadline` readable text, or a fixed sheet height.
- Run `./scripts/check_ui_rules.sh`. It compares `Sources/SpinLabApp/Features` with the recorded baseline in `scripts/ui_rules_baseline.json`: a count may only go down. Never raise the baseline to make it pass. After cleaning old code, tighten it with `./scripts/check_ui_rules.sh --update-baseline`.

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

This section is the single source of the version rules. Other places (version file comment, Version Guard messages) only point here.

- The app version lives in one place: `Sources/SpinLabApp/App/AppVersion.swift`. `build_desktop_app.sh` reads it; branch names never carry version meaning.
- Bump it on every PR merged into `main`. After merge, CI tags `main` with the same `vX.Y.Z`. Docs/CI-only PRs use the `no-release` label instead of bumping.
- **Patch and minor are the AI's call; Jack does not decide them.** Patch = fixes only. Minor = a new user-visible capability (reset patch to 0). Mixed PR → highest level, bump once. Ordinary UI changes or new features, however large, only bump the minor digit.
- **Every bumping PR description must contain one line** `Version: vX.Y.Z - <why this digit moved>`. Version Guard fails without it, and also rejects bumps that do not reset the lower digits.
- **Major (first digit) needs Jack's explicit confirmation, every time.** It only moves when (1) a Library data-format change needs migration, or (2) the product gains a whole new way of being used. Before asking, state in one plain sentence what this major version is. The PR must then carry the `major-approved` label, or Version Guard fails (this also applies to `no-release` PRs). The AI uses Jack's GitHub account, so the label cannot prove approval by itself: never add it without Jack's explicit say-so in the current conversation.
- Versions before v5.6.0 are historical and inconsistent; do not rewrite them.

### v6.0.0 = Publish integration complete

v6.0.0 is reserved for the moment Publish (the web library) is finished. v7 and beyond have no planned trigger yet. The checklist below is the definition of "finished" (Jack confirmed v6.0.0 on 2026-11-17; all items met).

- [x] Publishing the Library to the web repository works from the Publish area of the app in one action
- [x] The Web Repository location is a setting; when unset, nothing is published automatically and nothing breaks
- [x] After publishing, the live page is checked automatically and a failed check is reported
- [x] A sample submitted from the phone shows up in the desktop Library
- [x] A note written on the phone reaches the desktop sample
- [x] One real publish to the live site has been verified end to end by Jack

Duties for the AI:

- Every PR that touches Publish updates the checklist status above in the same PR.
- When every item is checked, stop and ask Jack in plain words: "Publish integration is complete; bump to v6.0.0?" Bump only after he says yes, then add `major-approved`.
- If the checklist and reality disagree (an item regressed, or a needed item is missing), fix the checklist and tell Jack.

## Usage assumptions

- SpinLab is used by a single person, so concurrent writers to the same Library (two people editing one batch at once) are out of scope. Do not add locking or cross-writer conflict handling for it.
- **Exception to the no-locking rule above:** `docs/architecture/spinlab/execution/brief-3-single-writer.md` explicitly requires a minimal **same-machine, same-Library process write lease** so a second SpinLab instance is read-only. This is not multi-user conflict coordination; do not interpret the general assumption as blocking Task 3.
- A Batch ID is never reused for a different batch: once a batch number such as PN100 has been used, it is not created again later. Review findings that depend on a reused or colliding Batch ID are out of scope.
- Keep the existing data-safety guards (path containment, fail-closed on unreadable Library, rollback on failed writes); these assumptions only remove the need for new multi-writer or batch-reuse handling.
