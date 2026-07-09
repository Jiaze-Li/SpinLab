# Render Route Audit — Workbench Plot Rendering by Plot Kind

Status: audit only. No rendering behavior, analysis logic, or renderer code was changed
to produce this document.

## 1. Target architecture

- A workflow's job is to produce a **plot payload** (data + minimal presentation intent)
  and nothing else — no axis-override bookkeeping, no pipeline construction.
- `TabRenderManager` is responsible for **display/control state**: per-tab overrides
  (title, axis range/tick overrides, series order, hidden series), shared display
  settings (grid, series render mode, chart style, legend anchor), and merging that
  state into a renderer `Input` via `preparedDisplayState(...)` + `buildPipelineInput(...)`.
- Renderer routes are organized **by plot kind**, not by workflow:
  1. **xy** — the common single-axis chart route, shared across all xy tabs regardless
     of which workflow produced the payload.
  2. **dualAxis** — the shared dual-axis chart route.
  3. **heatmap** — the shared heatmap route.
  4. **special** — only when a tab has a genuine structural reason it cannot fit one of
     the three routes above (justification required per tab, see §7).

Concretely: a workflow store builds a payload → hands it to `TabRenderManager` for
display-state preparation → the resulting `Input` is rendered by the plot-kind's shared
pipeline (`WorkbenchRenderPipeline`, `DualAxisRenderPipeline`, `HeatmapRenderPipeline`).
Nothing workflow-specific should live inside a pipeline call.

## 2–5. Tabs: plot kind, current route, target route, migration need

| Workflow | Tab | Plot kind | Current route | Target route | Migration needed | Risk |
|---|---|---|---|---|---|---|
| AHE | main | xy | Shared — `AHEWorkspaceStore` → `tabs.buildPipelineInput` → `WorkbenchRenderPipeline.render` | Shared XY route | No (already there) | — |
| IV | 1st/I (voltage) | xy | Shared — `IVWorkspaceStore._rerenderActiveTab` → `tabs.buildPipelineInput` → `WorkbenchRenderPipeline.render` | Shared XY route | No (already there) | — |
| IV | 2nd/I (resistance) | xy | Shared, same as above | Shared XY route | No (already there) | — |
| RT | R(T) | xy | Shared — `RTPlotRenderer` is payload-only; `RTWorkspaceStore` does `buildPipelineInput` + `render` | Shared XY route | No (already there, cleanest example) | — |
| XYRotation | Rxx vs φ | xy | Shared — `XYRotationWorkspaceStore` → `makeRxxVsPhiDisplayPayload` → `tabs.buildPipelineInput` → `WorkbenchRenderPipeline.render` | Shared XY route | No (migrated) | — |
| XYRotation | Rxy vs φ | xy | Shared, same pattern via `makeRxyVsPhiDisplayPayload` | Shared XY route | No (migrated) | — |
| ThreeOmega | RAHE | xy | Shared — payload via `ThreeOmegaPlotRenderer.makeRAHEPayload`, then `buildPipelineInput` + `render` | Shared XY route | No (already there) | — |
| ThreeOmega | RAHE(1ω) Dev | xy | Shared, same pattern | Shared XY route | No | — |
| ThreeOmega | RAHE(3ω) Dev | xy | Shared, same pattern | Shared XY route | No | — |
| ThreeOmega | Hc | xy | Shared, same pattern | Shared XY route | No | — |
| ThreeOmega | RT | xy | Shared, same pattern | Shared XY route | No | — |
| ThreeOmega | Scaling Law | xy | Shared, same pattern | Shared XY route | No | — |
| ThreeOmega | fieldSweep1omega (AHE 1ω) | xy | Shared — `makeR1omegaDisplayPayload` → `tabs.buildPipelineInput` → `WorkbenchRenderPipeline.render`. Obsolete `renderR1omega`/`renderAllTabs` entry points deleted (see `docs/ThreeOmegaFieldSweepRouteAudit.md` §11) | Shared XY route | No (migrated, cleanup complete) | — |
| ThreeOmega | fieldSweep3omega (AHE 3ω) | xy | Shared — `makeR3omegaDisplayPayload`, same pattern. Obsolete `renderR3omega` entry point deleted | Shared XY route | No (migrated, cleanup complete) | — |
| ThreeOmega | RAHE(1ω)/RAHE(3ω) vs T | n/a | Legacy/hidden tabs, excluded from `visibleTabs`, always emit empty output, no pipeline call | N/A (dead code) | Consider removal separately | Low |
| ThreeOmega | Temperature Dependence | dualAxis | Custom, separate pipeline entirely — `renderTemperatureDependence` builds `DualAxisRenderPipeline.Input` and calls `DualAxisRenderPipeline.render`, a distinct type from `WorkbenchRenderPipeline` | Unified dual-axis route (shared `DualAxisRenderPipeline` entry point, reached the same way xy tabs reach `WorkbenchRenderPipeline`) | Yes | High (own display-state model, `ThreeOmegaWorkspaceStore+DualAxisControls.swift`) |
| RSM | heatmap tabs | heatmap | Separate stack — `HeatmapRenderPipeline` / `HeatmapPlotPayload` / `HeatmapPlotLayout` under `Workbench/V3/Heatmap/`, used only by `RSMWorkspaceStore` | Audit only for now | Audit only | — |

## 6. "Shared route" mechanics (for reference)

`TabRenderManager` never calls `render` itself — it only assembles `Input`:
1. Workflow store builds a `WorkbenchPlotPayload`.
2. `tabs.preparedDisplayState(for:sourceIdentityKey:policy:)` produces a
   `WorkbenchTabDisplayStateSnapshot`, clearing stale per-tab overrides when the
   source identity changed.
3. `tabs.buildPipelineInput(payload:tabState:...)` merges that snapshot with shared
   display settings into a `WorkbenchRenderPipeline.Input`.
4. The workflow store itself calls `WorkbenchRenderPipeline.render(input)`.

AHE, IV, RT, XYRotation's two tabs, and all seven active ThreeOmega xy tabs now follow
this exactly. See §8 for the finalized per-workflow state — the obsolete-renderer
dead-code cleanup on the workflow `PlotRenderer` structs is now complete (§8.3).

## 7. Notes on tabs remaining "special"

- **ThreeOmega Temperature Dependence**: genuinely special today — it uses a different
  pipeline type (`DualAxisRenderPipeline` vs `WorkbenchRenderPipeline`) and a separate
  display-state model. It belongs on the target **dualAxis** route, not on xy, and is
  the highest-risk migration because unifying it means giving dual-axis tabs the same
  `TabRenderManager`-mediated path that xy tabs already have, not just an `Input`
  reshuffle. Out of scope for this (xy-only) audit; a known pre-existing test failure
  in this area is tracked separately and was not touched here (§8.5).
- **ThreeOmega RAHE(1ω)/RAHE(3ω) vs T**: not part of the plot-kind classification —
  these are legacy hidden tabs with no live render path. Any cleanup here is a
  dead-code removal, unrelated to the xy/dualAxis/heatmap reorganization.
- **RSM heatmap tabs**: out of scope for this audit's workflow list; noted only to
  confirm the heatmap route already exists as its own pipeline and is not entangled
  with the workflows being reorganized.

## 8. Finalized state (shared XY route audit)

This section is the authoritative summary as of the final ordinary-xy render route
cleanup landing (ThreeOmega field sweeps + remaining xy tabs, XYRotation, IV — see
§8.3). §2–§7 above are kept as the historical record of how each tab got here; read this
section for "where things stand now."

### 8.1 Shared XY confirmed

Every one of these renders via: workflow store builds a payload → payload-only accessor
(or, for AHE/RT, the payload is the only thing the renderer produces) →
`tabs.buildPipelineInput(...)` → `WorkbenchRenderPipeline.render(...)`. No workflow-owned
code calls `WorkbenchRenderPipeline.render` from inside a `PlotRenderer` method anymore
for any of these tabs.

- **AHE** — main tab
- **IV** — 1st/I (voltage), 2nd/I (resistance)
- **RT** — R(T)
- **XYRotation** — Rxx vs φ, Rxy vs φ
- **ThreeOmega** — RAHE, RAHE(1ω) Dev, RAHE(3ω) Dev, Hc, RT, Scaling Law,
  fieldSweep1omega (AHE 1ω), fieldSweep3omega (AHE 3ω) — all seven visible xy tabs

### 8.2 Non-shared routes with valid reason (out of scope, unchanged)

- **ThreeOmega Temperature Dependence** — separate `DualAxisRenderPipeline` / dual-axis
  display-state model. Structurally different plot kind, not a leftover custom route.
- **RSM heatmap tabs** — separate `HeatmapRenderPipeline` / `HeatmapPlotPayload` /
  `HeatmapPlotLayout` stack. Structurally different plot kind, not a leftover custom
  route.

### 8.3 Removed obsolete routes

All obsolete non-shared "ordinary xy" render entry points identified by this audit have
now been deleted. Each removal followed the same template: migrate tests to a
shared-route test helper (payload accessor → `TabRenderManager.buildPipelineInput` →
`WorkbenchRenderPipeline.render`), confirm `rg` shows no remaining real call sites, then
delete the obsolete entry point and any private helpers used only by it.

- **ThreeOmega field-sweep entry points** — `renderR1omega`, `renderR3omega`, and
  `renderAllTabs` (plus the private `_stackedOptions` helper that only fed them) are
  **fully deleted** from `ThreeOmegaPlotRenderer.swift`. See
  `docs/ThreeOmegaFieldSweepRouteAudit.md` §11. Verified via
  `rg -n "renderR1omega\(|renderR3omega\(|renderAllTabs\(" Sources Tests`: no
  production definitions, no real call sites.
- **ThreeOmega remaining xy tabs** — `renderRAHE`, `renderRAHE1omegaVsDevice`,
  `renderRAHE3omegaVsDevice`, `renderHcVsT`, `renderRT`, `renderScaling` (plus the
  private `_renderRAHEVsDevice`, `_render`, `_consume`, `RenderOutcome`, and
  `defaultOptions` helpers used only by them) are **fully deleted** from
  `ThreeOmegaPlotRenderer.swift`. The RAHE-vs-Device multiple-temperature warning that
  used to live only inside the obsolete `_renderRAHEVsDevice` guard-failure branch was
  moved into the shared runtime route first (`makeRAHE1omegaVsDeviceWarnings`/
  `makeRAHE3omegaVsDeviceWarnings` in `ThreeOmegaPlotRenderer.swift`, wired into
  `ThreeOmegaWorkspaceStore+Rendering.swift`'s `.rahe1omegaVsDevice`/
  `.rahe3omegaVsDevice` nil-payload branches), so no warning behavior was lost. See
  `docs/ThreeOmegaRemainingRenderRouteAudit.md`. Verified via
  `rg -n "renderRAHE\(|renderRAHE1omegaVsDevice\(|renderRAHE3omegaVsDevice\(|renderHcVsT\(|renderRT\(|renderScaling\(" Sources Tests`:
  no production definitions, no real call sites.
- **XYRotation** old custom Rxx/Rxy renderer route — `renderRxxVsPhi`/`renderRxyVsPhi`
  (plus the private `_render`/`_consume`/`_stackedOptions`/`RenderOutcome` helpers used
  only by them) are **fully deleted** from `XYRotationPlotRenderer.swift`, superseded by
  `makeRxxVsPhiDisplayPayload`/`makeRxyVsPhiDisplayPayload` + `buildPipelineInput`. See
  `docs/XYRotationRenderRouteAudit.md`. Verified via
  `rg -n "renderRxxVsPhi\(|renderRxyVsPhi\(" Sources Tests`: no production definitions,
  no real call sites (only the identically-named test-only `XYRotationRenderRoute`
  helper methods remain).
- **IV entry points** — `renderFirstHarmonicVsCurrent`, `renderSecondHarmonicVsCurrent`,
  and their backward-compatible aliases `renderVoltageVsCurrent`/
  `renderResistanceVsCurrent` are **fully deleted** from `IVPlotRenderer.swift`,
  superseded by `makeFirstHarmonicPayloads`/`makeSecondHarmonicPayloads` +
  `buildPipelineInput`. See `docs/IVRenderRouteAudit.md`. Verified via
  `rg -n "renderFirstHarmonicVsCurrent\(|renderSecondHarmonicVsCurrent\(|renderVoltageVsCurrent\(|renderResistanceVsCurrent\(" Sources Tests`:
  no production definitions, no real call sites (only the identically-named test-only
  `IVRenderRoute` helper methods remain).

### 8.4 Remaining non-shared routes (intentional, out of scope)

- **ThreeOmega Temperature Dependence** — still genuinely special: a different pipeline
  type (`DualAxisRenderPipeline` vs `WorkbenchRenderPipeline`) and a separate
  display-state model. Unifying it onto the target **dualAxis** route is real migration
  work (giving dual-axis tabs the same `TabRenderManager`-mediated path xy tabs already
  have), not a mechanical `Input` reshuffle, and remains intentionally out of scope —
  it was not touched by any of the xy-route cleanups above.
- **RSM heatmap tabs** — still a structurally separate `HeatmapRenderPipeline` /
  `HeatmapPlotPayload` / `HeatmapPlotLayout` stack, intentionally independent of the xy
  route reorganization. Not touched.

### 8.5 Known pre-existing issue (still present)

- `V5115ThreeOmegaWorkspaceStoreCharacterizationTests
  .testTransportDerivedRefreshUsesIngestionResultAndCurrentV3Method` still fails on
  `main`, unrelated to any of the xy-route cleanups above (it was already failing before
  the field-sweep cleanup started, per the original `git stash` bisection, and none of
  the xy cleanups touch `rerenderTemperatureDependenceForDualAxisControlChange` or
  `renderTemperatureDependence`). It's a source-string characterization assertion, not a
  behavioral regression. Confirmed still failing as of this update
  (`swift test --filter 'V5115ThreeOmegaWorkspaceStoreCharacterizationTests'`). Dual-axis
  is out of scope for the xy cleanup — not fixed here.

### 8.6 Validation summary (as of this update)

- `swift test --filter 'ThreeOmega'`: 240 tests passed.
- `swift test --filter 'XYRotation'`: 21 tests passed.
- `swift test --filter 'IV'`: 68 tests passed.
- `rg` confirms zero production definitions and zero real call sites remain for every
  entry point listed in §8.3 (only test-only shared-route helper methods of the same
  name remain, e.g. `XYRotationRenderRoute.renderRxxVsPhi`, `IVRenderRoute
  .renderFirstHarmonicVsCurrent`, `ThreeOmegaFieldSweepRenderRoute.renderR1omega`).
- No changes to `temperatureDependence` dual-axis or RSM/heatmap behavior.
