# Gate 8.5A — Stale PlotSystem Path Audit

> Status: audit-only branch. This gate documents stale PlotSystem path cleanup after Gate 8.4. It does not authorize Swift behavior changes or workflow grouping moves.

## Purpose

Gate 8.4 moved the mature PlotSystem surfaces into the canonical physical root:

```text
Sources/SpinLabApp/Workbench/Modules/PlotSystem/
```

Gate 8.5A audits stale references and physical leftovers that may still point agents, tests, or active architecture maps to old PlotSystem locations.

## Scope

Audit and, in a later cleanup commit, update only:

- active architecture maps;
- source-inspection tests;
- scripts or checks that read source files by path;
- physical PlotSystem leftovers outside `Workbench/Modules/PlotSystem`.

## Non-Goals

Do not use Gate 8.5A to:

- move workflow stores or workflow views;
- start the P4 workflow grouping pass;
- change renderer behavior;
- fix RT metadata, legend, or series-order semantics;
- change pack schemas;
- split `WorkbenchFeatureStore`;
- rewrite historical or archived records only to make grep output clean.

Historical documents may keep old paths when they describe past state. Active docs and tests must use current paths.

## Canonical PlotSystem Homes

| Capability | Canonical path |
|---|---|
| Canvas | `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Canvas/` |
| Pipeline | `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Pipeline/` |
| Preservation | `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Preservation/` |
| Contracts | `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Contracts/` |
| Controls/Common | `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/` |
| Controls/CartesianXY | `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/` |
| Legend | `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Legend/` |
| SeriesOrder | `Sources/SpinLabApp/Workbench/Modules/PlotSystem/SeriesOrder/` |

## Findings to Verify

### F1 — Possible physical orphan: `WorkbenchSeriesMetadataBuilder`

Observed candidate path:

```text
Sources/SpinLabApp/Workbench/PlotSystem/Legend/WorkbenchSeriesMetadataBuilder.swift
```

Expected canonical path, if this file remains PlotSystem-owned:

```text
Sources/SpinLabApp/Workbench/Modules/PlotSystem/Legend/WorkbenchSeriesMetadataBuilder.swift
```

Reason: the file builds resolver-compatible metadata for shared legend auto-resolution, so it appears to belong with PlotSystem Legend rather than a parallel `Workbench/PlotSystem` root.

Required follow-up:

- confirm there is no duplicate at the canonical path;
- move the file with no behavior changes if the orphan is confirmed;
- update any active references.

### F2 — Old active PlotSystem paths

Active docs, tests, or scripts must not rely on these old locations:

```text
Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift
Sources/SpinLabApp/Features/Workbench/PlotCanvasMouseTracker.swift
Sources/SpinLabApp/Features/Workbench/WorkbenchPlottingStore.swift
Sources/SpinLabApp/Features/Workbench/WorkbenchPlotControlsPanel.swift
Sources/SpinLabApp/Features/Workbench/WorkbenchStandardPlotControls.swift
Sources/SpinLabApp/Features/Workbench/WorkbenchAxisRangeControls.swift
Sources/SpinLabApp/Features/Workbench/WorkbenchSeriesAppearanceControls.swift
Sources/SpinLabApp/Features/Workbench/WorkbenchTitleTemplateField.swift
Sources/SpinLabApp/Features/Workbench/SharedPlotTextControls.swift
Sources/SpinLabApp/Features/Workbench/SharedPlotFontSizeControls.swift
Sources/SpinLabApp/Features/Workbench/SharedPlotTickCountControls.swift
Sources/SpinLabApp/Features/Workbench/WorkbenchSeriesOrderPanel.swift
Sources/SpinLabApp/UseCases/LegendDimensionResolver.swift
Sources/SpinLabApp/Workbench/V3/WorkbenchRenderPipeline.swift
Sources/SpinLabApp/Workbench/V3/TabRenderManager.swift
Sources/SpinLabApp/Workbench/V3/WorkbenchResultContracts.swift
Sources/SpinLabApp/Workbench/V3/WorkbenchSeriesOrderKeyResolver.swift
```

Allowed exception: historical or archived documents that explicitly describe old state.

### F3 — Deferred workflow files are not stale PlotSystem leftovers

These files are allowed to remain under `Sources/SpinLabApp/Features/Workbench/` until the separate P4 workflow grouping pass:

```text
AHEWorkspaceStore.swift
AHEWorkspaceView.swift
IVWorkspaceStore.swift
IVWorkspaceView.swift
RSMWorkspaceStore.swift
RSMWorkspaceView.swift
XYRotationWorkspaceStore.swift
XYRotationWorkspaceView.swift
ThreeOmegaWorkspaceStore*.swift
ThreeOmegaWorkspaceView.swift
```

Do not move them in Gate 8.5A.

### F4 — Explicit non-PlotSystem placements

`WorkbenchRunTraceProviding.swift` is intentionally not part of PlotSystem. It may remain in the workspace layer until a later WarningTrace / workspace lifecycle move.

`RSMViewSelector.swift` is RSM-specific. It must not be moved into PlotSystem Common or CartesianXY controls. It may be reconsidered only during a future RSM workflow grouping pass.

## Audit Commands

```bash
git grep -n \
  -e 'Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift' \
  -e 'Sources/SpinLabApp/Features/Workbench/PlotCanvasMouseTracker.swift' \
  -e 'Sources/SpinLabApp/Features/Workbench/WorkbenchPlottingStore.swift' \
  -e 'Sources/SpinLabApp/Features/Workbench/WorkbenchPlotControlsPanel.swift' \
  -e 'Sources/SpinLabApp/Features/Workbench/WorkbenchStandardPlotControls.swift' \
  -e 'Sources/SpinLabApp/Features/Workbench/WorkbenchAxisRangeControls.swift' \
  -e 'Sources/SpinLabApp/Features/Workbench/WorkbenchSeriesAppearanceControls.swift' \
  -e 'Sources/SpinLabApp/Features/Workbench/WorkbenchTitleTemplateField.swift' \
  -e 'Sources/SpinLabApp/Features/Workbench/SharedPlotTextControls.swift' \
  -e 'Sources/SpinLabApp/Features/Workbench/SharedPlotFontSizeControls.swift' \
  -e 'Sources/SpinLabApp/Features/Workbench/SharedPlotTickCountControls.swift' \
  -e 'Sources/SpinLabApp/Features/Workbench/WorkbenchSeriesOrderPanel.swift' \
  -e 'Sources/SpinLabApp/UseCases/LegendDimensionResolver.swift' \
  -e 'Sources/SpinLabApp/Workbench/V3/WorkbenchRenderPipeline.swift' \
  -e 'Sources/SpinLabApp/Workbench/V3/TabRenderManager.swift' \
  -e 'Sources/SpinLabApp/Workbench/V3/WorkbenchResultContracts.swift' \
  -e 'Sources/SpinLabApp/Workbench/V3/WorkbenchSeriesOrderKeyResolver.swift' \
  -- Sources Tests docs scripts
```

```bash
find Sources/SpinLabApp/Workbench -path '*PlotSystem*' -type f | sort
git grep -n 'Sources/SpinLabApp/Workbench/PlotSystem/' -- Sources Tests docs scripts
git grep -n 'Workbench/PlotSystem/' -- Sources Tests docs scripts
```

```bash
find Sources/SpinLabApp/Features/Workbench -maxdepth 1 -type f | sort | grep -E 'Plot|SharedPlot|SeriesOrder|AxisRange|Legend|Canvas|RenderPipeline|ResultContracts|TabRender'
```

## Cleanup Rules

- Treat active tests and active architecture maps as authoritative. Fix stale paths there.
- Treat archived/history docs as historical records. Do not rewrite them unless they are explicitly marked current.
- Move only confirmed PlotSystem physical leftovers.
- Keep each cleanup commit move-only or docs-only.
- If a cleanup requires behavior changes, stop and open a separate architecture gate.

## Validation Plan

After any cleanup commit:

```bash
swift build
swift test --filter V78EPlotSystemStructuralBoundaryTests
swift test --filter V710PlotControlsMigrationTests
scripts/check_required_actions.sh
```

## Closeout Criteria

Gate 8.5A can close when:

- active docs/tests/scripts no longer point to old PlotSystem source paths;
- no physical PlotSystem files remain under a non-canonical `Workbench/PlotSystem` root;
- workflow files intentionally deferred to P4 are documented as deferred, not treated as stale leftovers;
- validation status is recorded in this file or a closeout note.
