# Workbench Workflow State Boundaries

This document makes the current workflow state boundaries explicit so they can be enforced by tests and assertions.

## Search Boundary

- Canonical owner: `WorkbenchFeatureStore`
- Canonical state:
  - `searchQueryTexts`
  - `searchResults`
  - `searchMessages`
  - `searchRunning`
- Workflow-local projections/caches:
  - `cachedSearchResults`
  - `cachedSampleNumericDisplay`
  - workflow-specific query defaults such as `rtQuery`
- Read path:
  - Shell search UI reads `WorkbenchFeatureStore` for query text, result lists, status messages, and running state.
  - Workflow rows read workflow-local cached results and numeric display projections.
- Forbidden reverse dependencies:
  - Workflow stores must not become the source of truth for top-level search status.
  - Search UI must not infer canonical search results from render output or canvas state.

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

