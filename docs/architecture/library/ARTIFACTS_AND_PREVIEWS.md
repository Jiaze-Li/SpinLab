# Library Artifacts and Previews

## Artifact Storage Layout

Workbench writes analysis results (charts, metric data) into the Library measurement directory under a `_spinlab/` subdirectory. Library owns the storage namespace and cleanup invariants; Workbench owns generation.

Boundary rule `SP-007`: Workbench writes Library `_spinlab` artifacts/indexes; Library owns storage namespace and cleanup invariants. Do not bypass `LibraryPathResolver` for root-relative path construction.

`LibraryPathResolver` is shared across Library and Workbench (`SP-008`). Use it for root-relative paths. Avoid hand-built absolute/relative path logic.

## Plot Index and Chart Discovery

When Library loads a measurement, `LoadMeasurementPlotIndexUseCase` reads the `_spinlab/` plot index file to discover available charts and metric artifacts. `LoadRelatedChartsUseCase` resolves related chart paths for multi-chart measurements.

`MeasurementPlotPreviewPanel` renders the chart preview using the resolved artifact paths. It does not re-run analysis; it reads persisted artifacts only.

## Stale and Recompute Banners

`RecomputeStaleBannerView` displays when a stored artifact is detected as stale (source data changed after last analysis). `RecomputePreviewPanel` hosts the recompute trigger UI.

Recompute is a Workbench operation — Library only displays the stale state and routes the user to Workbench for re-analysis.

## Preview Computation Service

`LibraryPreviewComputationService` orchestrates background preview loading for the detail panel. It is an App-layer service, not a FeatureStore concern, to keep async I/O off the observable class.

`LibraryViewComputationService` is the UI-layer bridge that triggers preview loading and surfaces results to the view.

`LibrarySheets` contains the sheet presentation modifiers used by Library views (e.g., edit sheet, preview sheet).

## Workbench Write Boundary

Workbench writes chart artifacts via `SaveActiveChartToLibraryUseCase` (owned by Workbench). Library surfaces the results via the preview pipeline. Cross-boundary details: `docs/architecture/INDEX.md` Workbench → "Save chart/metrics to Library" row; risk `SP-007`.

## Invariants

- Library reads persisted artifacts only; it does not re-run analysis.
- All artifact path construction goes through `LibraryPathResolver` — no hand-built absolute/relative paths.
- Stale state is display-only in Library; recompute is a Workbench operation.

## Tests

Start with `V41217MeasurementPlotIndexTests.swift`.

## Code Map

- `Sources/SpinLabApp/Features/Library/MeasurementPlotPreviewPanel.swift` — chart preview panel; renders persisted artifact by resolved path
- `Sources/SpinLabApp/Features/Library/RecomputePreviewPanel.swift` — recompute trigger UI panel
- `Sources/SpinLabApp/Features/Library/RecomputeStaleBannerView.swift` — stale artifact banner (display only; recompute routes to Workbench)
- `Sources/SpinLabApp/Features/Library/LibrarySheets.swift` — Library sheet presentation modifiers (edit, preview sheets)
- `Sources/SpinLabApp/Features/Library/LibraryViewComputationService.swift` — UI-layer bridge for preview loading; surfaces results to view
- `Sources/SpinLabApp/Library/LibraryPathResolver.swift` — root-relative path construction for artifact and sidecar locations (shared: Library + Workbench, SP-008)
- `Sources/SpinLabApp/UseCases/LoadMeasurementPlotIndexUseCase.swift` — reads _spinlab/ plot index to discover available charts
- `Sources/SpinLabApp/UseCases/LoadRelatedChartsUseCase.swift` — resolves related chart paths for multi-chart measurements
- `Sources/SpinLabApp/App/LibraryPreviewComputationService.swift` — preview group + actionable preview index pure computation
