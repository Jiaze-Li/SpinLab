# Workbench Readiness Consumption Audit

Status: Gate 6 readiness audit
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

There is one projection builder today, and it is not yet consumed by runtime UI code:

| Producer | Location | Notes |
|---|---|---|
| `WorkbenchReadinessProjection.init(workbench:workflowID:store:)` | `Sources/SpinLabApp/Features/Workbench/WorkbenchReadAdapter.swift` | Builds the projection from canonical search state, workflow-local selection, analysis state, render output, and persistence outcome. |
| `WorkbenchFeatureStore.readinessProjection(for:store:)` | `Sources/SpinLabApp/Features/Workbench/WorkbenchReadAdapter.swift` | Convenience wrapper around the projection builder. |

## Current Runtime Consumption

No runtime view or action currently calls `readinessProjection(for:store:)` or constructs `WorkbenchReadinessProjection` for UI gating.

The live shell still consumes raw state directly in these places:

| File | Current read surface | What it is doing today |
|---|---|---|
| `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceActionBar.swift` | `isSearchRunning`, `searchResultsList`, `selectedSearchResultIDs`, `isAnalyzing`, `library.librarySettings.rootPath` | Gates Search, Select All, Analyze, and progress display with direct checks. |
| `Sources/SpinLabApp/Features/Workbench/WorkbenchResultHeaderShell.swift` | `hasActiveImageData`, `hasAnalysisResult`, `isAnalyzing`, `matchingVaultPack`, `analysisMessage`, `warningCount` | Gates Clear Plot, Save Analysis / Update Analysis, and Save to Library with direct checks. |
| `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceSearchSection.swift` | `library.librarySettings.rootPath` | Shows the library-root line and submits search from the search bar. |
| `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceResultsList.swift` | `searchResultsList`, `searchMessage`, `selectedSearchResultIDs`, `cachedSampleNumericDisplay` | Renders hit-list empty states and row selection directly from search state. |
| `Sources/SpinLabApp/Features/Workbench/WorkbenchLoadPackPopover.swift` | vault pack list, `hasUnsavedAnalysis` | Gates Load Pack availability and unsaved-analysis confirmation directly from vault / workflow state. |
| `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceStatusBlock.swift` and `Sources/SpinLabApp/Features/Workbench/WorkbenchStatusArea.swift` | trace / warning / status messages | Renders status content directly from workflow-local message and warning state. |
| `Sources/SpinLabApp/Features/Workbench/WorkbenchView.swift` and `Sources/SpinLabApp/Features/Workbench/WorkflowRegistryView.swift` | route / registry selection | Handles registry routing and workflow selection; this is not readiness gating. |

## Missing Or Partial Consumers

The following runtime surfaces still rely on scattered direct checks instead of a shared readiness projection:

| Surface | Current direct check | Classification |
|---|---|---|
| Search button | `isSearchRunning` and `library.librarySettings.rootPath == nil` | Partial. Running is readiness-related; missing library root is not currently modeled by readiness. |
| Select All button | `searchResultsList(for:).isEmpty` | Safe candidate for Gate 6.2. |
| Analyze button | `selectedSearchResultIDs.isEmpty || isAnalyzing` | Safe candidate for Gate 6.2. |
| Progress indicator | `isSearchRunning || isAnalyzing` | Safe candidate for Gate 6.2. |
| Clear Plot button | `!hasActiveImageData && !isAnalyzing` | Safe candidate for Gate 6.2, but it currently keys off render output directly rather than readiness. |
| Save Analysis / Update Analysis / Save to Library buttons | `!hasAnalysisResult` | Safe candidate for Gate 6.2. |
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
| Analysis running | `WorkflowWorkspaceActionBar.swift`, `WorkbenchResultHeaderShell.swift` | Maps to `running`. |
| No analysis result | `WorkbenchResultHeaderShell.swift` | Maps to `resultReady` / `saved` availability. |
| No active image data | `WorkbenchResultHeaderShell.swift` | Can be expressed by the result-ready side of the projection for button gating. |
| Save / update availability | `WorkbenchResultHeaderShell.swift` | Projection already carries the active-result and saved-state inputs needed for this gate. |

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

The current tests cover the projection and the state signals feeding it, but not live UI consumption.

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

### Coverage gaps for Gate 6.2 / 6.3

| Gap | Why it matters |
|---|---|
| No UI integration test asserts that the action bar and result header consume `WorkbenchReadinessProjection` | Gate 6.2 needs proof that the new consumer path exists, not just a unit-tested projection type. |
| No test covers a live `WorkbenchFeatureStore.readinessProjection(for:store:)` read path in the shell | The helper exists, but nothing exercises it at render time. |
| No test covers the retained direct preflight checks that are intentionally outside readiness | Library-root, vault availability, and load-pack policy should stay explicit. |
| No test covers the final mixed case where readiness gates button state but direct preflight still blocks Search | The search button still needs the library-root guard even after readiness consumption. |

## Recommended Gate 6.2 Implementation Plan

1. Wire the existing readiness projection into the workbench shell surfaces that already make readiness decisions: action bar and result header.
2. Replace the directly duplicated `foundData` / `selectedData` / `running` / `resultReady` checks with a single projected value per render.
3. Keep non-readiness preflight checks explicit: library-root availability, vault pack availability, and route selection.
4. Add integration coverage that proves the shell reads the projection for button gating while preserving the direct preflight checks that are not part of readiness.
5. Leave search mirroring, selection ownership, warning/trace ownership, save metadata semantics, and pack/restore orchestration for Gate 7.

## Gate 6.2 Forbidden Changes

Do not:

- add a new readiness store, coordinator, service, registry, or protocol
- expand readiness into library-root, vault, or registry-selection state
- change search, selection, analysis, save, load, or restore behavior
- move warning or trace ownership into the readiness projection
- remove the current direct preflight checks that are not readiness signals
- treat `WorkbenchReadinessProjection` as canonical lifecycle state

## Related Docs

- `docs/architecture/workbench/MAIN_BOARD_READINESS.md`
- `docs/architecture/workbench/WORKBENCH_ROADMAP.md`
- `docs/architecture/workbench/SHELL_BLOCKS.md`
- `docs/architecture/workbench/MAIN_BOARD_LAYOUT.md`
- `docs/architecture/workbench/MODULE_BOUNDARIES.md`
- `docs/architecture/workbench/workflows/ahe/ASSEMBLY.md`
- `docs/architecture/workbench/workflows/xy-rotation/ASSEMBLY.md`
- `docs/architecture/workbench/workflows/three-omega/ASSEMBLY.md`
