# Workbench Readiness Consumption Audit

Status: Gate 6 complete
Scope: read-only audit of `WorkbenchReadinessProjection` generation, current runtime consumption, and direct readiness-adjacent checks in the Workbench shell.

This file documents the current state only. It does not introduce a new readiness architecture, coordinator, store, service, registry, or protocol.

## Current Readiness Model

`WorkbenchReadinessProjection` is a derived, read-only projection that summarizes board-facing workflow state.

The current ladder is:

| Ladder value | Derived meaning |
|---|---|
| `empty` | No usable workflow search result or analysis output is present. |
| `foundData` | Search has produced at least one usable hit list. |
| `selectedData` | The user has selected one or more search hits. |
| `running` | Search or analysis/render work is in flight. |
| `resultReady` | The workflow has active render output available for display or save. |
| `saved` | The current analysis has an associated save outcome or active saved pack reference. |

The projection currently records these source signals:

| Source signal | Current origin |
|---|---|
| Search result count | `WorkbenchFeatureStore.searchResultsList(for:)` |
| Selected count | `store.selectedSearchResultIDs.count` |
| Running state | `WorkbenchFeatureStore.isSearchRunning(for:)` or `store.isAnalyzing` |
| Result-ready state | `store.activeChartPNG != nil && store.activeChartManifestPayload != nil` |
| Saved state | `WorkbenchReadinessProjection.hasSavedPersistenceOutcome(_:)` over `store.persistenceOutcome` |

## Current Readiness Producers

There is one projection builder today, and it is consumed by the runtime shell:

| Producer | Location | Notes |
|---|---|---|
| `WorkbenchReadinessProjection.init(workbench:workflowID:store:)` | `Sources/SpinLabApp/Features/Workbench/WorkbenchReadAdapter.swift` | Builds the projection from canonical search state, workflow-local selection, analysis state, render output, and persistence outcome. |
| `WorkbenchFeatureStore.readinessProjection(for:store:)` | `Sources/SpinLabApp/Features/Workbench/WorkbenchReadAdapter.swift` | Convenience wrapper around the projection builder. |

## Current Runtime Consumption

The runtime shell now calls `readinessProjection(for:store:)` in the narrow gating paths that map cleanly onto the existing projection.

The live shell still consumes raw state directly in these places:

| File | Current read surface | What it is doing today |
|---|---|---|
| `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceActionBar.swift` | `isSearchRunning`, `library.librarySettings.rootPath`, `readinessProjection(for:store:)` | Gates Search with a direct library-root preflight and direct search-running check while using readiness for Select All, Analyze, and progress display. |
| `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceResultArea.swift` | `store.hasAnalysisResult`, `activeImageData`, `isAnalyzing` | Keeps pack-analysis availability explicit in the shared header shell while keeping active-image and analyzing state explicit. |
| `Sources/SpinLabApp/Features/Workbench/WorkbenchResultHeaderShell.swift` | `hasActiveImageData`, `hasAnalysisResult`, `isAnalyzing`, `matchingVaultPack`, `analysisMessage`, `warningCount` | Gates Clear Plot, Save Analysis / Update Analysis, and Save to Library with shell-local checks. Pack-state selection remains separate from readiness. |
| `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceSearchSection.swift` | `library.librarySettings.rootPath` | Shows the library-root line and submits search from the search bar. |
| `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceResultsList.swift` | `searchResultsList`, `searchMessage`, `selectedSearchResultIDs`, `cachedSampleNumericDisplay` | Renders hit-list empty states and row selection directly from search state. |
| `Sources/SpinLabApp/Features/Workbench/WorkbenchLoadPackPopover.swift` | vault pack list, `hasUnsavedAnalysis` | Gates Load Pack availability and unsaved-analysis confirmation directly from vault / workflow state. |
| `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceStatusBlock.swift` and `Sources/SpinLabApp/Features/Workbench/WorkbenchStatusArea.swift` | trace / warning / status messages | Renders status content directly from workflow-local message and warning state. |
| `Sources/SpinLabApp/Features/Workbench/WorkbenchView.swift` and `Sources/SpinLabApp/Features/Workbench/WorkflowRegistryView.swift` | route / registry selection | Handles registry routing and workflow selection; this is not readiness gating. |

## Final Consumption Boundaries

The following runtime surfaces still rely on direct checks or intentionally keep them explicit:

| Surface | Current direct check | Classification |
|---|---|---|
| Search button | `isSearchRunning` and `library.librarySettings.rootPath == nil` | Partial. Running is readiness-related; missing library root is not currently modeled by readiness. |
| Select All button | `readiness.hasFoundData` | Implemented in Gate 6.2 and kept narrow to the action bar. |
| Analyze button | `readiness.hasSelectedData || isAnalyzing` | Implemented in Gate 6.2; the direct `isAnalyzing` guard still prevents duplicate analysis starts. |
| Progress indicator | `readiness.isRunning` | Implemented in Gate 6.2. |
| Clear Plot button | `!hasActiveImageData && !isAnalyzing` | Kept explicit because it keys off render output directly rather than readiness. |
| Save to Library button | `!hasAnalysisResult` | Remains explicit in the header shell; readiness does not replace this pack-analysis availability check. |
| Load Pack button | `allPacks.isEmpty` | Direct workflow-local vault logic; not readiness. |
| Empty-results messaging | `results.isEmpty` and `searchMessage` | UI messaging, not gating. |
| Status / warning display | raw message and warning logs | Not readiness; this is a display surface. |

## Direct Checks Found In Runtime Code

### Gate 6.2 safe replacement candidates

These are the direct checks that can be replaced by the existing readiness projection without changing search, selection, analysis, save, or restore behavior:

| Candidate | Current site(s) | Why it fits Gate 6.2 |
|---|---|---|
| No search results | `WorkflowWorkspaceActionBar.swift`, `WorkflowWorkspaceResultsList.swift` | Maps to `foundData` / `empty`. |
| No selected hits | `WorkflowWorkspaceActionBar.swift` | Maps to `selectedData`. |
| Analysis running | `WorkflowWorkspaceActionBar.swift` | Maps to `running` for the action-bar progress indicator. |
| No analysis result | `WorkbenchResultHeaderShell.swift` | Remains packed-analysis specific; the header keeps this state explicit. |
| No active image data | `WorkbenchResultHeaderShell.swift` | Remains explicit for Clear Plot and save preflight logic. |

### Explicit non-readiness inputs for result-header pack state

These inputs remain outside readiness even though they are related to save/update UI:

| Input | Current site(s) | Why it stays explicit |
|---|---|---|
| `matchingVaultPack` | `WorkbenchResultHeaderShell.swift` | Decides whether the header shows Save Analysis or Update Analysis. This is pack-match state, not readiness. |
| `activePackID` | `AnalysisVault` / workflow store pack state | Tracks which pack is active after load/save. This is not a readiness signal. |
| Analysis-vault saved state | `AnalysisVault`, `matchingVaultPack`, `activePackID` | Determines pack identity and update semantics. This is related to save/update behavior but not to readiness itself. |
| Save Analysis vs Update Analysis label choice | `WorkbenchResultHeaderShell.swift` | Related to saved pack matching, not to readiness. Gate 6.2 must preserve this split. |

### Should stay as direct workflow-local logic

These checks are real, but they are not readiness signals and should remain explicit:

| Candidate | Current site(s) | Reason to keep direct |
|---|---|---|
| Missing library root | `WorkflowWorkspaceSearchSection.swift`, `WorkflowWorkspaceActionBar.swift` | This is a library-configuration preflight, not board readiness. |
| No saved packs | `WorkbenchLoadPackPopover.swift` | This is vault contents, not workflow readiness. |
| Load-pack unsaved-analysis prompt | `WorkbenchLoadPackPopover.swift` | This is pack-policy / unsaved-state behavior, not readiness. |
| No workflow selected | `WorkbenchView.swift`, `WorkflowRegistryView.swift` | This is registry routing, not workbench readiness. |
| Warning / status visibility | `WorkflowWorkspaceStatusBlock.swift`, `WorkbenchStatusArea.swift` | This is message presentation, not readiness gating. |

### Must wait for Gate 7 module extraction

These are not readiness replacements; they are boundary debts that remain part of later runtime extraction work:

| Candidate | Why it waits |
|---|---|
| Search mirror cleanup (`cachedSearchResults`) | Search remains a common module boundary debt until Gate 7.1. |
| Canonical selection ownership | Selected IDs still live in workflow stores until Gate 7.2. |
| Secondary input search / RT slot extraction | 3ω RT is the current live instance of the optional auxiliary-slot candidate and remains Gate 7.3 work. |
| Warning / trace centralization | Warning and trace projection are still split across workflow stores and shell surfaces until Gate 7.7. |
| Save metadata projection | Metric semantics still flow through raw `PendingMetricEntry[]` bridges until Gate 7.5. |
| Pack / restore orchestration | Restore is still distributed per workflow and remains Gate 7.6. |

### Not readiness-related

These signals do not belong to the readiness ladder and should not be forced into it:

| Candidate | Current site(s) | Reason |
|---|---|---|
| Route / registry selection | `WorkbenchView.swift`, `WorkflowRegistryView.swift` | It is app navigation, not board readiness. |
| Search result empty-state copy | `WorkflowWorkspaceResultsList.swift` | It is messaging, not gating. |
| Status block content | `WorkflowWorkspaceStatusBlock.swift`, `WorkbenchStatusArea.swift` | It is display of warnings/traces/messages, not readiness. |

## Test Coverage Map

The current tests cover the projection, the state signals feeding it, and source-audit coverage for the shell consumption paths.

| Test file | What it protects |
|---|---|
| `Tests/SpinLabAppTests/V538WorkbenchReadinessProjectionTests.swift` | Unit coverage for the readiness ladder, precedence order, saved-state detection, and derived-input behavior. |
| `Tests/SpinLabAppTests/V537AHESearchSnapshotConsumptionTests.swift` | AHE analysis consumes the selected-hit snapshot and falls back to cached search state only in the documented legacy path. |
| `Tests/SpinLabAppTests/V537XYSearchSnapshotConsumptionTests.swift` | XY analysis consumes the selected-hit snapshot and preserves the fallback path behavior. |
| `Tests/SpinLabAppTests/V537ThreeOmegaSearchSnapshotConsumptionTests.swift` | 3ω analysis consumes the selected-hit snapshot, preserves the RT side input, and keeps the fallback path intact. |
| `Tests/SpinLabAppTests/V537SaveModuleBoundaryTests.swift` | Save guards remain contained, and save messages stay separate from analysis messages. |
| `Tests/SpinLabAppTests/V537PackRestoreModuleBoundaryTests.swift` | Restore order, session-only fields, and no-trace-commit behavior stay bounded. |
| `Tests/SpinLabAppTests/V537AnalysisLifecycleBoundaryTests.swift` | End-to-end analysis still produces output, trace, and status without crossing boundaries. |
| `Tests/SpinLabAppTests/V537WorkflowShellPhase4Tests.swift` | Tab-state survival is preserved through rerender paths and guard exits. |
| `Tests/SpinLabAppTests/V563WorkflowStateBoundaryTests.swift` | Active-image projection, tab-output ownership, and boundary behavior around shell-facing state remain stable. |
| `Tests/SpinLabAppTests/V537WorkbenchSearchMirrorTests.swift` | The workflow-local search mirror and `isAllSelected` denominator behavior are still explicit. |
| `Tests/SpinLabAppTests/V537WorkbenchSelectionShellTests.swift` | Selection shell actions remain isolated from canonical search state. |
| `Tests/SpinLabAppTests/V538WorkbenchReadinessConsumptionTests.swift` | Source-audit coverage proves the action bar reads the readiness projection while the result header keeps pack-analysis availability explicit. |

### Closeout Notes

- No additional UI integration test was added for Gate 6.3. The source-audit test plus the existing boundary suites are sufficient for the narrow readiness closeout.
- The result header keeps `store.hasAnalysisResult`, `matchingVaultPack`, `activePackID`, and analysis-vault saved-state logic explicit by design.
- Library-root preflight, direct search-running checks, and Load Pack availability remain outside readiness by design.
- Gate 7 continues to own search-mirror cleanup, selection ownership, pack/restore orchestration, and the other boundary debts listed above.

## Related Docs

- `docs/architecture/workbench/MAIN_BOARD_READINESS.md`
- `docs/architecture/workbench/WORKBENCH_ROADMAP.md`
- `docs/architecture/workbench/SHELL_BLOCKS.md`
- `docs/architecture/workbench/MAIN_BOARD_LAYOUT.md`
- `docs/architecture/workbench/MODULE_BOUNDARIES.md`
- `docs/architecture/workbench/workflows/ahe/ASSEMBLY.md`
- `docs/architecture/workbench/workflows/xy-rotation/ASSEMBLY.md`
- `docs/architecture/workbench/workflows/three-omega/ASSEMBLY.md`
