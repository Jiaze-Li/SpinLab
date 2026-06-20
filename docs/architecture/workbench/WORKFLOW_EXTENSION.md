# Workbench Workflow Extension

This document is the canonical contract for adding or changing Workbench workflows and workflow controls.

## Adding a New Workflow

### Step 0 — Define the Workflow Assembly contract

Before writing any code, define the Workflow Assembly. See [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md) for the stable contract fields and ownership boundaries. Key decisions:

- Workflow Identity: stable workflow ID registered in `WorkbenchWorkflowID`
- Physics Function: scientific model, measurement inputs, expected outputs
- Optional Panels / optional contributions: which additional workflow-specific content the workflow needs beyond the default set
- Plot Defaults: how this workflow's result should be displayed by default
- Save Metadata Provider: how a saved chart should be interpreted later
- Pack Metadata Provider: how the full workspace should be restored later
- Required Tests: regression gates the workflow must pass

Default modules attach automatically. Do not redeclare them in the Workflow Assembly.

### Steps 1–8 — Implementation checklist

1. Register workflow ID in `WorkbenchWorkflowID` enum (`Workflow/WorkflowID.swift`).
2. Create `<Name>IngestionContracts.swift` — domain result struct (`Codable`, `Hashable`, `Sendable`).
3. Create `Ingest<Name>SelectionsUseCase.swift` — stateless ingestion from search hits to result.
4. Create `<Name>PackContracts.swift` — `PackConfig` (UI state snapshot) + `PackResult` (must include `ingestionResult`). This is the Pack Metadata Provider implementation.
5. Create `<Name>WorkspaceStore.swift` — `@MainActor @Observable final class` conforming `WorkbenchWorkspaceProviding`.
6. Create `<Name>WorkspaceView.swift` — thin view wrapping `WorkflowWorkspaceShell` with workflow-specific optional panel or contribution content.
7. Register store in `WorkbenchFeatureStore` and view in `WorkflowWorkspaceRegistry`.
8. Add search case in `WorkbenchFeatureStore.runWorkflowMeasurementSearch()`.

### Code Placement for New Workflows

| Artifact | Destination |
|---|---|
| New workflow workspace store | `Sources/SpinLabApp/Features/Workbench/<Name>WorkspaceStore.swift` conforming `WorkbenchWorkspaceProviding` |
| New workflow workspace view | `Sources/SpinLabApp/Features/Workbench/<Name>WorkspaceView.swift` wrapping `WorkflowWorkspaceShell` |
| New workflow ingestion UseCase | `Sources/SpinLabApp/UseCases/Ingest<Name>SelectionsUseCase.swift` |
| New workflow pack contracts | `Sources/SpinLabApp/Workbench/V3/<Name>PackContracts.swift` (`PackConfig` + `PackResult`) |
| New workflow ingestion contracts | `Sources/SpinLabApp/Workbench/V3/<Name>IngestionContracts.swift` |

## [HARD] Main Board Invariants

These invariants are enforced at the Main Board level; all steps above must respect them:

- New workflows must use the Main Board (`WorkflowWorkspaceShell`). Do not build standalone two-column views.
- `runAnalysis()` is the sole entry point for trace commit. Restore and rerender paths must not commit trace.
- `PackResult` must include `ingestionResult` so that restore can rerender without re-ingestion.
- Main Board-triggered analysis entry must consume `WorkbenchSearchSnapshot` as canonical search input.
- Workflow analysis entry should consume a run-scoped selected-hit snapshot and must not use workflow-local `cachedSearchResults` as primary selection input.
- New workflow implementations must not treat workflow-local `cachedSearchResults` mirrors as canonical search state.
- The Physics Function must not own running / message / warning / trace state. Those belong to the Analysis Lifecycle Module.
- Analysis must not mutate Search Module state, Selection Module state, or tab override state.

Full workflow contract: [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md)

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
