# XYRotation Render Route Audit — renderRxxVsPhi / renderRxyVsPhi

Status: audit only. No rendering behavior, payload construction, or renderer code was
changed to produce this document. Follow-up to `docs/RenderRouteAudit.md` §8.4, which
flagged `XYRotationPlotRenderer.renderRxxVsPhi`/`renderRxyVsPhi` as the same
dead-mutating-renderer pattern already cleaned up for ThreeOmega field sweeps
(`ThreeOmegaFieldSweepRouteAudit.md`).

## 1. Runtime status

`rg -n "renderRxxVsPhi|renderRxyVsPhi" Sources Tests` shows:

- **Zero runtime call sites.** `XYRotationWorkspaceStore` (the only caller of
  `XYRotationPlotRenderer` in `Sources/SpinLabApp/Features/Workbench`) builds both tabs
  via `makeRxxVsPhiPayload`/`makeRxyVsPhiPayload` (manifest) and
  `makeRxxVsPhiDisplayPayload`/`makeRxyVsPhiDisplayPayload` (display), then routes
  through `tabs.buildPipelineInput(...)` + `WorkbenchRenderPipeline.render(...)` —
  confirmed already in `docs/RenderRouteAudit.md` §8.1.
- **Twelve test call sites** across 5 files, all constructing a fresh
  `XYRotationPlotRenderer()` and calling the obsolete mutating entry point directly.
- The production definitions (`XYRotationPlotRenderer.swift:55` `renderRxxVsPhi`,
  `:89` `renderRxyVsPhi`) and one doc comment referencing them (`:116`) are otherwise
  unreferenced from any workspace store.

Unlike the ThreeOmega case, `renderRxxVsPhi`/`renderRxyVsPhi` are the *only* callers of
this file's private `_render`, `_consume`, `_stackedOptions`, and `RenderOutcome` (each
used exactly twice, once per obsolete entry point, per
`rg -n "_consume\(|_render\(|_stackedOptions\(" Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift`).
There is no other still-active XYRotation render+pipeline method sharing this
infrastructure (XYRotation only has two tabs), so once the two obsolete entry points are
deleted, `_render`/`_consume`/`_stackedOptions`/`RenderOutcome` become dead in the same
pass — a smaller, cleaner deletion than the ThreeOmega one (which had to keep `_render`/
`_consume`/`RenderOutcome` alive for RAHE/Hc/RT/Scaling/RAHE-vs-Device).

The public `static func stackedOptions(sweepCount:base:)` is unaffected — the runtime
route and `makeRxxVsPhiDisplayPayload`'s callers already use it directly, exactly like
ThreeOmega's `stackedOptions`.

## 2. Per-test-site classification

Decision rule (same as `ThreeOmegaFieldSweepRouteAudit.md` §10): a test that only
inspects `WorkbenchPlotPayload` content (series order/y-values, warnings produced during
payload construction) migrates to the payload-only accessors
(`makeRxxVsPhiDisplayPayload`/`makeRxyVsPhiDisplayPayload`). A test that inspects `Data`
(PNG bytes) or `WorkbenchPlotLayout` (`legendRows`, etc.) needs an actual pixel render
and migrates to the shared route (`WorkbenchRenderPipeline.Input` built from a display
payload + `XYRotationPlotRenderer.stackedOptions`, then
`WorkbenchRenderPipeline.render(input)`). A test that only exercises implementation
statelessness of the obsolete mutating renderer is flagged for deletion.

| Test file | Test name | Obsolete call | Actual behavior protected | Recommended action |
|---|---|---|---|---|
| `V5114RendererStatelessTests.swift` | "INV-5b: consecutive XYRotationPlotRenderer calls have independent warnings" | `renderRxxVsPhi` (×2, same instance) | Renderer struct doesn't leak mutable state between consecutive renders | **Delete.** Same rationale as the already-deleted ThreeOmega INV-5a: the runtime path constructs a fresh `XYRotationPlotRenderer()` per render and calls non-mutating `makeRxxVsPhiDisplayPayload`/`makeRxyVsPhiDisplayPayload`, so the invariant is structurally guaranteed. |
| `V563XYRxxSeriesOrderTests.swift` | "XY Rxx chips, legend, and display share one identity order" | `renderRxxVsPhi` | `layout.legendRows` order, `SeriesControlModel` chip order, and display-series identity order all match a requested full-identity-key `seriesOrder`; no "seriesOrder mismatch" warning | Migrate to shared route — needs `Output.layout.legendRows`, not obtainable from a payload accessor alone. |
| `V563XYRxxSeriesOrderTests.swift` | "XY Rxx stacked display keeps descending mean-y order under reordered input" | `renderRxxVsPhi` | `displayPayload` series mean-y order matches requested visual order; no "seriesOrder mismatch" warning | Migrate to payload accessor (`makeRxxVsPhiDisplayPayload`) — only inspects `displayPayload`/warnings, no layout. |
| `V563XYRxxSeriesOrderTests.swift` | "XY Rxx hidden filtering compacts stack and preserves order" | `renderRxxVsPhi` | Hidden series excluded/compacted in display payload, order preserved, no spurious warnings | Migrate to payload accessor (`makeRxxVsPhiDisplayPayload`) — no layout inspected. |
| `V563XYRxxSeriesOrderTests.swift` | "XY Rxx all-hidden behavior keeps old warning and visible series" | `renderRxxVsPhi` | All-hidden fallback keeps every series visible and emits "series visibility ignored: all series were hidden" | Migrate to payload accessor (`makeRxxVsPhiDisplayPayload`) — this warning is produced at payload-construction time; no pixel render needed. |
| `V563XYRxySeriesOrderTests.swift` | "XY Rxy chips, legend, and display share one identity order" | `renderRxyVsPhi` | Same as the Rxx version, for Rxy | Migrate to shared route — needs `layout.legendRows`. |
| `V563XYRxySeriesOrderTests.swift` | "XY Rxy stacked display keeps descending mean-y order under reordered input" | `renderRxyVsPhi` | Same as Rxx version | Migrate to payload accessor (`makeRxyVsPhiDisplayPayload`). |
| `V563XYRxySeriesOrderTests.swift` | "XY Rxy hidden filtering compacts stack and preserves order" | `renderRxyVsPhi` | Same as Rxx version | Migrate to payload accessor (`makeRxyVsPhiDisplayPayload`). |
| `V563XYRxySeriesOrderTests.swift` | "XY Rxy all-hidden behavior keeps old warning and visible series" | `renderRxyVsPhi` | Same as Rxx version | Migrate to payload accessor (`makeRxyVsPhiDisplayPayload`). |
| `V565HiddenSeriesStackingTests.swift` | "XY stacked sweeps compact after hidden filtering" | `makeRxxVsPhiPayload` + `renderRxxVsPhi` | Hidden series excluded/compacted in display payload, no spurious "all hidden" warning | Migrate to payload accessor (`makeRxxVsPhiDisplayPayload`) — only inspects `displayPayload`/warnings, no layout. |
| `V563WorkflowStateBoundaryTests.swift` | "XYRotation render helpers return pre-pipeline displayPayload for export" | `renderRxxVsPhi` | `imageData`/`layout` non-nil, and the `displayPayload` returned is the pre-pipeline-mutation snapshot (a second, independent `WorkbenchRenderPipeline.render` call on that same `displayPayload` proves the pipeline doesn't bake `reverseSeriesForLegend` into series labels) | Migrate to shared route — asserts on `Data`/`layout`, requires an actual pixel render. The second `WorkbenchRenderPipeline.render` call in this test already doesn't depend on the obsolete renderer and needs no change. |

Tests not listed above that call `makeRxxVsPhiPayload`/`makeRxyVsPhiPayload`/
`makeRxxVsPhiDisplayPayload`/`makeRxyVsPhiDisplayPayload` directly (e.g.
`fullIdentityKeyReorder`, `noSeriesOrderMismatchWarning`, `packRestorePreservesSeriesOrder`
in both `V563XYR{xx,xy}SeriesOrderTests.swift`) already exercise the shared route or a
payload accessor and require no change.

## 3. Planned migration shape

Mirrors `ThreeOmegaFieldSweepRouteAudit.md`'s pattern exactly:

1. Introduce a small XYRotation-specific counterpart to
   `Tests/SpinLabAppTests/Support/ThreeOmegaFieldSweepRenderRouteHelper.swift` (e.g.
   `XYRotationRenderRouteHelper`) that mirrors `XYRotationWorkspaceStore`'s Rxx/Rxy
   branches: `makeRxxVsPhiDisplayPayload`/`makeRxyVsPhiDisplayPayload` →
   `TabRenderManager.buildPipelineInput` (threading `seriesOrder`/`hiddenSeriesKeys`
   through `WorkbenchTabDisplayStateSnapshot`, not just the payload accessor, so the
   pipeline-level "seriesOrder mismatch" check the layout-needing tests rely on still
   fires) → `WorkbenchRenderPipeline.render`.
2. Migrate the 4 payload-only tests (§2) to the payload accessors directly.
3. Migrate the 3 render-output tests (§2, need `layout`/`Data`) to the new helper.
4. Delete `V5114RendererStatelessTests`'s INV-5b.
5. Once `rg -n "renderRxxVsPhi\(|renderRxyVsPhi\(" Sources Tests` shows no real call
   sites, delete `renderRxxVsPhi`, `renderRxyVsPhi`, and the now-dead `_render`/
   `_consume`/`_stackedOptions`/`RenderOutcome` from `XYRotationPlotRenderer.swift` in
   one commit. `makeRxxVsPhiPayload`, `makeRxyVsPhiPayload`,
   `makeRxxVsPhiDisplayPayload`, `makeRxyVsPhiDisplayPayload`, and
   `stackedOptions(sweepCount:base:)` are untouched throughout.

This audit does not migrate any test or delete any production code — that is separate,
later work per the steps above.
