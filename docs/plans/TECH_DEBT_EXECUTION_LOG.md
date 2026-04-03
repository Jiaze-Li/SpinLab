# Technical Debt Execution Log

Status: active

## 2026-03-27 Round A

Scope:
- Start incremental architecture debt reduction without breaking current behavior.

Completed:
- Introduced repository-to-app reactive projection baseline.
  - `InboxRepository.pendingImportsStream`
  - `LibraryRepository.archivedRecordsStream`
  - `LibraryRepository.projectsStream`
  - `SpinLabAppState` now subscribes and projects stream updates back into observable UI state.
- Added lifecycle-safe projection tasks in `SpinLabAppState` with cancellation in `deinit`.
- Unified several state mutation paths to use projection/replace helpers instead of ad-hoc direct assignment.

Rationale:
- Keep single UI observation boundary in `SpinLabAppState`.
- Reduce coupling and future merge conflicts around core arrays.

## 2026-03-27 Round B

Scope:
- Address critical I/O error blind spots and strengthen parser/match confidence.

Completed:
- Improved registry install error visibility:
  - `SpinLabManagedStorage.installSampleRegistry(from:)` now throws structured errors.
  - `SpinLabAppState.loadSampleRegistry(from:)` now catches and surfaces failures via `AppError` alert + log.
- Added parse boundary tests:
  - conflict warning when filename sample ID and folder sample ID disagree.
  - file-stem fallback when workflow token cannot be detected.
- Added drawer match boundary tests:
  - empty input returns `nil`.
  - duplicate canonical candidates return `nil` for exact canonical query.

Rationale:
- Eliminate silent failure in user-facing registry workflow.
- Increase confidence in research-data parsing edge cases where correctness risk is high.

## 2026-03-27 Round C

Scope:
- Improve scientific traceability and add lightweight cache staleness guard.

Completed:
- Added batch-level edit audit log:
  - On `LibraryStore.updateSample`, changes now append to both:
    - per-sample `sample_change_log.json`
    - per-batch `edit_log.json`
  - Batch log entry format reuses `LibrarySampleChangeLogEntry` for consistent schema.
- Added lightweight index staleness check:
  - `LibraryStore.needsIndexRefresh(rootURL:)` compares batch-root modification time vs index timestamp.
  - `SpinLabAppState.validateLibraryCacheOnAppear()` triggers `syncLibraryFromFiles()` when stale.
  - `LibraryView` now invokes cache validation on appear through `LibraryViewModel`.

Rationale:
- Preserve provenance at batch level for auditability in research workflows.
- Reduce risk of stale UI index after external filesystem updates without introducing full filesystem event watching yet.

## 2026-03-27 Round D

Scope:
- Apply projection performance hardening, repository batching primitives, AppEnvironment integration tests, and structured main-thread isolation.

Completed:
- Repository transaction support:
  - `InboxRepository.performTransaction(...)`
  - `LibraryRepository.performTransaction(...)`
  - transaction-aware deferred persist + deferred stream emission (single flush per transaction).
- Projection batching in `SpinLabAppState`:
  - Added buffered projection queues for pending imports, archived records, and projects.
  - Added main-loop coalescing drain using `Task.yield()` to avoid bursty UI updates.
- AppEnvironment integration test scaffolding:
  - Added `V223AppEnvironmentIntegrationTests` with mock persistence + mock data actor.
  - Covered import flow projection and registry-load failure surfacing path.
- Structured main-thread isolation:
  - Marked `SpinLabAppState` as `@MainActor`.
  - Updated cross-boundary callers/providers/view-models to respect actor isolation.
  - Bridged domain context adapter synchronous protocol boundary via `MainActor.assumeIsolated`.

Rationale:
- Improve responsiveness under bursty stream updates.
- Ensure future batch operations can scale without N-times UI churn.
- Increase confidence in dependency-injected orchestration paths.
- Make UI-state mutation thread guarantees explicit and compiler-checked.

## 2026-04-03 Round E

Scope:
- Close high-impact V2.7 debt around apply path unification, duplicate-guard extraction, and rules canonicalization single-source.

Completed:
- Apply path unification:
  - Moved shared apply context/progress loop ownership into `ApplyCoordinator`.
  - `SpinLabAppState` selected/apply-all now share one coordinator async path.
  - Removed local dual apply helper surface from `SpinLabAppState`.
- Rules canonicalization single-source:
  - Added `RuleCanonicalizer`.
  - `RuleLoader` and `ConditionRulesHandbookStore` now both delegate to shared canonicalization routines.
- Duplicate guard extraction:
  - Added explicit `DuplicateGuard`.
  - Integrated into `SpinLabManagedStorage.importMeasurementFiles(...)`.
- Pending cleanup side-effect isolation:
  - Added `PendingCleanupService` and routed `InboxFacade.clearPendingImports()` through it.
  - Removed redundant clear helper from `InboxWorkflowService`.

Rationale:
- Reduce drift risk between runtime loader migration and handbook migration.
- Keep app-shell orchestration thinner while preserving current behavior.
- Make duplicate rejection and clear-imports safety boundaries explicit and testable.

## 2026-04-03 Round F (UI切换卡顿排查与修正)

Scope:
- Investigate repeated first-level sidebar area-switch lag (`Inbox`/`Workbench`/`Library`) and apply low-risk responsiveness fixes.

Completed:
- Reproduced and instrumented sidebar switching path with temporary latency probes (later removed after conclusion).
- Confirmed lag concentration at `tap -> selectedArea` transition window, not in snapshot persistence writes.
- Applied/kept the following fixes:
  - Keep detail views alive in `RootSplitView` using layered view composition (no full page reconstruction on each area switch).
  - Persist sidebar provider instance in `RootSplitView` state so library subtree cache can survive view refreshes.
  - Removed duplicate `rebuildPreviewDerivedData()` call on `LibraryView.onAppear`.
  - Added short cooldown to `validateLibraryCacheOnAppear()` to avoid rapid repeated cache-validation sync checks during frequent switches.
  - Reduced redundant sidebar interaction persistence churn by persisting on explicit expansion actions instead of generic expanded-set observer churn.
- Removed all temporary latency logging code after diagnosis and fix validation.

Evidence summary:
- Field logs repeatedly showed area switch latency around ~8-23ms with occasional spikes (~25-29ms).
- `navigate(...)` path itself remained low single-digit ms when observed.
- No meaningful snapshot write-latency signals correlated with the perceived switch hitch.

Conclusion:
- Primary contributor was UI transaction/render cost from area-switch detail view rebuilds and same-frame sidebar state churn, not storage I/O.

Validation:
- Regression suite remained green during iterations:
  - `V223AppEnvironmentIntegrationTests`
  - `V230ApplyTests`
  - `V272PendingCleanupSafetyTests`

## Next Planned Steps

1. Continue splitting `SpinLabAppState` by extracting feature-owned mutable state and actions into focused `@Observable` stores while preserving current routing orchestration in app shell.
2. Audit high-impact `try?` usage in `LibraryStore` and convert selected write/read paths to explicit error propagation.
