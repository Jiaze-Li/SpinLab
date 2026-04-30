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

**Code Map**:
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

**Code Map**:
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

**Code Map**:
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` (623 lines)
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift`
- `Sources/SpinLabApp/UseCases/XYRotationDATParser.swift`
- `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift`
- `Sources/SpinLabApp/Workbench/V3/XYRotationPackContracts.swift`
