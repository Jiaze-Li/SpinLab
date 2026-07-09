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
