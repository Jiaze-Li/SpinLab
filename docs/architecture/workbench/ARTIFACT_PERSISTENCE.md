# Workbench — Artifact Persistence

> Persistence layer: Pack save/load、`_spinlab/` 写入边界（Workbench owns generation；Library owns namespace 与 cleanup）、stale detection、Recompute UI 钩子。

## Workbench Write Boundary

Workbench writes analysis results into the Library measurement directory under `_spinlab/`. Workbench owns generation; Library owns the storage namespace and cleanup invariants.

**Boundary rule `SP-007`**: do not bypass `LibraryPathResolver` for root-relative path construction. All artifact path construction goes through `LibraryPathResolver` (`SP-008`).

Library-side view (preview pipeline, stale banner, path resolution ownership): `docs/architecture/library/ARTIFACTS_AND_PREVIEWS.md`.

## Save Entry Point

`SaveActiveChartToLibraryUseCase` is the sole save entry point for Workbench. It orchestrates:

1. `PersistChartArtifactUseCase` — writes chart artifact (PNG) and `_spinlab/` plot index entry
2. `PersistMeasurementDataUseCase` — writes metric data artifact alongside chart
3. `BackfillMeasurementPlotIndexUseCase` — backfills the plot index for pre-existing measurements that didn't have one

## Written Fields

| Artifact | Path | Owner |
|---|---|---|
| Chart PNG | `_spinlab/<uuid>.png` | Workbench writes |
| Plot index | `_spinlab/plot_index.json` | Workbench writes; Library reads |
| Related charts | `_spinlab/related_charts.json` | Workbench writes; Library reads |
| Measurement data | `_spinlab/<uuid>_data.json` | Workbench writes |

## Pack Envelope

`AnalysisPack` + `AnalysisVault` are the persistence envelope for a complete analysis session:

- `AnalysisPack` — domain model: workflow result + config + UI state snapshot
- `AnalysisVault` — runtime: collection of packs for a measurement, with save/load/overlay lifecycle

Pack restore path: `restoreFromPack()` → deserializes `PackResult` → calls `_rerenderActiveTab()` / `_rerenderAllTabs()`. Must not call `runAnalysis()` or `commitRunTrace()`.

## Stale Detection

A stored artifact is stale when source data changed after last analysis. Detection uses dual-layer sidecar comparison (`ruleSnapshot` vs current rules). When stale, Library displays a banner; recompute is a Workbench operation.

Stale banner and Recompute UI hook: `RecomputeStaleBannerView` / `RecomputePreviewPanel` (Library-side display only). Route user to Workbench for re-analysis.

## Invariants

- Workbench never reads Library preview artifacts directly — it reads raw measurement files and re-ingests.
- All path construction through `LibraryPathResolver`; no hand-built paths.
- Save is user-triggered only — no auto-save on analysis completion.

## Code Map

- `Sources/SpinLabApp/UseCases/SaveActiveChartToLibraryUseCase.swift`
- `Sources/SpinLabApp/UseCases/PersistChartArtifactUseCase.swift`
- `Sources/SpinLabApp/UseCases/PersistMeasurementDataUseCase.swift`
- `Sources/SpinLabApp/UseCases/BackfillMeasurementPlotIndexUseCase.swift`
- `Sources/SpinLabApp/Workbench/V3/WorkbenchResultContracts.swift`
- `Sources/SpinLabApp/App/State/AnalysisVault.swift`
- `Sources/SpinLabApp/Domain/AnalysisPack.swift`
- `Sources/SpinLabApp/Domain/RecomputePreviewItem.swift`
