# Agent Instructions

Purpose: make the testing strategy automatically discoverable for Codex and other agents working in this repository.

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
