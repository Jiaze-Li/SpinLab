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

## Next Planned Steps

1. Continue splitting `SpinLabAppState` by extracting feature-owned mutable state and actions into focused `@Observable` stores while preserving current routing orchestration in app shell.
2. Audit high-impact `try?` usage in `LibraryStore` and convert selected write/read paths to explicit error propagation.
3. Add lightweight cache validation on Library entry as first step before file-system event stream integration.
