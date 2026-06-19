# Workbench Workflow Extension

This document records the extension rules for adding or changing workflows and workflow controls.

## Plot System Contract

The shared Plot System owns:

- font family
- font-size rendering
- tick formatting
- tick overlap protection
- axis drawing
- label drawing
- legend layout
- PNG rendering
- layout measurement consistency

Workflow renderers own:

- domain-specific data transformations
- physical unit conversion
- workflow-specific default labels
- workflow-specific controls
- workflow-specific pack persistence
- data-to-`WorkbenchPlotPayload` conversion

Examples:

- Times New Roman default font belongs to the common Plot System.
- compact scientific tick labels belong to the common Plot System.
- x-axis tick overlap protection belongs to the common Plot System.
- IV Peak/RMS current basis belongs to the IV workflow.
- IV A-to-mA display conversion belongs to the IV workflow.
- Library workflow override belongs to sidecar.
- Library set membership belongs to `MeasurementSet`.

## Persistence and Migration Rules

When adding a new control, decide the scope first:

1. global plot default
2. per-workflow
3. per-tab
4. per-source
5. sidecar
6. measurement set

Then persist in the correct owner.

Rules:

- Old packs must load safely.
- Use `decodeIfPresent` with safe defaults for newly added pack fields.
- Migrate legacy auto-generated labels only when the saved label matches a known old auto label.
- Never overwrite manual user label overrides silently.
- Raw imported data must not be modified for display-unit changes; do display scaling in workflow renderers.

## Tick Control Wording

`tickTargetX` and `tickTargetY` are approximate tick targets, not exact tick counts.

Preferred UI wording:

- `X tick target`
- `Y tick target`

or

- `Approx. X ticks`
- `Approx. Y ticks`

## Finalization Rule

After any code change, agents must run:

```bash
./scripts/finalize_agent_change.sh
```

The final report must include:

- whether desktop rebuild was required
- whether desktop rebuild was run
- `/Applications/SpinLab.app` version
- `CFBundleVersion`
- whether `~/Desktop/SpinLab.app` exists

## State Scope Reminder

- Global plot defaults are shared across workflows.
- `chartStyleOverrides` / `styleParams` are render-time transport.
- `TabRenderState` is per-tab / per-source display state.
- Workflow pack config remains workflow-specific.
