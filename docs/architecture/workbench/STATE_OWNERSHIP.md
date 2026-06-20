# Workbench State Ownership

This document defines where Workbench state belongs. It is the ownership contract for shared plot defaults, workflow-local display overrides, workflow packs, sidecars, and measurement sets.

## Global Plot Defaults

Global Plot Defaults are shared plot appearance defaults across workflows.

Owned keys:

- `titleFontSize`
- `axisTitleFontSize`
- `tickLabelFontSize`
- `legendFontSize`
- `pointLabelFontSize`
- `plotFontName`
- `plotBoldFontName`

Rules:

- These values are app-level plot appearance state.
- A change in one workflow must be inherited by the other workflows.
- They persist across app relaunch.
- They do not belong in workflow pack config.

## chartStyleOverrides / styleParams

`chartStyleOverrides` and `styleParams` are render-time transport, not workflow semantics.

Rules:

- Use them for plot-style transport and workflow-local style overrides only when required.
- Do not use them to encode workflow-specific physical meaning.
- Global plot defaults may be merged into render-time style params, but the underlying ownership stays separate.

## TabRenderState

`TabRenderState` is the per-tab / per-plot display override owner.

Owned fields:

- `titleOverride`
- `xLabelOverride`
- `yLabelOverride`
- legend position
- series rename / reorder / point-label visibility state

Rules:

- These overrides are per-tab and may be source-scoped so stale labels do not leak across samples.
- They must remain independent of global plot defaults.

## Workflow Pack Config

Workflow pack config owns workflow-specific physical or analysis options.

Examples:

- IV `xCurrentBasis` (`Peak` / `RMS`)
- IV channel mapping
- IV scale factors
- workflow-specific fitting / analysis options

Rules:

- Pack config is workflow-owned.
- Old packs must load safely.
- Use `decodeIfPresent` with safe defaults for newly added pack fields.
- Raw imported data must not be modified for display-unit changes; display scaling belongs in workflow renderers.

## WorkbenchChartStyle

`WorkbenchChartStyle` is the renderer style contract.

Owns:

- default font family
- font-size parsing
- tick target parsing

Rules:

- It is responsible for renderer style resolution only.
- It should not know workflow physics.

## Sidecar

The sidecar owns measurement metadata and workflow identity routing.

Owned fields:

- `autoDetectedWorkflow`
- `workflowOverride`
- `workflowSource`
- `resolvedWorkflow`

Rules:

- Sidecar is the measurement-level workflow metadata source.
- It records workflow routing state, not plot state.

## MeasurementSet

`MeasurementSet` owns set membership.

Owned fields:

- `memberFileNames`

Rules:

- Do not store set membership in sidecar.
- Set membership lives in the Library domain model.
