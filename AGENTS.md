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

## Long output handling

Decide by the length of the **final user-visible body**, not by task type or
keywords (audit / review / diagnosis / implementation / validation / migration /
test are not triggers by themselves).

- If the final user-visible body is expected to exceed **2000 Unicode
  characters**, write the complete report to a descriptive `.txt` file under
  `~/Desktop/`, and in the terminal print only a concise summary, the 3–5 most
  important findings, and the absolute path to that file.
- If it is 2000 characters or fewer, do not create a file — print the full
  content in the terminal so it is easy to copy.
- If the user explicitly asks to save the report / write it to a txt / put it on
  the Desktop, always write the file regardless of length.
- When near the threshold and unsure, write the final body to a temp file,
  count Unicode characters exactly, then decide.

File rules:

- Path: `~/Desktop/`. Filename: `<project>_<topic-slug>_<YYYYMMDD-HHMM>.txt`
  (project = current repo dir name; topic-slug = short lowercase `-`-joined ASCII
  slug, no spaces or `/ \ : * ? " < > |`).
- Never overwrite an existing file — append `-2`, `-3`, … on collision.
- UTF-8 encoding; CJK content must be preserved. Do not `git add` / commit the
  file. Never write the report inside any git-tracked repo path unless the user
  asks.
- The report contains only user-visible results — no chain-of-thought, drafts,
  raw tool logs, or private notes. Clearly separate confirmed facts from
  hypotheses; record concrete file paths / functions / commands; mark anything
  not runtime-verified as "not verified".
- This only adds the "long output → Desktop" action; it does not replace any
  report-content requirements stated elsewhere in this file.
- If `~/Desktop/` is missing or unwritable, say so in the conversation and fall
  back to `~/Documents/`, then `/tmp/`, always stating the final actual path.
- After saving, do not repeat the full long report in the conversation.
