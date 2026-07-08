# Heatmap Render Path Contract

## Purpose

Heatmap is the Plot System render path for grid / Z-value plots. It is parallel to the Cartesian XY render path and DualAxis render path.

This document keeps the heatmap-specific contract out of `PLOT_SYSTEM.md` so the Plot System entry document stays readable.

## Ownership

| Plot System owns | Workflow Assembly owns |
|---|---|
| `HeatmapPlotPayload` type definition | scientific grid construction |
| `HeatmapRenderPipeline` | X/Y/Z physical labels and units |
| `HeatmapRenderer` | workflow-specific analysis and warnings |
| `HeatmapPlotLayout` | workflow-specific pack/save metadata |
| `HeatmapColorScale` and colorbar geometry | workflow-specific view selection |
| heatmap display state / heatmap controls | workflow-specific controls mounted through host slots |

RSM is the first workflow to produce heatmap output, but Heatmap is not an RSM module. Future workflows may reuse the same heatmap path by filling a `HeatmapPlotPayload`.

## Parallel-Path Rule

Heatmap must not extend or repurpose Cartesian XY types:

- do not add heatmap fields to `WorkbenchPlotPayload`;
- do not branch `WorkbenchRenderPipeline` for heatmap data;
- do not pass fake `WorkbenchPlotLayout` values to the shared canvas;
- do not store heatmap-only fields in Cartesian XY `TabRenderState`.

The boundary between workflow analysis and Plot System rendering is `HeatmapPlotPayload`.

## Pipeline

```text
Workflow analysis result
→ workflow heatmap payload builder
  [Assembly-owned scientific semantics]
→ HeatmapPlotPayload
  [Plot System contract]
→ HeatmapRenderPipeline
  [display overrides → colormap → Z range → layout → PNG]
→ HeatmapRenderer + HeatmapPlotLayout
→ PNG Data
→ shared plot canvas as PNG display shell
→ copy / save / pack restore path
```

## Display State

Heatmap display overrides must live in a heatmap-specific state type, not in Cartesian XY `TabRenderState`.

Current state fields include:

- title override,
- X label override,
- Y label override,
- Z/colorbar label override,
- color scale mode,
- colormap key,
- optional Z range override.

The rendered PNG and `HeatmapPlotLayout` are re-derived on restore and are not serialized as canonical display state.

## Controls

Heatmap controls belong to the heatmap render path, not to RSM.

Heatmap controls may know heatmap geometry:

- colormap;
- Z/colorbar label;
- color scale mode;
- manual Z range.

They must not know RSM view semantics, surface-fit parameters, or RSM dataset compatibility. Workflow-specific controls enter through explicit host-control slots.

## Canvas Rule

The shared canvas is reused as a PNG display shell. For the current heatmap scope:

- pass heatmap PNG/PDF data through the shared `WorkbenchGraphicExportArtifacts` envelope (see `modules/PLOT_SYSTEM.md`'s Copy Graphic Artifact Contract);
- pass Cartesian XY layout as nil;
- disable XY-only interactions such as legend drag and point labels;
- keep Copy PNG and Copy PDF available. `HeatmapRenderer.renderPDF(...)` reuses the same `drawCanvas(...)` path as `renderPNG(...)` — every grid cell, tick, and colorbar strip is a real PDF path/fill, so this is true vector output, not a raster heatmap wrapped in a PDF container. `HeatmapRenderPipeline.Output.pdfData` carries it; RSM stores it in `renderedPdfData` beside `renderedImageData`.

Any future heatmap hit-testing needs a real heatmap layout contract or a dedicated heatmap canvas. Do not fake XY layout to unlock interactions.

## Save / Pack Rule

- Workflow pack state owns analysis provenance needed to re-derive the grid.
- Heatmap display state owns display overrides only.
- Save-to-library receives workflow-supplied metadata and metrics; common save code must not infer heatmap physics.

## Tests To Protect This Contract

- payload Codable round-trip;
- linear and log color-scale mapping;
- colorbar tick generation;
- renderer non-empty PNG;
- XY renderer regression unchanged;
- canvas smoke test with heatmap image and nil XY layout;
- heatmap display state does not pollute Cartesian XY `TabRenderState`.
