# IV Render Route Audit — Obsolete Renderer Entry Point Cleanup

Status: audit + migration plan for the two obsolete IV `PlotRenderer` entry points
flagged in `docs/RenderRouteAudit.md` §8.4. Same template as
`docs/XYRotationRenderRouteAudit.md` and the ThreeOmega field-sweep cleanup.

## 1. Obsolete entry points

- `IVPlotRenderer.renderFirstHarmonicVsCurrent` (+ backward-compatible alias
  `renderVoltageVsCurrent`)
- `IVPlotRenderer.renderSecondHarmonicVsCurrent` (+ backward-compatible alias
  `renderResistanceVsCurrent`)

Runtime (`IVWorkspaceStore._rerenderActiveTab` / `_refreshManifestPayloads`-equivalent
loop over `IVWorkbenchTab.allCases`) already builds payloads via
`makeFirstHarmonicPayloads`/`makeSecondHarmonicPayloads` and renders through
`tabs.buildPipelineInput(...)` → `WorkbenchRenderPipeline.render(...)` — the shared xy
route. `rg` across `Sources/SpinLabApp/Features/Workbench` for the four names above
returns zero hits; the four functions are reachable only from tests.

## 2. Call-site classification

`rg -n "renderFirstHarmonicVsCurrent\(|renderSecondHarmonicVsCurrent\(|renderVoltageVsCurrent\(|renderResistanceVsCurrent\(" Sources Tests`
(pre-cleanup) hits, classified:

| File | Line(s) | Classification | Disposition |
|---|---|---|---|
| `IVPlotRenderer.swift` | 61, 82, 86, 118, 141, 145 | definition only | delete |
| `V565IVSeriesOrderTests.swift` | 104, 127, 149, 172 | test call protecting useful behavior (series order / chip-legend-display alignment / hidden-filtering / warnings) | migrate to shared-route helper |
| `V565HiddenSeriesStackingTests.swift` | 195 | test call protecting useful behavior (hidden-filter stack compaction) | migrate to shared-route helper |
| `V536CurveDragOrderTests.swift` | 856 | test call protecting useful behavior (sourceRef reorder + pipeline-level legend warning) | migrate to shared-route helper |
| `V81IVParserChannelMappingTests.swift` | 182, 187 (`plotRendererRendersCartesianOutput`) | test call protecting useful behavior (actual imageData/layout existence) | migrate to shared-route helper |
| `V81IVParserChannelMappingTests.swift` | 160, 202, 224, 253, 276 | payload/data-only assertions (metadata, axis label, x-scaling, title, series y) that don't need a real render — obsolete *route*, not obsolete *coverage* | switch to `makeFirstHarmonicPayload`/`makeSecondHarmonicPayload` (or `makeFirstHarmonicPayloads`/`makeSecondHarmonicPayloads` where hidden-series filtering matters) |
| `V556IVLabelMigrationRegressionTests.swift` | 36, 37 (`renderResistanceVsCurrentMatchesSecondHarmonicVoltage`) | obsolete implementation-detail test — only proves the legacy alias forwards to `renderSecondHarmonicVsCurrent`, an invariant about the soon-to-be-deleted wrapper itself | delete |

No comment/doc-only hits (aside from this audit and `docs/RenderRouteAudit.md` §8.4,
which already describe the entry points by name).

## 3. Migration approach

Mirrors `XYRotationRenderRoute` (`Tests/SpinLabAppTests/Support/XYRotationRenderRouteHelper.swift`):
a test-only `IVRenderRoute` enum wrapping
`makeFirstHarmonicPayloads`/`makeSecondHarmonicPayloads` →
`TabRenderManager<IVWorkbenchTab>.buildPipelineInput` → `WorkbenchRenderPipeline.render`,
returning the same `(Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String])` shape
the obsolete entry points returned (IV's tuple has no separate `pdfData` slot, unlike
ThreeOmega/XYRotation's 5-tuple).

## 4. Post-deletion verification

`rg -n "renderFirstHarmonicVsCurrent\(|renderSecondHarmonicVsCurrent\(|renderVoltageVsCurrent\(|renderResistanceVsCurrent\(" Sources Tests`
must show zero production definitions and zero real call sites (only the
`IVRenderRoute` helper's own method names, if reused verbatim).
