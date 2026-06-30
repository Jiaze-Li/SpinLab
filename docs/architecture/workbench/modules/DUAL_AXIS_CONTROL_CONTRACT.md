# DualAxis Control Contract

## Purpose

DualAxis is the Plot System render path for charts with one X axis and two independent Y axes.

This document records the control/state contract for DualAxis before the template implementation. It supplements `PLOT_SYSTEM.md` and `PLOT_CONTROLS_SPLIT_PLAN.md`; it does not replace either document.

## Ownership

| Plot System owns | Workflow Assembly owns |
|---|---|
| DualAxis payload type, layout, renderer, render pipeline | scientific meaning of each left/right series |
| DualAxis display-state type and captured render snapshot | unit conversion and default physics labels |
| DualAxis controls panel and generic template defaults | workflow-specific payload construction |
| left/right axis geometry, marker policy, axis color policy | workflow-specific warnings and result validity |

Plot System must not infer physics meaning from workflow ID, tab name, axis label text, sample metadata, or series values.

Workflow Assemblies must not own renderer geometry, generic dual-axis style controls, or persistent dual-axis display overrides.

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

Copy PNG/export must re-render from payload + display snapshot at the requested scale.

Cached image data may be used only as a fallback where explicitly documented. Export must not re-run workflow analysis or reapply non-idempotent workflow transforms.

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
