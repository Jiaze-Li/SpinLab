# AHE Workflow Assembly

> Semantic assembly audit for the AHE workflow.

## Reality Check

- Workflow ID: `ahe`
- Runtime display name is loaded from `WorkflowDefinitionStore` / `config/workflow.json`.
- There is no runtime Assembly object. The workflow contract is distributed across registry dispatch, the workspace view/store, parser and use cases, pack contracts, and tests.
- Common Main Board behavior stays out of this record: search execution, selection mechanics, analyze/save lifecycle, plot-canvas internals, related-chart hover behavior, and default pack button behavior.

## Search Hints

| Semantic item | Current behavior | Trace |
|---|---|---|
| Workflow match token | Workflow config matches token `AHE`; runtime workflow ID is `ahe`. | `Sources/SpinLabApp/config/workflow.json`; `Sources/SpinLabApp/Workflow/WorkflowDefinitionStore.swift` |
| Search aliases | Search aliases are `ahe` and `a`; `anomaloushall` participates in canonicalization but not search token aliases. | `Sources/SpinLabApp/Domain/Workflow/WorkflowID.swift`; `Sources/SpinLabApp/UseCases/SearchWorkflowMeasurementsUseCase.swift` |
| Extra search slots | None. AHE uses the common Workbench search only. | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift` |
| Result mirror | AHE keeps `cachedSearchResults` as the workflow-local mirror for selection denominator, pack state, title context, and legacy restore fallback. This is common bridge behavior, not an AHE-only search module. | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift`; `docs/architecture/workbench/modules/MEASUREMENT_SEARCH.md` |

## Input Adapter Surface

The AHE Input Adapter converts raw PPMS `.dat` files into the `AHEIngestionResult` workflow-domain dataset. All downstream stages (fit, render, save) consume `AHEIngestionResult` only.

| Field | Current state |
|---|---|
| Accepted file formats | PPMS `.dat` files in two structural variants: (1) `[Header]` / `[Data]` section, then `Comment,...` column header; (2) file starts directly with `Comment,...`. Both produce the same `PPMSParsedFile` output. |
| Parser entry point | `AHEDataParser.parse(fileURL:) throws -> PPMSParsedFile`. Structural failures throw `AppError.io` or `AppError.validation`; ingestion catches and converts to adapter warnings. |
| Column mapping | Adapter-owned via `AHEAxisDetector`. Raw `Magnetic Field (Oe)` → semantic `H (T)` (multiplied by `1e-4`). Raw `Bridge N Resistance (Ohms)` or `Bridge N Resistivity…` → semantic `R_H (Ω)` for the selected bridge/channel. Column mapping is resolved at adapter time; no downstream stage re-reads raw column names. |
| Unit conversion | Oe → T at adapter boundary (×1e-4). Resistivity fallback carries no unit conversion and must warn explicitly. |
| Sidecar condition injection | No sidecar temperature override in AHE. Bridge/channel selection comes from `AHEPlotSelectionItem.channel.bridgeIndex`, which is user-selection state, not a sidecar field. |
| Adapter output type | `AHEIngestionResult` (via `IngestAHESelectionsUseCase`). Contains per-series `WorkbenchPlotSeries` values with semantic x/y in declared units. |
| Warning policy | Parse failures → adapter warning per file. Inactive bridge (no resistance/resistivity column) → per-bridge skip warning. Resistivity fallback → explicit "no unit conversion applied" warning. Empty paired x/y after column resolution → skip warning. No silent fallback to a different semantic column. |

**Invariant check:**
- Main Board does not call `AHEDataParser` or `AHEAxisDetector`. ✅
- Common plot/save modules consume `AHEIngestionResult`-derived series only. ✅
- Column mapping (bridge → column name) is not re-derived inside `BuildAHEPlotPayloadUseCase`. ✅

## Data / Physics Mapping Contract

| Semantic item | Current behavior | Trace |
|---|---|---|
| Accepted file formats | PPMS `.dat` files in two variants: `[Header]` / `[Data]` followed by `Comment,...` column header, or files starting directly with `Comment,...`. | `Sources/SpinLabApp/UseCases/AHEDataParser.swift`; `Tests/SpinLabAppTests/V321AHEIngestionAxisDetectionTests.swift` |
| Parser entry point | `AHEDataParser.parse(fileURL:)` returns `PPMSParsedFile` with raw column names, rows, and source ref. | `Sources/SpinLabApp/UseCases/AHEDataParser.swift`; `Sources/SpinLabApp/Domain/PPMSParsedFile.swift` |
| Field column mapping | Fixed semantic x is `H (T)`, resolved from raw `Magnetic Field (Oe)` and converted by `× 1e-4`. Fixed semantic y is `R_H (Ω)`, but no raw `R_H (Ω)` column is required; ingestion resolves it per selected channel to `Bridge N Resistance (Ohms)` or active `Bridge N Resistivity...`. | `Sources/SpinLabApp/UseCases/AHEAxisDetector.swift`; `Sources/SpinLabApp/UseCases/IngestAHESelectionsUseCase.swift`; `Tests/SpinLabAppTests/V321AHEIngestionAxisDetectionTests.swift` |
| Bridge/channel mapping | `AHEPlotSelectionItem.channel.bridgeIndex` selects Bridge 1/2/3. The selected bridge determines the internal y data column for semantic `R_H (Ω)`. | `Sources/SpinLabApp/UseCases/IngestAHESelectionsUseCase.swift`; `Sources/SpinLabApp/Workbench/V3/AHEIngestionContracts.swift` |
| Unit conversion | Magnetic field defaults to tesla display by converting Oe to T. Resistivity fallback is not converted; the warning says no unit conversion was applied. | `Sources/SpinLabApp/UseCases/IngestAHESelectionsUseCase.swift` |
| Derived metrics | Hc and R_AHE are extracted from rendered series. Hc uses midpoint crossings where possible, otherwise nearest midpoint. R_AHE uses high-field plateau medians when both plateaus exist, otherwise half range. | `Sources/SpinLabApp/UseCases/ExtractAHEMetricsUseCase.swift`; `Tests/SpinLabAppTests/V5111ExtractAHEMetricsUseCaseTests.swift`; `Tests/SpinLabAppTests/V5114AHEMetricSourceTests.swift` |
| UI controls | The workflow exposes title template, grid toggle, Hc override, and R_AHE override. X/y raw-column axis pickers are retired. | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift`; `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` |

## Analysis Pipeline

| Stage | Current behavior | Trace |
|---|---|---|
| Parse | Parse unique selected file paths once into `PPMSParsedFile`. Structural parser failures are captured as warnings by ingestion. | `Sources/SpinLabApp/UseCases/IngestAHESelectionsUseCase.swift` |
| Ingest | Build one `WorkbenchPlotSeries` per selected sample/channel. Selection order is preserved after unique file parsing. | `Sources/SpinLabApp/UseCases/IngestAHESelectionsUseCase.swift` |
| Transform | Convert magnetic field to T for fixed semantic x; resolve y to bridge resistance/resistivity; attach metadata for title/legend resolvers. | `Sources/SpinLabApp/UseCases/IngestAHESelectionsUseCase.swift` |
| Render payload | Build a single-tab `WorkbenchPlotPayload` with the resolved axis mapping and series; render through the common `WorkbenchRenderPipeline`. | `Sources/SpinLabApp/UseCases/BuildAHEPlotPayloadUseCase.swift`; `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` |
| Metrics | Extract Hc and R_AHE from active chart series and allow pre-persist manual overrides. | `Sources/SpinLabApp/UseCases/ExtractAHEMetricsUseCase.swift`; `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` |
| Warnings/failure | Empty selection returns an empty result. Parse failures, unparseable files, inactive bridges, resistivity fallback, and empty paired data become warnings/skips rather than silent fallback. | `Sources/SpinLabApp/UseCases/IngestAHESelectionsUseCase.swift`; `Tests/SpinLabAppTests/V321AHEIngestionAxisDetectionTests.swift` |

## Optional Contributions

| Contribution | Assembly-owned semantics | Trace |
|---|---|---|
| AHE plot controls | Title template, grid, render mode, and style controls are workflow-specific contribution content mounted in the shell. AHE uses a custom `AHEPlotControlsPanel` (defined inline in `AHEWorkspaceView.swift`) rather than `WorkbenchStandardPlotControls`. This is a legitimate specialization: AHE is single-tab with no curve stacking, so the tab picker and stack/gap controls in `WorkbenchStandardPlotControls` do not apply. | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift` |
| Hc override panel | AHE allows manual Hc correction before persistence. | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift`; `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` |
| R_AHE override panel | AHE allows manual R_AHE correction before persistence. | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift`; `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` |

## Plot Contract / Overrides

| Semantic item | Current behavior | Trace |
|---|---|---|
| Common plot behavior | Legend editing, label overrides, render mode, style params, copy PNG, related-chart display, and tab render-state preservation remain common plot shell behavior. | `docs/architecture/workbench/modules/PLOT_SYSTEM.md`; `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift`; `Sources/SpinLabApp/Workbench/V3/TabRenderManager.swift` |
| Workflow-specific axes | Fixed x is `H (T)`. Fixed y is semantic `R_H (Ω)` and resolves internally to the selected bridge resistance/resistivity data. | `Sources/SpinLabApp/UseCases/AHEAxisDetector.swift`; `Sources/SpinLabApp/UseCases/IngestAHESelectionsUseCase.swift` |
| Tabs | AHE is a single-tab workflow. | `Sources/SpinLabApp/Workbench/V3/TabRenderManager.swift`; `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` |
| Title default | `#tab #device #sample` (with `#tab` resolved to `AHE`) is the Assembly-owned default title template (Layer 1 of the three-layer title model; see `docs/architecture/workbench/modules/PLOT_SYSTEM.md`). The editable template state (`titleTemplate` on the workspace store) is workflow-store-owned boundary debt; the per-tab inline title override is `TabRenderState.titleOverride` (Plot Preservation-owned). | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` |
| Metrics/annotations | Hc and R_AHE are workflow metrics saved with chart artifacts; manual overrides are AHE-specific. | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift`; `Sources/SpinLabApp/UseCases/ExtractAHEMetricsUseCase.swift` |

## Validation / Warning Policy

- Missing or malformed `.dat` structure throws parser validation errors, which ingestion reports as parse warnings.
- A selected bridge with no active resistance/resistivity data is skipped with a bridge-specific warning.
- Resistivity fallback is allowed but explicitly warns that no unit conversion was applied.
- Empty paired x/y data is skipped with a warning.
- Metric extraction can fail on missing sample IDs; tests protect label/source behavior, but the workflow currently favors extracted `sampleID` over label parsing.

## Persistence / Pack-Restore Contract

| State | Current persistence behavior | Trace |
|---|---|---|
| Display state | Saves title template, grid flag, and per-tab render states. `legendAnchor` is not serialized in `AHEPackConfig` — it resets to `""` after pack restore. This is a known coverage gap (documented in `docs/architecture/workbench/modules/PLOT_SYSTEM.md`); no schema change is required at Gate 7.8. | `Sources/SpinLabApp/Workbench/V3/AHEPackContracts.swift` |
| Search/selection state | Saves cached search results, selected IDs, and common search query text for restore bridging. | `Sources/SpinLabApp/Workbench/V3/AHEPackContracts.swift` |
| Result snapshot | Saves `AHEIngestionResult` so restore can rerender without re-ingestion. | `Sources/SpinLabApp/Workbench/V3/AHEPackContracts.swift` |
| Metrics | Saved chart metrics are built from active render state at persistence time, including pending Hc/R_AHE overrides if present. | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` |

## Save Metadata / Metric Contract

Target owner: AHE Assembly owns Hc and R_AHE meaning, extraction semantics, and override policy. The common Save module owns chart/metric writes only.

| Concern | Current state |
|---|---|
| Metric definitions | Hc and R_AHE are Assembly-owned. They are extracted from rendered series, not invented by save code. |
| Current implementation surface | `ExtractAHEMetricsUseCase` fills `lastExtractedMetrics`; `AHEWorkspaceStore.buildActiveChartMetrics()` maps that state to `PendingMetricEntry` values with canonical units `T` and `Ω`, and applies `pendingMetricOverride` / `pendingRAHEOverride` when the active chart is single-sample. `persistToLibrary()` forwards the projection to `SaveActiveChartToLibraryUseCase`. |
| Forbidden ownership | Common save code must not derive Hc, R_AHE, units, or override meaning; it must not infer AHE semantics from labels or chart payloads. |
| Pack/restore implications | Override candidates are save-time only. Pack restore may repopulate analysis state and library root so save-after-restore works, but it must not serialize saved metrics, override candidates, or save outcome. |
| Tests protecting current behavior | `V537SaveModuleBoundaryTests`, `V4111SaveActiveChartToLibraryUseCaseTests`, `V5111ExtractAHEMetricsUseCaseTests`, `V5114AHEMetricSourceTests`, `V537PackRestoreModuleBoundaryTests`. |
| Extraction readiness | Medium. The workflow already computes and maps metrics, but the save bridge is still a raw `PendingMetricEntry[]` rather than an explicit provider contract. |
| Exit condition | AHE exposes a typed save metadata projection for Hc and R_AHE, including metric name, unit, conditions, override info, and semantic identity, and the common Save module only persists that projection. |

## Required Behavior Tests

| Behavior class | Current coverage | Missing / later consideration |
|---|---|---|
| Data mapping | Parser variants, fixed semantic axis mapping, Oe→T conversion, parse-once, multi-file/multi-channel, inactive bridge skip, and ch2 Bridge 2 data selection. | Add direct warning text coverage before changing resistivity fallback semantics. |
| Unit conversion | Field conversion is indirectly covered by default-axis behavior; resistivity no-conversion is warning-only. | Add direct warning text coverage before changing resistivity fallback semantics. |
| Analysis pipeline | Store isolation, view extraction, multi-series extraction, search snapshot consumption, tab-state boundary. | No single Assembly manifest test exists. |
| Warning/failure | Inactive bridge and parse failure paths have focused coverage. | Missing-column warning text should be locked before changing parser/axis detection. |
| Pack/restore | Pack contract and workflow state boundary tests cover restored ingestion/result state and deprecated axis-override pack failure. | Add metric override candidate round-trip if persistence semantics change. |
| Plot semantics | Single-tab state preservation, fixed semantic axes, and metric source tests cover current behavior. | Plot semantic tests should be added if AHE gains workflow-specific plot modes. |

## Findings Summary

- Common and out of Assembly: Workbench search execution, selection toggles, analyze/save buttons, plot-canvas internals, related-chart hover, and render pipeline mechanics.
- Assembly-owned: `ahe` identity/search aliases, `.dat` variants, fixed semantic axes, bridge-to-channel y mapping, Oe→T conversion, AHE metric extraction, AHE metric override panels, single-tab plot semantics, and pack fields required to rerender/interpret AHE results.
- Currently implicit/distributed: the semantic `R_H (Ω)` y default is implemented as bridge-column resolution, not a raw column; metric extraction and save metadata are store/use-case behavior, not provider objects.
- Later Gate 3 / Gate 7 consideration: if module extraction proceeds, preserve the AHE semantic mapping as a workflow-owned contract and do not move bridge resolution or Oe→T conversion into generic plot/search modules.
