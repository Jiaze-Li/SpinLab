# Plot Controls Split Plan

## Purpose

This document defines the ownership split for Workbench Plot Controls before further physical moves or Swift refactors.

The current problem is not only file location. Some controls files mix three responsibilities:

1. common plot controls,
2. Cartesian XY-specific controls,
3. workflow-owned controls injected through slots.

Gate 8.4 should not hide this by only moving files into a cleaner folder.

## Target Ownership Model

### Common Plot Controls

Common Plot Controls are controls that can apply to more than one plot family.

Examples:

- plot title override,
- X/Y label override when the plot has X/Y axes,
- shared font-size controls,
- shared control container layout,
- common control row layout utilities.

Target home:

Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/

Common controls must not know AHE, 3omega, XY rotation, IV, RSM, or any workflow-specific physics.

### Cartesian XY Controls

Cartesian XY Controls apply specifically to line/scatter-style XY charts.

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

Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/

Cartesian XY controls may depend on XY plot layout, style, and tab render preservation. They must not know workflow physics.

### Workflow-Owned Controls

Workflow-owned controls have meaning specific to one workflow or physics model.

Examples:

- AHE-specific controls,
- 3omega fitting or geometry controls,
- XY rotation detrend or baseline controls,
- RSM view selector,
- heatmap colormap or color-scale controls.

These must not be absorbed into common Plot Controls.

If they need to appear inside the same visual panel, they must enter through an explicit slot.

## Module Cleanliness Criteria

A control module is not clean merely because its property names look correct.

A control module is clean only when all of the following are true:

1. Its name matches its real responsibility.
2. Its inputs are inside its declared scope.
3. It does not know workflow-specific physics unless it is a workflow-owned module.
4. It does not own state that belongs to another module.
5. It emits user intent through callbacks instead of directly mutating unrelated systems.
6. It can be reused in its claimed scope without hidden assumptions.

For example, a shared text-control module may display title, X-label, and Y-label fields. It may receive current values and emit committed text changes. It must not decide what the semantic X or Y axis means, must not know whether the workflow is AHE or 3omega, and must not own tab render state.

For Cartesian XY controls, the same rule applies. A Cartesian XY module may provide line/scatter mode, tick density, axis range, stack controls, series order, or point-tag controls. It must not decide the physics meaning of a tab, a curve, a fitting method, or a workflow-specific parameter.

This means physical relocation is not enough. A file should not move into a cleaner folder unless its actual behavior matches the module boundary, or unless the debt is explicitly documented before the move.

## Physical Move Rule

Do not move all controls together just because they contain the word Plot or Controls.

A file can move into Plot System only if its responsibility is one of:

- Common Plot Controls,
- Cartesian XY Plot Controls,
- Heatmap Plot Controls,
- Plot Controls layout shell that does not own workflow semantics.

If a file contains workflow-specific decision logic, keep it with the workflow assembly or split it first.

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

### P1.6d Cartesian XY Controls Physical Move

Move Cartesian XY-specific controls after confirming they do not own workflow semantics.

Candidate files:

- WorkbenchPlotControlsPanel.swift
- WorkbenchStandardPlotControls.swift
- WorkbenchAxisRangeControls.swift
- WorkbenchSeriesAppearanceControls.swift

This gate needs more scrutiny because WorkbenchStandardPlotControls accepts workflow-owned bindings and slots.

### P1.6e Protocol Boundary Decision

WorkbenchPlottingStore.swift has been split: run-trace read access stays in the Workbench workspace layer, while plot interaction and Cartesian XY plot-state contracts live under Plot System Contracts.

It is not just a controls view. It is a protocol boundary between workflow stores and plot interaction surfaces.

## Decision

Do not perform a bulk Controls move.

First clarify and document ownership. After that, move only files whose responsibility is already clear.
