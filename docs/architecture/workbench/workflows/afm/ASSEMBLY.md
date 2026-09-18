# AFM Workflow — Assembly Record

> AFM V1 is a single-file heatmap workflow, architecturally closest to RSM (see
> `docs/architecture/workbench/workflows/rsm/DRAFT_ASSEMBLY.md`). This record tracks the actual
> implementation status — sections marked **(Phase N — not yet implemented)** describe accepted
> design intent, not shipped code; update the status line as each phase lands.

---

## Workflow Identity

| Field | Value |
|---|---|
| Workflow ID | `afm` — configured in the active Rule Book's `workflow.json` (`matchRules`: tokens `afm`, `ibw`) |
| `WorkbenchWorkflowKind` case | `.afm` |
| Selection mode | `.single` (see `WorkbenchSelectionMode`) — same policy as RSM |
| Implementation status | **Phases 2–4 implemented**: Input Adapter Contract, `CanonicalAFMDataset`, processing pipeline, `AFMHeatmapPayloadBuilder`, `AFMWorkspaceStore`/`AFMWorkspaceView`, dispatch/registration, pack/restore, Save to Library. |

---

## Input Adapter Contract

| Field | Detail |
|---|---|
| Accepted file format | Igor Binary Wave (`.ibw`), version 5, little-endian, `NT_FP32` (Float32) numeric type only |
| Parser entry point | `IBWReader.read(_:)` (`Sources/SpinLabApp/AFM/IBW/IBWReader.swift`) — pure byte-level decode, returns `IBWWave`; knows nothing about AFM |
| Adapter entry point | `AFMInputAdapter.build(from:sourceRef:)` (`Sources/SpinLabApp/AFM/AFMInputAdapter.swift`) — converts `IBWWave` → `CanonicalAFMDataset`, performs unit interpretation and channel/provenance extraction |
| Supported wave shape | 2D spatial + 1 channel dimension: `nDim[0]` = fast-scan X, `nDim[1]` = slow-scan Y, `nDim[2]` = channel count (0 or absent treated as 1 channel) |
| Binary layout reference | `BinHeader5` (64 bytes) + `WaveHeader5` (320 bytes to `wData`) = 384-byte header, verified against Igor's own `TN003` reference implementation and cross-checked against real Asylum Research `.ibw` files on this machine (not committed to the repo) |
| Data storage order | Column-major / Fortran order per IBW spec ("row/column/layer/chunk"): linear index `= x + y·nDim[0] + channel·nDim[0]·nDim[1]` |
| Calibration | `sfA[d]·index + sfB[d]` per dimension (`d=0` → X, `d=1` → Y), read directly from `WaveHeader5` |
| Channel labels | IBW dimension labels for dimension 2 (`dimLabelsSize[2]` / 32-byte fixed blocks in v5); label index 0 = whole-dimension label (ignored), labels 1…N = per-channel labels (`sourceIndex = label index − 1`) |
| Channel semantic type | Parsed from the IBW wave note's `Channel<N>DataType` fields (1-based `N`) — see `AFMNoteFields` |
| Provenance | IBW wave note's `Planefit <n>` / `PlanefitOrder <n>` / `FlattenOrder <n>` / `Planefit Offset <n>` / `Planefit X Slope <n>` / `Planefit Y Slope <n>` fields (0-based `<n>` = `sourceIndex`) |
| Unsupported input | Non-v5 version, big-endian byte order, non-Float32 numeric type, checksum mismatch, malformed/inconsistent dimensions, channel label count mismatch, missing spatial calibration — each raises a distinct `IBWReadError` case; no silent reinterpretation |
| Preview thumbnails | Never read as scientific data — V1 only reads the wave's own numeric data array |

---

## Canonical Dataset

See `docs/architecture/workbench/datasets/AFMDatasetContract.md` for the full `CanonicalAFMDataset`
/ `CanonicalAFMChannel` contract, unit-interpretation policy, and channel-identity rules. Summary:

- X/Y coordinates: explicit arrays in µm.
- Channel values: `values[y][x]`, converted to nm when the source unit is a recognized length
  unit (µm/mm/cm/m/nm/Å), otherwise passed through unchanged with `canonicalUnit == sourceUnit`.
- Channel identity (`CanonicalAFMChannel.id`) is derived from `sourceIndex` + `sourceLabel`,
  never from the (later user-editable) `displayLabel`.

## Channel Resolution Policy

`AFMChannelResolver.resolveDefaultChannel(in:)`:

1. First channel whose semantic type case-insensitively equals `"Height"`.
2. Otherwise, first channel whose `sourceLabel` contains `"height"` (case-insensitive).
3. Otherwise, the first available channel, with a warning.
4. No channels: no default, warning only.

The representative probed file (`HeightRetrace`/`DeflectionRetrace`/`ZSensorRetrace`, semantic
types `Height`/`Deflection`/`ZSensor`) resolves to `HeightRetrace` via rule 1.

Changing the active channel in the UI (Phase 4) never re-reads the source file — it reprocesses
from the already-parsed, immutable `CanonicalAFMDataset`.

---

## Processing (Phase 3 — implemented)

`AFMProcessingConfiguration` (`Sources/SpinLabApp/AFM/Processing/AFMProcessingConfiguration.swift`):

| Field | Type | Default |
|---|---|---|
| `activeChannelID` | `String` (matches `CanonicalAFMChannel.id`) | resolved via channel policy above |
| `planeLevelEnabled` | `Bool` | `false` |
| `lineFlattenOrder` | `AFMLineFlattenOrder` (`.off`/`.order0`/`.order1`/`.order2`) | `.off` |
| `zeroReference` | `AFMZeroReference` (`.none`/`.mean`/`.minimum`) | `.none` |

Pipeline (every reprocess starts from the immutable source channel matrix — never from the
previous UI/render state):

```
source selected-channel matrix
    ↓ Plane Level (least-squares first-order plane, finite pixels only), if enabled
    ↓ Line Flatten (per-row polynomial vs. actual X coordinates, order 0/1/2), if enabled
    ↓ Zero Reference (subtract mean or minimum of finite pixels), if enabled
ProcessedAFMChannel
    ↓
HeatmapPlotPayload (AFMHeatmapPayloadBuilder)
```

Source `Planefit`/`Flatten` provenance from the IBW note is surfaced via `CanonicalAFMChannel.
provenance` (run trace wiring is Phase 4) but is never read by `AFMProcessingPipeline` or used to
seed `AFMProcessingConfiguration` defaults — SpinLab's own leveling/flattening always starts off
regardless of what the instrument reports having done at scan time.

Implementation notes:

- `LinearSystemSolver` (Gaussian elimination with partial pivoting) is shared by Plane Level (3
  unknowns: a, b, c) and Line Flatten (1–3 unknowns depending on order); both build normal
  equations from actual coordinates, not pixel index, and treat a singular/degenerate system as
  "insufficient data" (warning, values left unchanged) rather than crashing.
- `AFMProcessingPipeline.process(channel:xCoordinates:yCoordinates:configuration:)` always takes
  the immutable `CanonicalAFMChannel` as input — callers (Phase 4 workspace store) must never
  chain a previous `ProcessedAFMChannel` back in, which is what keeps repeated toggling
  non-compounding.

## Heatmap Payload Mapping (Phase 3 — implemented)

`AFMHeatmapPayloadBuilder` (`Sources/SpinLabApp/Workbench/V3/Heatmap/AFM/`, mirroring
`RSMHeatmapPayloadBuilder`'s placement): `CanonicalAFMDataset` + `ProcessedAFMChannel` → direct
`HeatmapPlotPayload` (no grid-fitting needed — AFM data is already a dense rectangular matrix).
Default X/Y labels are in µm; default Z/colorbar label is `"<channel display label> (<canonical
unit>)"` (e.g. `"HeightRetrace (nm)"`), each overridable via `Options`. Heatmap owns all
rendering; no AFM conditional branches exist in Heatmap renderer/pipeline/layout/Z-domain code —
`AFMHeatmapPayloadBuilder` and everything above it in `Sources/SpinLabApp/AFM/` are the only AFM
code that exists so far, and neither is imported by any Heatmap-module file.

## Workspace / UI (Phase 4 — implemented)

`AFMWorkspaceStore` (`Sources/SpinLabApp/Features/Workbench/AFMWorkspaceStore.swift`) +
`AFMWorkspaceView`, following RSM's structure exactly (shared search, single selected-hit
snapshot, Analyze lifecycle, warning/status area, plot canvas, Save, Pack/Restore, common
Heatmap controls). Registered through the five standard surfaces (see
`docs/architecture/workbench/ADDING_WORKFLOW.md`): `WorkflowKey.afm`, `WorkbenchWorkflowKind.afm`,
`WorkflowWorkspaceRegistry` left/right dispatch, `WorkbenchFeatureStore.afmWorkspace` +
`workflowKind(for:)`, and `WorkbenchMainSearchRuntime`'s per-workflow search-result mirrors.

`AFMPlotControls` (channel picker, Plane Level toggle, Line Flatten order picker, Zero
reference picker) mounts through the generic Heatmap plugin-controls slot
(`HeatmapPlotControlsPanel.pluginControls`, added in Phase 1B) via
`WorkbenchPlotControlsPluginSection` + `ControlRow` — no AFM-specific width constants or layout
experiments in Heatmap itself. `AFMWorkspaceStore.updateActiveChannel`/`updatePlaneLevelEnabled`/
`updateLineFlattenOrder`/`updateZeroReference` all reprocess from the immutable `parsedDataset`
and never re-read the source file; Heatmap display-only controls share the same
`reprocessAndRerender()` path (never mutating `AFMProcessingConfiguration`).

## Pack / Save (Phase 4 — implemented)

`AFMPackConfig`/`AFMPackState` persist selected channel identity + `AFMProcessingConfiguration`
+ `HeatmapTabRenderState` + search/selection state, matching the other five workflows' pack
convention exactly. `AFMPackResult` carries the full `CanonicalAFMDataset` (Codable), so
`restoreFromPack` never re-reads or re-parses the source `.ibw` file — it reprocesses the
restored dataset with the restored `AFMProcessingConfiguration` and rerenders. Both
`AFMPackState.processingConfiguration` and `AFMProcessingConfiguration` itself decode old/missing
fields to V1 defaults via a custom `Decodable` initializer (not the synthesized one, which would
require every key present).

Save to Library reuses the RSM save pattern verbatim: `AFMSaveProjection` +
`SaveAFMChartToLibraryUseCase` mirror `RSMSaveProjection`/`SaveRSMChartToLibraryUseCase` (same
underlying Library artifact/index primitives), attaching workflow-owned metadata (channel
identity, semantic type, processing configuration) into `semanticParams` without teaching the
common Save module (`SaveActiveChartToLibraryUseCase`) any AFM semantics.

## Run Trace / Warnings (Phase 4 — implemented)

`AFMWorkspaceStore.buildRunTrace()` records: source file, active channel ID + source label +
semantic type, source Planefit provenance (when present), and the current Plane Level / Line
Flatten / Zero Reference settings. Warnings (no Height channel found, IBW parse errors,
insufficient-finite-points fit skips) flow through the shared `WorkbenchWarningLog`, which already
coalesces identical source+message pairs — so a repeated Line Flatten warning across many rows is
one aggregated entry (see `AFMLineFlattenProcessor`), not one per row.

## Deferred (Out of Scope for V1)

Mouse/ROI-based interaction, ROI-specific Plane Level, crop, masks, despike, FFT filtering,
line-profile interaction, grain analysis, Ra/Rq ROI analysis, multiple simultaneous AFM maps,
comparison panels, AFM-specific renderer/canvas — all deferred to a future generic Heatmap
Interaction architecture gate (see task acceptance criteria "Out of Scope for AFM V1").

---

## Code Map

- `Sources/SpinLabApp/AFM/IBW/IBWReader.swift` - native Igor Binary Wave v5 byte-level decoder, AFM-agnostic
- `Sources/SpinLabApp/AFM/CanonicalAFMDataset.swift` - immutable canonical AFM dataset/channel/provenance contract
- `Sources/SpinLabApp/AFM/AFMInputAdapter.swift` - converts a parsed IBW wave into a unit-explicit `CanonicalAFMDataset`
- `Sources/SpinLabApp/AFM/AFMLengthUnit.swift` - IBW length-unit string to meters conversion
- `Sources/SpinLabApp/AFM/AFMNoteFields.swift` - parses IBW wave note key:value fields (channel semantic type, Planefit/Flatten provenance)
- `Sources/SpinLabApp/AFM/AFMChannelResolver.swift` - default active-channel resolution policy (Height-first)
- `Sources/SpinLabApp/AFM/Processing/AFMProcessingConfiguration.swift` - user-controlled Plane Level/Line Flatten/Zero Reference state
- `Sources/SpinLabApp/AFM/Processing/AFMProcessingPipeline.swift` - deterministic source-to-`ProcessedAFMChannel` pipeline
- `Sources/SpinLabApp/AFM/Processing/AFMPlaneLevelProcessor.swift` - least-squares first-order plane leveling
- `Sources/SpinLabApp/AFM/Processing/AFMLineFlattenProcessor.swift` - per-row polynomial line flattening
- `Sources/SpinLabApp/AFM/Processing/AFMZeroReferenceProcessor.swift` - mean/minimum zero-reference subtraction
- `Sources/SpinLabApp/AFM/Processing/LinearSystemSolver.swift` - shared small dense linear-system solver for the two fits above
- `Sources/SpinLabApp/AFM/Processing/ProcessedAFMChannel.swift` - processing pipeline output contract
- `Sources/SpinLabApp/Workbench/V3/Heatmap/AFM/AFMHeatmapPayloadBuilder.swift` - AFM dataset/processed channel to `HeatmapPlotPayload` mapping
- `Sources/SpinLabApp/Workbench/V3/Heatmap/AFM/AFMPackState.swift` - AFM pack-persisted channel/processing state
- `Sources/SpinLabApp/Workbench/V3/Heatmap/AFM/AFMSaveProjection.swift` - AFM Save-to-Library metadata projection
- `Sources/SpinLabApp/Features/Workbench/AFMWorkspaceStore.swift` - AFM workflow workspace store owning analysis, processing, pack, and render state
- `Sources/SpinLabApp/Features/Workbench/AFMWorkspaceView.swift` - AFM workflow shell view mounting the Heatmap plugin controls
- `Sources/SpinLabApp/Features/Workbench/AFMPlotControls.swift` - AFM's channel/Plane-Level/Line-Flatten/Zero plugin controls
- `Sources/SpinLabApp/UseCases/SaveAFMChartToLibraryUseCase.swift` - AFM-specific Save-to-Library use case (mirrors RSM's)
- `Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift` - workflow registration, routing, and shared search/plot ownership for AFM
- `Sources/SpinLabApp/App/State/WorkbenchMainSearchRuntime.swift` - main search orchestration and AFM search mirror sync
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift` - dispatches `AFMWorkspaceView` for `afm`
