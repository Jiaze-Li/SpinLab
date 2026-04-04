# SpinLab V3.2 Acceptance Checklist

Status: draft (gate not yet executed)  
Owner: implementation + QA shared gate

This checklist is the acceptance gate for V3.2 only.

## Scope Boundary (must pass)

- [ ] V3.2 includes `V3.2.0` through `V3.2.8` from `V3_2_ITERATION_ADDENDUM_2026-04-03.md`.
- [ ] V3.2 does not include V3.4 (Library writeback/read models) scope items.
- [ ] V3.2 does not include V3.5 reliability hardening scope items.

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

- [ ] Chart identity is semantic-based and deterministic (`V3.2.4`).
- [ ] Style-only changes overwrite; semantic changes produce new artifacts.
- [ ] Run manifest provenance is emitted and visible (`V3.2.6`).
- [ ] V3.2 writes use `AtomicFileWriter` + `LibraryPathResolver` (`V3.2.7`).
- [ ] App restart can rediscover/open persisted V3.2 artifacts.

## Plot UX Freeze (must pass)

- [ ] Plot UX freeze is completed after persistence closure (`V3.2.8`).
- [ ] Legend drag/reposition works.
- [ ] In-plot title editing works.
- [ ] Plot interaction model is workflow-agnostic and reusable.

## Early Integration Risk Control (must pass)

- [x] Atomic write-path smoke test passes immediately after default render (`V3.2.2`).
- [ ] No late-discovered write-path incompatibility blocks V3.2 final gate.

## Build and Runtime Gate (must pass)

- [ ] `swift test` passes.
- [ ] Desktop app build/overwrite completes for QA target.
- [ ] App version is bumped to the accepted V3.2 iteration.

## MR/RT Onboarding Readiness Check (must pass before starting MR/RT)

- [ ] Unified plot API has been used by at least one real AHE batch end-to-end.
- [ ] Atomic write-path works on real library paths (not test-only temp paths).
- [ ] V3.2 architecture boundaries remain intact (workflow compute vs unified plot).
- [ ] Decision recorded: MR/RT can onboard without changing unified plot main flow.
