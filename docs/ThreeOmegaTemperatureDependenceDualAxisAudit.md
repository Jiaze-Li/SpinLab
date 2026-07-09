# ThreeOmega Temperature Dependence Dual-Axis Route Audit

Status: audit only. No rendering behavior, payload construction, renderer code, or test
expectations were changed to produce this document. Follow-up to
`docs/ThreeOmegaRemainingRenderRouteAudit.md` §1/§7, which confirmed
`renderTemperatureDependence` was left untouched by the RAHE/Hc/RT/Scaling cleanup because
it does not use the same shared-XY infrastructure. This document is the dedicated audit of
that route.

Temperature-dependence dual-axis is not an exception to the ordinary XY route; it is a
separate plot-type route with different rendering semantics: two Y axes with independent
scales sharing one X axis, rather than one Y axis. The ordinary XY cleanup (unifying every
xy-plot-kind tab onto `tabs.buildPipelineInput(...)` → `WorkbenchRenderPipeline.render(...)`)
is complete and does not apply here, because this is a different plot type, not a leftover
xy route.

## 1. Route diagram

```
User action (analysis run / control edit)
  │
  ├─ renderThreeOmegaTab(.temperatureDependence, ...)
  │     [ThreeOmegaWorkspaceStore+Rendering.swift:406-421]
  │     preparedRender = .dualAxis(scalingResult)
  │       └─ Task.detached
  │            └─ renderer.renderTemperatureDependence(
  │                   result: scalingResult,
  │                   displayState: temperatureDependenceDisplayState.snapshot(),
  │                   legendPoint: tabSnapshot.legendPoint
  │               )                              [ThreeOmegaPlotRenderer+DualAxis.swift:8]
  │                 ├─ makeTemperatureDependencePayload(result:)   [ThreeOmegaPlotRenderer.swift:556]
  │                 ├─ title via WorkbenchTitleResolver (falls back to
  │                 │   "Temperature Dependence" if empty)
  │                 └─ DualAxisRenderPipeline.render(Input(...))  [DualAxisRenderPipeline.swift:27]
  │                       ├─ payload = displayState.applying(to: payload)
  │                       ├─ per-series finite/count validation → warnings
  │                       ├─ DualAxisPlotLayout.compute(...)
  │                       ├─ DualAxisChartRenderer().renderPNG(...)
  │                       └─ DualAxisChartRenderer().renderPDF(...)
  │       └─ TabRenderOutput(renderKind: .dualAxis, dualAxisLayout:, dualAxisPayload:,
  │              imageData:, pdfData:)   [manifestPayload/displayPayload/layout all nil]
  │       └─ tabs.setOutput(output, for: .temperatureDependence, policy:)
  │
  └─ rerenderTemperatureDependenceForDualAxisControlChange()
        [ThreeOmegaWorkspaceStore+DualAxisControls.swift, whole file]
        (fired on any DualAxis-only control edit: title template, label override,
        axis range, tick count, series style, axis-color policy, legend drag)
        — bypasses renderThreeOmegaTab entirely, but converges on the exact same
        renderer.renderTemperatureDependence(...) → tabs.setOutput(...) sequence.
```

Two independent entry points exist (full re-render vs. live control-only re-render), and
both converge on the same renderer call and the same `DualAxisRenderPipeline`. Neither
uses `tabs.buildPipelineInput(...)` or `WorkbenchRenderPipeline.render(...)` — the shared
XY route every other visible ThreeOmega tab now uses.

## 2. Entry points and call graph

| Piece | Location |
|---|---|
| Tab identity | `ThreeOmegaWorkbenchTab.swift:14,30,47` — `.temperatureDependence`, stableKey `"temperatureDependence"` |
| Live display state | `ThreeOmegaWorkspaceStore.swift:196` — `temperatureDependenceDisplayState: DualAxisDisplayState`, stored separately from the generic per-tab `TabRenderState` |
| Legend drag geometry | `ThreeOmegaWorkspaceStore.swift:303-304` — reads `tabs.output(for: .temperatureDependence).dualAxisLayout?.legendDragGeometry`, not the generic `WorkbenchPlotLayout` path |
| Full re-render | `ThreeOmegaWorkspaceStore+Rendering.swift:79-80, 95-110, 406-421, 424-454, 463-514, 536-549` |
| Control-only re-render | `ThreeOmegaWorkspaceStore+DualAxisControls.swift` (whole file, 68 lines) |
| Runtime renderer overload (5-tuple, has `pdfData`) | `ThreeOmegaPlotRenderer+DualAxis.swift:8-45` |
| Older renderer overload (4-tuple, no `pdfData`) | `ThreeOmegaPlotRenderer.swift:527-554` — dead in production, only referenced by tests |
| Payload builder | `ThreeOmegaPlotRenderer.swift:556-594` — `makeTemperatureDependencePayload(result:)`, shared by both overloads |
| Dual-axis pipeline/types (workflow-agnostic) | `Sources/SpinLabApp/Workbench/Modules/PlotSystem/DualAxis/`: `DualAxisRenderPipeline.swift`, `DualAxisPlotPayload.swift`, `DualAxisPlotLayout.swift`, `DualAxisChartRenderer.swift`, `DualAxisDisplayState.swift`, `DualAxisPlotControlsPanel.swift` |
| Persistence | `Workbench/V3/ThreeOmegaPackContracts.swift:32,48,59,85` — `temperatureDependenceDisplayState: DualAxisDisplayStateSnapshot?`, its own pack field, independent of the generic `WorkbenchTabDisplayStateSnapshot` persistence XY tabs use |

The payload puts exactly one series on each axis: left Y = `E_AHE^(3ω)/E_xx^3` (scaled by
`ThreeOmegaDisplayScale.temperatureDependenceLeftY`), right Y = `σxx` (scaled by
`.temperatureDependenceRightY`), sharing the temperature X axis.

## 3. Current output capabilities

- Produces PNG (`imageData`) and PDF (`pdfData`) via `DualAxisChartRenderer`, both drawn
  from the same private `drawCanvas(...)` so the PDF is a true vector re-draw, not a
  wrapped raster (`DualAxisChartRenderer.swift:61-137`, added in `ec110b0`, "feat: add
  vector Copy PDF export across all Plot System render paths").
- `TabRenderManager.swift:164`'s doc comment still says DualAxis is one of the render
  kinds that "do not yet produce a PDF artifact" — **stale**, predates `ec110b0`.
- `TabRenderManager.makeSeriesControlModel(for:tab:)` returns `nil` whenever
  `output.renderKind == .dualAxis` (`TabRenderManager.swift:859`) — this route never
  populates the generic series-control chip UI.

## 4. Display override support matrix

| Control | Mechanism | Status |
|---|---|---|
| Title | `titleTemplate` → `WorkbenchTitleResolver`, plus `DualAxisDisplayStateSnapshot.titleOverride` | Works |
| X-axis label | `DualAxisDisplayStateSnapshot.xLabelOverride` | Works |
| Left Y-axis label | `.leftYLabelOverride` | Works |
| Right Y-axis label | `.rightYLabelOverride` | Works |
| Axis ranges (X, left-Y, right-Y, independent min/max) | `DualAxisAxisRangeOverride` via a pure reducer that rejects inverted/invalid pairs | Works |
| Tick counts (X, left-Y, right-Y independently) | `chartStyleOverrides["tickTargetX"/"tickTargetLeftY"/"tickTargetRightY"]` — same key-value plumbing XY tabs use | Works |
| Legend position (drag-to-place) | `legendPoint` threaded through both render entry points; geometry read from `dualAxisLayout`, not `WorkbenchPlotLayout` | Works, via a route-specific mechanism |
| Legend position (preset anchor dropdown, as used by XY tabs) | `globalSettings.legendAnchor` | **Ignored** — never consumed by `DualAxisRenderPipeline.Input`/`DualAxisPlotLayout.compute`; unset default is hard-coded to bottom-right |
| Hidden series | `TabRenderState.hiddenSeriesKeys` / chip UI | **Not applicable** — `makeSeriesControlModel` returns `nil` for `.dualAxis`; only 2 fixed series exist (one per axis), no per-series hide concept anywhere in the DualAxis types |
| Series order | `TabRenderState.seriesOrder` | **Not applicable** — same reasoning, no `seriesOrder` concept exists in the DualAxis payload/display-state |
| Series visual style (line width/pattern, marker shape/fill, point radius) | `DualAxisSeriesVisualStyle` per axis | Works — DualAxis-specific, richer per-axis control than generic XY styling |
| Axis color policy (paired vs. monochrome) | `DualAxisAxisColorPolicy` | Works — DualAxis-only, no XY equivalent |
| PNG export | `DualAxisChartRenderer.renderPNG` | Works |
| PDF (vector) export | `DualAxisChartRenderer.renderPDF` | Works (since `ec110b0`) |

## 5. Known failing test analysis

**File**: `Tests/SpinLabAppTests/V5115ThreeOmegaWorkspaceStoreCharacterizationTests.swift`
**Test**: `testTransportDerivedRefreshUsesIngestionResultAndCurrentV3Method()`
**Failing line** (76):

```swift
XCTAssertTrue(tdHelper.contains("let (imageData, layout, payload, warnings) = renderer.renderTemperatureDependence("))
```

This is a literal-source-text characterization test: it reads
`ThreeOmegaWorkspaceStore+DualAxisControls.swift` off disk, extracts
`rerenderTemperatureDependenceForDualAxisControlChange()`'s body by brace matching
(`extractFunction`, lines 236-260), and asserts a substring match against it. No
`XCTExpectedFailure`, skip annotation, or comment marks it as a known/expected failure —
confirmed by running:

```
swift test --filter 'V5115ThreeOmegaWorkspaceStoreCharacterizationTests/testTransportDerivedRefreshUsesIngestionResultAndCurrentV3Method'
→ .../V5115ThreeOmegaWorkspaceStoreCharacterizationTests.swift:76: error: XCTAssertTrue failed
```

**Root cause**: the actual line in `+DualAxisControls.swift:40` is now

```swift
let (imageData, pdfData, layout, payload, warnings) = renderer.renderTemperatureDependence(
```

— a 5-element tuple (gained `pdfData`) since `ec110b0` ("feat: add vector Copy PDF export
across all Plot System render paths", 2026-07-08) updated the call site to destructure
`output.pdfData` alongside the rest. The test's expected 4-element substring was never
updated. A later, unrelated commit (`eceba48`, "Route ThreeOmega field sweeps through
shared input builder", 2026-07-09) touched this same test file for a different reason and
didn't catch the now-stale assertion.

**Classification: stale test, not a real bug and not a route-mismatch artifact.** The
dual-axis PDF export path itself works correctly — `DualAxisRenderPipelineTests`/
`DualAxisRenderPathTests.swift` (which assert on `pdfData` semantically, not by source
string) pass. The fix is mechanical: update the expected substring to include `pdfData`.
Left unfixed per this audit's scope (docs-only; no test or code changes made).

**Adjacent, unrelated findings** (flagged so they aren't mistaken for the one above):
`V78CPlotControlsSpecializationTests` has 2 more currently-failing static-source-text
assertions ("DualAxisPlotControlsPanel.swift stays DualAxis-only", "uses the compact
weighted row layout") plus 2 in "V7.8C XY Rotation standard plot controls path" — these
concern panel-layout/specialization boundaries, not `pdfData`, and are out of scope here.

## 6. Classification summary

| Item | Classification |
|---|---|
| Dual-axis render/export path (PNG + PDF) | Works correctly |
| Title, axis labels, axis ranges, tick counts, legend drag, series style, axis-color policy | Works correctly |
| Legend anchor-preset dropdown | Known limitation — ignored by this route |
| Hidden series / series reorder | Known limitation — not applicable to a fixed 2-series dual-axis payload; no chip UI |
| `TabRenderManager.swift:164` doc comment ("DualAxis... does not yet produce a PDF artifact") | Stale doc, harmless — worth a one-line fix whenever that file is next touched |
| `V5115...testTransportDerivedRefreshUsesIngestionResultAndCurrentV3Method` `pdfData` assertion | Stale test — mechanical fix (add `pdfData` to expected substring) |
| Two independent entry points (`renderThreeOmegaTab` vs. `rerenderTemperatureDependenceForDualAxisControlChange`) converging on one renderer call | Working as designed, but a candidate for consolidation if the shared dual-axis pipeline is ever unified with the XY route |
| Whether to unify into the shared `tabs.buildPipelineInput` / `WorkbenchRenderPipeline` route | Candidate for future work — see §7 |

## 7. Recommended next steps

1. **Minimal bug fix**: none required. No functional bug found in this route.
2. **Test update (stale)**: update the expected substring in
   `V5115ThreeOmegaWorkspaceStoreCharacterizationTests.swift:76` to match the current
   5-element `(imageData, pdfData, layout, payload, warnings)` destructure. Small,
   isolated, no production code touched.
3. **Doc fix (stale)**: correct `TabRenderManager.swift:164`'s comment — DualAxis now
   produces `pdfData`.
4. **Larger shared dual-axis migration (optional, not urgent)**: `DualAxisRenderPipeline`
   is already workflow-agnostic infrastructure parallel to `WorkbenchRenderPipeline`, not
   a ThreeOmega-specific hack. Unifying would mean giving dual-axis tabs a
   `tabs.buildPipelineInput`-equivalent (so hidden-series/series-order/legend-anchor
   concepts either extend to 2-series dual-axis payloads or are explicitly declared N/A
   at the shared-pipeline boundary) and collapsing the two current entry points
   (`renderThreeOmegaTab` case + `rerenderTemperatureDependenceForDualAxisControlChange`)
   into one. This is worthwhile only if another dual-axis tab is added elsewhere in the
   app (currently `temperatureDependence` is the only consumer); with a single consumer,
   the added abstraction cost is not yet justified.

No commands other than the targeted test filter above were run. No product code, test
expectations, or the `TabRenderManager.swift:164` comment were changed in this commit.
