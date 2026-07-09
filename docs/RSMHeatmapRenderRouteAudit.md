# RSM / Heatmap Render Route Audit

Status: audit only. No rendering behavior, payload construction, renderer code, or test
expectations were changed to produce this document. Follow-up to
`docs/RenderRouteAudit.md` §8.2/§8.4, which already flagged RSM/heatmap as the third
plot-type route (xy / dualAxis / heatmap), and to
`docs/ThreeOmegaTemperatureDependenceDualAxisAudit.md`, the sibling audit for the
dual-axis plot-type route. This is the dedicated audit of RSM/heatmap.

RSM/heatmap is not an exception to the ordinary XY route; it is a separate plot-type
route with different rendering semantics: it renders a 2D x-y grid with z/color-scale
semantics (colormap, color-scale domain, colorbar), rather than one or more line series
against a shared coordinate axis. The ordinary XY cleanup (unifying every xy-plot-kind tab
onto `tabs.buildPipelineInput(...)` → `WorkbenchRenderPipeline.render(...)`) is complete
and does not apply here, because this is a different plot type, not a leftover xy route.

## 1. Route diagram

```
RSMWorkspaceView                                     [RSMWorkspaceView.swift]
  │  mounts HeatmapPlotControlsPanel(hostControls: RSMViewSelector, ...)
  │
User action (file selection / restore / view switch / control edit)
  │
  └─ RSMWorkspaceStore analysis/restore flow
        ├─ RSMDataParser.parse(text:title:sourceRef:)         → CanonicalRSMDataset
        ├─ RSMWorkspaceStore.buildHeatmapPayload(...)          [RSMWorkspaceStore.swift:541]
        │     └─ RSMHeatmapPayloadBuilder.build(from:options:)  [RSMHeatmapPayloadBuilder.swift:41]
        │           → HeatmapPlotPayload (grid, title, xLabel/yLabel/zLabel,
        │              colormapKey defaults to "rsmTurbo")
        │        then applies displayState label/colormap overrides
        └─ RSMWorkspaceStore.renderHeatmap(payload:displayState:globalPlotDefaults:)
              [RSMWorkspaceStore.swift:572]
              └─ HeatmapRenderPipeline.render(Input(...))       [HeatmapRenderPipeline.swift:59]
                    ├─ optional interpolation/smoothing (display-only)
                    ├─ HeatmapZDomainState.resolve(rawValues:) → zRangeClampMin/Max
                    ├─ apply title/xLabel/yLabel/zLabel overrides
                    ├─ HeatmapPlotLayout.compute(...)
                    ├─ HeatmapRenderer().renderPNG(...)          [HeatmapRenderer.swift:30]
                    └─ HeatmapRenderer().renderPDF(...)          [HeatmapRenderer.swift:87]
              → Output(imageData, pdfData, layout)
        └─ store.renderedImageData / store.renderedPdfData assigned
        └─ WorkbenchSaveCoordinating: activeLayout → nil (no hit-testing, V1)
        └─ WorkbenchPlotCanvas displays the image without hit-testing
        └─ WorkbenchGraphicExportArtifacts (pngData/pdfData) feeds Copy PNG / Copy PDF
```

Confirmed by a semantic test already in the suite: `rsmDoesNotOwnHeatmapRendering()`
(`V820RSMWorkflowWiringTests.swift:183-196`) asserts RSM produces only the payload, and
`HeatmapRenderPipeline.render(...)` produces the image — i.e. RSM has no render logic of
its own.

`HeatmapRenderPipeline` does **not** use `tabs.buildPipelineInput(...)` /
`WorkbenchRenderPipeline.render(...)` anywhere. It is the direct structural analog of
`DualAxisRenderPipeline`: same "parallel, not a subclass" doc-comment convention on every
type (`HeatmapRenderPipeline.swift:17`: *"Parallel to WorkbenchRenderPipeline; does not
call or extend it."*; `HeatmapRenderer.swift:7`: *"Parallel to WorkbenchChartRenderer;
must not extend it."*; `HeatmapTabRenderState.swift:3-4`: *"Parallel structure to
TabRenderState — must not extend or inherit from it."*), its own `Input`/`Output`
structs, its own display-state type, invoked directly by the workflow store rather than
through `TabRenderManager`.

## 2. Entry points and call graph

| Piece | Location |
|---|---|
| Workspace store | `RSMWorkspaceStore.swift:24` — doc comment (line 19): "Wires RSMDataParser → RSMHeatmapPayloadBuilder → HeatmapRenderPipeline → WorkbenchPlotCanvas" |
| Payload builder | `Workbench/V3/Heatmap/RSM/RSMHeatmapPayloadBuilder.swift:41` — `build(from:options:)`, `CanonicalRSMDataset` → `HeatmapPlotPayload` |
| Grid/payload types | `Workbench/V3/Heatmap/HeatmapPlotPayload.swift:5` (`HeatmapGrid`), `:35` (`HeatmapPlotPayload`) |
| Render pipeline | `Workbench/V3/Heatmap/HeatmapRenderPipeline.swift:19,59` |
| Renderer | `Workbench/V3/Heatmap/HeatmapRenderer.swift:30` (PNG), `:87` (PDF), `:129` (shared `drawCanvas`) |
| Layout | `Workbench/V3/Heatmap/HeatmapPlotLayout.swift` |
| Color scale | `Workbench/V3/Heatmap/HeatmapColorScale.swift` — `viridis` (9-stop) and `rsmTurbo` (17-stop, non-uniform spacing to preserve Bragg-peak contrast), unknown key falls back to `.viridis` |
| Z-domain (range clamping) | `Workbench/V3/Heatmap/HeatmapZDomain.swift` |
| Per-tab display state | `Workbench/V3/Heatmap/HeatmapTabRenderState.swift:7` |
| Controls UI | `HeatmapPlotControlsPanel.swift`, `HeatmapColorScaleControls.swift`, `HeatmapZRangeControl.swift`, `HeatmapZLabelControl.swift`, `HeatmapInterpolationControls.swift`, `RSM/RSMViewSelector.swift` |
| Save/export | `SaveRSMChartToLibraryUseCase.swift`, `RSM/RSMSaveProjection.swift` |

## 3. Payload/data construction

`HeatmapGrid` (`HeatmapPlotPayload.swift:5-31`): `xValues: [Double]`, `yValues: [Double]`,
`zMatrix: [[Double]]` (row-major, row↔yValues, col↔xValues). `RSMHeatmapPayloadBuilder`
requires an exact rectangular grid (`pointCount == nX * nY`, throws `.irregularGrid`
otherwise) and rejects duplicate (x, y) cells the same way. Axis selection (`hl`/`kl`/
`hk`) comes from `RSMView`; the third axis is held fixed. Default `colormapKey =
"rsmTurbo"`; `zLabel` defaults from `dataset.detectorColumnName` unless overridden.

## 4. Renderer

`HeatmapRenderer` is pure CoreGraphics/CoreText/ImageIO (no SwiftUI/AppKit dependency),
structurally identical in pattern to `DualAxisChartRenderer`: `renderPNG` and `renderPDF`
both call the same private `drawCanvas(...)` — PNG rasterizes into a `CGBitmapContext`,
PDF opens a `CGContext(consumer:mediaBox:)` PDF context. The PDF doc comment
(`HeatmapRenderer.swift:81-86`) is explicit that this is true vector output: every grid
cell, axis tick, and colorbar strip is a real fill/stroke path, not a raster image wrapped
in a PDF container.

## 5. Display override support matrix

| Control | Mechanism | Status |
|---|---|---|
| Title | `HeatmapTabRenderState.titleOverride` → pipeline `Input.titleOverride` | Works |
| X-axis label | `.xLabelOverride` | Works |
| Y-axis label | `.yLabelOverride` | Works |
| Colorbar/Z label | `.zLabelOverride`; defaults via `RSMWorkspaceStore.publicationZLabel(for:)` ("Detector" → "Intensity (counts)") | Works |
| X/Y axis ranges | No override exists anywhere in `HeatmapTabRenderState`/`Input` | **Not implemented** — by design; grid extents are purely data-derived, no manual-clamp analog exists for X/Y (unlike Z) |
| Z-range / color-scale clamping | `HeatmapZDomainState`: `auto` / `manual` (explicit min/max) / `percentile` (presets 0.5-99.5 … 5-95, or custom) | Works, validated (`invalidZRangeClamp` error on bad input) |
| Tick counts (X, Y) | `xTickCount`/`yTickCount` via shared `PlotTickConfiguration`, clamped 2…20 | Works |
| Colormap choice | `colormapKey` override in display state; precedence: override > payload default (`"rsmTurbo"`) > `viridis` fallback | Works, correct precedence |
| Colorbar visibility | `showColorbar: Bool` | Works |
| Colorbar/legend position | Fixed — always right of the grid, no position/anchor control was ever offered in the UI | **Not configurable** — a known V1 limitation, not a regression (no affordance was ever promised) |
| Interpolation/smoothing (display-only) | `HeatmapInterpolationMode`: `.nearest` (default) / `.logSpaceGaussian1p5x` (opt-in) | Works, explicitly documented as display-only, never mutates stored data |
| PNG export | `HeatmapRenderer.renderPNG` → `renderedImageData` → `activeChartPNG` | Works |
| PDF/vector export | `HeatmapRenderer.renderPDF` → `renderedPdfData` → `activePdfData` | Works |
| Hidden series / series order | N/A — single grid, no series concept | Not applicable |
| Hit-testing / legend drag | `activeLayout` is hard-coded `nil` (`RSMWorkspaceStore.swift:407`); `WorkbenchPlotCanvas` comment: "display image without hit-testing (heatmap V1 path)" | Not applicable in V1 — intentional, documented |

## 6. Obsolete test-only entry points

Grepped every `render*` method under the Heatmap/RSM source tree:

```
HeatmapRenderer.swift:30    func renderPNG(...)
HeatmapRenderer.swift:87    func renderPDF(...)
HeatmapRenderer.swift:435   static func renderedZLabel(...)
HeatmapPlotLayout.swift:279 static func renderedZLabel(...)
HeatmapRenderPipeline.swift:59 static func render(_ input: Input)
RSMWorkspaceStore.swift:572 nonisolated private static func renderHeatmap(...)
```

None are dead. There is no `renderRAHE`/`renderScaling`-style obsolete entry point here —
unlike ThreeOmega, RSM was built directly on `HeatmapRenderPipeline` from the start, so
there was never a workflow-owned custom renderer predating it to clean up.

## 7. Stale test check

Searched for source-text/characterization-style tests (matching the dual-axis `pdfData`
stale-test pattern: tuple-destructure or function-signature substring assertions) across
RSM/Heatmap:

- `V825HeatmapTabRenderStatePersistenceTests.swift:542-554` ("HeatmapPlotLayout uses
  tickConfiguration target counts") reads `HeatmapPlotLayout.swift` off disk and checks
  loose substrings (`"tickConfiguration"`, `"xTargetCount"`, `"yTargetCount"`).
  Cross-checked against current `HeatmapPlotLayout.swift:32,83-84` — **still accurate**,
  not stale. It's also a much less brittle style than the dual-axis tuple-destructure
  check (no exact signature match), so it's less likely to go stale on unrelated
  refactors.
- `V823RSMPackRestoreRuntimeTests.swift:396` / `V822RSMRestoreIntegrationTests.swift:339`
  use `String(contentsOfFile:...)` only to load real RSM data fixtures for restore-flow
  testing, not as Swift-source characterization — unrelated pattern.
- `V820RSMWorkflowWiringTests.swift:183-196` (`rsmDoesNotOwnHeatmapRendering`) is a
  semantic test (real payload/grid/image assertions), the style the dual-axis audit
  recommends over source-text matching — already the norm here.

No stale tests found requiring a fix.

**Test run results** (verbatim):

```
swift test --filter 'RSM'      → Test run with 132 tests in 10 suites passed after 0.343 seconds.
swift test --filter 'Heatmap'  → Test run with 187 tests in 12 suites passed after 0.226 seconds.
```

## 8. Classification

| Item | Classification |
|---|---|
| Render route classification | **Separate plot-type route** — the heatmap plot type (xy / dualAxis / heatmap), `HeatmapRenderPipeline` structurally parallel to `DualAxisRenderPipeline`, neither uses the shared XY pipeline. Not an xy-cleanup exception. |
| PNG / PDF (vector) export | Works correctly |
| Title / axis / colorbar label overrides | Works correctly |
| Z-range clamping, tick counts, colormap choice, colorbar visibility | Works correctly |
| X/Y axis range override | Known limitation — not implemented, no analog exists (data-derived grid extents) |
| Colorbar position control | Known limitation — fixed right-of-grid, no UI ever offered otherwise |
| Hit-testing / legend drag | Not applicable in V1 — intentional, documented |
| Dead/obsolete render entry points | None found |
| Stale characterization tests | None found |

## 9. Recommended next steps

1. **Minimal bug fix**: none required.
2. **Test update**: none required — no stale tests found.
3. **Shared route migration**: not recommended. Heatmap is a structurally different plot
   kind (2D grid + colorbar vs. line series on a coordinate axis); forcing it through
   `WorkbenchRenderPipeline` would not reduce complexity, only add an adapter layer for a
   route already correctly isolated. Matches the existing conclusion in
   `docs/RenderRouteAudit.md` §8.2/§8.4.
4. Two known, intentional V1 limitations are worth keeping on the product radar
   (not urgent, not bugs): no manual X/Y axis range override, and colorbar position is
   fixed. Both are things Jack may eventually want as product features, not code issues.

This closes out the third and last item from `docs/RenderRouteAudit.md`'s three-plot-type
model (xy — unified; dualAxis — audited in
`docs/ThreeOmegaTemperatureDependenceDualAxisAudit.md`; heatmap — audited here). All three
are confirmed to be separate plot-type routes with different rendering semantics, not
xy-cleanup exceptions, and no accidental bypass of shared controls was found in any of
them.
