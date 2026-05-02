# Workbench — Workflow Contracts

> Workflow layer: 3-Omega AHE / AMR-PHE / XY Rotation 各自的 ingestion / pack / tag normalization / semantic identity。

## Workflow ID Mapping

| Old ID | New ID | Workflow |
|--------|--------|----------|
| `A` | `ahe` | AMR/PHE (Anomalous Hall Effect) |
| `B` | `3w` | 3 Omega |

Pre-v4.1.3 `"A"` / `"B"` IDs in sidecar files or persisted JSON are legacy artifacts. No backward-compatibility code exists — replace with new IDs.

Search accepts both old and new IDs as query aliases; all persisted data uses new IDs only.

## 3-Omega AHE

**Ingestion**: search hits → `IngestThreeOmegaSelectionsUseCase` → `ThreeOmegaIngestionResult` (Codable, Hashable, Sendable).

**Pack contract**:
- `ThreeOmegaPackConfig` — UI state snapshot (tab, fit ranges, style params, series order)
- `ThreeOmegaPackResult` — must include `ingestionResult`; restore rerenders without re-ingestion

**Tag normalization**: AHE workflow uses raw tag values from sidecar; normalization handled by `AHEAxisDetector` on ingestion.

**Semantic identity**: fit ranges are part of scaling chart semantic identity — different fit configurations produce separate chart entries, not overwrites. (See `ARTIFACT_PERSISTENCE.md` for Pack envelope detail.)

**Physics**: `THREE_OMEGA_PHYSICS.md` — 3ω physical model, Scaling Law derivation, RAHE extraction.

**Core files:**
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift` (1517 lines — ⭐ large file)
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift`
- `Sources/SpinLabApp/UseCases/ThreeOmegaFitUseCase.swift`
- `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift`
- `Sources/SpinLabApp/Workbench/V3/ThreeOmegaPackContracts.swift`

## AMR/PHE

**Ingestion**: search hits → `IngestAHESelectionsUseCase` → `AHEIngestionResult`.

**Pack contract**: `AHEPackConfig` + `AHEPackResult` (must include `ingestionResult`).

**Tag normalization**:
- AMR → `R_xx`
- PHE → `R_xy`

**Core files:**
- `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` (763 lines — ⭐ large file)
- `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift`
- `Sources/SpinLabApp/UseCases/AHEDataParser.swift`
- `Sources/SpinLabApp/UseCases/AHEAxisDetector.swift`
- `Sources/SpinLabApp/UseCases/BuildAHEPlotPayloadUseCase.swift`
- `Sources/SpinLabApp/Workbench/V3/AHEPackContracts.swift`

## XY Rotation

**Ingestion**: search hits → `IngestXYRotationSelectionsUseCase` (if present) → `XYRotationIngestionResult`.

**Pack contract**: `XYRotationPackConfig` + `XYRotationPackResult` (must include `ingestionResult`).

**Tag normalization**:
- `XY_90shift` → workflow=XY + angle_shift=+90deg

**Semantic identity**:
- Default y-axis title: Rxx tab → `"Rxx (Ω)"`, Rxy tab → `"Rxy (Ω)"` — stacked/center info not shown in title.
- Optional auxiliary line at x=180 (toggle in plot controls).

**Core files:**
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` (623 lines)
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift`
- `Sources/SpinLabApp/UseCases/XYRotationDATParser.swift`
- `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift`
- `Sources/SpinLabApp/Workbench/V3/XYRotationPackContracts.swift`

## Code Map

- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift` — 3ω workflow store; coordinates search selection, RT selection, analysis/render state, scaling, overlays, pack restore, and chart persistence
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift` — 3ω workspace view; assembles fit, scaling, geometry, and plot panels
- `Sources/SpinLabApp/UseCases/ThreeOmegaFitUseCase.swift` — runs 3ω curve fitting algorithm and returns fit result for each run
- `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift` — renders all 3ω chart tabs from ingestion/scaling outputs through the shared render pipeline
- `Sources/SpinLabApp/Workbench/V3/ThreeOmegaPackContracts.swift` — pack config and result contracts for the 3ω workflow
- `Sources/SpinLabApp/UseCases/ThreeOmegaLVMParser.swift` — parses LVM files containing 3ω measurement data into structured types
- `Sources/SpinLabApp/UseCases/ThreeOmegaScalingUseCase.swift` — computes thermal conductivity scaling from 3ω fit results
- `Sources/SpinLabApp/UseCases/ThreeOmegaStackOffsetUseCase.swift` — applies per-curve stack offsets to 3ω plot series
- `Sources/SpinLabApp/UseCases/IngestThreeOmegaSelectionsUseCase.swift` — ingests selected files into 3ω analysis via LVM parsing and condition mapping
- `Sources/SpinLabApp/Workbench/V3/ThreeOmegaIngestionContracts.swift` — defines 3ω parsed-file, processed-result, scaling, geometry, and tab contracts
- `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` — AHE workflow store; coordinates ingestion, plot render state, metrics, persistence, packs, and related charts
- `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift` — AHE workspace view; assembles plot controls, metric override panels, and workflow shell content
- `Sources/SpinLabApp/UseCases/AHEDataParser.swift` — parses raw AHE measurement files into structured domain types
- `Sources/SpinLabApp/UseCases/AHEAxisDetector.swift` — detects AHE measurement axes (Rxx/Rxy) from ingested data columns
- `Sources/SpinLabApp/UseCases/BuildAHEPlotPayloadUseCase.swift` — builds plot payload from AHE ingestion results for the plot canvas
- `Sources/SpinLabApp/Workbench/V3/AHEPackContracts.swift` — pack config and result contracts for the AHE workflow
- `Sources/SpinLabApp/UseCases/IngestAHESelectionsUseCase.swift` — ingests selected files into AHE analysis via data parsing and axis detection
- `Sources/SpinLabApp/Workbench/V3/AHEIngestionContracts.swift` — ingestion input contracts and result types for the AHE workflow
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` — XY Rotation workflow store; coordinates ingestion, tab render state, persistence, packs, related charts, and series ordering
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift` — XY Rotation workspace view; assembles Rxx/Rxy tabs and auxiliary line panels
- `Sources/SpinLabApp/UseCases/XYRotationDATParser.swift` — parses DAT files containing XY Rotation measurement data
- `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift` — renders XY Rotation data as Rxx/Rxy chart series for the plot canvas
- `Sources/SpinLabApp/Workbench/V3/XYRotationPackContracts.swift` — pack config and result contracts for the XY Rotation workflow
- `Sources/SpinLabApp/UseCases/XYRotationLVMParser.swift` — parses LVM files containing XY Rotation measurement data
- `Sources/SpinLabApp/UseCases/IngestXYRotationSelectionsUseCase.swift` — ingests selected files into XY Rotation analysis via LVM/DAT parsing
- `Sources/SpinLabApp/Workbench/V3/XYRotationIngestionContracts.swift` — ingestion input contracts and result types for the XY Rotation workflow

- `Sources/SpinLabApp/Features/Workbench/UnitTagEditor.swift` — editor for attaching and editing unit tags on measurement conditions
- `Sources/SpinLabApp/Workbench/V3/ConditionAliasConfig.swift` — per-workflow condition alias configuration for display name remapping
- `Sources/SpinLabApp/Workbench/V3/SeriesOrderAlignHelper.swift` — aligns persisted series order with the current sweep identifiers after re-analysis
