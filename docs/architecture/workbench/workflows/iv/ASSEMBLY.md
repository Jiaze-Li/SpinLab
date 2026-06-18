# IV Workflow Assembly

> Gate 8.1 new-workflow dry run. This record defines the real IV workflow contract while validating whether the Workbench Main Board can accept a new workflow without common-shell edits.

## Reality Check

- Workflow ID: `iv`
- Runtime display name: `IV`
- Current config status: `config/workflow.json` already contains an `IV` workflow entry, but Workbench runtime support still requires explicit store/view/search registration.
- Runtime model: no runtime Assembly object exists. The workflow is realized through this Assembly record plus workflow-owned Swift files and explicit Workbench registration surfaces.
- Gate scope: chart-only IV workflow with Save to Library and analysis pack restore. Metric persistence, fitting, threshold extraction, and derivative conductance are deferred.

## Main Board Contract

IV must use the existing Main Board path:

- `IVWorkspaceView` wraps `WorkflowWorkspaceShell`.
- `IVWorkspaceStore` conforms to `WorkbenchWorkspaceProviding`.
- Search, selected-hit tray, Analyze button, plot canvas, copy PNG, warnings, run trace, Save to Library, Save Analysis, and Load Pack are provided by common Workbench modules.
- IV must not modify `WorkflowWorkspaceShell`, `WorkbenchPlotCanvas`, `SaveActiveChartToLibraryUseCase`, or `AnalysisPackProviding` default save/load behavior unless the change is separately classified as a Main Board boundary finding.

## Workflow Identity / Search Hints

- Canonical runtime ID: `iv`
- Display name: `IV`
- Search prefix: `iv `
- Suggested aliases: `iv`, `i-v`, `currentvoltage`
- Workflow definition condition fields: `device`, `temperature`, `field`

Search should continue to use the common Workbench search module. Search results are projected into `IVWorkspaceStore.cachedSearchResults` only as a compatibility mirror; selected-hit snapshots remain the canonical analysis input.

## Input Adapter Contract

### Accepted files

- `.lvm` files produced by the current IV measurement workflow.

### Parser entry point

- `IVLVMParser`
- `IngestIVSelectionsUseCase`

### Raw file structure

The parser finds the `Tableau:` line and reads the following tab-separated numeric block.

Expected columns:

1. `Current`
2. `1st X`
3. `1st Y`
4. `1st R`
5. `1st Theta`
6. `2nd X`
7. `2nd Y`
8. `2nd R`
9. `2nd Theta`
10. `1st R_H`
11. `Frequency_after`

### Adapter output

- `IVIngestionResult`
- Each parsed file becomes an `IVTrace`.
- The parser preserves raw channel data. It must not permanently choose X or Y.

### Metadata extraction

Filename and sidecar metadata are both part of the adapter surface.

Filename examples include:

- sample/batch: `PN80`, `PN74`
- angle: `150deg`, `60deg`, `120deg`
- harmonic hints: `IV_1w`, `IV_3w`, `IV_dc_ac`
- field: `H_25000 Oe`, `H_0 Oe`
- temperature: `T_50 K`

Sidecar conditions may override filename-derived metadata where present.

### Unit convention

- `Current` is peak current.
- RMS current is `Current / sqrt(2)`.
- A selected voltage component converted to resistance-like output uses `R = V_selected / I_rms`.
- Existing `1st R_H` values in the raw file are reference data and should be preserved, but the workflow's selected-signal resistance must be derived from the user-confirmed channel/component mapping.

### Warning policy

The adapter must warn and continue when possible for:

- unsupported extension
- missing `Tableau:` section
- missing or malformed column header
- numeric row with wrong column count
- empty parsed trace
- missing filename metadata that is not recoverable from sidecar conditions

## IV-Specific Interpretation Module

IV has one workflow-specific optional plot-control module: channel/component mapping.

### Responsibility

The module decides how raw X/Y lock-in channels become plotted voltage and resistance-like series.

### Auto-detection

For each channel:

- compare a robust magnitude score for X and Y, preferably `median(abs(component))`
- selected component defaults to the larger component
- confidence is `max(scoreX, scoreY) / min(scoreX, scoreY)` when denominator is nonzero
- the auto-detected selection is written back into store state so the UI shows what was inferred

### User override

The plot-control module must allow the user to override:

- channel: `1st` / `2nd`
- selected component: `X` / `Y`
- harmonic label: `1ω` / `2ω` / `3ω` / `dc/ac` / custom or unknown

Override behavior:

- override triggers rerender only
- override must not reparse raw files
- override must not mutate search or selection state
- override must be persisted in pack config

### Default physical convention

- Odd harmonic responses usually use X.
- Even harmonic responses may use Y.
- The software should use measured X/Y dominance as the default, not hard-code harmonic parity as the only rule.

## Analysis Pipeline

1. Main Board provides selected-hit snapshot.
2. `IVWorkspaceStore.runAnalysis(selectedHitsSnapshot:)` consumes selected hits.
3. `IngestIVSelectionsUseCase` parses selected `.lvm` files into `IVIngestionResult`.
4. IV mapping state is auto-filled from parsed traces when no user override exists.
5. `IVPlotRenderer` builds `WorkbenchPlotPayload` for the active tab.
6. Common render pipeline produces PNG/layout/manifest payload.
7. Store applies output to `TabRenderManager` and commits run trace after analysis.

Rerender paths must reuse `IVIngestionResult` and mapping state; they must not commit run trace.

## Plot Contract

Initial Gate 8.1 tabs:

- `Selected V vs Current`
  - x: peak current from `Current`
  - y: selected voltage component from channel mapping
- `Selected R vs Current`
  - x: peak current from `Current`
  - y: `selected voltage / (Current / sqrt(2))`

Suggested labels:

- x-axis: `Current (A, peak)`
- selected-voltage y-axis: `Selected V (V RMS)`
- selected-resistance y-axis: `Selected R (Ω)`

Suggested series label tokens:

- sample/batch
- angle
- harmonic label
- field, preferably displayed in T when derived from Oe
- temperature

## Persistence / Pack-Restore

### Pack config owns

- active tab
- title template
- plot grid flag
- tab render states
- chart style overrides if supported by store
- cached search results mirror
- selected search result IDs
- search query text
- auto-detected channel/component mapping
- user override channel/component mapping
- harmonic labels

### Pack result owns

- `IVIngestionResult`

### Restore contract

- Restore search mirror and selection through provided callbacks.
- Restore `IVIngestionResult` from pack result.
- Restore mapping state from pack config.
- Rerender from restored ingestion result.
- Do not reparse raw files during normal restore.
- Do not commit run trace directly from restore.

## Save Metadata / Metric Contract

Gate 8.1 is chart-only.

- `buildActiveChartMetrics()` returns `[]`.
- Metric persistence for resistance slope, thresholds, nonlinear coefficients, or conductance is deferred.

## Required Behavior Tests

Minimum targeted tests:

- `IVLVMParserTests`
  - parses `Tableau:` block
  - extracts 11 expected numeric columns
  - verifies RMS relation on fixture data where appropriate
- `IngestIVSelectionsUseCaseTests`
  - parses selected hits
  - injects filename/sidecar metadata
  - warns on unsupported files
- `IVChannelMappingTests`
  - auto-selects X when X dominates Y
  - auto-selects Y when Y dominates X
  - preserves user override after rerender
- `IVPackRoundTripTests`
  - config/result encode and decode
  - `IVPackResult` includes `IVIngestionResult`
- `IVWorkspaceStoreRunAnalysisTests`
  - consumes selected-hit snapshot
  - does not use cached search results as primary selected-hit source
- `IVRestoreBoundaryTests`
  - restore does not commit run trace directly
  - restore rerenders from pack result without reparsing raw files

## Boundary Findings to Feed Back into EXTENSION_BOUNDARIES

This dry run has already clarified these extension requirements:

- `EXTENSION_BOUNDARIES.md` must list `WorkbenchMainSearchRuntime.swift` as a required registration surface.
- `WorkbenchFeatureStore.swift` currently lives under `Sources/SpinLabApp/App/State/`, not under `Features/Workbench/`.
- New workflow config entries do not automatically imply Workbench runtime support.
- Workflow-specific plot controls are optional modules mounted through `WorkflowWorkspaceShell` slots, not Main Board edits.
- Parser and physics interpretation are separate ownership surfaces for IV.
