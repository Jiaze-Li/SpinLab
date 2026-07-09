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
| XYRotation | Rxx vs φ | xy | Custom — `XYRotationPlotRenderer.renderRxxVsPhi` builds `Input` and calls `render` itself inside a private `_render`, bypassing `buildPipelineInput` | Shared XY route | Yes | Medium |
| XYRotation | Rxy vs φ | xy | Custom — `renderRxyVsPhi`, same pattern as above | Shared XY route | Yes | Medium |
| ThreeOmega | RAHE | xy | Shared — payload via `ThreeOmegaPlotRenderer.makeRahePayload`, then `buildPipelineInput` + `render` | Shared XY route | No (already there) | — |
| ThreeOmega | RAHE(1ω) Dev | xy | Shared, same pattern | Shared XY route | No | — |
| ThreeOmega | RAHE(3ω) Dev | xy | Shared, same pattern | Shared XY route | No | — |
| ThreeOmega | Hc | xy | Shared, same pattern | Shared XY route | No | — |
| ThreeOmega | RT | xy | Shared, same pattern | Shared XY route | No | — |
| ThreeOmega | Scaling Law | xy | Shared, same pattern | Shared XY route | No | — |
| ThreeOmega | fieldSweep1omega (AHE 1ω) | xy / special | Custom — payload via `makeR1omegaPayload`, but `renderR1omega` builds `Input` and calls `render` directly, bypassing `buildPipelineInput` even though `preparedDisplayState` seeds it upstream | Shared XY route, pending justification review | Audit → likely yes | Medium (dynamic chart height + series-order logic currently baked into the renderer) |
| ThreeOmega | fieldSweep3omega (AHE 3ω) | xy / special | Custom — `renderR3omega`, same pattern as fieldSweep1omega | Shared XY route, pending justification review | Audit → likely yes | Medium |
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

AHE, IV, RT, and six of ThreeOmega's seven active xy tabs already follow this exactly.
XYRotation's two tabs and ThreeOmega's two field-sweep tabs keep their own copies of
override state (axis range/tick overrides, labels) inside the renderer and build+render
`Input` inside a private method, instead of going through step 3–4 above.

## 7. Notes on tabs remaining "special"

- **XYRotation Rxx/Rxy vs φ**: not structurally special — override fields line up
  almost 1:1 with `WorkbenchTabDisplayStateSnapshot`. The complicating factor is
  stacking/offset logic (`stackOffsetMultiplier`, `minGapFraction`, stacked options)
  baked into payload construction rather than the pipeline call itself, so this is
  reclassified as **migratable**, not permanently special.
- **ThreeOmega fieldSweep1omega/3omega**: deep audit complete, see
  `docs/ThreeOmegaFieldSweepRouteAudit.md`. Both tabs already call the same
  `WorkbenchRenderPipeline.render` as the shared route — the "custom" path is a
  duplicate hand-assembly of the same `Input`, plus dynamic chart height and a
  field-sweep-specific default series order that belong upstream of
  `buildPipelineInput` rather than inside the renderer. Stack offsets are already
  baked into the payload at construction time and are route-agnostic. Reclassified
  **migratable**, risk **Low–Medium**.
- **ThreeOmega Temperature Dependence**: genuinely special today — it uses a different
  pipeline type (`DualAxisRenderPipeline` vs `WorkbenchRenderPipeline`) and a separate
  display-state model. It belongs on the target **dualAxis** route, not on xy, and is
  the highest-risk migration because unifying it means giving dual-axis tabs the same
  `TabRenderManager`-mediated path that xy tabs already have, not just an `Input`
  reshuffle.
- **ThreeOmega RAHE(1ω)/RAHE(3ω) vs T**: not part of the plot-kind classification —
  these are legacy hidden tabs with no live render path. Any cleanup here is a
  dead-code removal, unrelated to the xy/dualAxis/heatmap reorganization.
- **RSM heatmap tabs**: out of scope for this audit's workflow list; noted only to
  confirm the heatmap route already exists as its own pipeline and is not entangled
  with the workflows being reorganized.
