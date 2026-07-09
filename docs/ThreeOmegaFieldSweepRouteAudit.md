# ThreeOmega Field Sweep Render Route Audit — fieldSweep1omega / fieldSweep3omega

Status: audit only. No rendering behavior, payload construction, or renderer code was
changed to produce this document. Follow-up to `docs/RenderRouteAudit.md` §7, which
flagged these two tabs for deeper audit.

## Files inspected

- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Rendering.swift`
- `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift`
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/SeriesOrder/SeriesVisualPlanner.swift`
- `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Preservation/TabRenderManager.swift`

## 1–2. What does the custom renderer do that the shared XY route "cannot" express?

Nothing at the pipeline level. `renderR1omega` / `renderR3omega` →
`ThreeOmegaPlotRenderer._render(payload:options:)` builds a
`WorkbenchRenderPipeline.Input` by hand and calls `WorkbenchRenderPipeline.render(input)`
directly — **the exact same pipeline type and entry point** that `tabs.buildPipelineInput`
+ `WorkbenchRenderPipeline.render` uses for every already-shared xy tab (RAHE, Hc, RT,
Scaling, etc.). There is no second rendering backend, no different `Input` shape, no
special-case inside `WorkbenchRenderPipeline` itself.

The two things that look like renderer-only behavior turn out to be payload/display-state
concerns that are already resolved *before* the renderer is invoked:

- **Dynamic chart height** (scales with sweep count) is computed twice: once generically
  at the top of `renderThreeOmegaTab` into `baseOptions` (lines 70–79, already keyed on
  `.fieldSweep1omega`/`.fieldSweep3omega`), and a second time inside
  `ThreeOmegaPlotRenderer._stackedOptions(sweepCount:)`, which is what actually gets used.
  The generically-computed `baseOptions` is silently discarded for these two tabs because
  the `.rendered` branch never reaches `tabs.buildPipelineInput(baseOptions:...)`. This is
  duplicated logic, not a capability the shared route lacks — `buildPipelineInput` already
  accepts a `baseOptions` parameter for exactly this purpose.
- **Series stacking/offset** happens in `ThreeOmegaPlotRenderer.makeStackedFieldSweepPayloads`
  via `SeriesVisualPlanner.plan(..., stackingPolicy: .orderEnforcingVertical(multiplier:minGapFraction:))`,
  which shifts each series' `y` values directly (`SeriesVisualPlanner.swift:68–88`) before
  the payload is ever handed to a renderer. This runs identically regardless of which route
  consumes the resulting payload — it is payload-construction-time, not render-route-time.

## 3. Are the plots standard XY series with vertical offsets?

Yes. `WorkbenchPlotPayload.series` for both tabs is an ordinary array of
`WorkbenchPlotSeries` (x = field, y = R(1ω) or R(3ω) + baked-in stack offset). Structurally
indistinguishable from any other xy payload once `displaySeries` is built.

## 4. Are stack offsets stored in payload, styleParams, or renderer-only state?

**Payload.** `displaySeries[i].y` already contains the shifted values by the time
`makeStackedFieldSweepPayloads` returns. `stackOffsetMultiplier` / `minGapFraction`
(renderer-only fields today, sourced from `ThreeOmegaRendererGlobalSettings`) are
consumed once at payload-build time and are not needed again downstream — they do not
leak into `WorkbenchRenderPipeline.Input` or styleParams.

## 5. Are legend labels / hidden series / series order compatible with `WorkbenchPlotPayload`?

Mostly yes, with one real gap:

- Hidden series: `hiddenSeriesKeys` flows into `SeriesVisualPlanningInput` the same way
  for field-sweep tabs as for any other stacked/plain xy payload (e.g. the RAHE-vs-T
  combined payload uses the identical `SeriesVisualPlanner.plan(...)` call with
  `stackingPolicy: .none`). No field-sweep-specific behavior here.
- Legend labels / series metadata: built through the same `_seriesMetadata` /
  `WorkbenchSeriesIdentityMetadata` helpers used everywhere else. No gap.
- Series order: **this is the one genuine gap.** When no explicit order has been set yet
  (fresh tab, no user reordering), field-sweep tabs fall back to
  `defaultFieldSweepVisualSeriesOrder` — reversed `stableSourceRef` order — computed in
  `ThreeOmegaWorkspaceStore+Rendering.swift`. This fallback is resolved into
  `effectiveTabSnapshot` via `.with(seriesOrder: visualOrder)`, exactly mirroring how
  `.xy`-route tabs build `effectiveTabState`. So the *pipeline* already gets the right
  order. The gap is downstream: `TabRenderManager.setOutput` auto-populates
  `seriesControlModel` (the series-chip UI contract) from `tabStates[tab].seriesOrder`
  (the *persisted* per-tab state), not from the transient resolved order — so if the
  auto-populate path were used as-is, chips would show raw payload order instead of the
  reversed-default order actually drawn. That's why the store manually calls
  `SeriesControlModel.fromPayload(manifestPayload, currentSeriesOrder: resolvedFieldSweepVisualOrder, hiddenSeriesKeys:)`
  after rendering, instead of letting `setOutput`'s default `makeSeriesControlModel` run.

## 6. Are PNG/PDF/export paths different from shared XY?

No. Both routes return `(Data?, Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String])`
from the same `WorkbenchRenderPipeline.render` call and both get wrapped into the same
`TabRenderOutput` type by the caller. Export code downstream (`imageData`/`pdfData`/`layout`)
does not know or care which branch produced them.

## 7. What would need to change in the shared XY route to support these cleanly?

Nothing needs to change in `WorkbenchRenderPipeline` or `buildPipelineInput` itself — both
already accept `baseOptions` and a `tabState.seriesOrder`. What needs to move is workflow
logic currently living inside the renderer/store's custom branch, into the same shape the
`.xy` branch already uses:

1. Route `.fieldSweep1omega`/`.fieldSweep3omega` through the same
   `tabs.buildPipelineInput(...)` + `WorkbenchRenderPipeline.render(input)` call as `.rahe`,
   `.hcVsT`, etc., using the `baseOptions` already computed generically at the top of
   `renderThreeOmegaTab` (delete the duplicate `_stackedOptions` computation, or keep it
   only as the shared computation).
2. Keep computing `defaultFieldSweepVisualSeriesOrder` and folding it into
   `effectiveTabSnapshot`/`tabState.seriesOrder` before calling `buildPipelineInput` — this
   part already works today and needs no redesign.
3. Preserve the manual `SeriesControlModel.fromPayload(..., currentSeriesOrder: resolvedFieldSweepVisualOrder, ...)`
   construction (or teach `setOutput`'s auto-populate path to accept an explicit order
   override) so series chips reflect the resolved default order rather than whatever
   `tabStates[tab].seriesOrder` happens to hold before the user first touches ordering.
4. Stacking (`stackOffsetMultiplier`/`minGapFraction`) stays exactly where it is today —
   inside `makeStackedFieldSweepPayloads`, at payload-construction time — since it already
   does not depend on which route consumes the payload.

## 8. Risk

**Low–Medium.** Both tabs already render through `WorkbenchRenderPipeline` — there is no
second pipeline to unify, unlike XYRotation (which was already reclassified migratable) or
Temperature Dependence (genuinely separate `DualAxisRenderPipeline`, high risk). The
remaining work is deleting a duplicated `Input`-construction path and relocating one
workflow-specific default (`defaultFieldSweepVisualSeriesOrder`) so it's applied before
`buildPipelineInput` instead of inside a bespoke `_buildRenderer`/`_render` call. The one
place migration could visibly regress behavior is series-chip ordering on a tab's first
render before any user reorder — needs explicit before/after comparison in a follow-up
implementation pass, not just a diff review.

## Conclusion

`fieldSweep1omega` and `fieldSweep3omega` are **not structurally special**. They already
use the shared `WorkbenchRenderPipeline`; the "custom render route" is a duplicate
hand-assembly of the same `Input` struct plus two pieces of field-sweep-specific default
logic (dynamic height, default series order) that belong upstream of `buildPipelineInput`
rather than inside the renderer. Reclassified from "xy / special" to **migratable**,
consistent with how XYRotation was reclassified in `docs/RenderRouteAudit.md` §7.

## 9. Post-migration entry-point classification

Status update after the migration landed
(`eceba48` "Route ThreeOmega field sweeps through shared input builder"):
`fieldSweep1omega`/`fieldSweep3omega` now call `renderer.makeR1omegaPayload`/
`makeR3omegaPayload` (manifest), `renderer.makeR1omegaDisplayPayload`/
`makeR3omegaDisplayPayload` (stacked + hidden-filtered display payload), and
`ThreeOmegaPlotRenderer.stackedOptions(sweepCount:)`, then route the result through
`tabs.buildPipelineInput(...)` + `WorkbenchRenderPipeline.render(...)` — the same shared
path RAHE/Hc/RT/Scaling already use. `renderR1omega`/`renderR3omega` (the old
mutating, pipeline-calling entry points) are no longer reachable from
`ThreeOmegaWorkspaceStore+Rendering.swift`. Verified by `rg` across `Sources/` and
`Tests/`:

| Symbol | Runtime use | Test use | Current status | Next action |
|---|---|---|---|---|
| `ThreeOmegaPlotRenderer.stackedOptions(sweepCount:)` | Yes — `ThreeOmegaWorkspaceStore+Rendering.swift:73` (adaptive chart height for both field-sweep tabs) | Indirectly, via `_stackedOptions` delegation inside `renderR1omega`/`renderR3omega` | Runtime-used | Keep |
| `makeR1omegaPayload(sweeps:device:seriesOrder:)` | Yes — `ThreeOmegaWorkspaceStore+Rendering.swift:173` (manifest payload for `.fieldSweep1omega`) | Yes — `V563WorkflowStateBoundaryTests`, `V557MagneticFieldMagnitudeDisplayUnitTests`, `V563ThreeOmegaFieldSweepSeriesOrderTests`, `V556MagneticFieldUnitConversionTests`, `V565HiddenSeriesStackingTests` | Runtime-used | Keep |
| `makeR3omegaPayload(sweeps:device:seriesOrder:)` | Yes — `ThreeOmegaWorkspaceStore+Rendering.swift:220` (manifest payload for `.fieldSweep3omega`) | Yes — `V563ThreeOmegaFieldSweepSeriesOrderTests` | Runtime-used | Keep |
| `makeR1omegaDisplayPayload(sweeps:device:seriesOrder:hiddenSeriesKeys:)` | Yes — `ThreeOmegaWorkspaceStore+Rendering.swift:188` (display payload fed to `buildPipelineInput`) | Yes — source-inspection assertions in `V563SeriesVisualPlannerSourceInspectionTests`, `V5115ThreeOmegaWorkspaceStoreCharacterizationTests` | Runtime-used | Keep |
| `makeR3omegaDisplayPayload(sweeps:device:seriesOrder:hiddenSeriesKeys:)` | Yes — `ThreeOmegaWorkspaceStore+Rendering.swift:235` | Yes — source-inspection assertions in `V563SeriesVisualPlannerSourceInspectionTests`, `V5115ThreeOmegaWorkspaceStoreCharacterizationTests` | Runtime-used | Keep |
| `renderR1omega(sweeps:device:seriesOrder:hiddenSeriesKeys:)` | No — no call sites remain under `Sources/SpinLabApp/Features/Workbench/`. Only remaining production caller is `ThreeOmegaPlotRenderer.renderAllTabs`, which is itself unreferenced from any workspace store (see below) | Yes — `V5114RendererStatelessTests`, `V563ThreeOmegaFieldSweepSeriesOrderTests`, `V565HiddenSeriesStackingTests`, `V542CopyPNGWYSIWYGTests`, `V400ThreeOmegaTests`, `V536CurveDragOrderTests` | Test-only | Migrate tests to `makeR1omegaDisplayPayload` (+ direct `WorkbenchRenderPipeline.render` where PNG/PDF bytes are actually asserted on), then delete |
| `renderR3omega(sweeps:device:seriesOrder:hiddenSeriesKeys:)` | No — same as above; only reached via `renderAllTabs` | Yes — `V542CopyPNGWYSIWYGTests`, `V563ThreeOmegaFieldSweepSeriesOrderTests` | Test-only | Migrate tests to `makeR3omegaDisplayPayload` (+ direct `WorkbenchRenderPipeline.render` where PNG/PDF bytes are actually asserted on), then delete |

Note on `ThreeOmegaPlotRenderer.renderAllTabs(...)`: this convenience method still calls
`renderR1omega`/`renderR3omega` internally (`ThreeOmegaPlotRenderer.swift:100,102`), but
`renderAllTabs` itself has exactly one caller in the whole tree —
`Tests/SpinLabAppTests/ThreeOmegaRAHEVsDeviceManifestTests.swift`. No workspace store
calls it. It is therefore also test-only and should be migrated/retired in the same pass
as `renderR1omega`/`renderR3omega`, not kept as a reason to preserve them.

This audit does not delete `renderR1omega`/`renderR3omega`/`renderAllTabs` — that is a
separate, later change once the listed test files are migrated to the payload-only +
`WorkbenchRenderPipeline.render` pattern.

## 10. Per-test-site migration classification

Every remaining `renderR1omega`/`renderR3omega`/`renderAllTabs` call site, classified
before any test is touched. No production code and no test file was changed to produce
this table.

Decision rule applied: a test that only inspects `WorkbenchPlotPayload` content (series
count/order/y-values, `semanticParams`, `axisMapping`, warnings produced during payload
construction) migrates to the payload-only accessors (`makeR1omegaDisplayPayload`/
`makeR3omegaDisplayPayload`/manifest accessors). A test that inspects `Data` (PNG/PDF
bytes) or `WorkbenchPlotLayout` (`legendRows`, hit rects, etc.) needs an actual pixel
render and migrates to the shared route (`WorkbenchRenderPipeline.Input` built from a
display payload + `ThreeOmegaPlotRenderer.stackedOptions`, then
`WorkbenchRenderPipeline.render(input)`). A test that only exercises implementation
statelessness of the obsolete mutating renderer, or reaches `renderAllTabs` purely as a
convenience wrapper for behavior unrelated to field sweeps, is flagged for deletion or
rewrite instead of migration.

| Test file | Test name | Current obsolete call | Actual behavior protected | Recommended action |
|---|---|---|---|---|
| `V5114RendererStatelessTests.swift` | "INV-5a: consecutive ThreeOmegaPlotRenderer calls have independent warnings" | `renderR1omega` (×2, same instance) | Renderer struct doesn't leak mutable state between consecutive renders | **Delete.** Implementation-detail invariant of the old mutating-renderer design; the runtime path now constructs a fresh `ThreeOmegaPlotRenderer()` per render and calls non-mutating `makeR1omegaDisplayPayload`, so the invariant is structurally guaranteed. |
| `V563ThreeOmegaFieldSweepSeriesOrderTests.swift` | "R1ω render with legacy sweeps (nil sourceFilePath + nil sampleID) does not crash and has non-empty sourceRefs" | `renderR1omega` | Full pixel-render pipeline doesn't crash / emit a "pipeline failure" warning for sweeps missing `sourceFilePath`/`sampleID` | Migrate to shared route — `makeR1omegaDisplayPayload` → `WorkbenchRenderPipeline.render`, assert no "pipeline failure" in `output.warnings`. |
| `V563ThreeOmegaFieldSweepSeriesOrderTests.swift` | "R1ω reorderable payload: all series have non-empty sourceRef" | `renderR1omega` | Pipeline produces a non-nil `layout` for the same edge-case metadata | Migrate to shared route — assert `output.layout` (non-throwing render is the success signal). |
| `V563ThreeOmegaFieldSweepSeriesOrderTests.swift` | "R3ω render with legacy sweeps does not crash" | `renderR3omega` | Same crash-safety guarantee for R(3ω) | Migrate to shared route via `makeR3omegaDisplayPayload`. |
| `V563ThreeOmegaFieldSweepSeriesOrderTests.swift` | "Field-sweep stacked render consumes full identity keys in requested visual order" | `renderR1omega` + `renderR3omega` | `layout.legendRows` order and display-series identity order match a requested full-identity-key `seriesOrder`, no "seriesOrder mismatch" warning | Migrate to shared route — needs `Output.layout.legendRows`, not obtainable from a payload accessor alone. |
| `V563ThreeOmegaFieldSweepSeriesOrderTests.swift` | "R3ω stacked render: legend and chip order both match canonical visual series order" | `renderR3omega` | `layout.legendRows` order and `SeriesControlModel` chip order both match `canonicalVisualSeriesOrder` | Migrate to shared route — same reason, needs rendered `layout`. |
| `V565HiddenSeriesStackingTests.swift` | "3ω stacked field sweeps compact after hidden filtering and keep raw manifest complete" | `makeR1omegaPayload` + `renderR1omega` | Hidden series excluded/compacted in display payload **and** `layout.legendRows` order matches the compacted display order | Migrate to shared route — the `legendRows` assertion forces a real render; fold the existing `makeR1omegaPayload` call into `makeR1omegaDisplayPayload` for the display-side checks. |
| `V565HiddenSeriesStackingTests.swift` | "3ω stacked field sweeps ignore hidden filter when every series is hidden" | `makeR1omegaPayload` + `renderR1omega` | All-hidden fallback keeps every series visible and emits "series visibility ignored: all series were hidden" | Migrate to payload accessor (`makeR1omegaDisplayPayload`) — this warning is produced by `SeriesVisualPlanner` at payload-construction time; `renderR1omega`'s own `Input.hiddenSeriesKeys` is always `[]`, so the pipeline never re-filters here. No pixel render needed. |
| `V542CopyPNGWYSIWYGTests.swift` | `testR1omegaDisplayPayloadCarriesOffsetAppliedYValues` | `renderR1omega` | `displayPayload` series are non-overlapping stacked y-bands (offset baked in) | Migrate to payload accessor (`makeR1omegaDisplayPayload`) — despite the WYSIWYG file name, the assertion only inspects payload y-values, never pixels/layout. |
| `V542CopyPNGWYSIWYGTests.swift` | `testR3omegaDisplayPayloadCarriesOffsetAppliedYValues` | `renderR3omega` | Same, for R(3ω) | Migrate to payload accessor (`makeR3omegaDisplayPayload`). |
| `V542CopyPNGWYSIWYGTests.swift` | `testR1omegaDisplayPayloadDiffersFromRawManifest` | `renderR1omega` | Sorted-by-min-y series means strictly increase (stacking offset present) | Migrate to payload accessor (`makeR1omegaDisplayPayload`). |
| `V400ThreeOmegaTests.swift` | "renderR1omega returns non-nil Data for valid sweeps" | `renderR1omega` | PNG bytes are produced for a valid single sweep | Migrate to shared route — asserts on `Data`, requires an actual pixel render. |
| `V400ThreeOmegaTests.swift` | "rendering remains numerically unchanged under angle-sweep metadata" | `renderR1omega` | PNG bytes + non-nil layout + zero warnings for `angle_sweep` device metadata | Migrate to shared route. |
| `V536CurveDragOrderTests.swift` | "renderR1omega recalculates stack offsets based on reordered sweep amplitudes" | `renderR1omega` | PNG bytes produced when an explicit `seriesOrder` is supplied — the offset-math assertions in this same test already call `ThreeOmegaStackOffsetUseCase` directly, bypassing the renderer entirely | Migrate to shared route for the `data != nil` check only; everything else in this test already doesn't depend on the renderer. |
| `ThreeOmegaRAHEVsDeviceManifestTests.swift` | "renderAllTabs populates rahe1omegaVsDevice and rahe3omegaVsDevice fields" | `renderAllTabs` (transitively calls `renderR1omega`/`renderR3omega`, but this test asserts none of that output) | `rahe1omegaVsDevice`/`rahe3omegaVsDevice` PNG + display payload are populated | Not actually a field-sweep test — `renderAllTabs` is reached only as a convenience wrapper. Every other test in this file already calls `renderRAHE1omegaVsDevice`/`renderRAHE3omegaVsDevice` directly; rewrite this one to match instead of migrating it toward the field-sweep shared route. |

No test file was modified to produce this table. Migration/deletion is a separate,
later change per row above.
