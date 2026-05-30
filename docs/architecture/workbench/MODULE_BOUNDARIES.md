# Workbench Module Boundaries

This document makes the current module ownership boundaries explicit so they can be enforced by tests and assertions. Each section names one module's canonical state, what it does not own, and the forbidden mutations other modules must not perform against it.

Architecture routing and compliance rules (when to consult this doc, how to report compliance, what to do on a boundary conflict): [`EXTENSION_BOUNDARIES.md` § Architecture Usage Rules](EXTENSION_BOUNDARIES.md#architecture-usage-rules).

## Search Boundary

- Canonical owner: `WorkbenchFeatureStore`
- Canonical state:
  - `searchQueryTexts`
  - `searchResults`
  - `searchMessages`
  - `searchRunning`
- Scope model:
  - all canonical search state is workflow-keyed
  - route switch preserves per-workflow search state by default
- Workflow-local projections/caches:
  - `cachedSearchResults`
  - `cachedSampleNumericDisplay`
  - workflow-specific query defaults such as `rtQuery`
- Canonical read surface for shell-triggered analysis:
  - `WorkbenchSearchSnapshot` (`queryText`, `results`, `isRunning`, `message`)
- Read path:
  - Shell search UI reads `WorkbenchFeatureStore` for query text, result lists, status messages, and running state.
  - Workflow rows read workflow-local cached results and numeric display projections.
- Forbidden reverse dependencies:
  - Workflow stores must not become the source of truth for top-level search status.
  - Search UI must not infer canonical search results from render output or canvas state.
  - New analysis paths must not use `cachedSearchResults` as primary analysis input.
  - New shell UI paths must not treat `cachedSearchResults` as canonical search state.
  - Plot controls/title/legend/rerender paths must not read/write search query/results/running/message.
  - Plot controls/title/legend/rerender/preservation paths must not mutate `cachedSearchResults`.
  - Search state must not depend on `TabRenderState`, `TabRenderOutput`, manifest payload, or image/layout output.

### Search Module does not own

- selection IDs (`selectedSearchResultIDs`)
- workflow scientific ingestion/analysis state
- plot payload/layout/image output
- title/legend/axis override state
- rerender preservation state

### Search Module reset rules

- canonical reset: `clearSearch` resets query/results/message/running for one workflow key
- workflow-local `clearResults` is not canonical Search Module clear
- analysis/rerender must not implicitly clear search state

### Search Module and Selection Module relationship

- Search Module owns hit-list and query lifecycle state
- Selection Module owns selected IDs
- Selection Module consumes hit identities from `WorkbenchSearchSnapshot`
- Selection Module must not mutate query/results/running/message except through explicit Search Module API
- Select All denominator must be explicit; current transition denominator is workflow-local `cachedSearchResults`

## Selection Boundary (Phase 5C-1A)

- Canonical owner (target contract): Selection Module (formerly SelectionShell)
- Current owner (transition): workflow stores (`AHEWorkspaceStore`, `XYRotationWorkspaceStore`, `ThreeOmegaWorkspaceStore`)
- Canonical state (contract):
  - `selectedSearchResultIDs`
  - selection mutations (`toggle`, `selectAll`, `deselectAll`, `clearSelection`)
  - `selectedCount` / `isAllSelected`
  - run-scoped `selectedHitsSnapshot`
- Current transition state (Phase 5C-3 checkpoint):
  - `selectedSearchResultIDs` remains workflow-local
  - `WorkbenchSelectedHitsSnapshot` is now the run-scoped selected-hit read surface (Phase 5C complete)
  - `cachedSearchResults` remains local mirror / selection denominator / pack compatibility
  - `legacyHits` parameter in `WorkbenchSelectedHitsSnapshot` factory is the explicit bridge from mirror to ephemeral snapshot
  - duplicate-state bridge is intentional and deferred — rename/removal awaits Save / Pack Module work

### Selection Module does not own

- search query text
- search result generation
- search running/message state
- plot output/layout/image state
- rerender/preservation state
- workflow scientific ingestion/calculation

### Selection Module and Workflow Function relationship

- Workflow Function should consume a run-scoped `selectedHitsSnapshot`
- Workflow Function should not read workflow-local `cachedSearchResults` as primary analysis input
- nil-snapshot analysis entry remains legacy/restore compatibility only

### Clear semantics

- `clearSelection`: clears selected IDs only
- `clearSearch`: belongs to SearchShell (`query/results/message/running`)
- current `clearResults` in workflow stores is legacy mixed behavior and must not be treated as Selection Module canonical clear
- 3ω `clearResults` also resets RT-side state; this is workflow-specific cleanup, not generic Selection Module behavior

### Migration direction

- `WorkbenchSelectedHitsSnapshot` is complete (Phase 5C); run-scoped selected-hit read surface is established.
- `selectAll` / `isAllSelected` denominator remains `cachedSearchResults` — correct by definition; denominator is intrinsically the search result set.
- `cachedSearchResults` will not be renamed now; deferred to Save / Pack Module (rename requires pack `CodingKey` backward compatibility handling).
- Possible future name: `searchResultMirror`.

### Phase 5C selection regression plan

- selection toggle does not mutate search query/results/running/message
- selectAll uses declared denominator source-of-truth
- deselectAll clears selected IDs only
- clearResults behavior remains explicit and workflow-scoped
- analysis consumes selected-hit snapshot
- pack restore restores selected IDs without corrupting canonical search state

### Search Module and Workflow Function relationship

- workflow functions consume a selected-hit snapshot
- workflow functions must not own top-level search query/results/running/message
- analysis and rerender paths must not mutate Search Module lifecycle state

### Current state and migration direction (Phase 5C-3)

- `WorkbenchSearchSnapshot` is the canonical run-scoped search read surface (Phase 5A complete).
- `WorkbenchSelectedHitsSnapshot` is the run-scoped selected-hit read surface (Phase 5C complete).
- `cachedSearchResults` mirrors canonical search results into workflow-local store; also serves as pack-compat field, selection denominator, and nil-snapshot fallback.
- No current path incorrectly reads `cachedSearchResults` when a snapshot is available (verified Phase 5C-3 audit).
- `cachedSearchResults` will not be renamed until Save / Pack Module work; rename requires pack `CodingKey` backward compatibility handling.
- Search Module remains canonical query/results/running/message owner.

### Current shell invocation note

- AHE / XY / 3ω analysis consumes `WorkbenchSelectedHitsSnapshot` when called from `WorkflowWorkspaceShell` (Phase 5C complete).
- `WorkbenchSelectedHitsSnapshot` is built from `WorkbenchSearchSnapshot` (canonical) with `cachedSearchResults` as `legacyHits` fallback.
- Nil-snapshot `runAnalysis()` is legacy/restore compatibility only.

### Phase 5A test plan

- title edit does not mutate search query/results/running/message
- legend edit does not mutate search query/results/running/message
- rerender path does not mutate search query/results/running/message
- selection toggle does not mutate query text
- workflow route switch preserves per-workflow search state by default
- mirror consistency after run/restore/clear while bridge still exists

## Analysis / Ingestion Boundary

- Canonical owner: each workflow store
  - `AHEWorkspaceStore`
  - `ThreeOmegaWorkspaceStore`
  - `XYRotationWorkspaceStore`
- Canonical state:
  - `ingestionResult`
  - `analysisTask` / `plotTask`
  - `isAnalyzing` / `isPlotRendering`
  - workflow-specific analysis parameters
- Workflow-local projections/caches:
  - `cachedInputFiles`
  - `cachedSampleKeys`
  - `cachedConditionsBySampleKey`
  - `_titleTokens`
  - `currentRunTrace`
  - `analysisMessage` / `plotMessage`
  - `persistenceOutcome`
- Forbidden reverse dependencies:
  - Render output must not replace ingestion state.
  - Canvas interaction must not mutate ingestion contracts.
  - Save-to-Library must not re-run analysis.

## Analysis Lifecycle Module Boundary (Phase 5D)

- Target contract owner: Analysis Lifecycle Module (default Main Board module)
- Current owner (transition): workflow stores (`AHEWorkspaceStore`, `XYRotationWorkspaceStore`, `ThreeOmegaWorkspaceStore`)
- Canonical state (contract):
  - analysis running / loading state (`isAnalyzing`, `isPlotRendering`, task handles)
  - user-facing message / error state (`analysisMessage`, `plotMessage`)
  - warning log (via `WorkbenchWarningLog`)
  - run trace (`currentRunTrace`)
  - workflow result / output state (`ingestionResult` and workflow-specific caches)
  - plot-ready output projection
  - save/pack-ready handoff data (stable post-analysis state)

### Analysis Lifecycle Module does not own

- canonical Search Module state (query, results, running, message)
- selected IDs except through explicit selection actions
- tab override state (owned by Preservation Module via `TabRenderState`)
- save-to-library write paths
- pack vault write paths
- physics logic (owned by Physics Function inside Workflow Assembly)

### Clear semantics

- `clearAnalysis` / `clearPlot`: belongs to Analysis Lifecycle Module
- `clearSearch`: belongs to Search Module
- `clearSelection`: belongs to Selection Module
- workflow-specific extras (e.g., 3ω `clearResults` RT-side cleanup): workflow-owned behavior inside Physics Function, not generic Analysis Lifecycle Module behavior

### Forbidden mutations

- analysis lifecycle state changes must not mutate canonical Search Module state
- rerender and restore paths must not commit trace
- analysis trigger must not write to save-to-library or pack vault
- Analysis Lifecycle Module must not read `TabRenderState` to decide ingestion inputs

### Handoff rules

- Analysis Lifecycle outputs plot-ready state to Plot Display / Preservation modules
- Save Module reads stable post-analysis output only
- Pack/Restore Module target: consume a stable `AnalysisResultSnapshot` envelope (deferred; current implementation reads ad hoc workflow store internals)

### Current transition state (Phase 5D-1 checkpoint)

- Analysis lifecycle state remains workflow-local in all three workflow stores
- `WorkbenchSelectedHitsSnapshot` is the run-scoped analysis input (Phase 5C complete)
- Phase 5D-1 tests lock current cross-module boundaries: no mutation of Search / Selection / Preservation state during analysis
- `AnalysisRunContext` / `AnalysisResultSnapshot` extraction deferred until contract and tests are stable

## Save Module Boundary (Phase 5E)

- Target contract owner: Save Module (default Main Board module)
- Current owner (transition): workflow stores (`AHEWorkspaceStore`, `XYRotationWorkspaceStore`, `ThreeOmegaWorkspaceStore+Persistence`)
- Canonical state (contract):
  - `persistenceOutcome` — set after each `persistToLibrary()` call; nil on `clearPlot()`
  - save status / message — current: `plotMessage` (AHE) or `analysisMessage` (XY / 3ω); target: dedicated `saveMessage` field (Phase 5E-3)
  - `currentRunTrace` — updated from `outcome.trace` after save

### Save Module does not own

- canonical Search Module state (`queryText`, `searchResults`, `isRunning`, `statusMessage`)
- `selectedSearchResultIDs` or `cachedSearchResults`
- tab override state (`TabRenderState` / `tabStates`) — owned by Preservation Module
- `ingestionResult` or any workflow output cache — owned by Analysis Lifecycle Module
- pack vault state (`activePackID`, vault contents) — owned by Pack / Restore Module
- analysis trigger or plot re-render

### Save Module read contract

- PNG: `TabRenderManager.activeImageData` (Preservation Module projection)
- Manifest payload: `TabRenderManager.activeManifestPayload` (Preservation Module projection)
- Sample keys and metrics: Workflow Assembly Save Metadata Provider (`ActiveChartProviding` protocol)
- Library root path: set by search flow; consumed as write target

### Save-side trace update rule

`currentRunTrace` is written from `outcome.trace` inside `persistToLibrary()` after a successful or partial save. This is the save-side trace update and is distinct from the analysis-side `commitRunTrace()` call. `persistToLibrary()` must never call `commitRunTrace()`.

### Forbidden mutations

- Save must not mutate canonical Search Module state
- Save must not mutate `selectedSearchResultIDs` or `cachedSearchResults`
- Save must not mutate tab override state (`TabRenderState`)
- Save must not mutate `ingestionResult` or workflow output caches
- Save must not call `commitRunTrace()` (analysis-side only)
- Save must not re-trigger analysis or plot re-render

### Known current gaps (tracked for Phase 5E-3)

- **Message field inconsistency**: AHE save guard and save result messages write to `plotMessage`; XY and 3ω write to `analysisMessage`. Target: dedicated `saveMessage` field decoupled from analysis message.
- **Missing `refreshRelatedCharts()` in AHE**: XY and 3ω call `refreshRelatedCharts()` after save success/partial; AHE does not. This causes the related charts sidebar to not update after saving in AHE.

### Current transition state (Phase 5E-1 checkpoint)

- `persistToLibrary()` remains workflow-local in all three workflow stores
- `SaveActiveChartToLibraryUseCase` is already a generic, workflow-agnostic write path
- Phase 5E-2 boundary tests will lock current save-boundary behavior before extraction
- `saveMessage` field extraction and `refreshRelatedCharts()` gap fix deferred to Phase 5E-3

Full module contract: [`SHELL_BLOCKS.md` § Save Module](SHELL_BLOCKS.md).

## Pack / Restore Module Boundary (Phase 5F)

- Target contract owner: Pack/Restore Module
- Current owner (transition): workflow stores (`AHEWorkspaceStore`, `XYRotationWorkspaceStore`, `ThreeOmegaWorkspaceStore+Pack.swift`)

Pack/Restore is the **only module** allowed to write multiple module states simultaneously, and only through the explicit restore contract documented in [`modules/PACK_RESTORE.md`](modules/PACK_RESTORE.md). This is not a general permission for cross-module mutation — it is a bounded exception for workspace restoration.

### Forbidden mutations

- Restore must not write `persistenceOutcome`, `saveMessage`, `analysisMessage`, `currentRunTrace`, or `warningLog` — these are session-only and excluded from all pack formats
- Restore must not write `activePackID` inside `restoreFromPack()` — `activePackID` is set by the `loadPack()` caller after restore returns
- Restore must not call `runAnalysis()` or `commitRunTrace()` — except the documented AHE legacy exception for packs with nil `ingestionResult`
- Restore must not treat `cachedSearchResults` as canonical search state — canonical state is written only through the explicit `restoreSearchState` callback to `WorkbenchFeatureStore`
- Restore must not serialize or restore active PNG / manifest / layout output — these are re-derived by the re-render call at the end of restore
- Save must not be triggered by restore — no pack format may encode `persistenceOutcome` or save-side state

### What restore is allowed to write (summary)

Full write map: [`modules/PACK_RESTORE.md` § Restore Write Map](modules/PACK_RESTORE.md#restore-write-map). Key categories:

- search mirror (`cachedSearchResults`) and canonical search state (via `restoreSearchState` callback)
- selection IDs (`selectedSearchResultIDs`)
- analysis result (`ingestionResult`, `scalingResult`)
- plot preservation state (`tabStates`, `chartStyleOverrides`, `activeTab`, `showPlotGrid`, `legendAnchor`) through `TabRenderManager.restoreStates()`
- workflow-specific physics parameters (geometry, fit ranges, phi offsets, etc.)
- local pack inputs (`cachedInputFiles`, `cachedSampleKeys`)
- library root dependency (`lastLibraryRootPath` from vault)

### Tests

Phase 5F-3 boundary tests: see [`modules/PACK_RESTORE.md` § Boundary Test Plan](modules/PACK_RESTORE.md#boundary-test-plan-phase-5f-3).

## Render / Output Boundary

- Canonical owner: `TabRenderManager`
- Canonical state:
  - `activeTab`
  - `tabStates`
  - `tabOutputs`
  - shared render settings (`showPlotGrid`, `seriesRenderMode`, `chartStyleOverrides`)
- Projections:
  - `activeImageData`
  - `activeLayout`
  - `activeManifestPayload`
  - `activeSeriesLabelOverrides`
- Forbidden reverse dependencies:
  - Workflow stores must not keep a second canonical copy of rendered image/layout/manifest output.
  - Plot rendering code must not write directly into canvas UI state.
  - `activeImageData` must remain a projection over `tabOutputs`.

## Canvas Interaction Boundary

- Canonical owner: `TabRenderManager` for canvas-owned plot state; workflow store for workflow data.
- Canonical state:
  - legend position
  - title / axis / label overrides
  - per-series ordering
  - point-label visibility
- Projections:
  - `WorkbenchPlotCanvas` receives `imageData`, `layout`, `seriesLabelOverrides`, `seriesPayload`, and related chart data as read-only inputs.
- Forbidden reverse dependencies:
  - Canvas must not own canonical plot output or ingestion state.
  - Canvas must not mutate search results or library storage state.

### Series Reorder Boundary

Series reorder is a Plot Controls Module concern, not a canvas concern.

- Canvas must not own or trigger series reorder. Direct curve hit-test reorder is forbidden.
- Reorder intent (`updateSeriesOrder([seriesKey])`) must flow from Plot Controls Module → workflow store → render pipeline.
- The render pipeline applies order; canvas code must not mutate render geometry to achieve reorder.
- Reorder identity is the per-series `sourceRef` key, not `sampleID`.

Full series reorder contract and review checklist: [`modules/PLOT_SYSTEM.md` § Series Reorder Contract](modules/PLOT_SYSTEM.md).

## Phase 4: Plot Preservation Module (Plot System Module Group)

The Plot Preservation Module is part of the Plot System Module Group. Full contract: [`SHELL_BLOCKS.md` § Plot Preservation Module](SHELL_BLOCKS.md#plot-preservation-module-phase-4).

Boundary: no module other than Plot Preservation may write `TabRenderState` override fields or call `clearStates()`. `TabRenderManager` is the single owner of override state and render output.

**Enforcement**: `XYRotationWorkspaceStore.runAnalysis()` previously called `tabs.clearStates()` (Phase 4 regression); removed in 5.3.7.

Tests: `V537WorkflowShellPhase4Tests` (AHE + XY), `V563WorkflowStateBoundaryTests` (TabRenderManager + 3ω).

## Module Override Boundary (Phase 3)

- Canonical owners: each override is owned by its respective module; workflow function output is separate.
- Canonical state:
  - `defaultPlotPayload` — produced by Workflow Function; read-only input to the composer.
  - `titleOverride` — owned by the title module.
  - `legendOverride` — owned by the legend module.
  - `axisLabelOverride` — owned by the axis-label module.
  - `seriesOrder` — owned by the series-order module.
- Composition:
  - `WorkflowWorkspaceShell` (parent composer) merges `defaultPlotPayload` with the four override layers to produce the final display payload.
  - No sibling module may perform this merge.
- Forbidden reverse dependencies:
  - Plot-control changes must not reset search or selection state.
  - Title, legend, or axis-label overrides must not depend on each other's state.
  - Override modules must not read from `tabOutputs` or `activeImageData`.
  - Workflow Function output (`defaultPlotPayload`) must not be mutated by any module.

## Persistence Boundary

- Canonical owner: `SaveActiveChartToLibraryUseCase`
- Canonical state:
  - `SaveActiveChartInput`
  - persistence validation
  - chart/metric write orchestration
- Lower-level path ownership:
  - `LibraryPathResolver` owns canonical root-relative path construction.
  - `LibraryRootAccess` owns library-root discovery and security-scoped traversal.
- Projections:
  - `PersistenceOutcome`
  - `WorkbenchRunTraceProjection`
- Forbidden reverse dependencies:
  - Persistence must not depend on canvas internals.
  - Save logic must not bypass `LibraryPathResolver`.
  - Search must not become the path-resolution authority for writes.

## Canonical Identity and Duplicate Identity

- Stable sample identity:
  - `sampleID` is the preferred stable series identity for reorderable payloads.
- Search identity:
  - `WorkflowMeasurementSearchHit.id` is a selection/UI identity, not the same thing as sample identity.
- Chart identity:
  - `WorkbenchChartIdentity.makeIdentityKey(from:)` identifies persisted chart artifacts.
- Remaining duplicate identity surfaces:
  - `selectedSearchResultIDs` duplicates information already present in `cachedSearchResults`.
  - legacy Int-string series keys still exist in `TabRenderState` migration paths.

### Workflow ID Mapping

| Old ID | New ID | Workflow |
|--------|--------|----------|
| `A` | `ahe` | AMR/PHE (Anomalous Hall Effect) |
| `B` | `3w` | 3 Omega |

Pre-v4.1.3 `"A"` / `"B"` IDs in sidecar files or persisted JSON are legacy artifacts. No backward-compatibility code exists — replace with new IDs. Search accepts both old and new IDs as query aliases; all persisted data uses new IDs only.
