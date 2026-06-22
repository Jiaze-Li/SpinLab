# Workbench Workflow Extension

This document is the canonical contract for adding or changing Workbench workflows and workflow controls.

## Workflow Onboarding Pipeline

A repeatable pipeline for introducing a new workflow from a raw experimental data file to a fully integrated Workbench workflow. Each stage must be completed and accepted before the next begins.

**Pilot case:** RSM (Resonant Spin Manipulation). Stage examples use RSM where concrete illustrations are needed; substitute the relevant workflow name for future additions.

---

### Stage 0 — Intake

**Goal:** Establish that the experimental data is well-defined enough to build on.

- Collect at least one representative raw data file from the experimenter.
- Identify the measurement instrument, file format, and any known format variations.
- Confirm: what physical quantity is measured, under what conditions, with what parameters swept.
- Output: a one-paragraph experiment summary naming the measurement axes and independent variable(s).

**Gate:** Accepted when the experiment summary is confirmed by the product owner.

---

### Stage 1 — Data Probe

**Goal:** Characterize the raw data file structure without committing to any representation.

Parse the file to identify:
- Header / metadata fields
- Column names and units as written in the file
- Any multi-segment or multi-block structure
- Encoding / delimiter / line-ending quirks
- Known edge cases (empty sweeps, repeated headers, truncated files)

Output: a structured field map (table of column → unit → observed range → notes).

**Gate:** Accepted when the field map is reviewed and all ambiguous fields are resolved.

---

### Stage 2 — Canonical Dataset Contract

**Goal:** Define the stable domain representation that all downstream layers build on.

Translate the field map into a named, typed domain schema:
- Name each domain quantity in plain English (not raw file-column names)
- Assign SI or display units
- Decide which fields are mandatory vs. optional
- Define the sweep identity (what uniquely identifies one sweep in a multi-sweep file)

Output: a Dataset Contract document (e.g. `docs/architecture/workbench/datasets/<Name>DatasetContract.md`).

**Gate:** Dataset Contract accepted by the product owner. No ingestion code may be written before this gate clears.

---

### Stage 3 — Plot Feasibility Gate

**Goal:** Confirm the workflow can be built on the existing Plot System without requiring common Plot System changes.

Enumerate what the workflow needs to display and classify each item:
- **Covered** — existing Plot System already supports it.
- **Workflow-owned** — new rendering logic that belongs to the workflow renderer only (data transform, unit conversion, label wording).
- **Common change required** — a capability that does not exist yet and would need to be added to the shared Plot System.

**[HARD] Architecture gate rule:** If any item is classified as **Common change required**, implementation of this workflow MUST STOP immediately. Open a separate architecture gate before proceeding. The architecture gate must be resolved and the Plot System extended first; only then may this workflow resume from Stage 4.

**Gate:** Accepted when no **Common change required** items remain unresolved.

---

### Stage 4 — Workflow Assembly

**Goal:** Produce the complete Workflow Assembly contract (see [Step 0](#step-0--define-the-workflow-assembly-contract) and [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md)).

Work through every field of the Workflow Assembly contract:
- Workflow Identity
- Physics Function
- Optional Panels / optional contributions
- Plot Defaults
- Save Metadata Provider
- Pack Metadata Provider
- Required Tests

**[HARD] Implementation gate:** Workflow implementation (Stage 5) must not begin until the Workflow Assembly is explicitly accepted by the product owner. Acceptance must be recorded (e.g. a comment in the PR or task log) before any code from Steps 1–8 is written.

**Gate:** Workflow Assembly accepted by the product owner.

---

### Stage 5 — Implementation

**Goal:** Build the workflow following the established checklist.

Execute [Step 0](#step-0--define-the-workflow-assembly-contract) and [Steps 1–8](#steps-18--implementation-checklist) from **Adding a New Workflow** below. All Main Board Invariants apply in full.

No deviation from the accepted Workflow Assembly is permitted without returning to Stage 4 for re-acceptance.

If a deviation would require a common Plot System change, stop and open an architecture gate (same rule as Stage 3).

---

### Stage 6 — Validation

**Goal:** Confirm the workflow behaves correctly against the canonical dataset.

- Run the Required Tests defined in the Workflow Assembly.
- Load the representative data file from Stage 0 and verify the plot output matches expected physics.
- Confirm pack/restore round-trips correctly (save a chart, reload, verify identical render).
- Run `./scripts/check_required_actions.sh` and address any required actions.
- Confirm no regression in existing workflows.

**Gate:** All Required Tests pass; product owner confirms plot output matches expectations on the representative dataset.

---

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
