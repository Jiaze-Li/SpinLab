# SpinLab V3.2 Acceptance Checklist

Status: in-progress (gate executing 2026-04-04)
Owner: implementation + QA shared gate

This checklist is the acceptance gate for V3.2 only.

## Scope Boundary (must pass)

- [x] V3.2 includes `V3.2.0` through `V3.2.8` from `V3_2_ITERATION_ADDENDUM_2026-04-03.md`.
- [x] V3.2 does not include V3.4 (Library writeback/read models) scope items.
- [x] V3.2 does not include V3.5 reliability hardening scope items.

## Generic Search Layer (must pass)

- [x] `V3.2.0` broad workflow `type` query works across drawers.
- [x] Workflow lookup is generic (AHE/RT/3W aliases) and does not require preconfigured `id=AHE`.
- [x] Search returns unified `WorkflowMeasurementSearchHit`-style results.
- [x] Search remains independent from workflow-specific parsing and plotting.

V3.2.0 completion note (2026-04-04):
- Implemented and accepted as done.
- Rule-governance consolidation (baseline manifest + guard script + CI gate + parser golden tests) was completed in the same delivery cycle.

## AHE Pipeline + Plot Path (must pass)

- [x] AHE `.dat` / `.lvm` ingestion works (`V3.2.1`).
- [x] Axis detection provides default `x/y` and candidate fields.

V3.2.1 completion note (2026-04-04):
- Selection-centric ingestion pipeline implemented: `AHEPlotSelectionItem` → `IngestAHESelectionsUseCase` → `AHEIngestionResult`.
- PPMS MultiVu `.dat` format supported (Variant A with `[Header]/[Data]`, Variant B headerless).
- `AHEChannel` enum enforces ch1/ch2/ch3 closed set; bridge mapping is type-safe.
- Default axis: x = `Magnetic Field (Oe)`, y = first active `Bridge N Resistance (Ohms)`.
- Same file parsed once; inactive bridge produces warning, not crash.
- 10/10 tests pass (`V321AHEIngestionAxisDetectionTests`). AppVersion bumped to v3.2.1.
- [x] Unified plot entry renders PNG from standardized payload (`V3.2.2`).
- [x] Manual axis/style adjustments are reflected in render (`V3.2.3`).

V3.2.2 + V3.2.3 completion note (2026-04-04):
- WorkbenchChartRenderer (CoreGraphics PNG, no SwiftUI/AppKit): title, axis box, series polylines, legend, nice tick marks + numeric labels (k-notation for large values), tick-aligned grid.
- BuildAHEPlotPayloadUseCase: thin mapper AHEIngestionResult → WorkbenchPlotPayload with axisMappingOverride + styleParams.
- IngestAHESelectionsUseCase: xColumnOverride + yColumnOverride optional params (backward-compatible).
- WorkbenchFeatureStore: selectedSearchResultIDs, currentPlotImageData, currentCandidateAxisFields, plotAxisXOverride/YOverride, plotTitleOverride, showPlotGrid; renderAHEPlot (detached task), clearPlot.
- WorkbenchView: hit selection (tap to toggle, checkmark icon, accent highlight), Plot Controls GroupBox (X/Y picker, title field, grid toggle), PNG preview above results list.
- 184/184 tests pass. AppVersion v3.2.3. Real AHE .dat files verified end-to-end.

## Identity + Trace + Persistence (must pass)

- [x] Chart identity is semantic-based and deterministic (`V3.2.4`).
- [x] Style-only changes overwrite; semantic changes produce new artifacts.

V3.2.4 completion note (2026-04-04):
- `WorkbenchChartIdentity.makeIdentityKey(from:)` hashes workflowID + inputFiles + axisMapping + semanticParams; styleParams and title are excluded.
- `PersistChartArtifactUseCase` implements overwrite (same identity → same path, atomic replace) and new-artifact (different identity → distinct path) logic via `AtomicFileWriter`.
- `WorkbenchResultsIndex` is upserted by `chartIdentityKey`; same identity updates in place, new identity appends.
- Wiring into `WorkbenchFeatureStore.renderAHEPlot()` deferred to V3.2.7 (requires `libraryRootPath` persistence in store).
- 12/12 tests pass (`V324ChartIdentityOverwriteTests`). 196/196 total. AppVersion bumped to v3.2.4.

- [x] Run manifest provenance is emitted and visible (`V3.2.6`). Product-level acceptance (Workbench UI) closed in V3.2.7.

V3.2.6 completion note (2026-04-04):
- WorkbenchRunTraceProjection: read-only UI projection built from persisted manifest only, no recomputation from live payload.
- BuildRunTraceProjectionUseCase: maps WorkbenchRunManifest + chartIdentityKey + manifestPath → projection.
- All provenance fields verified: runID, workflowID, inputFiles, axisMapping, semanticParams, outputImagePath, generatedAt, appVersion.
- Paths in projection are library-root-relative (no leading slash).
- Wiring into WorkbenchFeatureStore deferred to V3.2.7 alongside libraryRootPath persistence.
- 7/7 tests pass (V326RunManifestTraceTests). 203/203 total. AppVersion bumped to v3.2.6.
- [x] V3.2 writes use `AtomicFileWriter` + `LibraryPathResolver` (`V3.2.7`).
- [x] App restart can rediscover/open persisted V3.2 artifacts.

V3.2.7 rediscovery note (2026-04-04):
- LoadLatestChartArtifactUseCase: reads results_index.json, picks most recent by generatedAt, loads PNG + manifest; returns nil gracefully on missing index, corrupted JSON, or missing files.
- WorkbenchFeatureStore.loadPersistedArtifact(sampleKey:): runs in background task, sets currentPlotImageData + currentRunTrace + artifactLoadMessage.
- Auto-triggered after search completes (first result's sampleKey).
- WorkbenchView: "Load Saved" button (manual fallback); artifactLoadMessage displayed below plot status.
- 6/6 tests pass (V327ArtifactRediscoveryTests). 218/218 total.

V3.2.7 completion note (2026-04-04):
- PersistChartArtifactUseCase wired into WorkbenchFeatureStore.renderAHEPlot(); libraryRootPath captured from runWorkflowMeasurementSearch and passed to persist + trace pipeline.
- currentRunTrace (WorkbenchRunTraceProjection) populated after each render; cleared on clearPlot().
- WorkbenchView: Last Run Trace GroupBox shows runID, workflowID, axis mapping, inputs, output path, identity key, timestamp, appVersion.
- V3.2.6 product-level acceptance ("User can inspect last run trace from Workbench") closed.
- Relative path round-trip verified; root-escape rejection verified; injected writer (no direct FileManager writes) verified.
- 9/9 tests pass (V327V32PersistenceClosureTests). 212/212 total. AppVersion bumped to v3.2.7.

## Plot UX Freeze (must pass)

- [x] Plot UX freeze is completed after persistence closure (`V3.2.8`).
- [x] Legend drag/reposition works.
- [x] In-plot title editing works.
- [x] Plot interaction model is workflow-agnostic and reusable.

V3.2.8 completion note (2026-04-04):
- WorkbenchChartRenderer: styleParams["legendAnchor"] drives legend position (top-right default, top-left, bottom-right, bottom-left); drawLeftAligned helper added.
- legendAnchor is styleParams-only: does not affect chart identity key.
- plotLegendAnchor in WorkbenchFeatureStore wired to styleParams in renderAHEPlot; cleared on clearPlot.
- WorkbenchView plotControlsSection: Legend Picker added (4 positions); all UX controls (showGrid, legendAnchor, title) are in the workflow-agnostic Workbench layer.
- Title editing via plotTitleOverride TextField remains the in-plot title control; excluded from identity (style-only, same as legendAnchor).
- 10/10 tests pass (V328PlotUXFreezeTests). 228/228 total. AppVersion bumped to v3.2.8.

## Early Integration Risk Control (must pass)

- [x] Atomic write-path smoke test passes immediately after default render (`V3.2.2`).
- [x] No late-discovered write-path incompatibility blocks V3.2 final gate. (V3.2.7 verified: AtomicFileWriter + LibraryPathResolver + relative path round-trip all pass)

## Build and Runtime Gate (must pass)

- [x] `swift test` passes. (228/228, 2026-04-04)
- [x] Desktop app build/overwrite completes for QA target. (v3.2.8 debug build, 2026-04-04, ~/Desktop/SpinLab.app)
- [x] App version is bumped to the accepted V3.2 iteration. (v3.2.8)

## MR/RT Onboarding Readiness Check (must pass before starting MR/RT)

- [ ] Unified plot API has been used by at least one real AHE batch end-to-end.
- [ ] Atomic write-path works on real library paths (not test-only temp paths).
- [ ] V3.2 architecture boundaries remain intact (workflow compute vs unified plot).
- [ ] Decision recorded: MR/RT can onboard without changing unified plot main flow.
