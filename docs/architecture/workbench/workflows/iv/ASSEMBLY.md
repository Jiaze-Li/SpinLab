# IV Workflow — Assembly Record

> Gate 8 dry-run workflow. Purpose: validate that the architecture can accommodate a new workflow using only the Workflow Assembly extension path, without modifying the Main Board or any default module.

---

## Workflow Identity

| Field | Value |
|---|---|
| Workflow ID | `IV` |
| Display name | `IV` |
| `WorkflowKey` case | `.iv` |
| Search prefix | `IV ` |
| Condition fields | `device`, `temperature`, `field` |

---

## Input Adapter Contract

| Field | Detail |
|---|---|
| Accepted file formats | Zurich Instruments `.lvm` (same container as XY Rotation) |
| Parser entry point | `IVLVMParser.parse(fileURL:temperatureOverride:fieldOverride:)` |
| Column layout | Col 0: Current (A, peak); Col 1: 1st X (V); Col 2: 1st Y (V); Col 5: 2nd X (V); Col 6: 2nd Y (V) |
| Raw data preserved | `ch1X`, `ch1Y`, `ch2X`, `ch2Y`, `firstR`, `firstTheta`, `secondR`, `secondTheta`, `firstRH`, `frequencyAfter` — component selection deferred to store; raw `1st R_H` is retained as an audit/reference column |
| Unit conversion | Current in A (peak); voltage in V |
| Sidecar condition injection | `temperature` → `IVSweep.temperatureK`; `field` → `IVSweep.fieldT`; `device` → `IVIngestionResult.device` |
| Adapter output type | `IVIngestionResult` (sweeps, device, warnings, ch1State, ch2State) |
| Warning policy | Parse failures per file → warning, file skipped. Mixed devices → warning. No files → "No files selected." |

---

## Channel Mapping

Auto-detection runs during ingestion in `IngestIVSelectionsUseCase`:

| Step | Detail |
|---|---|
| Score | `scoreX = median(abs(ch1X across all sweeps))`, same for Y |
| Selection | `autoComponent = scoreX >= scoreY ? .x : .y` |
| Confidence | `max(scoreX, scoreY) / min(scoreX, scoreY)`; 1.0 when indeterminate |
| Store state | `ch1Component` / `ch2Component` — auto-filled after analysis; user can override via dropdown |
| Override effect | Triggers `rerenderForStyleChange()`, not re-parse |

`firstRH` (`1st R_H`) is parsed and stored on `IVSweep` for audit/reference only.
It is **not currently consumed by any renderer or use case** — no code path reads
it back out. The relation it is meant to validate,
`1st R_H ≈ 1st X * sqrt(2) / Current_peak`, is asserted here in prose only; it is
not checked anywhere in code.

---

## Physics Function

IV currently renders **harmonic voltage vs current** — it does not compute
resistance. Both tabs plot a raw voltage channel against current; neither
divides voltage by current.

Two tabs (internal case name `IVWorkbenchTab.resistance` is a naming leftover —
see below):

| Tab | Key | X-axis | Y-axis |
|---|---|---|---|
| `voltage` (`IVWorkbenchTab.voltage`) | "1st / I" | Current (mA, display) | V (V) — selected ch1 component |
| `IVWorkbenchTab.resistance` (display name "2nd / I") | "2nd / I" | Current (mA, display) | V (V) — selected ch2 component |

`IVWorkbenchTab.resistance` is a legacy case name from an earlier design; its
`displayName` is `"2nd / I"` (not "resistance") and its render path
(`IVPlotRenderer.renderSecondHarmonicVsCurrent` / `renderResistanceVsCurrent`)
plots the raw ch2 voltage channel — no `V / I` division occurs. There is no
`R (Ω)` computation anywhere in the IV workflow today.

Raw current is stored in A and treated as **peak** amplitude for display
conversion (see `IVLVMParser` column-layout comment). X-axis display converts
to mA depending on `xCurrentBasis`, which is a **display-only** conversion of
the stored peak current — it does not change what is stored, and it is not
part of a resistance calculation:

- **Peak**: `x_mA = current_A × 1000`
- **RMS** (display-only conversion from stored peak current): `x_mA = current_A / √2 × 1000`

Each tab renders 2 series per sweep: ch1 and ch2, using the currently selected component.

Series label: `"{temp} K ch1"` and `"{temp} K ch2"`.

---

## Optional Contributions

None. IV uses the default shell with no optional panels or secondary input search.

---

## Plot Semantics

| Field | Value |
|---|---|
| Default tab | `.voltage` ("V vs I") |
| Default title template | `#tab #device #sample` |
| Stacking | Supported: `stackOffsetMultiplier` / `minGapFraction` — Workflow Assembly-owned parameters exposed via `WorkbenchStandardPlotControls` |
| X-axis basis | `xCurrentBasis` — selectable: Peak or RMS; controls mA conversion applied before render |
| Legend | Default position |
| Tab picker | Rendered by `WorkflowWorkspaceShell` (two-tab workflow) |

Plot controls panel (`IVPlotControlsPanel`): title template field, grid toggle, ch1 component picker (X/Y + confidence), ch2 component picker, xCurrentBasis picker (Peak / RMS), stack offset and gap controls.

IV uses the shared Plot System render path for legend and series-order behavior:

- `IVPlotRenderer` must route through `WorkbenchRenderPipeline.render(...)`.
- `IVPlotRenderer` must pass `metadata: sweep.sampleMetadata ?? [:]` into every `WorkbenchPlotSeries`.
- `WorkbenchRenderPipeline` owns legend auto-resolution for IV through `LegendDimensionResolver` when `legendDimension` is nil.
- `IVSweep` ingestion must populate `sampleMetadata` so the shared resolver can infer temperature, field, harmonic, device, substrate, thickness, and related labels.
- IV uses the shared series order and rename controls in `WorkbenchStandardPlotControls` / `WorkbenchSeriesOrderPanel`; IV must not define workflow-local reorder or legend-guessing logic.

---

## Validation / Warning Policy

- No files selected → `IVIngestionResult(warnings: ["No files selected."])`.
- File parse failure → warning per file; file is skipped.
- Mixed devices → warning; first device used.
- Shared legend inference is required: IV must not pre-set `payload.legendDimension`, and any legend choice must come from the shared Plot System path.

---

## Persistence / Pack-Restore

| Contract type | Swift type |
|---|---|
| `PackConfig` | `IVPackConfig` |
| `PackResult` | `IVPackResult` |
| `packWorkflowID` | `"IV"` |

`IVPackConfig` carries: `activeTab`, `titleTemplate`, `showPlotGrid`, `seriesRenderMode`, `chartStyleOverrides`, `ch1Component`, `ch2Component`, `xCurrentBasis`, `stackOffsetMultiplier`, `minGapFraction`, `tabStates`, `cachedSearchResults`, `selectedSearchResultIDs`, `searchQueryText`.

`IVPackResult` carries: `ingestionResult: IVIngestionResult`.

Restore re-applies all config fields, restores channel components, and re-renders all tabs through the shared `WorkbenchRenderPipeline`.

Save-to-Library is chart-only for IV: the shared active-chart export path persists the rendered PNG plus manifest payload, and IV does not emit metric records.

---

## Required Behavior Tests

| Test | File |
|---|---|
| LVM parser extracts all channel columns | `V81IVParserChannelMappingTests.swift` |
| Channel mapping selects dominant component | `V81IVParserChannelMappingTests.swift` |
| Channel mapping confidence = max/min ratio | `V81IVParserChannelMappingTests.swift` |
| Tie-break / empty-array edge cases | `V81IVParserChannelMappingTests.swift` |
| Restore round-trips `activeTab`, `ch1Component`, `ch2Component`, `seriesRenderMode`, `xCurrentBasis`, `stackOffsetMultiplier`, `minGapFraction`, and chart style overrides | IV pack/restore tests |
| Restore preserves per-tab title / axis / series-order overrides and re-renders through `WorkbenchRenderPipeline` | IV pack/restore tests |
| Peak/RMS x-axis basis toggles produce correct mA conversion before render | IV current-basis tests |
| Stack offset and gap controls change rendered curve spacing correctly | IV stacking tests |
| `runAnalysis(selectedHitsSnapshot:)` consumes snapshot, not `cachedSearchResults` | IV analysis boundary tests |
| Save-to-Library writes only chart artifacts, not metric records | IV save tests |

---

## Implementation Surface

| Layer | File |
|---|---|
| Ingestion contracts | `Sources/SpinLabApp/Workbench/V3/IVIngestionContracts.swift` |
| LVM parser | `Sources/SpinLabApp/UseCases/IVLVMParser.swift` |
| Ingestion use case | `Sources/SpinLabApp/UseCases/IngestIVSelectionsUseCase.swift` |
| Plot renderer | `Sources/SpinLabApp/UseCases/IVPlotRenderer.swift` |
| Pack contracts | `Sources/SpinLabApp/Workbench/V3/IVPackContracts.swift` |
| Workspace store | `Sources/SpinLabApp/Features/Workbench/IVWorkspaceStore.swift` |
| Workspace view | `Sources/SpinLabApp/Features/Workbench/IVWorkspaceView.swift` |
| Workflow ID registration | `WorkflowKey.iv` case in `WorkflowKey.swift`; dispatched via `WorkflowWorkspaceRegistry` |
| View dispatch | `WorkflowWorkspaceRegistry.swift` case `"iv"` |
| Search / mirror wiring | `WorkbenchMainSearchRuntime.swift` three switch cases |
- Shared plot controls / order / legend path | `WorkbenchStandardPlotControls.swift`, `WorkbenchSeriesOrderPanel.swift`, `WorkbenchRenderPipeline.swift`, `LegendDimensionResolver.swift`, `WorkbenchSeriesOrderKeyResolver.swift` |

## Code Map

- `Sources/SpinLabApp/Features/Workbench/IVWorkspaceStore.swift` - IV workflow workspace store owning IV analysis, pack, and render state
- `Sources/SpinLabApp/Features/Workbench/IVWorkspaceView.swift` - IV workflow shell view and workflow-specific control content
- `Sources/SpinLabApp/UseCases/IVLVMParser.swift` - IV LVM parser that preserves raw channels and audit columns
- `Sources/SpinLabApp/UseCases/IVPlotRenderer.swift` - IV workflow renderer that builds plot payloads from IV sweeps
- `Sources/SpinLabApp/UseCases/IngestIVSelectionsUseCase.swift` - IV ingestion use case that derives `IVIngestionResult` from selected hits
- `Sources/SpinLabApp/Workbench/V3/IVIngestionContracts.swift` - IV ingestion result and sweep contracts
- `Sources/SpinLabApp/Workbench/V3/IVPackContracts.swift` - IV pack config and pack result contracts
- `Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift` - workflow registration, routing, and shared search/plot ownership for IV
- `Sources/SpinLabApp/App/State/WorkbenchMainSearchRuntime.swift` - main search orchestration and IV search mirror sync
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift` - dispatches `IVWorkspaceView` for `iv`
- `Sources/SpinLabApp/UI/WorkbenchUIStyle.swift` - shared compact Workbench control styling tokens used by IV controls
