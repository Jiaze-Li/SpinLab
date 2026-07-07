# DualAxis Control Contract

## Purpose

DualAxis is the Plot System render path for charts with one X axis and two independent Y axes.

This document records the control/state contract for DualAxis before the template implementation. It supplements `PLOT_SYSTEM.md`, `PLOT_CONTROLS_SPLIT_PLAN.md`, `PHYSICAL_MODULE_LAYOUT.md`, and the 3ω Assembly record; it does not replace those documents.

## Ownership

| Plot System owns | Workflow Assembly owns |
|---|---|
| DualAxis payload type, layout, renderer, render pipeline | scientific meaning of each left/right series |
| DualAxis display-state type and captured render snapshot | unit conversion and default physics labels |
| DualAxis controls panel and generic template defaults | workflow-specific payload construction |
| left/right axis geometry, marker policy, axis color policy | workflow-specific warnings and result validity |

Plot System must not infer physics meaning from workflow ID, tab name, axis label text, sample metadata, or series values.

Workflow Assemblies must not own renderer geometry, generic dual-axis style controls, or persistent dual-axis display overrides.

## Target Physical Home

```text
Sources/SpinLabApp/Workbench/Modules/PlotSystem/DualAxis/
  DualAxisPlotPayload.swift
  DualAxisPlotLayout.swift
  DualAxisChartRenderer.swift
  DualAxisRenderPipeline.swift
  DualAxisDisplayState.swift
  DualAxisDisplayStateSnapshot.swift
  DualAxisPlotControlsPanel.swift
  DualAxisExportSnapshot.swift        // optional if export needs a distinct value type
```

The first four files already represent the render path. The display-state, controls, and export snapshot files are the next template/control target. If the implementation reuses a generalized preservation type instead of `DualAxisDisplayState`, the ownership rule stays the same: DualAxis display overrides must not be stored in a Cartesian XY-only `TabRenderState` shape.

## Render Input Rule

DualAxis rendering reads only:

```text
DualAxisPlotPayload
+ DualAxisDisplayStateSnapshot
+ global plot defaults / renderer defaults
```

The renderer must not read live store state. The renderer must not mutate controls or preservation state.

## Controls Rule

DualAxis controls edit display state only. The first template should cover:

- title override,
- X-axis label override,
- left Y-axis label override,
- right Y-axis label override,
- X manual range override,
- left Y manual range override,
- right Y manual range override,
- left/right series style,
- left/right marker policy,
- left/right axis color policy.

Controls emit committed user intent through callbacks or a typed display-state binding. They do not construct scientific payloads.

## Canvas Rule

The shared plot canvas remains a PNG display shell and interaction dispatcher.

For DualAxis V1:

- labels, ranges, marker policy, and style editing live in Plot Controls, not on the canvas;
- the canvas may show the rendered PNG and Copy PNG context menu;
- any future dual-axis hit-testing must use an explicit DualAxis layout contract, not a fake `WorkbenchPlotLayout`.

## Export Rule

Cartesian XY Copy PNG no longer re-renders at copy time (see `modules/PLOT_SYSTEM.md`); it copies the canvas's current imageData directly. DualAxis Copy PNG follows the same rule: it uses the cached rendered image data shown on screen. There is no per-scale DualAxis export path to build toward.

## Template Rule

The first template may default to a paper-like dual-axis presentation:

- left axis visually paired with left series,
- right axis visually paired with right series,
- line + marker support,
- open marker support,
- distinct left/right axis colors.

These are display defaults. They are not 3ω physics and must not mention `σxx`, `E_AHE`, RAHE, or Temperature Dependence.

## 3ω Temperature Dependence Adapter Boundary

The 3ω workflow may construct a DualAxis payload where:

```text
x = T
left y = E_AHE^(3ω) / E_xx^3
right y = σxx
```

That adapter owns physics labels, unit scaling, point sorting, and warning policy. It must not duplicate DualAxis display state.

## 3ω Temperature Dependence Tests To Add With Implementation

- Payload points are sorted by `T` before line rendering.
- Left-axis values match the declared `E_AHE^(3ω) / E_xx^3` display contract.
- Right-axis values match the declared `σxx` display contract.
- Default labels and unit scale factors are asserted.
- Empty or invalid scaling results produce no misleading DualAxis plot.
- When scale-aware DualAxis export is implemented, Copy PNG/export re-renders from payload + display snapshot at the requested scale.
