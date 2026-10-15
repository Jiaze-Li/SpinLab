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

## Test storage lifecycle

Test processes never use the real `Application Support/SpinLab` folder; default-path stores and
loggers resolve to a per-process `Application Support/com.spinlab.tests.<pid>` folder instead
(`AppInternalPaths.userDataDirectory(in:)`). `TestStorageLifecycle` keeps that area from growing:

- A test process deletes its own folder at exit. Only `logs/` is kept, and only when the process
  logged an error, so a failing run stays diagnosable.
- At start, a test process removes folders of dead processes that are older than 1 hour (24 hours
  for log-only folders, of which only the newest is kept). A folder is removed only if its name is
  exactly `com.spinlab.tests.<digits>`, it is a real directory owned by the current user, its
  top-level entries are all known test artifacts, and its pid is not a running test process.
  Anything else is left in place.
