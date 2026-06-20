# Gate 7.0 Main Search Extraction Readiness Handoff

> Docs-only audit. No runtime behavior is changed by this file.

## Scope

This audit records the exact runtime boundaries that must stay intact before Gate 7.1 Main Search extraction begins.

It covers:

- canonical Main Search ownership in `WorkbenchFeatureStore`
- workflow-local mirror state in `AHEWorkspaceStore`, `XYRotationWorkspaceStore`, and `ThreeOmegaWorkspaceStore`
- restore and pack paths that still depend on the mirror
- the test suite that currently blocks unsafe extraction order

It does not authorize any runtime changes.

## 1. Current Main Search Ownership Map

| Concern | Canonical owner | Current runtime surface | Notes |
|---|---|---|---|
| Query text | `WorkbenchFeatureStore.searchQueryTexts` | `searchQueryText(for:)`, `setSearchQueryText(_:for:)` | `setSearchQueryText` also persists to `UserDefaults` under `workbench.searchQuery.<workflowID>`. `searchQueryText(for:)` falls back to `wf.searchPrefix`. |
| Result list | `WorkbenchFeatureStore.searchResults` | `searchResultsList(for:)` | Shell result UI reads canonical results from here, not from workflow-local caches. |
| Status / message | `WorkbenchFeatureStore.searchMessages` | `searchMessage(for:)` | Search status is canonical and workflow-keyed. |
| Running state | `WorkbenchFeatureStore.searchRunning` | `isSearchRunning(for:)` | Search running state is canonical and workflow-keyed. |
| Canonical read surface | `WorkbenchFeatureStore` | `searchSnapshot(for:)` | `WorkbenchSearchSnapshot` is the shell-facing immutable read surface. |
| Search execution | `WorkbenchFeatureStore` | `runWorkflowMeasurementSearch(workflowID:libraryRootPath:librarySettings:)` | Writes canonical search state first, then mirrors into workflow-local caches. |
| Search reset | `WorkbenchFeatureStore` | `clearWorkflowMeasurementSearch(workflowID:)` | Clears canonical search state and workflow-local mirrors, then resets query text to the workflow prefix. |
| Restore bridge | `WorkbenchFeatureStore` | `restoreSearchState(results:queryText:for:)` | Restores canonical results/query/message/running state. It does not touch selection. |

### Current read consumers

- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceSearchSection.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceResultsList.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceResultArea.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceActionBar.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkbenchReadAdapter.swift`
- `Tests/SpinLabAppTests/V332WorkflowWorkspaceDispatchTests.swift`
- `Tests/SpinLabAppTests/V538WorkbenchReadinessConsumptionTests.swift`
- `Tests/SpinLabAppTests/V537WorkbenchSearchMirrorTests.swift`

## 2. Workflow-Local Mirror Map

| Workflow | Local mirror state | Current role |
|---|---|---|
| AHE | `selectedSearchResultIDs`, `cachedSearchResults`, `cachedSampleNumericDisplay` | Local selection state, local hit mirror, and title/numeric-display cache. |
| XY Rotation | `selectedSearchResultIDs`, `cachedSearchResults`, `cachedSampleNumericDisplay` | Local selection state, local hit mirror, and title/numeric-display cache. |
| 3ω | `selectedSearchResultIDs`, `cachedSearchResults`, `cachedSampleNumericDisplay` | Local selection state, local hit mirror, and title/numeric-display cache. |
| 3ω auxiliary slot | `rtQuery`, `rtSearchResults`, `rtSearchMessage`, `isRTSearching`, `showRTPopover`, `selectedRTHit`, `pendingRTSidecarPath`, `cachedRTFilePath` | Secondary-input search state. This is not part of Main Search and belongs to Gate 7.3. |

### Workflow-local selection helpers

- `isAllSelected`
- `selectAll()`
- `deselectAll()`
- `toggleSearchHitSelection(_:)`
- `clearResults()`

### Workflow-local search caches that still matter

- `cachedSearchResults`
- `cachedSampleNumericDisplay`

`cachedSampleNumericDisplay` is not canonical search state, but it is still needed for title-token rebuilds and analysis-time display projection.

## 3. Why `cachedSearchResults` Still Exists

`cachedSearchResults` is still required for five separate runtime reasons.

| Required for | Why it still matters | Current code path |
|---|---|---|
| Selected-hit snapshot bridge | `WorkflowWorkspaceActionBar` passes `legacyHits: store.cachedSearchResults` into `WorkbenchFeatureStore.selectedHitsSnapshot(...)`. The snapshot factory uses canonical results first and only falls back to legacy hits when canonical results are empty. | `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceActionBar.swift`, `Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift` |
| Select-all denominator | `isAllSelected` and `selectAll()` are still defined against the workflow-local mirror count and IDs. | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift`, `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift`, `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift` |
| Pack decode / restore compatibility | Pack configs persist the mirror, restore writes it before rerender, and `loadPack()` sets `activePackID` only after restore returns. | `Sources/SpinLabApp/Workbench/V3/*PackContracts.swift`, `Sources/SpinLabApp/Workbench/V3/AnalysisPackProviding.swift`, `Sources/SpinLabApp/Features/Workbench/*Pack.swift` |
| Analysis input fallback | Legacy `runAnalysis()` / `runAnalysis(searchSnapshot: nil)` still read the mirror for pack-restore and direct-call compatibility. | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift`, `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift`, `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Analysis.swift` |
| Workflow-local display state | Title/context rebuilds still read the mirror and `cachedSampleNumericDisplay` after restore or rerender. | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift`, `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift`, `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Rendering.swift`, `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+ManifestCache.swift` |

### Restore-order dependency

Pack restore must still preserve this order:

1. restore workflow-local mirror state
2. restore canonical search state through `restoreSearchState`
3. rerender from restored analysis state
4. rebuild manifest / title / related-chart projections

That order is locked by the pack boundary tests and must not be changed as part of Gate 7.1.

## 4. Restore and Pack Paths

### Canonical pack load flow

- `AnalysisPackProviding.loadPack(id:restoreSearchState:)` cancels in-flight work, decodes pack config/result, calls `restoreFromPack(...)`, then sets `activePackID = id` and `analysisMessage = "Loaded: ..."` after restore returns.
- `WorkbenchLoadPackPopover.load(_:)` wires the workflow load callback to `WorkbenchFeatureStore.restoreSearchState(results:queryText:for:)`.

### Workflow restore entry points

| Workflow | Restore entry point | Mirror write | Canonical search callback | Post-restore action |
|---|---|---|---|---|
| AHE | `AHEWorkspaceStore.restoreFromPack(...)` | `cachedSearchResults`, `selectedSearchResultIDs` | `restoreSearchState(config.cachedSearchResults, config.searchQueryText)` | Rerender active tab or legacy `runAnalysis()` path |
| XY Rotation | `XYRotationWorkspaceStore.restoreFromPack(...)` | `cachedSearchResults`, `selectedSearchResultIDs` | `restoreSearchState(config.cachedSearchResults, config.searchQueryText)` | `_rerenderAllTabs()` and `refreshRelatedCharts()` |
| 3ω | `ThreeOmegaWorkspaceStore+Pack.restoreFromPack(...)` | `cachedSearchResults`, `selectedSearchResultIDs`, `selectedRTHit`, `rtQuery`, `cachedRTFilePath` | `restoreSearchState(config.cachedSearchResults, config.searchQueryText)` | `_rerenderAllTabsFromRestoredState()`, `_snapshotAndCacheManifestPayloads()`, `refreshRelatedCharts()` |

### Canonical-search fallback rule

- `WorkbenchFeatureStore.selectedHitsSnapshot(...)` uses canonical search results first.
- `legacyHits` are used only when canonical results are empty.
- `ThreeOmegaWorkspaceStore+ManifestCache._snapshotAndCacheManifestPayloads()` still has a no-arg overload that rebuilds from the workflow-local mirror after restore.
- `AHEWorkspaceStore.runAnalysis(searchSnapshot:)`, `XYRotationWorkspaceStore.runAnalysis(searchSnapshot:)`, and `ThreeOmegaWorkspaceStore.runAnalysis(searchSnapshot:)` still fall back to the mirror when the snapshot is nil.

## 5. Gate 7.1A Classification

### Safe in 7.1A

| Change class | Safe because |
|---|---|
| Read-only canonical search interface consolidation | It does not move selection ownership, pack restore behavior, or analysis input construction. |
| Shell/UI callers reading from `searchQueryText(for:)`, `searchResultsList(for:)`, `searchMessage(for:)`, `isSearchRunning(for:)` | These are already canonical search reads and do not require mirror access. |
| New regression tests that pin the current search bridge order | Tests are read-only and protect the extraction boundary. |
| Internal refactor inside `WorkbenchFeatureStore` that preserves every current public search API and restore ordering | Canonical ownership stays put while the seam becomes clearer. |

### Unsafe until Selection extraction

| Change class | Why it is unsafe now |
|---|---|
| `selectedSearchResultIDs` ownership move | Selection state still lives in workflow stores. |
| `selectAll()`, `deselectAll()`, `toggleSearchHitSelection(_:)` move | These are the current selection mutations. |
| `isAllSelected` denominator change | It is still defined against `cachedSearchResults`. |
| `selectedHitsSnapshot(...)` construction change | The selected-hit bridge still depends on the mirror fallback and must stay stable. |
| `WorkflowWorkspaceActionBar` removing `legacyHits: store.cachedSearchResults` | That bridge is the current compatibility path. |

### Unsafe until Pack / Restore extraction

| Change class | Why it is unsafe now |
|---|---|
| `restoreSearchState(results:queryText:for:)` behavior change | Pack restore still depends on the explicit canonical callback. |
| `AnalysisPackProviding.loadPack(...)` ordering change | `activePackID` must remain set by the caller after restore returns. |
| Pack config schema changes for `cachedSearchResults` | Existing packs still decode this field. |
| Removing the AHE legacy nil-ingestion path | That path is a backward-compatibility requirement. |
| Changing restore-to-rerender order | The current restore path depends on local mirror first, canonical search second, rerender last. |

### Must remain as bridge state for compatibility

| State | Why it must remain |
|---|---|
| `cachedSearchResults` | Pack compatibility, select-all denominator, nil-snapshot fallback, and selected-hit bridge. |
| `cachedSampleNumericDisplay` | Title/context rebuilds and analysis-time display projection still read it. |
| `selectedRTHit`, `rtQuery`, `rtSearchResults`, `rtSearchMessage`, `isRTSearching`, `showRTPopover`, `pendingRTSidecarPath`, `cachedRTFilePath` | 3ω auxiliary-input search state. It is not Main Search and must stay out of Gate 7.1. |

### Not part of Main Search extraction

- 3ω auxiliary-slot RT search state
- `cachedInputFiles`
- `cachedSampleKeys`
- `cachedConditionsBySampleKey`
- `_titleTokens`

Those are analysis / pack / display caches. They are related to restore, but they are not the Main Search ownership boundary.

## 6. Merge-Blocker Test Coverage

### Selected-hit bridge

- `Tests/SpinLabAppTests/V537WorkbenchSelectedHitsSnapshotTests.swift`
- `Tests/SpinLabAppTests/V538WorkbenchReadinessConsumptionTests.swift`
- `Tests/SpinLabAppTests/V537AnalysisLifecycleBoundaryTests.swift`

### Pack restore

- `Tests/SpinLabAppTests/V537PackRestoreModuleBoundaryTests.swift`
- `Tests/SpinLabAppTests/V4117AnalysisPackVaultTests.swift`
- `Tests/SpinLabAppTests/V5114RestoreUseCaseStatelessTests.swift`
- `Tests/SpinLabAppTests/V5114PackRestoreNoTraceCommitTests.swift`
- `Tests/SpinLabAppTests/V535TabRenderStatePackTests.swift`

### Analysis lifecycle

- `Tests/SpinLabAppTests/V537AHESearchSnapshotConsumptionTests.swift`
- `Tests/SpinLabAppTests/V537XYSearchSnapshotConsumptionTests.swift`
- `Tests/SpinLabAppTests/V537ThreeOmegaSearchSnapshotConsumptionTests.swift`
- `Tests/SpinLabAppTests/V537AnalysisLifecycleBoundaryTests.swift`

### Workflow state boundary

- `Tests/SpinLabAppTests/V537WorkbenchSearchMirrorTests.swift`
- `Tests/SpinLabAppTests/V537WorkbenchSelectionShellTests.swift`
- `Tests/SpinLabAppTests/V563WorkflowStateBoundaryTests.swift`
- `Tests/SpinLabAppTests/V332WorkflowWorkspaceDispatchTests.swift`

### Readiness consumption

- `Tests/SpinLabAppTests/V538WorkbenchReadinessConsumptionTests.swift`

### Shell contract

- `Tests/SpinLabAppTests/V332WorkflowWorkspaceDispatchTests.swift`
- `Tests/SpinLabAppTests/V538WorkbenchReadinessConsumptionTests.swift`
- `Tests/SpinLabAppTests/V330WorkbenchShellContractTests.swift`

### Search-specific tests

- `Tests/SpinLabAppTests/V320WorkflowSearchAcrossDrawersTests.swift`
- `Tests/SpinLabAppTests/V537WorkbenchSearchMirrorTests.swift`
- `Tests/SpinLabAppTests/V537WorkbenchSelectedHitsSnapshotTests.swift`

## 7. Recommended Gate 7.1A Implementation Plan

1. Keep `WorkbenchFeatureStore` as the canonical search owner for query text, results, running state, and status message.
2. Treat `cachedSearchResults` as a compatibility bridge, not as a deletion target, until selection and pack/restore extraction finish.
3. If any runtime refactor is attempted in 7.1A, constrain it to read-only search-surface consolidation and preserve every current search API, restore ordering, and UserDefaults side effect.
4. Keep `selectedHitsSnapshot(...)`, `restoreSearchState(...)`, and `loadPack(...)` behavior unchanged in 7.1A.
5. Add or keep regression coverage for the mirror bridge, restore ordering, and selected-hit fallback before any runtime ownership transfer.

## 8. Hard No's for Gate 7.1

- Do not delete `cachedSearchResults`.
- Do not change selected-hit snapshot construction.
- Do not change selection ownership.
- Do not change pack restore behavior.
- Do not change `restoreSearchState(...)` behavior.
- Do not change analysis input construction.
- Do not start Gate 7.1 runtime extraction until the Selection and Pack / Restore dependencies above stay green under the current test suite.

## 9. Evidence Pointers

- `Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift`
- `Sources/SpinLabApp/App/State/WorkbenchSearchSnapshot.swift`
- `Sources/SpinLabApp/App/State/WorkbenchSelectedHitsSnapshot.swift`
- `Sources/SpinLabApp/Workbench/V3/AnalysisPackProviding.swift`
- `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift`
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift`
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift`
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift`
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Analysis.swift`
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+ManifestCache.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceActionBar.swift`
- `Sources/SpinLabApp/Features/Workbench/WorkbenchLoadPackPopover.swift`
- `docs/architecture/workbench/MODULE_BOUNDARIES.md`
- `docs/architecture/workbench/WORKBENCH_ROADMAP.md`
