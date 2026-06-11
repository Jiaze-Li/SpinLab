# XY Rotation Workflow Assembly

> Semantic assembly audit for the XY Rotation workflow.

## Reality Check

- Workflow ID in runtime config: `XY`; Workbench pack ID: `xy`.
- Runtime display name is loaded from `WorkflowDefinitionStore` / `config/workflow.json`.
- There is no runtime Assembly object. The contract is distributed across registry dispatch, the workspace view/store, parsers, renderer, pack contracts, and tests.
- Common Main Board behavior stays out of this record: search execution, selection mechanics, analyze/save lifecycle, plot-canvas internals, related-chart hover behavior, and default pack button behavior.

## Search Hints

| Semantic item | Current behavior | Trace |
|---|---|---|
| Workflow match token | Workflow config matches token `xy`; configured condition fields are `device`, `temperature`, `field`, and `shift`. | `Sources/SpinLabApp/config/workflow.json`; `Sources/SpinLabApp/Workflow/WorkflowDefinitionStore.swift` |
| Search aliases | XY is not a case in `WorkflowID`; search still tokenizes workflow ID/display name and sidecar conditions, so `xy` and `XY Rotation` are searchable through common tokenization rather than a dedicated alias enum. | `Sources/SpinLabApp/Domain/Workflow/WorkflowID.swift`; `Sources/SpinLabApp/UseCases/SearchWorkflowMeasurementsUseCase.swift` |
| Extra search slots | None. XY uses the common Workbench search only. | `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift` |
| Result routing/cache | The workflow-local `cachedSearchResults` mirror supports selection denominator, pack restore, title context, and legacy fallback. This is the common search bridge, not XY-specific search logic. | `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift`; `docs/architecture/workbench/modules/MEASUREMENT_SEARCH.md` |

## Data / Physics Mapping Contract

| Semantic item | Current behavior | Trace |
|---|---|---|
| Accepted file formats | `.lvm` Zurich Instruments angle sweeps and PPMS `.dat` files. Unsupported extensions are skipped with warnings. | `Sources/SpinLabApp/UseCases/IngestXYRotationSelectionsUseCase.swift` |
| LVM parser mapping | Positional LVM mapping: column 0 angle degrees, column 1 V1ω_X, column 5 V2ω_X for Rxy, column 9 R_H for Rxx. `I_rms = mean(col1 / col9)` over leading rows; `Rxx = col9`; `Rxy = col5 / I_rms`. Temperature prefers sidecar override, then filename. | `Sources/SpinLabApp/UseCases/XYRotationLVMParser.swift`; `Tests/SpinLabAppTests/V420XYRotationTests.swift` |
| DAT parser mapping | Named PPMS mapping: `Sample Position (deg)` → angle; Bridge 2 resistance/resistivity → Rxx; Bridge 3 resistance/resistivity → optional Rxy; `Temperature (K)` mean or filename supplies temperature when no override exists. | `Sources/SpinLabApp/UseCases/XYRotationDATParser.swift`; `Tests/SpinLabAppTests/V420XYRotationTests.swift` |
| Condition mapping | Sidecar `temperature` overrides parser temperature. Sidecar `shift` leading number becomes per-sweep default φ offset. Sidecar `device` participates in device title/metadata and mixed-device warnings. | `Sources/SpinLabApp/UseCases/IngestXYRotationSelectionsUseCase.swift` |
| Unit conversions | LVM derives resistance from voltage/current for Rxy; DAT uses stored resistance/resistivity values without conversion. Angle remains degrees. | `Sources/SpinLabApp/UseCases/XYRotationLVMParser.swift`; `Sources/SpinLabApp/UseCases/XYRotationDATParser.swift` |
| Derived transforms | Optional linear detrend subtracts first-to-last line. Optional center baseline subtracts per-curve mean. φ rebasing subtracts sweep offset, wraps to `[0, 360)`, sorts, and adds ghost points for near-full cycles. | `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift` |
| UI overrides | Workflow exposes stack offset, gap fraction, baseline centering, linear detrend, `x=180` reference line, title template, and per-sweep φ offset controls. | `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift`; `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` |

## Analysis Pipeline

| Stage | Current behavior | Trace |
|---|---|---|
| Parse | Deduplicate hits by measurement path, sort by path, then dispatch by extension to LVM or DAT parser. | `Sources/SpinLabApp/UseCases/IngestXYRotationSelectionsUseCase.swift` |
| Ingest | Build `XYRotationAngleSweep` values, attach metadata, apply sidecar temperature/shift/device, sort sweeps by temperature. | `Sources/SpinLabApp/UseCases/IngestXYRotationSelectionsUseCase.swift` |
| Transform | Optional detrend/centering, stack offsets, φ rebasing, and periodic ghost points are applied in renderer. | `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift` |
| Render payload | Render two tabs: Rxx vs φ and Rxy vs φ. Rxy tab silently has no payload when no sweep has Rxy data. | `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift`; `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` |
| Metrics | No current XY chart metrics are saved; `buildActiveChartMetrics()` returns empty pending implementation. | `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` |
| Warnings/failure | Empty selected input produces "No files selected." Unsupported extensions and parser failures become warnings. Mixed device values warn and use the first sorted device. Pipeline failures are logged and returned as warnings. | `Sources/SpinLabApp/UseCases/IngestXYRotationSelectionsUseCase.swift`; `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift` |

## Optional Contributions

| Contribution | Assembly-owned semantics | Trace |
|---|---|---|
| XY plot controls | Stack offset, baseline centering, linear detrend, grid/render/style controls, and `x=180` reference line are workflow-specific contribution content. XY uses `WorkbenchStandardPlotControls` for the common two-row tab/stack/title/grid layout. `stackOffsetMultiplier` and `minGapFraction` are Assembly-owned parameters: their values bind into `WorkbenchStandardPlotControls` but are owned and serialized by the XY workspace store. | `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift` |
| φ offset panel | Per-sweep φ offsets are editable after analysis and immediately rerender the active tab. | `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift`; `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` |

## Plot Contract / Overrides

| Semantic item | Current behavior | Trace |
|---|---|---|
| Common plot behavior | Plot canvas interactions, style editor, copy PNG, legend positioning, series label overrides, and tab state preservation are common shell behavior. | `docs/architecture/workbench/modules/PLOT_SYSTEM.md`; `Sources/SpinLabApp/Workbench/V3/TabRenderManager.swift` |
| Tabs | Two workflow tabs: `Rxx vs φ` and `Rxy vs φ`. | `Sources/SpinLabApp/Workbench/V3/XYRotationIngestionContracts.swift`; `Tests/SpinLabAppTests/V420XYRotationTests.swift` |
| Default axes | X is `φ (deg)` on both tabs. Y is `Rxx (Ω)` or `Rxy (Ω)` by tab. | `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift` |
| Stacking and order | Stacking uses `ThreeOmegaStackOffsetUseCase`; legend order is reversed; series are reorderable. | `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift`; `Tests/SpinLabAppTests/V5111AlignXYSeriesOrderUseCaseTests.swift` |
| Special plot modes | Optional baseline centering, linear detrend, φ offset override, 180-degree vertical reference line, and ghost-point periodic extension are XY-specific. | `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift` |
| Title/legend | Default title template `#tab #device #sample` is Assembly-owned (Layer 1 of the three-layer title model; see `docs/architecture/workbench/modules/PLOT_SYSTEM.md`). The editable template state (`titleTemplate` on the workspace store) is workflow-store-owned boundary debt; the per-tab inline title override is `TabRenderState.titleOverride` (Plot Preservation-owned). Series labels default to temperature. | `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift`; `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift` |

## Validation / Warning Policy

- LVM parser throws when data rows are absent, temperature cannot be resolved, or `I_rms` cannot be derived.
- DAT parser throws when required angle/Rxx columns are absent, valid rows are absent, or temperature cannot be resolved.
- Ingestion converts parser errors to warnings and skips affected files.
- Unsupported extensions are skipped with warnings.
- Rxy tab currently returns no payload when no Rxy data exists; this is implicit and not surfaced as a user warning.
- Mixed devices warn and choose the first sorted device string.

## Persistence / Pack-Restore Contract

| State | Current persistence behavior | Trace |
|---|---|---|
| Analysis parameters | Saves φ offset overrides, center baseline, and linear detrend. | `Sources/SpinLabApp/Workbench/V3/XYRotationPackContracts.swift` |
| Display state | Saves active tab, title template, stack offset, gap fraction, grid flag, and per-tab render states. `legendAnchor` is not serialized in `XYRotationPackConfig` — it resets to `""` after pack restore. This is a known coverage gap (documented in `docs/architecture/workbench/modules/PLOT_SYSTEM.md`); no schema change is required at Gate 7.8. | `Sources/SpinLabApp/Workbench/V3/XYRotationPackContracts.swift` |
| Search/selection state | Saves cached search results, selected IDs, and search query text. | `Sources/SpinLabApp/Workbench/V3/XYRotationPackContracts.swift` |
| Result snapshot | Saves `XYRotationIngestionResult` so restore can rerender both tabs without re-ingestion. | `Sources/SpinLabApp/Workbench/V3/XYRotationPackContracts.swift`; `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` |
| Metadata for saved results | Saves chart artifacts from active tab; no XY metrics are currently emitted. | `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` |

## Save Metadata / Metric Contract

Target owner: XY Assembly owns the current absence of a saved metric contract. The common Save module owns the generic chart persistence path.

| Concern | Current state |
|---|---|
| Metric definitions | None. `buildActiveChartMetrics()` returns `[]` pending future Fourier-fit work. |
| Current implementation surface | `XYRotationWorkspaceStore.persistToLibrary()` still uses `SaveActiveChartToLibraryUseCase`, but the workflow supplies no metric entries. |
| Forbidden ownership | Common save code must not invent XY metric names, units, or semantic identity. It may only persist the chart artifact and trace projection. |
| Pack/restore implications | Restore only needs to rebuild analysis, render state, and library root; there is no metric state to restore or persist. |
| Tests protecting current behavior | `V420XYRotationTests`, `V4111SaveActiveChartToLibraryUseCaseTests`, `V537SaveModuleBoundaryTests`, `V537PackRestoreModuleBoundaryTests`. |
| Extraction readiness | Complete for the current sentinel of "no saved metrics". Low for future metric extraction because no explicit contract exists yet. |
| Exit condition | XY introduces a typed metric contract before any metric records are saved; until then, the common Save module must keep XY as chart-only save. |

## Required Behavior Tests

| Behavior class | Current coverage | Missing / later consideration |
|---|---|---|
| Data mapping | LVM parser angles/Rxx/Rxy/I_rms/temperature; DAT parser angle/Rxx/Rxy/temperature; pack codable round trips. | Add direct tests for sidecar `shift` and `device` warning behavior before changing condition mapping. |
| Unit conversion | LVM Rxy derivation from voltage/current is covered. DAT no-conversion semantics are covered by column mapping values. | Add explicit `I_rms` multi-row averaging test if parser tolerance changes. |
| Analysis pipeline | Search snapshot consumption and workflow state boundary tests cover run/restore surfaces. | Add unsupported extension warning coverage before expanding accepted formats. |
| Warning/failure | Parser failures are represented in parser tests; renderer warning independence is covered. | Rxy-empty-tab behavior is implicit; add a test if UI warning policy changes. |
| Pack/restore | Pack config/result codable and state-boundary tests cover persisted state. | Add restore assertion for `linearDetrend`, `x=180`, and per-sweep φ offsets if these semantics are refactored. |
| Plot semantics | Tab display names, series-order alignment, reversed legend index mapping, and state survival are covered. | Add plot payload tests for φ rebasing, ghost points, and `auxVerticalX=180` before Gate 7 extraction. |

## Findings Summary

- Common and out of Assembly: common search, selection, analyze/save lifecycle, plot canvas internals, and shared style/legend mechanics.
- Assembly-owned: XY identity token, `.lvm` vs `.dat` mapping, sidecar shift-to-φ offset, Rxx/Rxy tab meanings, detrend/center transforms, φ rebasing, 180-degree marker, and XY pack state.
- Currently implicit/distributed: `xy` search is tokenized from config rather than represented in `WorkflowID`; Rxy-tab empty behavior is silent; no XY metric contract exists yet.
- Later Gate 3 / Gate 7 consideration: before extracting plot or analysis modules, add tests around φ rebasing, sidecar shift, and Rxy-empty warning policy so workflow semantics do not disappear into common modules.
