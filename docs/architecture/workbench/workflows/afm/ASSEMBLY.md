# AFM Workflow — Assembly Record

> AFM V1 is a single-file heatmap workflow, architecturally closest to RSM (see
> `docs/architecture/workbench/workflows/rsm/DRAFT_ASSEMBLY.md`). This record tracks the actual
> implementation status — sections marked **(Phase N — not yet implemented)** describe accepted
> design intent, not shipped code; update the status line as each phase lands.

---

## Workflow Identity

| Field | Value |
|---|---|
| Workflow ID | Rule Book AFM workflow id (see `workflow.json`) |
| `WorkbenchWorkflowKind` case | `.afm` (Phase 4 — not yet added) |
| Selection mode | `.single` (see `WorkbenchSelectionMode`) — same policy as RSM |
| Implementation status | **Phases 2–3 implemented**: Input Adapter Contract, `CanonicalAFMDataset`, processing pipeline (Plane Level / Line Flatten / Zero Reference), and `AFMHeatmapPayloadBuilder`. Phase 4 (workspace/UI, pack/save, Rule Book registration) not yet implemented. |

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

## Workspace / UI **(Phase 4 — not yet implemented)**

Planned: `AFMWorkspaceStore` + `AFMWorkspaceView`, following RSM's structure (shared search,
single selected-hit snapshot, Analyze lifecycle, warning/status area, plot canvas, Save,
Pack/Restore, common Heatmap controls). AFM-specific controls (channel picker, Plane Level
toggle, Line Flatten picker, Zero picker) mount through the generic Heatmap plugin-controls slot
(`HeatmapPlotControlsPanel.pluginControls`, added in Phase 1B) via
`WorkbenchPlotControlsPluginSection` — no AFM-specific width constants or layout experiments in
Heatmap itself.

## Pack / Save **(Phase 4 — not yet implemented)**

Planned: AFM Pack Config persists selected channel identity, `AFMProcessingConfiguration`,
`HeatmapTabRenderState`, and search/selection state per the current Workflow Extension pack
convention; Pack Result carries the ingestion/canonical result needed to rerender without
re-parsing the source file. Old/missing optional fields decode to V1 defaults. Save-to-Library
reuses the existing Heatmap/RSM save path; workflow-owned metadata (channel, processing config,
source provenance) is attached without teaching the common Save module any AFM semantics.

## Deferred (Out of Scope for V1)

Mouse/ROI-based interaction, ROI-specific Plane Level, crop, masks, despike, FFT filtering,
line-profile interaction, grain analysis, Ra/Rq ROI analysis, multiple simultaneous AFM maps,
comparison panels, AFM-specific renderer/canvas — all deferred to a future generic Heatmap
Interaction architecture gate (see task acceptance criteria "Out of Scope for AFM V1").
