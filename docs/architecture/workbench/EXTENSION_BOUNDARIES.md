# Workbench — Extension Boundaries

> Extension layer: Adding-a-new-workflow checklist (Workflow Assembly → implementation), extension import rules, Domain / ExtensionPoints dependency boundaries.

## Adding a New Workflow

### Step 0 — Define the Workflow Assembly (design phase)

Before writing any code, define the Workflow Assembly. See [`SHELL_BLOCKS.md` § New Workflow Onboarding](SHELL_BLOCKS.md) for the full design sequence. Key decisions:

- **Workflow Identity**: stable workflow ID registered in `WorkbenchWorkflowID` (implementation step 1).
- **Physics Function**: physical model, measurement inputs, expected outputs — confirm with user.
- **Optional Modules**: which optional modules the workflow needs beyond the default set (e.g., Scaling, Overlay, Multi-tab, Shift).
- **Plot Defaults**: how this workflow's result should be displayed by default.
- **Save Metadata Provider**: how a saved chart should be interpreted later.
- **Pack Metadata Provider**: how the full workspace should be restored later.
- **Required Tests**: regression gates the workflow must pass.

Default modules (Search, Selection, Analyze Lifecycle, Result Header, Plot Display, Plot Controls, Plot Preservation, Save, Pack/Restore, Trace, Warning, Status) attach automatically — do not redeclare them in the Workflow Assembly.

### Step 1–8 — Implementation checklist

1. Register workflow ID in `WorkbenchWorkflowID` enum (`Workflow/WorkflowID.swift`).
2. Create `<Name>IngestionContracts.swift` — domain result struct (`Codable`, `Hashable`, `Sendable`).
3. Create `Ingest<Name>SelectionsUseCase.swift` — stateless ingestion from search hits to result (Physics Function core).
4. Create `<Name>PackContracts.swift` — `PackConfig` (UI state snapshot) + `PackResult` (must include `ingestionResult`). This is the Pack Metadata Provider implementation.
5. Create `<Name>WorkspaceStore.swift` — `@MainActor @Observable final class` conforming `WorkbenchWorkspaceProviding`.
6. Create `<Name>WorkspaceView.swift` — thin view wrapping `WorkflowWorkspaceShell` with workflow-specific optional module content.
7. Register store in `WorkbenchFeatureStore` and view in `WorkflowWorkspaceRegistry`.
8. Add search case in `WorkbenchFeatureStore.runWorkflowMeasurementSearch()`.

## Adding a New Module

### Step 0 — Classify and define (design phase)

Before writing any code, classify the module and define its boundaries. See [`SHELL_BLOCKS.md` § Module](SHELL_BLOCKS.md) for the full module definition model. Key decisions:

- **Default or Optional**: does this module apply to all workflows (Default Module, always loaded) or only one workflow (Optional Module, declared in a specific Workflow Assembly)? See [`SHELL_BLOCKS.md` § Plot Controls Module vs Workflow-specific Optional Modules](SHELL_BLOCKS.md) for the classification rule.
- **Single responsibility**: name the one capability this module owns. If you cannot state it in one sentence, split into two modules.
- **Owned state**: list which fields this module owns exclusively. No sibling module may write them directly.
- **Inputs / outputs**: what does this module consume (from which modules, snapshots, or protocols), and what does it produce for other modules?
- **UI metadata**: declare all five — `defaultRegion`, `order`, `exclusive`, `layoutMode`, `sizePolicy`. See [`SHELL_BLOCKS.md` § Layout Host](SHELL_BLOCKS.md) for available layout regions.
- **Exclusive conflict**: if `exclusive: true`, verify no other module in the target region uses `exclusive`. The Main Board detects and reports mounting conflicts.
- **Cross-module handoff**: define how this module receives inputs and exposes outputs without directly accessing sibling module state. All cross-module coordination must flow through Main Board orchestration, explicit snapshots, or provider protocols. See [`SHELL_BLOCKS.md` § Canonical Communication Surfaces](SHELL_BLOCKS.md).

### Step 1–5 — Implementation checklist

1. Write owned state and responsibility contract into [`MODULE_BOUNDARIES.md`](MODULE_BOUNDARIES.md) — a new section following the existing boundary section format.
2. Declare layout metadata and verify no exclusive conflict with existing modules in the target region.
3. Write boundary tests locking current behavior before introducing or extracting the module. New boundary tests must lock current behavior before extraction begins, not after.
4. Implement the module. Do not directly read or write sibling module state; use canonical communication surfaces only.
5. Update architecture docs: add module to `SHELL_BLOCKS.md` Module Inventory; update Module Groups table if the module belongs to a Module Group; update relevant specialized docs if needed.

### Module Extraction Notes

When extracting existing behavior from a workflow store or the Main Board into a new module:

1. **Identify source logic**: locate the behavior and map its current state ownership.
2. **Decide scope**: sibling Default Module, Optional Module, or remains internal to an existing module?
3. **Define owned state before extraction**: state ownership must be explicit in [`MODULE_BOUNDARIES.md`](MODULE_BOUNDARIES.md) before any code moves.
4. **Define handoff**: how will the extracted module receive inputs and expose outputs? Choose the correct communication surface (Main Board orchestration, explicit snapshot, provider protocol). For Plot System modules, `TabRenderManager` projections are the correct output surface — direct `TabRenderState` writes are owned exclusively by Plot Preservation Module.
5. **Lock current behavior first**: write boundary tests that pass against the pre-extraction implementation. Extraction is complete only when the locked tests pass after extraction.

## [HARD] Main Board Invariants (applies to all workflows)

These invariants are enforced at the Main Board level; all steps above must respect them:

- New workflows must use the Main Board (`WorkflowWorkspaceShell`). Do not build standalone two-column views.
- `runAnalysis()` is the sole entry point for trace commit. Restore and rerender paths must not commit trace.
- `PackResult` must include `ingestionResult` so that restore can rerender without re-ingestion.
- Main Board-triggered analysis entry must consume `WorkbenchSearchSnapshot` as canonical search input.
- Workflow analysis entry should consume a run-scoped selected-hit snapshot and must not use workflow-local `cachedSearchResults` as primary selection input.
- New workflow implementations must not treat workflow-local `cachedSearchResults` mirrors as canonical search state.
- The Physics Function must not own running / message / warning / trace state — those belong to the Analysis Lifecycle Module. The Physics Function outputs ingestion result and computed payloads; the Analysis Lifecycle Module owns all surrounding run lifecycle state.
- Analysis must not mutate Search Module state, Selection Module state, or tab override state (owned by Plot Preservation Module).

Full Analysis Lifecycle Module contract: [`SHELL_BLOCKS.md` § Analyze Lifecycle Module](SHELL_BLOCKS.md).

Full shell contract: [`SHELL_BLOCKS.md`](SHELL_BLOCKS.md)

Current phase status is tracked only in [`WORKBENCH_ROADMAP.md`](WORKBENCH_ROADMAP.md).

## Workbench Intake Pipeline

Use this pipeline to classify new requests before implementation.

### Intake Classes

1. Physics Function
- The request changes scientific meaning, ingestion, fit/inference, or workflow-specific output contracts inside a Workflow Assembly.
- Route to: [`modules/PACK_RESTORE.md`](modules/PACK_RESTORE.md) for per-workflow pack/ingestion contracts; see also the relevant workflow store and UseCase files.

2. Default Module
- The request changes shared Main Board behavior reused across all workflows.
- Route to: [`SHELL_BLOCKS.md`](SHELL_BLOCKS.md).

3. New Workflow / Workflow Assembly / Optional Module
- Adding an entirely new workflow, or adding/modifying controls specific to one workflow (i.e., an optional module or Workflow Assembly configuration point).
- Route to: [`SHELL_BLOCKS.md` § New Workflow Onboarding](SHELL_BLOCKS.md) for the design sequence; [`EXTENSION_BOUNDARIES.md` § Adding a New Workflow](#adding-a-new-workflow) for the implementation checklist; [`SHELL_BLOCKS.md` § Workflow Assembly](SHELL_BLOCKS.md) for the configuration model.

4. Regression Patch / Boundary Gate
- The request fixes or hardens a known boundary contract.
- Route to: boundary doc for the contract (`MODULE_BOUNDARIES.md`, `modules/MEASUREMENT_SEARCH.md`) and add/extend regression tests.

5. Persistence / Export Change
- The request changes save/load packs, artifact write paths, stale detection, or export-related artifact contracts.
- Route to: [`modules/PACK_RESTORE.md`](modules/PACK_RESTORE.md) and linked library artifact docs.

6. New Module / Module Extraction
- Adding a new module to the Main Board or extracting existing behavior into a module.
- Route to: [`SHELL_BLOCKS.md`](SHELL_BLOCKS.md) for module definition and isolation rules; [`MODULE_BOUNDARIES.md`](MODULE_BOUNDARIES.md) for boundary documentation; [`EXTENSION_BOUNDARIES.md` § Adding a New Module](#adding-a-new-module) for the implementation checklist.

### Intake Routing Rule

When a request crosses classes, split by owner contract:

- scientific meaning changes stay in Workflow Function class
- shared UI behavior stays in Default Module class
- persistence/export behavior stays in Persistence class

Do not merge these concerns into one mixed contract section.

## Architecture Usage Rules

### Architecture Routing Rule

Before any non-trivial change, classify the task and consult the relevant architecture docs. Record a minimal routing note — proportional to change size; omit for typo/comment-only changes.

**Routing note format:**

```
Type:
Docs to check:
Boundary risk:
```

**Task routing examples:**

| Task | Docs to check |
|---|---|
| New workflow | `SHELL_BLOCKS.md`, `EXTENSION_BOUNDARIES.md`, `MODULE_BOUNDARIES.md`, relevant `modules/*.md` if touched |
| New module / module extraction | `SHELL_BLOCKS.md`, `EXTENSION_BOUNDARIES.md`, `MODULE_BOUNDARIES.md` |
| Pack / Restore change | `SHELL_BLOCKS.md`, `MODULE_BOUNDARIES.md`, `modules/PACK_RESTORE.md` |
| Plot change | `SHELL_BLOCKS.md`, `MODULE_BOUNDARIES.md`, `modules/PLOT_SYSTEM.md` |
| Search / Selection change | `SHELL_BLOCKS.md`, `MODULE_BOUNDARIES.md`, `modules/MEASUREMENT_SEARCH.md` |

### Architecture Compliance Rule

After implementation, report briefly:

- Relevant docs used: yes/no
- Boundary respected: yes/no
- Sibling module mutation introduced: yes/no
- Boundary tests added/updated: yes/no/not needed
- Related docs updated: yes/no/not needed

### Documentation Sync Rule

If a change modifies a module contract, module boundary, data flow, extension process, or complex module behavior, update the corresponding architecture doc in the same change.

| Change area | Doc to update |
|---|---|
| Pack / Restore behavior | `modules/PACK_RESTORE.md` |
| Search / Selection input-chain | `modules/MEASUREMENT_SEARCH.md` |
| Plot module group behavior | `modules/PLOT_SYSTEM.md` |
| Generic module rule | `MODULE_BOUNDARIES.md` |
| Main Board / Layout Host / Assembly | `SHELL_BLOCKS.md` |
| New workflow/module process | `EXTENSION_BOUNDARIES.md` (this file) |

### Deviation Rule

If a planned implementation conflicts with `SHELL_BLOCKS.md` or `MODULE_BOUNDARIES.md`, stop and report the conflict before implementing.

### Scope

This is a routing and check rule, not a long approval form. Small typo or comment-only changes do not need full routing. The routing note should be proportional to change size.

## Extension Module Import Rules

- Extension modules must **NOT** import `Features/` or `App/` modules.
- Extensions may only depend on:
  - `Domain/` types
  - Protocol contracts in `Extensions/ExtensionPoints.swift`
- New measurement types: add to domain enum first, then implement in extension.
- New workflow support must implement all four extension protocols: `WorkflowExtension`, `MetadataExtension`, `AnalysisModuleExtension`, `ViewExtension`.
- Register in `WorkflowRegistry.registerBuiltins()`.

## Code Placement for New Workflows

| Artifact | Destination |
|---|---|
| New workflow workspace store | `Sources/SpinLabApp/Features/Workbench/<Name>WorkspaceStore.swift` conforming `WorkbenchWorkspaceProviding` |
| New workflow workspace view | `Sources/SpinLabApp/Features/Workbench/<Name>WorkspaceView.swift` wrapping `WorkflowWorkspaceShell` |
| New workflow ingestion UseCase | `Sources/SpinLabApp/UseCases/Ingest<Name>SelectionsUseCase.swift` |
| New workflow pack contracts | `Sources/SpinLabApp/Workbench/V3/<Name>PackContracts.swift` (`PackConfig` + `PackResult`) |
| New workflow ingestion contracts | `Sources/SpinLabApp/Workbench/V3/<Name>IngestionContracts.swift` |

## Cross-Links

- [Shell Blocks](SHELL_BLOCKS.md)
- [Module Boundaries](MODULE_BOUNDARIES.md)
- [Pack/Restore](modules/PACK_RESTORE.md)
- [Workbench Roadmap](WORKBENCH_ROADMAP.md)

## Code Map

- `Sources/SpinLabApp/Domain/Workflow/WorkflowID.swift` — Tier 1 canonical workflow identity enum with alias normalization; cross-region contract <!-- legitimate_cross_cutting -->
- `Sources/SpinLabApp/Domain/Workflow/WorkflowDefinitionProviding.swift` — capability protocol for loading workflow definitions; WorkflowDefinitionStore conforms
- `Sources/SpinLabApp/Workflow/WorkflowDefinition.swift` — defines the workflow registration contract (ID, metadata, capabilities)
- `Sources/SpinLabApp/Extensions/ExtensionPoints.swift` — declares extension points for workflow opt-in capabilities
- `Sources/SpinLabApp/Workflow/WorkflowDefinitionStore.swift` — stores registered workflow definitions; populated at app startup
- `Sources/SpinLabApp/Workflow/WorkflowRegistry.swift` — global registry mapping workflow IDs to their definitions and capabilities
