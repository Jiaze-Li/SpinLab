# Render Output Semantics Audit

**Date:** 2026-07-01  
**Scope:** Cartesian XY, DualAxis, Heatmap, pack/export boundaries  
**Purpose:** Lock the current render-output contract for non-XY render kinds and document where export and pack state are owned.

---

## Current Render Kinds

The current implementation exposes these render kinds:

| Render kind | Current owner |
|---|---|
| Cartesian XY | `WorkbenchRenderPipeline` / `TabRenderManager` |
| DualAxis | `DualAxisRenderPipeline` / `DualAxisDisplayStateSnapshot` |
| Heatmap | `HeatmapRenderPipeline` / `HeatmapTabRenderState` |

No other render kind is currently implemented in the Plot System.

---

## Render Output Contract

| Render kind | Payload owner | `manifestPayload` | `displayPayload` | Render artifact references | Pack state owner | Export status |
|---|---|---|---|---|---|---|
| Cartesian XY | Workflow renderer + `TabRenderManager` | Present for persistence / library indexing | Present for export rerendering | `imageData`, `layout`, `manifestPayload`, `displayPayload` | `TabRenderState` via `TabRenderManager` | Full export rerender path via `WorkbenchPlotExportService` |
| DualAxis | 3ω temperature-dependence renderer + `DualAxisRenderPipeline` | `nil` | `nil` | `imageData`, `dualAxisLayout`, `dualAxisPayload` | `DualAxisDisplayState` at runtime; `DualAxisDisplayStateSnapshot` in `ThreeOmegaPackConfig` | Current export falls back to cached PNG; no generic dual-axis export rerender path is wired yet |
| Heatmap | Heatmap / RSM render path + `HeatmapRenderPipeline` | Not part of the current heatmap path | Not part of the current heatmap path | `renderedImageData` in `RSMWorkspaceStore` and `HeatmapRenderPipeline.Output(imageData, layout)` | `HeatmapTabRenderState` in `RSMPackConfig` / `RSMWorkspaceStore` | Current export is direct PNG reuse from the stored rendered image; no `TabRenderOutput` payloads are involved |

---

## Stable Semantics

### Cartesian XY

- May use `WorkbenchPlotPayload` for both manifest and export display paths.
- `manifestPayload` is the persistence / indexing record.
- `displayPayload` is the pre-pipeline payload used to rerender Copy PNG.
- `TabRenderState` owns XY display overrides.

### DualAxis

- `renderKind` must remain `.dualAxis`.
- `manifestPayload` must remain `nil`.
- `displayPayload` must remain `nil`.
- DualAxis state is carried separately through `DualAxisDisplayStateSnapshot` and `ThreeOmegaPackConfig.temperatureDependenceDisplayState`.
- The dual-axis payload is a separate render-path payload and must not be collapsed into `WorkbenchPlotPayload`.

### Heatmap

- Heatmap currently uses its own payload and state contract, not `TabRenderOutput`.
- Heatmap display state is owned by `HeatmapTabRenderState`.
- Heatmap rendering writes the rendered PNG directly to `renderedImageData`.
- The current implementation does not expose a generic `manifestPayload` / `displayPayload` pair for heatmap tabs.

---

## Rules

- Do not copy Cartesian `manifestPayload` or `displayPayload` into DualAxis outputs.
- Do not route DualAxis output through `WorkbenchPlotPayload`.
- Do not route Heatmap output through `TabRenderOutput` unless the render path is explicitly redesigned.
- Do not make non-XY export semantics depend on hidden Cartesian fallback behavior.
- Do not change pack schema or physics to satisfy export convenience.

---

## Validation Coverage

This audit is characterized by:

- `V563WorkflowStateBoundaryTests`
- `V85APackPersistenceGapTests`
- `V820HeatmapRenderPathTests`
- `DualAxisRenderPathTests`

The source of truth for the current runtime semantics remains the implementation files; this document records the current contract only.
