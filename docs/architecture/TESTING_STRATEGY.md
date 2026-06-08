# Testing Strategy

Status: active

This document defines how to choose, classify, and run tests while editing the
Rules Book and nearby subsystems.

## Test Tiers

- Tier 0: build / compile checks
  - Use for compiler validation, module linkage, and broad regression gating.
  - Examples: `swift build`.
- Tier 1: fast unit tests
  - Use for narrow behavior checks with small fixture setup and no heavy I/O.
  - Prefer these first when validating a targeted change.
- Tier 2: module fixture tests
  - Use for tests that rely on bundled fixtures, temporary directories, or
    harness helpers that construct a realistic but isolated module state.
  - Rules-dependent tests should prefer `withBundledRules`,
    `withTempRulesBook`, `withTempRulesDirectory`, and `withUnconfiguredRules`.
- Tier 3: integration-heavy tests
  - Use for cross-module flows, persistence-heavy scenarios, and tests with
    broader runtime orchestration.

## Failure Classification Before Editing

Classify the failure before changing code:

- Runtime regression
- Stale test expectation
- Invalid fixture
- Missing dependency injection
- Async scheduling / timeout
- Toolchain blocker
- Pre-existing baseline issue

If the failure is not yet classified, do not edit code until it is.

## Test Selection Rule

- Targeted tests first.
- Full `swift test` only at closeout.

## Owner To Test Map

### Rules Book / RulesPanel

- `V515RulesBookStateTests`
- `V515RulesPanelStoreTests`
- `V515RulesPanelSaveValidationTests`
- `V515RulesSaveImmediateEffectTests`
- `V5114SharedSingletonAbsenceTests`
- `V5115RulesBootstrapperCharacterizationTests`
- `V5116RecomputeBannerFalsePositiveTests`

### Workbench Main Search

- `V332WorkflowWorkspaceDispatchTests`
- `V537WorkbenchSearchMirrorTests`
- `V538SelectedHitsBridgeAuditTests`

### Render / Payload

- `V400PlotRendererTests`
- `V563WorkflowStateBoundaryTests`

### Integration-Heavy

- `V537AnalysisLifecycleBoundaryTests`
- `V537SaveModuleBoundaryTests`
- `V213InboxClosedLoopTests`
- `V517RecomputeUITests`

## Rules Test Guidance

- Prefer the shared Rules test harness over local ad-hoc temp directory helpers.
- Use explicit rule-source helpers so the test shows whether it depends on:
  - bundled rules
  - a temporary Rules Book
  - a temporary Rules directory
  - an unconfigured Rules state
- Keep fixture scope as small as possible while still exercising the behavior
  under test.
