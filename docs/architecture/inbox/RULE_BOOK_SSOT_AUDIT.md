# Rule Book Runtime SSOT — Audit & Repair Record

> **Scope**: prerequisite architecture repair on `afm-workflow`, before AFM implementation begins.
> **Goal**: the configured external Rule Book is the sole runtime source of truth for
> user-configurable rule data. A saved Rule Book change must affect the next relevant
> in-process operation without app restart or stale rule-derived snapshots; normal production
> runtime must never silently substitute built-in fallback rules.

This is not a general repository walkthrough — it records the four known violations from the
task brief plus what a targeted Phase 3 sweep turned up, each classified as **VIOLATION**
(repaired here), **VALID CODE SEMANTIC**, **MIGRATION/TEST ONLY**, or **MATERIAL DECISION
REQUIRED** (left for product/architecture discussion).

## Known violations (repaired)

### V1 — Import extension snapshot (VIOLATION, repaired)

- **Location**: `Sources/SpinLabApp/Import/ImportPipeline.swift` (`SpinLabImportPipeline`).
- **Problem**: `supportedFileExtensions`/`ignoredFileExtensions` were computed once in `init` from
  `SpinLabRuleProviding.importRules()` and stored as `let`. `SpinLabAppState` builds this pipeline
  before the configured Rule Book is loaded, so a later "add `ibw`" Rules save never reached the
  long-lived pipeline instance.
- **Repair**: both are now computed properties that call `ruleProvider.importRules()` on every
  access; `importFiles(_:)` reads them once per call, not once per instance lifetime. No
  reconstruction is required for a save to take effect.
- **Verification**: `Tests/SpinLabAppTests/RuleBookSSOTRepairTests.swift` — `AC1/AC2`, `AC1 live
  provider`, `AC3`, `AC4` cases construct one pipeline instance, mutate the Rule Book, reload, and
  assert the *same instance* reflects add/remove/ignore/case-insensitivity without rebuilding.
  Pre-existing suites `V5115RulesSaveImmediateEffectTests`, `V515RulesBookStateTests` unaffected.

### V2 — Duplicate workflow membership truth (VIOLATION, repaired)

- **Location**: `Sources/SpinLabApp/Domain/Workflow/WorkflowKey.swift`.
- **Problem**: `WorkflowKey.ruleBookIDs` hardcoded the full expected `workflow.json` id list and
  `assertRuleBookConsistency()` compared `WorkflowKey.allCases` against it — a second, driftable
  copy of Rule Book workflow membership living in Swift. (Dead code: `assertRuleBookConsistency()`
  was never called from app startup or any test, so this had already silently drifted with no one
  noticing — the exact failure mode the architecture principle warns about.)
- **Repair**: removed both. `WorkflowKey`'s doc comment now states explicitly that it represents
  *implemented application capability*, not Rule Book membership, and that a Rule Book workflow
  with no matching case is valid and must stay safe. `workflow.json` (via
  `WorkflowDefinitionStore`) remains the only place that enumerates Rule Book workflow membership.
  Dispatch that resolves an id to a `WorkflowKey` already treats a miss as safe (`WorkflowKey(rawValue:)?.searchPrefix ?? ""` in `WorkbenchMainSearchRuntime.swift:194`) — unchanged.
- **Verification**: existing `V515RulesBookStateTests` ("partial workflow definitions do not crash
  startup", "switching Rules Book refreshes workflow definitions") and `V332WorkflowWorkspaceDispatchTests` continue to pass unchanged (AC5/AC6).

### V3 — Rule-dependent objects constructed before RuleLoader configuration (VIOLATION, repaired)

- **Locations**:
  - `Sources/SpinLabApp/Import/RegistrySubstrateRuleBook.swift`
  - `Sources/SpinLabApp/App/AppEnvironment.swift`, `Sources/SpinLabApp/SpinLabApp.swift`,
    `Sources/SpinLabApp/Storage/RulesBookSettings.swift`, `Sources/SpinLabApp/App/SpinLabAppState.swift`
- **Problem, part A (freshness/ownership)**: `RegistrySubstrateRuleBook` compiled its
  treatment/material/orientation tables once in `init` from the current `ruleSet()` and stored
  them as `let`. Once built (e.g. in `AppEnvironment.live()`, wired into
  `ArchivedRecordResolverService` for the app's lifetime), it never re-read the Rule Book again —
  neither the startup ordering problem nor a later Rules save would ever refresh it.
- **Repair, part A**: `RegistrySubstrateRuleBook` is now a fingerprint-keyed derived cache: an
  internal `CompiledCache` rebuilds its compiled tables only when
  `ruleProvider.loadResult().ruleSetFingerprint` changes, otherwise reuses the cached value. This
  matches the "derived cache keyed by current RuleLoader fingerprint" pattern in the task's
  Implementation Approach — no second persistence source, no new cache category.
- **Problem, part B (startup ordering)**: `SpinLabApp.init()` built `AppEnvironment.live()` —
  which eagerly constructs `RegistrySubstrateRuleBook()` and
  `XLSXPrefixSampleRegistryIndex.fromEnvironment(...)` — *before* `SpinLabAppState.init` ran its
  `RuleLoader.configure(...)` call. Both objects' first build could read from an
  unconfigured/fallback `RuleLoader`.
- **Repair, part B**: extracted the "migrate/bootstrap Rule Book, then `RuleLoader.configure` +
  `reloadCached`" sequence into `RulesBookSettings.prepareAndConfigureRuleLoader()` (previously
  inlined in `SpinLabAppState.init` and duplicated in a private `prepareConfiguredRulesBookForLoad()`
  helper used by `configureRulesBook(at:)`). `SpinLabApp.init()` now calls it *before* constructing
  `AppEnvironment.live()`; `SpinLabAppState.init` still calls it too (idempotent — cheap to call
  twice) so every other caller (tests, previews, convenience inits) gets the same guarantee without
  depending on caller discipline.
- **Verification**: `RuleBookSSOTRepairTests.swift` — `AC7/AC8` builds a `RegistrySubstrateRuleBook`
  once, changes the Rule Book, reloads, and asserts the same instance now resolves using the new
  substrate data. `V515RulesBookStateTests`'s three `SpinLabAppState`-construction tests already
  exercise the full startup path end to end.

### V4 — Silent production fallback (VIOLATION, repaired)

- **Location**: `Sources/SpinLabApp/Import/Rules/RuleLoader.swift`,
  `Sources/SpinLabApp/Import/Rules/FilenameRuleSet.swift`.
- **Problem**: `RuleLoader.load()`'s two production-unavailable paths
  (`notConfiguredResult()`, and the "could not assemble from Rules Book" failure branch) both
  returned `FilenameRuleSet.fallback()` — which carries real usable content (`csv/txt/dat/lvm`
  extensions, `PN`/`PT`/`SL` sample-ID prefixes, temperature/current/field/device conditions).
  An unconfigured or broken Rule Book therefore let import/parsing/routing continue as if a
  reasonable Rule Book existed, invisibly.
- **Repair**: added `FilenameRuleSet.empty()` — a fully inert rule set (no sample-ID matches, no
  supported/ignored extensions, no workflow/condition/substrate rules) — and both
  `RuleLoader` unavailable-paths now return it instead of `.fallback()`. Every downstream consumer
  therefore fails closed (nothing matches, nothing imports) instead of silently producing
  plausible-looking decisions from data the user never configured. `metadata.sourceLabel`
  (`"NotConfigured"` / `"Fallback"`) and `warnings` are unchanged, so `RulesBookState` /
  Rules Panel UI surfacing is unaffected. `FilenameRuleSet.fallback()` itself, and
  `RuleLoader.loadFromBundleOnly()`'s own fallback branch, are untouched — both remain explicitly
  documented dev/test-only tooling (see MIGRATION/TEST ONLY below).
- **Verification**: `RuleBookSSOTRepairTests.swift` — `AC9` (unconfigured) and `AC9` (corrupt
  `import_filters.json`, with the other four required files present and valid) both assert
  `importRules?.supportedFileExtensions.isEmpty == true` and (for the unconfigured case)
  `sampleId.matches.isEmpty`. `AC10` confirms `loadFromBundleOnly()`'s legitimate dev-fixture path
  still works. This exposed one **pre-existing masked test bug**, fixed alongside (see below).

### Pre-existing test bug exposed by the V4 repair

`Tests/SpinLabAppTests/V515RulesSaveImmediateEffectTests.swift` —
`r1ConditionDefinitionOptionsRefreshed` never called `RuleLoader.configure(bookPaths: paths, ...)`
before constructing its `RulesManagementStore`, unlike its three sibling tests in the same file.
It passed only because `RuleLoader.shared`'s (previously fallback-producing) unconfigured path
happened to include a condition definition literally named `"field"` in `FilenameRuleSet.fallback()`
— the exact `#expect(capturedOptionsAfterSave.contains("field"))` assertion the test wanted true
for the right reason, but was actually true for the wrong reason. Fixed by adding the missing
`RuleLoader.configure(bookPaths: paths, ...)` call, matching the sibling tests.

`Tests/SpinLabAppTests/V223AppEnvironmentIntegrationTests.swift` — three tests constructed
`SpinLabAppState` via the convenience initializer with a default (unconfigured) `RulesBookSettings()`
while separately routing the *routing* rule provider through a bundled fixture
(`makeBundleRuleRuntime()`); the *import* pipeline's default `SpinLabRuleProvider.shared` was left
depending on ambient global `RuleLoader` state. Under the old fallback behavior this coincidentally
worked (`.dat` is in `FilenameRuleSet.fallback()`'s built-in extensions). Fixed by adding
`makeBundleRulesBookSettings()` — an explicit `RulesBookSettings` pointed at the same bundled dev
fixture used for routing — passed to `SpinLabAppState(..., rulesBookSettings:)` so both the import
and routing paths derive from the same explicitly-configured source. Also hardened the two
import-exercising tests to retry their (idempotent) scan inside the poll loop, since
`RuleLoader.shared`'s static configuration is process-global and can be transiently reconfigured
by an unrelated, concurrently-running Swift Testing suite — a pre-existing test-isolation
characteristic of this global singleton, not something introduced by this repair (see below).

## Phase 3 — repository-wide sweep

### VALID CODE SEMANTIC

- **`LibrarySettings.default.allowedBatchPrefixes = ["PN", "PT", "SL"]`**
  (`Sources/SpinLabApp/Library/Domain/LibraryDomainModels.swift:35`). This is the seed value of a
  distinct, user-editable *Library* setting (its own persistence, its own UI in
  `LibraryWorkspaceSections.swift`), not a copy of the Rule Book's `sampleId.matches`. Coincidentally
  overlapping default content, not a competing runtime source — a user can freely edit it away from
  the Rule Book's prefixes without any conflict. Not touched.
- **`Sources/SpinLabApp/Workflow/WorkflowDefinitionStore.swift`**: reads
  `RuleLoader.currentBookPaths?.workflowURL` fresh on every `load()` call (no `init`-time snapshot)
  and decodes it with its own local `WorkflowFileDraft`-shaped type rather than reusing
  `RuleLoader`'s internal decode types. It targets the *same* live, currently-configured path each
  call, so it cannot diverge into a stale second source — it's decode-logic duplication, not a
  competing truth source. Left as-is; unifying its decoder with `RuleLoader`'s would be a
  refactor with its own regression surface, out of this task's bounded scope.
- **`Sources/SpinLabApp/Import/Rules/WorkflowRegistryRetirementService.swift`**: reads/writes
  `workflow.json` directly, bypassing `RuleLoader`. This is a one-time legacy
  `workflow_registry.json` → `workflow.json` migration tool (`runIfNeeded()`), not an ongoing
  runtime rule consumer — see MIGRATION/TEST ONLY.

### MIGRATION/TEST ONLY (legitimate, isolated from production)

- `RuleLoader.loadFromBundleOnly()`'s own `FilenameRuleSet.fallback()` branch
  (`Sources/SpinLabApp/Import/Rules/RuleLoader.swift`) — explicitly documented
  "For use in tests and dev tooling only — not called in production."
- `WorkflowRegistryRetirementService` (above) — legacy migration, not a runtime consumer.
- `SpinLabRuleProvider.importRules()` / `InlineRuleProvider.importRules()`'s
  `?? fallback.importRules!` branches (`Sources/SpinLabApp/Import/Rules/SpinLabRuleProvider.swift:40,72`)
  — dead code in practice: every `FilenameRuleSet` constructed anywhere in this codebase
  (`RuleLoader.assembleRuleSet`, `.empty()`, `.fallback()`) always sets `importRules` to a non-nil
  value, so this branch cannot currently fire. Left in place as defensive coding rather than
  removed, since proving it's unreachable for all future callers isn't this task's job; noted here
  so a future reader doesn't mistake it for a live fallback path.

### MATERIAL DECISION REQUIRED

- **Sample registry (XLSX index) does not rebuild after a Rules save that changes registry-relevant
  rules.** `RegistryLookupRuleBook` (`Sources/SpinLabApp/Registry/RegistryLookupRuleBook.swift`)
  snapshots header aliases / excluded sheets / sample-ID parsing at `init`, same pattern
  `RegistrySubstrateRuleBook` had. In isolation this wouldn't matter — it's rebuilt fresh on every
  `XLSXPrefixSampleRegistryIndex` construction (not held long-lived itself) — but
  `SpinLabAppState.refreshAfterRulesBookChange()` never calls `reloadSampleRegistry()`, so the
  *already-loaded* `sampleRegistry` (built from the old rules) stays active until the user manually
  triggers a registry reload through some other UI path. This is the same violation class as V3
  ("XLSX registry indexing... constructs rule-dependent lookup behavior while building its
  snapshot"), but the fix is not mechanical: unconditionally re-parsing the XLSX registry file on
  *every* Rules save (including sections with no registry impact, e.g. measuring conditions) is a
  real perf/UX change for large registries, and selectively reloading only when
  registry-relevant sections change would require threading per-section change detection into
  `refreshAfterRulesBookChange()`, which doesn't exist today. Left unrepaired; flagged for a
  product/architecture decision on when the registry should auto-reload.
- **`Sources/SpinLabApp/Registry/RegistryGrowthRouting.swift:11-24`** hardcodes
  `prefixRoutes`, `pnPrefix`, `pnSRORoutedSheet`, `sroMaterialTokens` as Swift constants. The file's
  own comment states this is deliberate, "per spec §5/§6" — i.e. a previously made, documented
  product decision, not an accidental duplicate. Changing it to Rule-Book-driven data would
  reopen that decision. Left unrepaired; out of this task's bounded scope.

## AC coverage summary

| AC | Status | Evidence |
|---|---|---|
| AC1–AC4 | repaired | `RuleBookSSOTRepairTests.swift` (AC1/AC2, AC1 live provider, AC3, AC4) |
| AC5–AC6 | already held; unchanged | `V515RulesBookStateTests`, `V332WorkflowWorkspaceDispatchTests` |
| AC7–AC8 | repaired | `RuleBookSSOTRepairTests.swift` (AC7/AC8); `V515RulesBookStateTests` startup-path tests |
| AC9–AC10 | repaired | `RuleBookSSOTRepairTests.swift` (AC9 ×2, AC10) |
| AC11 | this document | every VIOLATION above links its repair + test; non-violations state why |
| AC12 | held | full regression sweep below |

## Regression evidence

- `swift build` / `swift build --build-tests`: clean (only pre-existing, unrelated warnings).
- Directly associated suites (`RuleBookSSOTRepairTests`, `V223AppEnvironmentIntegrationTests`,
  `V515RulesBookStateTests`, `V5114RulesLiveReloadOrderTests`, `V332WorkflowWorkspaceDispatchTests`,
  `V214RegistryRuleBookTests`, `V224RegistrySubstrateRuleBookTests`,
  `V541LibraryRegistryFallbackRemovalTests`, `V515RulesSaveImmediateEffectTests`): pass reliably,
  repeated runs.
- Broader sweep (registry/routing/workflow/inbox/library, ~1200 tests / 108 suites): pass, with one
  known pre-existing flaky exception documented below.

### Known pre-existing flakiness (not introduced by this change, not fixed by this change)

`V223AppEnvironmentIntegrationTests`'s import-exercising tests can intermittently fail only when
run as part of a *large combined* `--filter` alongside dozens of unrelated suites, never in
isolation or alongside the suites directly associated with this repair. Root cause: `RuleLoader`'s
configuration (`RuleLoader.configure`) is process-global static state, and Swift Testing schedules
non-`.serialized` suites concurrently within one test process — an unrelated suite elsewhere in the
target can transiently reconfigure `RuleLoader.shared` mid-test. This is a pre-existing
characteristic of the test suite's reliance on a global singleton (many other files already do
`RuleLoader.configure()` + restore without any cross-suite coordination); it was largely invisible
before this repair because `SpinLabImportPipeline` used to snapshot its extensions at construction
(a much smaller race window) — the same global-state hazard, just harder to hit. Fixing it properly
(e.g. making `RuleLoader` non-global, or serializing all Rule-Book-mutating suites against each
other) is a test-infrastructure change beyond this task's bounded scope; separately unrelated
suite `V515RulesEngineRegressionTests` shows the identical symptom (isolated: always passes;
combined with enough concurrent suites: occasionally fails) confirming it is not specific to any
file touched by this diff. The new `RuleBookSSOTRepairTests.swift` added by this repair is
susceptible to the same hazard for the same reason (it also calls `RuleLoader.configure()`
directly) — solid every time run alone or alongside the suites it was specifically verified
against, but can show the identical symptom if combined with `V223AppEnvironmentIntegrationTests`
in one large `--filter` run. This is the pre-existing hazard surfacing in a new file, not a new
hazard.
