# Plot Controls Split Plan

## Purpose

This document defines the ownership split for Workbench Plot Controls before further physical moves or Swift refactors.

The current problem is not only file location. Plot-control code can mix five responsibilities:

1. common controls shared by multiple plot families,
2. Cartesian XY-specific controls,
3. DualAxis-specific controls,
4. Heatmap-specific controls,
5. workflow-owned controls injected through explicit slots.

A control file is not clean merely because its name contains `Plot` or `Controls`. It is clean only when its UI, state inputs, and callbacks stay inside one declared ownership scope.

## Target Ownership Model

### Common Plot Controls

Common Plot Controls are controls that can apply to more than one plot family.

Examples:

- plot title override,
- X-axis label override,
- generic axis-title label fields when the caller supplies the axis role,
- shared font-size controls,
- shared control container layout,
- common control row layout utilities.

Target home:

```text
Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/
```

Common controls must not know AHE, 3omega, XY Rotation, IV, RSM, Temperature Dependence, scaling physics, heatmap Z semantics, or any workflow-specific physics.

### Cartesian XY Plot Controls

Cartesian XY Plot Controls apply specifically to line/scatter-style Cartesian XY charts.

Examples:

- line/scatter render mode,
- X/Y tick density,
- X/Y manual axis range,
- line width and scatter radius,
- stacked-series controls,
- stack offset,
- minimum gap,
- series reorder,
- point tags.

Target home:

```text
Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/
```

Cartesian XY controls may depend on XY plot layout, XY style, and tab render preservation. They must not know workflow physics.

### DualAxis Plot Controls

DualAxis Plot Controls apply specifically to two-independent-Y-axis charts.

Examples:

- title override routed through the common text-control surface,
- X-axis label override,
- left Y-axis label override,
- right Y-axis label override,
- X manual range,
- left Y manual range,
- right Y manual range,
- left/right series style,
- left/right marker policy,
- left/right axis color policy.

Target home:

```text
Sources/SpinLabApp/Workbench/Modules/PlotSystem/DualAxis/
```

DualAxis controls may know the geometry of a dual-Y chart: left axis, right axis, X axis, left/right series families, and dual-axis export state. They must not know whether a left series represents `E_AHE^(3ω)/E_xx^3`, `σxx`, RAHE, temperature dependence, or any other workflow quantity.

DualAxis rendering must read a captured display-state snapshot. The renderer must not infer style from workflow ID, tab name, axis label text, or sample metadata.

### Heatmap Plot Controls

Heatmap Plot Controls apply specifically to grid/Z-value charts.

Examples:

- colormap picker,
- Z-axis / colorbar label override,
- color scale range override,
- heatmap tick or colorbar style controls.

Target home:

```text
Sources/SpinLabApp/Workbench/Modules/PlotSystem/Heatmap/
```

Heatmap controls may know heatmap geometry: grid rect, colorbar, Z range, and colormap. They must not know RSM physics. RSM-specific view selection or dataset compatibility checks stay workflow-owned and enter through a host-controls slot.

### Workflow-Owned Controls

Workflow-owned controls have meaning specific to one workflow or physics model.

Examples:

- AHE-specific controls,
- 3omega geometry, fitting, V3ω method, RAHE method, RT auxiliary input, or scaling result controls,
- XY Rotation detrend or baseline controls,
- RSM view selector and RSM dataset compatibility controls.

These must not be absorbed into Common, Cartesian XY, DualAxis, or Heatmap controls.

If they need to appear inside the same visual panel, they must enter through an explicit slot or binding whose ownership remains declared by the Workflow Assembly.

## Module Cleanliness Criteria

A control module is not clean merely because its property names look correct.

A control module is clean only when all of the following are true:

1. Its name matches its real responsibility.
2. Its inputs are inside its declared scope.
3. It does not know workflow-specific physics unless it is a workflow-owned module.
4. It does not own state that belongs to another module.
5. It emits user intent through callbacks instead of directly mutating unrelated systems.
6. It can be reused in its claimed scope without hidden assumptions.

For example, a shared text-control module may display title, X-label, and axis-label fields. It may receive current values and emit committed text changes. It must not decide what the semantic X, left Y, right Y, or Z axis means. It must not know whether the workflow is AHE, 3omega, RSM, or XY Rotation, and must not own tab render state.

For plot-family controls, the same rule applies. A Cartesian XY module may provide line/scatter mode, tick density, axis range, stack controls, series order, or point-tag controls. A DualAxis module may provide left/right axis and series style controls. A Heatmap module may provide colormap and Z-range controls. None of these modules may decide the physics meaning of a tab, a curve, a fitting method, or a workflow-specific parameter.

This means physical relocation is not enough. A file should not move into a cleaner folder unless its actual behavior matches the module boundary, or unless the debt is explicitly documented before the move.

## Physical Move Rule

Do not move all controls together just because they contain the word Plot or Controls.

A file can move into Plot System only if its responsibility is one of:

- Common Plot Controls,
- Cartesian XY Plot Controls,
- DualAxis Plot Controls,
- Heatmap Plot Controls,
- Plot Controls layout shell that does not own workflow semantics.

If a file contains workflow-specific decision logic, keep it with the workflow assembly or split it first.

Current examples of the "layout shell" category (not plot-family controls, not workflow-owned): `WorkbenchPlotNavigationStrip` (workflow-agnostic tab/stack/gap row shared by CartesianXY workflows and 3ω's workspace-level tab strip) and `WorkbenchPlotControlsPluginSection` (divider-delimited slot boundary for workflow-owned content; must not carry result/status/info display). See `PLOT_SYSTEM.md` → "Plot Controls Shell Blocks" for the full shell inventory, including `WorkbenchPlotControlsPanel` and `WorkbenchStandardPlotControls`, which remain CartesianXY-scoped rather than universal shells.

## Documentation Noise Rule

Active docs should expose only current contracts and first-read routes. Historical gate closeouts, handoffs, and audit logs should live under `history/` or `archive/` and should not appear in the normal reading path unless they are the canonical evidence for a current boundary.

Do not delete historical records merely to make the tree shorter. Move or de-emphasize them so the active architecture surface stays readable.

## Proposed Next Gates

### P1.6b Controls Design Alignment

No Swift behavior change.

Tasks:

- document this split,
- update module docs to reference this split,
- mark current files as mixed where necessary.

### P1.6c Common Controls Physical Move

Move only clearly common controls.

Candidate files:

- SharedPlotTextControls.swift
- SharedPlotFontSizeControls.swift
- SharedPlotTickCountControls.swift

### P1.6d Plot-Family Controls Physical Move

Move plot-family-specific controls after confirming they do not own workflow semantics.

Candidate families:

- Cartesian XY controls: WorkbenchPlotControlsPanel.swift, WorkbenchStandardPlotControls.swift, WorkbenchAxisRangeControls.swift, WorkbenchSeriesAppearanceControls.swift.
- DualAxis controls: DualAxis display state, dual-axis controls panel, dual-axis range/style controls.
- Heatmap controls: Heatmap controls panel, colormap/Z-range controls.

This gate needs scrutiny because standard control composers accept workflow-owned bindings and slots.

### P1.6e Protocol Boundary Decision

WorkbenchPlottingStore.swift has been split: run-trace read access stays in the Workbench workspace layer, while plot interaction and Cartesian XY plot-state contracts live under Plot System Contracts.

It is not just a controls view. It is a protocol boundary between workflow stores and plot interaction surfaces.

## Decision

Do not perform a bulk Controls move.

First clarify and document ownership. After that, move only files whose responsibility is already clear.
