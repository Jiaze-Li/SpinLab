# Render Route Audit — Final Summary

Status: closed. For the current architecture (plot types, pipeline boundaries,
workflow/tab mapping), see `docs/RenderRouteArchitecture.md`. This document is the
compact index of what the render-route cleanup covered and where the detailed,
process-heavy audit trail lives.

## 1. What this cleanup covered

The workbench previously mixed two render patterns for ordinary XY tabs: some
workflows called `tabs.buildPipelineInput(...)` → `WorkbenchRenderPipeline.render(...)`
(the shared route), while others had workflow-owned `PlotRenderer` methods that built
a pipeline `Input` by hand and called `render` directly, bypassing `TabRenderManager`.
This cleanup:

1. Audited every workflow's tabs by plot kind (xy / dualAxis / heatmap).
2. Migrated every xy-plot-kind tab still on a custom route onto the shared route.
3. Deleted the obsolete custom entry points once no production or test code depended
   on them.
4. Audited dual-axis (ThreeOmega Temperature Dependence) and heatmap (RSM) separately,
   confirming both are legitimately separate plot-type routes — not leftover xy
   exceptions — and require no route change.
5. Cleaned up misleading test-helper names left over from the migration.

## 2. Completed cleanup areas

| Area | Result |
|---|---|
| AHE, IV, RT, XYRotation, ThreeOmega (7 xy tabs) | All confirmed/migrated onto the shared XY route |
| ThreeOmega field sweeps (fieldSweep1omega/3omega) | Migrated; obsolete entry points removed |
| ThreeOmega RAHE / RAHE-vs-Device / Hc / RT / Scaling | Migrated; obsolete entry points removed |
| XYRotation Rxx/Rxy | Migrated; obsolete entry points removed |
| IV 1st/2nd harmonic | Migrated; obsolete entry points removed |
| ThreeOmega Temperature Dependence (dual-axis) | Audited as separate plot-type route; no migration needed |
| RSM heatmap | Audited as separate plot-type route; no migration needed |
| Test-helper naming | Renamed shared-route test helpers to match current terminology |

## 3. Removed obsolete render entry points (high level)

All of the following were workflow-owned `PlotRenderer` methods that duplicated
`WorkbenchRenderPipeline.Input` construction outside `TabRenderManager`. Each was
deleted only after its test call sites were migrated to a shared-route test helper and
`rg` confirmed zero remaining production or test call sites:

- **ThreeOmega**: `renderR1omega`, `renderR3omega`, `renderAllTabs`, `renderRAHE`,
  `renderRAHE1omegaVsDevice`, `renderRAHE3omegaVsDevice`, `renderHcVsT`, `renderRT`,
  `renderScaling`, plus the private `_render`/`_consume`/`_stackedOptions`/
  `RenderOutcome`/`defaultOptions` helpers used only by them.
- **XYRotation**: `renderRxxVsPhi`, `renderRxyVsPhi`, plus their private
  `_render`/`_consume`/`_stackedOptions`/`RenderOutcome` helpers.
- **IV**: `renderFirstHarmonicVsCurrent`, `renderSecondHarmonicVsCurrent`, and their
  backward-compatible aliases `renderVoltageVsCurrent`/`renderResistanceVsCurrent`.

Full per-entry-point call-site classification and migration steps are archived — see
§5 below.

## 4. Non-goals confirmed by audit

Dual-axis and heatmap are not xy-cleanup exceptions and were deliberately left
untouched:

- **ThreeOmega Temperature Dependence** — genuinely a different pipeline type
  (`DualAxisRenderPipeline`), two independent-scale Y axes. Forcing it onto the xy
  route would be real migration work, not a mechanical reshuffle, and isn't justified
  with a single consumer.
- **RSM heatmap** — a 2D x-y grid with colorbar/z semantics, structurally unlike a
  line-series xy payload. Already isolated in its own pipeline from the start.

See `docs/RenderRouteArchitecture.md` §6 for the standing non-goal.

## 5. Archived detailed audits

Full route diagrams, per-test-site classification tables, migration-shape writeups,
and verbatim `rg`/`swift test` output for each area live under
`docs/archive/render-route-cleanup/`:

- `ThreeOmegaFieldSweepRouteAudit.md`
- `ThreeOmegaRemainingRenderRouteAudit.md`
- `ThreeOmegaTemperatureDependenceDualAxisAudit.md`
- `RSMHeatmapRenderRouteAudit.md`
- `XYRotationRenderRouteAudit.md`
- `IVRenderRouteAudit.md`

## 6. Final validation summary

- `swift test --filter 'ThreeOmega'`: 240 tests passed.
- `swift test --filter 'XYRotation'`: 21 tests passed.
- `swift test --filter 'IV'`: 68 tests passed.
- `swift test --filter 'RSM'`: 132 tests passed.
- `swift test --filter 'Heatmap'`: 187 tests passed.
- `rg` confirms zero production definitions and zero real call sites remain for every
  entry point listed in §3 (only identically-named test-only shared-route helper
  methods remain, e.g. `XYRotationRenderRoute.renderRxxVsPhi`,
  `IVRenderRoute.renderFirstHarmonicVsCurrent`,
  `ThreeOmegaFieldSweepRenderRoute.renderR1omega`).
- No changes to `temperatureDependence` dual-axis or RSM/heatmap rendering behavior at
  any point in this cleanup.
