# ThreeOmega Remaining Render Route Audit — RAHE / RAHE-vs-Device / Hc / RT / Scaling

Status: audit only. No rendering behavior, payload construction, or renderer code was
changed to produce this document. Follow-up to `docs/RenderRouteAudit.md` §8.4, which
flagged these six functions as the same dead-mutating-renderer pattern already cleaned
up for ThreeOmega field sweeps (`docs/ThreeOmegaFieldSweepRouteAudit.md`) and XYRotation
(`docs/XYRotationRenderRouteAudit.md`). fieldSweep1omega/fieldSweep3omega, Temperature
Dependence (dual-axis), IV, and XYRotation are all out of scope here and untouched.

## 1. Obsolete entry points

All six are `mutating func` entry points on `ThreeOmegaPlotRenderer`
(`Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift`) that build a payload and
call `WorkbenchRenderPipeline.render` directly via the private `_render`/`_consume`
helpers, instead of the shared `tabs.buildPipelineInput(...)` +
`WorkbenchRenderPipeline.render(...)` route the workspace store actually uses:

| Entry point | Line |
|---|---|
| `renderRAHE` | 107 |
| `renderRAHE1omegaVsDevice` | 401 |
| `renderRAHE3omegaVsDevice` | 410 |
| `renderHcVsT` | 542 |
| `renderRT` | 575 |
| `renderScaling` | 588 |

`renderRAHE1omegaVsDevice`/`renderRAHE3omegaVsDevice` both delegate to a shared private
`_renderRAHEVsDevice(harmonic:...)` (line 414). All six ultimately call the same private
`_render(payload:)` (line 763) / `_consume(_:into:)` (line 818) / `RenderOutcome` (line
76) — confirmed via `rg -n "_render(\|_consume("
Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift`: exactly 5 call sites (one per
function above, with the two vs-Device variants sharing one). `renderTemperatureDependence`
(the runtime-used dual-axis entry point) does **not** use this shared private
infrastructure — it goes through `DualAxisRenderPipeline` instead — so deleting these six
would not touch it.

## 2. Runtime status

`rg -n "renderRAHE\(|renderRAHE1omegaVsDevice\(|renderRAHE3omegaVsDevice\(|renderHcVsT\(|renderRT\(|renderScaling\(" Sources/SpinLabApp/Features/Workbench`
returns **zero hits** for all six. `ThreeOmegaWorkspaceStore+Rendering.swift`'s
`renderThreeOmegaTab` already builds each tab from a payload-only accessor —
`makeRAHEPayload`, `makeRAHE1omegaVsDevicePayload`, `makeRAHE3omegaVsDevicePayload`,
`makeHcPayload`, `makeRTPayload`, `makeScalingPayload` — then routes through
`tabs.preparedDisplayState(...)` → `tabs.buildPipelineInput(...)` →
`WorkbenchRenderPipeline.render(...)`, exactly the shared xy pattern documented in
`docs/RenderRouteAudit.md` §8.1. Every one of these six payload-only accessors already
exists and is unaffected by anything in this audit.

`rg -n "renderRAHE\(|renderRAHE1omegaVsDevice\(|renderRAHE3omegaVsDevice\(|renderHcVsT\(|renderRT\(|renderScaling\(" Sources Tests`
shows the only remaining call sites are in 8 test files (33 call sites total across 25
distinct test functions).

## 3. Entry-point summary

| Entry point | Runtime callers | Test callers | Behavior protected | Recommended action |
|---|---|---|---|---|
| `renderRAHE` | 0 | `V563ThreeOmegaRAHESeriesOrderTests.swift` (3 tests via a shared `makePayloads` helper), `V563ThreeOmegaFieldSweepSeriesOrderTests.swift` (2 tests) | RAHE combined-tab legend/chip/series-order alignment; hidden-series filtering; no false "seriesOrder mismatch" warning | Migrate — layout-needing tests to shared route; hidden-filtering assertions also to shared route (no payload accessor exposes `hiddenSeriesKeys` — production filters generically inside the pipeline, not at payload-construction time, so a payload-only accessor would test a different mechanism than production uses); one test's `renderRAHE` call is incidental and should simply be dropped (see §4) |
| `renderRAHE1omegaVsDevice` | 0 | `ThreeOmegaRAHEVsDeviceRendererTests.swift` (7 tests), `ThreeOmegaRAHEVsDeviceManifestTests.swift` (5 tests), `V830PointTagsTests.swift` (2 tests) | Angle-string parsing/sort, HFE-vs-WA value selection, axis labels, semantic params (`tabKey`/`v3method`), multi-temperature rejection, unparseable-device filtering, point-tag hit-target visibility | Migrate — payload/data-only tests to `makeRAHE1omegaVsDevicePayload` (already exists); the 2 point-tag tests to shared route (need `layout.pointDotHitTargets`, not obtainable from a payload) |
| `renderRAHE3omegaVsDevice` | 0 | `ThreeOmegaRAHEVsDeviceRendererTests.swift` (2 tests), `ThreeOmegaRAHEVsDeviceManifestTests.swift` (shares 2 combined-tab tests with the 1ω variant) | 3ω value computed as `v3omegaFit / iRms`; axis labels/semantic params for the 3ω tab | Migrate to `makeRAHE3omegaVsDevicePayload` (already exists) |
| `renderHcVsT` | 0 | `V413ThreeOmegaFitUseCaseTests.swift` (2 tests) | Valid sweeps render non-nil output; empty sweeps rejected (no image) | Migrate to `makeHcPayload` — replace `data != nil`/`== nil` with a payload-nil check (same guard/early-return logic backs both) |
| `renderRT` | 0 | `V413ThreeOmegaFitUseCaseTests.swift` (2 tests), `V5119RTLabelMigrationRegressionTests.swift` (1 test) | Valid/empty RT data handling; RT axis-label regression guard (plain-text x-label vs math-markup y-label) | Migrate to `makeRTPayload` |
| `renderScaling` | 0 | `V41216ThreeOmegaPlotRendererTests.swift` (5 tests), `ThreeOmegaScalingMathLabelTests.swift` (1 test), `V400ThreeOmegaTests.swift` (1 test) | Fit-line-extension / degenerate-range / segment-count render-success smoke tests; math-label axis wiring reaches a live render (needs `layout`); empty-result rejection | Migrate — the 6 Data-only tests to `makeScalingPayload` (payload-nil check); the 1 layout-needing test (`renderScalingProducesOutput`) to shared route |

## 4. Per-test classification

Decision rule (same as `docs/ThreeOmegaFieldSweepRouteAudit.md` §10 /
`docs/XYRotationRenderRouteAudit.md` §2): a test that only inspects `WorkbenchPlotPayload`
content (series values/order, axis labels, `semanticParams`, warnings produced at
payload-construction time) migrates to the existing payload-only accessor. A test that
inspects `Data` (PNG/PDF bytes) or `WorkbenchPlotLayout` (`legendRows`,
`pointDotHitTargets`, etc.) needs an actual pixel render and migrates to the shared route
(payload → `tabs.buildPipelineInput(...)` → `WorkbenchRenderPipeline.render(...)`). A test
whose obsolete call doesn't actually back any of its assertions is flagged to simply drop
the call rather than "migrate" it to anything.

### `renderRAHE`

| Test file | Test name | Obsolete call | Actual behavior protected | Recommended action |
|---|---|---|---|---|
| `V563ThreeOmegaRAHESeriesOrderTests.swift` | "RAHE chips, legend, and display share one identity order" | `renderRAHE` (via `makePayloads` helper + one direct call) | `output.layout.legendRows` order, `SeriesControlModel` chip order, and manifest/display identity order all match a requested reversed-default `seriesOrder` | Migrate to shared route — needs `layout.legendRows`, not obtainable from a payload accessor alone. |
| `V563ThreeOmegaRAHESeriesOrderTests.swift` | "RAHE hidden filtering preserves visual order" | `renderRAHE` (via `makePayloads` + one direct call) | Hiding one series drops it from the rendered/visible set while the remaining series keep their requested order; no "seriesOrder mismatch" warning | Migrate to shared route, asserting on `output.layout.legendRows` (not a separately-filtered "display" object) — production filters hidden series generically inside `WorkbenchRenderPipeline.applySeriesVisibility` via `tabState.hiddenSeriesKeys`, not by pre-baking the filter into the payload the way `renderRAHE`'s own `hiddenSeriesKeys` parameter does. `output.manifestPayload` from the pipeline is always the unfiltered original, so this test cannot migrate to a payload-nil-style check. |
| `V563ThreeOmegaRAHESeriesOrderTests.swift` | "RAHE render path emits no seriesOrder mismatch warning" | `renderRAHE` (via `makePayloads`, but this test only reads `result.manifest`/`result.requestedOrder` — `result.display`, the part that needs `renderRAHE`, is never used) | `WorkbenchRenderPipeline.render` on the manifest payload with a reversed `seriesOrder` produces no "seriesOrder mismatch" warning | Not actually protected by `renderRAHE` — this test's own body builds its own `WorkbenchRenderPipeline.Input`/`render` call from `makeRAHEPayload` output directly. Drop the shared `makePayloads` helper's `renderRAHE` call for this test (or give it a lighter payload-only helper) rather than "migrating" a dependency that isn't load-bearing here. |
| `V563ThreeOmegaFieldSweepSeriesOrderTests.swift` | "RAHE combined payload keeps both harmonic series identities and visibility" | `renderRAHE` | Hiding one harmonic series leaves the manifest payload with both series (persistence-complete) while the rendered/visible set has only the other one; axis mapping is preserved on both | Migrate to shared route — same reasoning as above: assert `output.layout.legendRows.count == 1` and label content instead of `displayPayload.series.count`, since no payload accessor exposes a pre-filtered "display" object matching production's filtering mechanism. |
| `V563ThreeOmegaFieldSweepSeriesOrderTests.swift` | "RAHE combined payload keeps manifest series while hiding one harmonic only in display payload" | `renderRAHE` | Same invariant as above, checking the specific remaining series' label/x-values | Migrate to shared route — same reasoning. |

Tests in these two files that call `makeRAHEPayload` only (no `renderRAHE`) — "RAHE
combined payload consumes full identity-key reorder", "RAHE combined payload uses
temperature-based extraction, not field-sweep x values" — already use the payload
accessor and need no change. `V563ThreeOmegaRAHESeriesOrderTests`'s
"RAHE pack restore preserves series order" drives a real `ThreeOmegaWorkspaceStore` and
already exercises the shared route; no change needed.

### `renderRAHE1omegaVsDevice` / `renderRAHE3omegaVsDevice`

| Test file | Test name | Obsolete call | Actual behavior protected | Recommended action |
|---|---|---|---|---|
| `ThreeOmegaRAHEVsDeviceRendererTests.swift` | "render produces non-nil data for valid sweeps with HFE method" | `renderRAHE1omegaVsDevice` | A valid single-temperature angle sweep renders image bytes, layout, and display payload with no warnings | Migrate to shared route for the `Data`/`layout` non-nil assertions (payload accessor alone can't prove a render succeeds); could alternatively split into a payload-nil check (`makeRAHE1omegaVsDevicePayload`) + a separate shared-route render-succeeds check. |
| `ThreeOmegaRAHEVsDeviceRendererTests.swift` | "x values are sorted by numeric angle" | `renderRAHE1omegaVsDevice` | Device-angle strings (e.g. "30deg") parse to numeric degrees and the x-series sorts ascending | Migrate to `makeRAHE1omegaVsDevicePayload` — payload-only. |
| `ThreeOmegaRAHEVsDeviceRendererTests.swift` | "y values match rahe(1, .highField)" | `renderRAHE1omegaVsDevice` | HFE (not WA) RAHE(1ω) value is plotted per device after angle sort | Migrate to `makeRAHE1omegaVsDevicePayload`. |
| `ThreeOmegaRAHEVsDeviceRendererTests.swift` | "axis labels are correct for 1ω HFE" | `renderRAHE1omegaVsDevice` | Correct axis-label/math-markup metadata for the RAHE(1ω)-vs-device tab | Migrate to `makeRAHE1omegaVsDevicePayload`. |
| `ThreeOmegaRAHEVsDeviceRendererTests.swift` | "render 3ω produces non-nil data" | `renderRAHE3omegaVsDevice` | The 3ω-vs-device variant renders successfully with no warnings | Migrate to `makeRAHE3omegaVsDevicePayload` (payload-nil check) or shared route if a real render-succeeds proof is wanted. |
| `ThreeOmegaRAHEVsDeviceRendererTests.swift` | "3ω y values come from rahe(3, method)" | `renderRAHE3omegaVsDevice` | RAHE(3ω) computed as `v3omegaFit / iRms`, not read from a stored field | Migrate to `makeRAHE3omegaVsDevicePayload`. |
| `ThreeOmegaRAHEVsDeviceRendererTests.swift` | "window method uses WA values" | `renderRAHE1omegaVsDevice` | Selecting `.window` switches the plotted 1ω value source from HFE to WA | Migrate to `makeRAHE1omegaVsDevicePayload`. |
| `ThreeOmegaRAHEVsDeviceRendererTests.swift` | "returns nil and warning when multiple temperatures are present" | `renderRAHE1omegaVsDevice` | Mixed-temperature input is rejected with a warning rather than silently rendering | Migrate to `makeRAHE1omegaVsDevicePayload` — the payload accessor already returns `nil` for mixed temperatures (`_makeRAHEVsDevicePayload` line 460); the warning text itself is only produced inside `_renderRAHEVsDevice`'s guard-failure branch (line 427-431), so preserving the warning assertion requires either moving that diagnostic into the payload accessor or reproducing it at the call site — flag this as the one non-mechanical part of the migration. |
| `ThreeOmegaRAHEVsDeviceRendererTests.swift` | "sweeps with non-angle device strings are excluded" | `renderRAHE1omegaVsDevice` | Sweeps with unparseable device names are silently filtered, not warned about | Migrate to `makeRAHE1omegaVsDevicePayload`. |
| `ThreeOmegaRAHEVsDeviceManifestTests.swift` | "rahe1omegaVsDevice display payload has correct workflowID and tabKey" | `renderRAHE1omegaVsDevice` | Display payload carries correct manifest identity/`semanticParams` for save/export routing | Migrate to `makeRAHE1omegaVsDevicePayload`. |
| `ThreeOmegaRAHEVsDeviceManifestTests.swift` | "rahe3omegaVsDevice display payload has correct tabKey and v3method WA" | `renderRAHE3omegaVsDevice` | `semanticParams` correctly reflect the 3ω tab and WA method choice | Migrate to `makeRAHE3omegaVsDevicePayload`. |
| `ThreeOmegaRAHEVsDeviceManifestTests.swift` | "x axis label is 'Device angle (deg)' for both new tabs" | `renderRAHE1omegaVsDevice` + `renderRAHE3omegaVsDevice` | Both device-vs-angle tabs share the same x-axis label | Migrate to both payload accessors. |
| `ThreeOmegaRAHEVsDeviceManifestTests.swift` | "y axis label for 1ω tab is 'RAHE(1ω) (Ω)'" | `renderRAHE1omegaVsDevice` | Correct y-axis math label for the 1ω tab | Migrate to `makeRAHE1omegaVsDevicePayload`. |
| `ThreeOmegaRAHEVsDeviceManifestTests.swift` | "y axis label for 3ω tab is 'RAHE(3ω) (Ω)'" | `renderRAHE3omegaVsDevice` | Correct y-axis math label for the 3ω tab | Migrate to `makeRAHE3omegaVsDevicePayload`. |
| `ThreeOmegaRAHEVsDeviceManifestTests.swift` | "rahe1omegaVsDevice and rahe3omegaVsDevice both render image data and display payloads" | `renderRAHE1omegaVsDevice` + `renderRAHE3omegaVsDevice` | Both vs-device tabs produce image bytes and a display payload for a minimal sweep | Migrate to shared route for the `Data` non-nil half of the assertion; payload-non-nil is covered by the accessors alone. |
| `V830PointTagsTests.swift` | "ThreeOmegaPlotRenderer RAHE vs Device: showPointTags=false strips point labels from layout" | `renderRAHE1omegaVsDevice` | Disabling point tags strips point labels so no hit targets are generated | Migrate to shared route — `layout.pointDotHitTargets` is layout-only, unreachable from any payload accessor. |
| `V830PointTagsTests.swift` | "ThreeOmegaPlotRenderer RAHE vs Device: showPointTags=true keeps point labels in layout" | `renderRAHE1omegaVsDevice` | Enabling point tags keeps point labels/hit targets in the layout | Migrate to shared route — same reason. |

`ThreeOmegaRAHEVsDeviceManifestTests.swift`'s "device tab stable keys are distinct from
vs-T keys" calls neither obsolete function (only `ThreeOmegaWorkbenchTab.stableKey`) —
not in scope, no change.

### `renderHcVsT` / `renderRT`

| Test file | Test name | Obsolete call | Actual behavior protected | Recommended action |
|---|---|---|---|---|
| `V413ThreeOmegaFitUseCaseTests.swift` | "renderHcVsT produces non-nil PNG for valid sweeps" | `renderHcVsT` | Valid processed field-sweep results (with Hc extracted) render a non-empty PNG | Migrate to `makeHcPayload` — replace `data != nil` with payload-non-nil (same guard backs both). |
| `V413ThreeOmegaFitUseCaseTests.swift` | "renderHcVsT returns nil for empty sweeps" | `renderHcVsT` | Empty input is rejected rather than producing spurious output | Migrate to `makeHcPayload` — payload-nil check. |
| `V413ThreeOmegaFitUseCaseTests.swift` | "renderRT produces non-nil PNG for valid RT result" | `renderRT` | Valid RT result renders a non-empty PNG | Migrate to `makeRTPayload` — payload-non-nil check. |
| `V413ThreeOmegaFitUseCaseTests.swift` | "renderRT returns nil for empty RT data" | `renderRT` | Empty RT data is rejected rather than producing spurious output | Migrate to `makeRTPayload` — payload-nil check. |
| `V5119RTLabelMigrationRegressionTests.swift` | "3ω RT render path keeps the current RT axis labels" | `renderRT` | RT plot's axis labels (plain "Temperature (K)" x-label, math-markup y-label) are unchanged across the v5.11.9 label migration | Migrate to `makeRTPayload` — payload-only, no render needed. |

`V5119RTLabelMigrationRegressionTests.swift`'s "RTPlotRenderer axis labels preserve
current plain-text labels" uses the unrelated `RTPlotRenderer` type, not
`ThreeOmegaPlotRenderer` — not in scope.

### `renderScaling`

| Test file | Test name | Obsolete call | Actual behavior protected | Recommended action |
|---|---|---|---|---|
| `V41216ThreeOmegaPlotRendererTests.swift` | "Fit line x-range extends ~5% beyond data on each side" | `renderScaling` | Rendering succeeds for typical multi-point scaling data (the actual extension amount is not verified here — pure smoke test) | Migrate to `makeScalingPayload` — payload-non-nil check. |
| `V41216ThreeOmegaPlotRendererTests.swift` | "Δx = 0 (all x identical) does not crash and produces non-nil data" | `renderScaling` | A degenerate zero-width x-range doesn't crash and still yields output | Migrate to `makeScalingPayload` — payload-non-nil check. |
| `V41216ThreeOmegaPlotRendererTests.swift` | "Single full-range segment uses legacy label 'Fitting Results'" | `renderScaling` | Rendering succeeds for a single full-range segment (the "legacy label" claim in the test name is not actually asserted against payload/series-label content) | Migrate to `makeScalingPayload` — payload-non-nil check; the unasserted label claim is a pre-existing gap, not something this migration should paper over or newly assert. |
| `V41216ThreeOmegaPlotRendererTests.swift` | "Multi-segment uses temperature-annotated labels" | `renderScaling` | Rendering succeeds for multi-segment fits (label claim likewise unasserted today) | Migrate to `makeScalingPayload` — same caveat as above. |
| `V41216ThreeOmegaPlotRendererTests.swift` | "No segments renders scatter only (no fit lines), returns non-nil data" | `renderScaling` | Zero-segment scaling data still renders (scatter-only fallback) | Migrate to `makeScalingPayload` — payload-non-nil check. |
| `ThreeOmegaScalingMathLabelTests.swift` | "Scaling-law render path still produces output" | `renderScaling` | A minimal single-point, zero-segment scaling result renders end-to-end (image + layout) with no warnings, proving the math-label axis constants are wired into a working render path | Migrate to shared route — asserts `layout != nil`, not obtainable from a payload accessor alone. |
| `V400ThreeOmegaTests.swift` | "renderScaling with no points returns nil" | `renderScaling` | An empty scaling result (no points) is rejected rather than producing a degenerate plot | Migrate to `makeScalingPayload` — payload-nil check. |

`ThreeOmegaScalingMathLabelTests.swift`'s two label-constant tests
("Scaling-law X/Y label uses math prefix") reference only the static
`ThreeOmegaPlotRenderer.scalingXAxisLabel`/`scalingYAxisLabel` constants — not in scope,
no change.

## 5. Migration shape (for the follow-up implementation commit)

Mirrors the field-sweep and XYRotation precedent:

1. Extend (or add sibling files next to) `Tests/SpinLabAppTests/Support/ThreeOmegaFieldSweepRenderRouteHelper.swift`
   with the RAHE / RAHE-vs-Device / Hc / RT / Scaling branches, each doing
   payload accessor → `TabRenderManager.buildPipelineInput` (threading `seriesOrder` /
   `hiddenSeriesKeys` through `WorkbenchTabDisplayStateSnapshot` where a test needs
   pipeline-level hidden-series/order behavior, not just the payload) →
   `WorkbenchRenderPipeline.render`.
2. Migrate the Data/Layout-needing tests (§4 tables) to that helper.
3. Migrate the payload-only tests directly to the existing `make*Payload` accessors —
   no new production code required, they already exist.
4. Resolve the two non-mechanical gaps flagged in §4 before deleting anything:
   - the "multiple temperatures" warning text in `_renderRAHEVsDevice` (currently only
     produced in the renderer's own guard-failure branch, not in
     `_makeRAHEVsDevicePayload`);
   - `V563ThreeOmegaRAHESeriesOrderTests`'s "RAHE render path emits no seriesOrder
     mismatch warning" test, whose `makePayloads` helper calls `renderRAHE` without
     needing its result — drop that dependency rather than migrate it.
5. Once `rg -n "renderRAHE\(|renderRAHE1omegaVsDevice\(|renderRAHE3omegaVsDevice\(|renderHcVsT\(|renderRT\(|renderScaling\("
   Sources Tests` shows no real call sites, delete all six from
   `ThreeOmegaPlotRenderer.swift` in one commit, along with the now-dead private
   `_render`/`_consume`/`RenderOutcome`/`_renderRAHEVsDevice` helpers (confirmed §1: no
   other caller, including `renderTemperatureDependence`, uses this infrastructure).
   `makeRAHEPayload`, `makeRAHE1omegaVsDevicePayload`, `makeRAHE3omegaVsDevicePayload`,
   `makeHcPayload`, `makeRTPayload`, `makeScalingPayload` are untouched throughout.

This audit does not migrate any test or delete any production code — that is separate,
later work per the steps above, matching how `docs/ThreeOmegaFieldSweepRouteAudit.md`
§10-11 and `docs/XYRotationRenderRouteAudit.md` were each split into a classify commit
followed by migrate/delete commits.

## 6. Conclusion

All six remaining ThreeOmega non-field-sweep renderer entry points
(`renderRAHE`, `renderRAHE1omegaVsDevice`, `renderRAHE3omegaVsDevice`, `renderHcVsT`,
`renderRT`, `renderScaling`) are dead in production — every visible ThreeOmega xy tab
already renders through the shared `tabs.buildPipelineInput(...)` +
`WorkbenchRenderPipeline.render(...)` route using a payload-only accessor that already
exists for each tab. 25 test functions across 8 files still call the obsolete entry
points directly; none of them require new production code to migrate, and two small
gaps (a warning-text location and one incidental, non-load-bearing call) need resolving
in the migration commit rather than the deletion commit. This closes out the last
"same dead-mutating-renderer pattern" item from `docs/RenderRouteAudit.md` §8.3 for
ThreeOmega specifically; IV and XYRotation's equivalents are tracked in their own audit
docs (`docs/IVRenderRouteAudit.md`, `docs/XYRotationRenderRouteAudit.md`) and were
resolved separately — see §7 below for how all three landed.

## 7. Cleanup complete

Status: **done.** Every gap flagged in §4/§5 has been resolved, in commits following
this document:

- The multiple-temperature RAHE-vs-Device warning gap (§4, §5 step 4) was resolved
  first: `makeRAHE1omegaVsDeviceWarnings`/`makeRAHE3omegaVsDeviceWarnings` (wrapping a
  shared private `_raheVsDeviceWarnings`) were added to `ThreeOmegaPlotRenderer.swift`
  and wired into `ThreeOmegaWorkspaceStore+Rendering.swift`'s `.rahe1omegaVsDevice`/
  `.rahe3omegaVsDevice` nil-payload branches, so the runtime shared route now surfaces
  this warning — previously it only existed inside the obsolete
  `_renderRAHEVsDevice`'s guard-failure branch and was never reachable from any tab a
  user could actually see.
- The `V563ThreeOmegaRAHESeriesOrderTests`/`V563ThreeOmegaFieldSweepSeriesOrderTests`
  "RAHE render path emits no seriesOrder mismatch warning" incidental, non-load-bearing
  `renderRAHE` call (§4, flagged for dropping rather than migrating) was dropped from the
  shared `makePayloads` test helper.
- All payload-only, warning, layout, and hidden-series-filtering tests migrated to
  either the existing `make*Payload` accessors directly, or a new test-only shared-route
  helper (`Tests/SpinLabAppTests/Support/ThreeOmegaSharedRenderRouteHelper.swift`) that
  mirrors `ThreeOmegaWorkspaceStore+Rendering.swift`'s `.rahe`/`.rahe1omegaVsDevice`/
  `.rahe3omegaVsDevice`/`.hcVsT`/`.rtCurve`/`.scaling` cases exactly: payload accessor →
  `TabRenderManager.buildPipelineInput` (hidden-series/order state threaded generically
  through `WorkbenchTabDisplayStateSnapshot`, matching how production filters — not
  baked into the payload accessor the way field-sweep tabs do) →
  `WorkbenchRenderPipeline.render`.
- `renderRAHE`, `renderRAHE1omegaVsDevice`, `renderRAHE3omegaVsDevice`, `renderHcVsT`,
  `renderRT`, `renderScaling`, and the private helpers used only by them
  (`_renderRAHEVsDevice`, `_render`, `_consume`, `RenderOutcome`, `defaultOptions`) have
  been **deleted** from `ThreeOmegaPlotRenderer.swift`. Verified via
  `rg -n "renderRAHE\(|renderRAHE1omegaVsDevice\(|renderRAHE3omegaVsDevice\(|renderHcVsT\(|renderRT\(|renderScaling\("
  Sources Tests`: no production definitions and no real call sites.
- `makeRAHEPayload`, `makeRAHE1omegaVsDevicePayload`, `makeRAHE3omegaVsDevicePayload`,
  `makeHcPayload`, `makeRTPayload`, `makeScalingPayload`,
  `makeRAHE1omegaVsDeviceWarnings`, `makeRAHE3omegaVsDeviceWarnings`, and
  `_makeRAHEVsDevicePayload` are unchanged and remain the only RAHE/Hc/RT/Scaling entry
  points.
- `renderTemperatureDependence` (dual-axis) and the `temperatureDependence` tab were not
  touched at any point in this cleanup.

Targeted validation: `swift test --filter 'ThreeOmega'` — 240 tests passed. See
`docs/RenderRouteAudit.md` §8.3–§8.6 for how this fits into the workbench-wide picture
alongside the ThreeOmega field-sweep, XYRotation, and IV cleanups.
