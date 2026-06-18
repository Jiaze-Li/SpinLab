# Workbench - Extension Boundaries

> Extension guide for adding workflows and modules, plus the routing rules that keep ownership boundaries explicit.

## Adding a New Workflow

### Step 0 - Define the Workflow Assembly contract

Before writing any code, define the Workflow Assembly. See [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md) for the stable contract fields and ownership boundaries. Key decisions:

- Workflow Identity: stable runtime workflow ID registered in `WorkbenchWorkflowID`; optionally add `WorkflowID` aliases when the workflow should participate in canonical cross-region identity normalization.
- Physics Function: scientific model, measurement inputs, expected outputs, and workflow-specific interpretation rules.
- Input Adapter: accepted raw file formats, parser entry point, column mapping, unit conversion, sidecar/filename metadata injection, warning policy.
- Optional Panels / optional contributions: which additional workflow-specific content the workflow needs beyond the default set.
- Plot Defaults: how this workflow's result should be displayed by default.
- Save Metadata Provider: how a saved chart should be interpreted later.
- Pack Metadata Provider: how the full workspace should be restored later.
- Required Tests: regression gates the workflow must pass.

Default modules attach automatically. Do not redeclare them in the Workflow Assembly.

### Runtime reality note

There is no single runtime `WorkflowAssembly` object. A new workflow is currently realized by one Assembly document plus distributed Swift registration and workflow-owned files. This file is the implementation checklist for that real surface, not a promise of plugin-style zero-touch registration.

Expected reusable Main Board behavior:

- workflow search box and search button
- search results list
- select all / selected hits tray
- analyze button
- plot canvas, legend drag, copy PNG
- title / axis-label overrides
- series label rename and point-label visibility where supported by payload
- warning and run-trace display
- Save to Library button
- Save Analysis / Load Pack shell

New workflows must provide only workflow-specific data interpretation, analysis, plot payload construction, optional controls, and pack restore semantics. If a new workflow requires edits to `WorkflowWorkspaceShell`, `WorkbenchPlotCanvas`, `SaveActiveChartToLibraryUseCase`, or `AnalysisPackProviding` default behavior, classify that as a Main Board boundary finding before continuing.

### Step 1-10 - Implementation checklist

1. Write `docs/architecture/workbench/workflows/<name>/ASSEMBLY.md` before runtime code.
2. Register runtime workflow identity in `WorkbenchWorkflowID` (`Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift`). Add `WorkflowID` aliases (`Sources/SpinLabApp/Domain/Workflow/WorkflowID.swift`) only when canonical search/alias behavior should recognize the workflow globally.
3. Ensure rules/config expose the workflow definition in `Sources/SpinLabApp/config/workflow.json` or the runtime rules book. Existing config entries are not enough: they make the workflow visible in registry metadata, not supported by Workbench runtime.
4. Create `<Name>IngestionContracts.swift` - domain result structs (`Codable`, `Hashable`, `Sendable`) and tab identifiers.
5. Create parser / adapter files and `Ingest<Name>SelectionsUseCase.swift` - stateless ingestion from selected search hits to the workflow result. Parser code owns raw column mapping and unit conversion.
6. Create `<Name>PackContracts.swift` - `PackConfig` (UI state snapshot) + `PackResult` (must include `ingestionResult`). This is the Pack Metadata Provider implementation.
7. Create `<Name>WorkspaceStore.swift` - `@MainActor @Observable final class` conforming `WorkbenchWorkspaceProviding`; use workflow-local cached search results only as compatibility mirrors, not as canonical selected-hit input.
8. Create `<Name>WorkspaceView.swift` - thin view wrapping `WorkflowWorkspaceShell` with workflow-specific optional panel or contribution content.
9. Register the concrete store and view:
   - store ownership / vault / selection injection in `Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift`
   - view dispatch in `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift`
   - search result projection, clear mirrors, numeric-display cache, and library-root propagation in `Sources/SpinLabApp/App/State/WorkbenchMainSearchRuntime.swift`
10. Add targeted tests, then run required actions:
   - parser / ingestion tests for raw fixtures
   - selected-hit snapshot consumption test
   - pack config/result round trip
   - restore boundary test: restore must not commit run trace directly
   - registry routing smoke test when feasible
   - `./scripts/check_required_actions.sh`

### Gate 8.1 IV dry-run findings

The IV workflow dry run is the current calibration case for this document. It records real extension surfaces while adding a real workflow.

Current IV decisions:

- Workflow ID: `iv`
- Display name: `IV`
- Input format: `.lvm` files with `Tableau:` numeric block.
- Raw columns: `Current`, `1st X`, `1st Y`, `1st R`, `1st Theta`, `2nd X`, `2nd Y`, `2nd R`, `2nd Theta`, `1st R_H`, `Frequency_after`.
- Current column is peak current. RMS current is `Current / sqrt(2)`.
- Parser stores raw channel data; it must not permanently choose X or Y.
- IV-specific plot control module owns channel interpretation:
  - auto-detect dominant component per channel by comparing robust magnitude of X and Y, preferably `median(abs(component))`
  - auto-fill selected component and confidence
  - allow user override via workflow-specific plot controls
  - rerender after override without reparsing files
- Resistance-like plots use selected voltage divided by RMS current.
- Pack config must persist auto-detected mapping and user overrides; pack result must persist `IVIngestionResult`.
- Gate 8.1 scope is chart-only plus pack/restore; metric persistence is intentionally deferred.

## Adding a New Module

### Step 0 - Classify and define

Before writing any code, classify the module and define its boundaries. See [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md) for ownership authority and [MAIN_BOARD_LAYOUT.md](MAIN_BOARD_LAYOUT.md) for the current implementation-level injection points. Key decisions:

- Default or Optional: does this module apply to all workflows or only one workflow? Workflow-specific optional panels / contributions live in [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md).
- Single responsibility: name the one capability this module owns. If you cannot state it in one sentence, split it into two modules.
- Owned state: list which fields this module owns exclusively. No sibling module may write them directly.
- Inputs / outputs: what does this module consume, and what does it produce for other modules?
- UI metadata: declare all five - `defaultRegion`, `order`, `exclusive`, `layoutMode`, `sizePolicy`.
- Exclusive conflict: if `exclusive: true`, verify no other module in the target area uses `exclusive`. The Main Board detects and reports mounting conflicts.
- Cross-module handoff: define how this module receives inputs and exposes outputs without directly accessing sibling module state. All cross-module coordination must flow through Main Board orchestration, explicit snapshots, or provider protocols.

### Step 1-5 - Implementation checklist

1. Write owned state and responsibility contract into [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md).
2. Declare layout metadata and verify no exclusive conflict with existing modules in the target area.
3. Write boundary tests locking current behavior before introducing or extracting the module. New boundary tests must lock current behavior before extraction begins, not after.
4. Implement the module. Do not directly read or write sibling module state; use canonical communication surfaces only.
5. Update architecture docs: add or update the module boundary section in [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md); update specialized docs if needed.

### Module Extraction Notes

When extracting existing behavior from a workflow store or the Main Board into a new module:

1. Identify source logic: locate the behavior and map its current state ownership.
2. Decide scope: sibling Default Module, Optional Module, or remains internal to an existing module.
3. Define owned state before extraction: state ownership must be explicit in [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md) before any code moves.
4. Define handoff: how will the extracted module receive inputs and expose outputs? Choose the correct communication surface (Main Board orchestration, explicit snapshot, provider protocol). For plot system modules, `TabRenderManager` projections are the correct output surface.
5. Lock current behavior first: write boundary tests that pass against the pre-extraction implementation. Extraction is complete only when the locked tests pass after extraction.

## Gate 7 Module Extraction Checklist

Use this checklist for every Gate 7+ runtime/module extraction. Each item is a hard gate — do not skip.

**Ownership**
- [ ] Canonical owner moves into the extracted runtime or module. Anything that was the source of truth must live there; the old location must not retain a parallel copy.
- [ ] `WorkbenchFeatureStore` becomes a pure facade: search state aggregation, cross-module coordination, and snapshot vending only. It must not gain new canonical state.
- [ ] Workflow-local copies of shared state (e.g. `cachedSearchResults`, `selectedSearchResultIDs`) are mirror/compatibility caches only — not primary sources. Document each one explicitly in [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md).

**Cleanup**
- [ ] Scattered workflow-specific logic (branches on workflow ID, per-workflow conditions inside shared code) is cleaned for or relocated to the extracted module before the Gate closes.
- [ ] Legacy bridges and compatibility shims introduced during extraction are filed in [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md) as named technical debt with a target Gate for removal.

**Tests and Fixtures**
- [ ] Audit tests and fixtures are updated when ownership or contracts move. A passing test that validates the wrong owner is a false signal.
- [ ] Full `swift test` failures are classified before fixing: identify whether each failure is a stale expectation, a missing fixture field, a genuine async timing issue, or a test structural problem. Do not adjust timeouts without a diagnosis.
- [ ] Boundary suites that exercise MainActor-heavy, I/O-heavy, or analysis-heavy async paths use `@Suite(.serialized)` rather than arbitrary timeout bumps. Serialization eliminates concurrency as a variable; a timeout bump just masks it.

**Gate Closeout**
- [ ] `./scripts/check_required_actions.sh` is clean: if Swift source changed, rebuild is complete; if web library inputs changed, publish is complete.
- [ ] Architecture docs are updated: [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md) reflects the new ownership map; Code Map entries are accurate.
- [ ] Do not proceed to the next Gate module until ownership, tests, docs, and required-action status are all clean in this Gate.

## [HARD] Main Board Invariants

These invariants are enforced at the Main Board level; all steps above must respect them:

- New workflows must use the Main Board (`WorkflowWorkspaceShell`). Do not build standalone two-column views.
- `runAnalysis()` is the sole entry point for trace commit. Restore and rerender paths must not commit trace.
- `PackResult` must include `ingestionResult` so that restore can rerender without re-ingestion.
- Main Board-triggered analysis entry must consume `WorkbenchSearchSnapshot` as canonical search input.
- Workflow analysis entry should consume a run-scoped selected-hit snapshot and must not use workflow-local `cachedSearchResults` as primary selection input.
- New workflow implementations must not treat workflow-local `cachedSearchResults` mirrors as canonical search state.
- Parser / input adapter code must preserve raw measurement data and metadata. Workflow-specific interpretation modules may derive plotting series from the raw result.
- The Physics Function must not own running / message / warning / trace state. Those belong to the Analysis Lifecycle Module.
- Analysis must not mutate Search Module state, Selection Module state, or tab override state.

Full workflow contract: [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md)

Current phase status is tracked only in [WORKBENCH_ROADMAP.md](WORKBENCH_ROADMAP.md).

## Workbench Intake Pipeline

Use this pipeline to classify new requests before implementation.

### Intake Classes

1. Physics Function
- The request changes scientific meaning, ingestion, fit/inference, or workflow-specific output contracts inside a Workflow Assembly.
- Route to: [`modules/PACK_RESTORE.md`](modules/PACK_RESTORE.md) for per-workflow pack/ingestion contracts; see also the relevant workflow store and UseCase files.

2. Default Module
- The request changes shared Main Board behavior reused across all workflows.
- Route to: [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md) and [MAIN_BOARD_LAYOUT.md](MAIN_BOARD_LAYOUT.md).

3. New Workflow / Workflow Assembly / Optional Panel or Contribution
- Adding an entirely new workflow, or adding/modifying controls specific to one workflow.
- Route to: [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md) for the contract model; [EXTENSION_BOUNDARIES.md](EXTENSION_BOUNDARIES.md) for the implementation checklist.

4. Regression Patch / Boundary Gate
- The request fixes or hardens a known boundary contract.
- Route to: boundary doc for the contract (`MODULE_BOUNDARIES.md`, `modules/MEASUREMENT_SEARCH.md`) and add or extend regression tests.

5. Persistence / Export Change
- The request changes save/load packs, artifact write paths, stale detection, or export-related artifact contracts.
- Route to: [`modules/PACK_RESTORE.md`](modules/PACK_RESTORE.md) and linked library artifact docs.

6. New Module / Module Extraction
- Adding a new module to the Main Board or extracting existing behavior into a module.
- Route to: [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md) for boundary documentation; [MAIN_BOARD_LAYOUT.md](MAIN_BOARD_LAYOUT.md) for injection points; [EXTENSION_BOUNDARIES.md](EXTENSION_BOUNDARIES.md) for the implementation checklist.

### Intake Routing Rule

When a request crosses classes, split by owner contract:

- scientific meaning changes stay in Workflow Function class
- shared UI behavior stays in Default Module class
- persistence/export behavior stays in Persistence class

Do not merge these concerns into one mixed contract section.

## Architecture Usage Rules

### Architecture Routing Rule

Before any non-trivial change, classify the task and consult the relevant architecture docs. Record a minimal routing note - proportional to change size; omit for typo/comment-only changes.

**Routing note format:**

```text
Type:
Docs to check:
Boundary risk:
```

**Task routing examples:**

| Task | Docs to check |
|---|---|
| New workflow | `WORKFLOW_ASSEMBLY.md`, `EXTENSION_BOUNDARIES.md`, `MODULE_BOUNDARIES.md`, relevant `modules/*.md` if touched |
| New module / module extraction | `MODULE_BOUNDARIES.md`, `MAIN_BOARD_LAYOUT.md`, `EXTENSION_BOUNDARIES.md` |
| Pack / Restore change | `MODULE_BOUNDARIES.md`, `modules/PACK_RESTORE.md` |
| Plot change | `MODULE_BOUNDARIES.md`, `modules/PLOT_SYSTEM.md` |
| Search / Selection change | `MODULE_BOUNDARIES.md`, `modules/MEASUREMENT_SEARCH.md` |

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
| Main Board / Layout / Assembly | `MAIN_BOARD_READINESS.md`, `MAIN_BOARD_LAYOUT.md`, `WORKFLOW_ASSEMBLY.md` |
| New workflow/module process | `EXTENSION_BOUNDARIES.md` (this file) |

### Deviation Rule

If a planned implementation conflicts with `WORKFLOW_ASSEMBLY.md` or `MODULE_BOUNDARIES.md`, stop and report the conflict before implementing.

### Scope

This is a routing and check rule, not a long approval form. Small typo or comment-only changes do not need full routing. The routing note should be proportional to change size.

## Extension Module Import Rules

The old extension-protocol rules below describe the legacy extension system, not the current Workbench Main Board workflow path. New Workbench workflows currently follow the `WorkflowWorkspaceShell` / `WorkbenchWorkspaceProviding` path above.

- Extension modules must NOT import `Features/` or `App/` modules.
- Extensions may only depend on:
  - `Domain/` types
  - Protocol contracts in `Extensions/ExtensionPoints.swift`
- New measurement types: add to domain enum first, then implement in extension.
- New workflow support must implement all four extension protocols: `WorkflowExtension`, `MetadataExtension`, `AnalysisModuleExtension`, `ViewExtension`.
- Register in `WorkflowRegistry.registerBuiltins()`.

## Code Placement for New Workflows

| Artifact | Destination |
|---|---|
| New workflow assembly record | `docs/architecture/workbench/workflows/<name>/ASSEMBLY.md` |
| New workflow workspace store | `Sources/SpinLabApp/Features/Workbench/<Name>WorkspaceStore.swift` conforming `WorkbenchWorkspaceProviding` |
| New workflow workspace view | `Sources/SpinLabApp/Features/Workbench/<Name>WorkspaceView.swift` wrapping `WorkflowWorkspaceShell` |
| New workflow parser / adapter | `Sources/SpinLabApp/UseCases/<Name>*Parser.swift` or equivalent workflow-owned adapter file |
| New workflow ingestion UseCase | `Sources/SpinLabApp/UseCases/Ingest<Name>SelectionsUseCase.swift` |
| New workflow plot payload builder / renderer | `Sources/SpinLabApp/UseCases/<Name>PlotRenderer.swift` or equivalent workflow-owned payload builder |
| New workflow pack contracts | `Sources/SpinLabApp/Workbench/V3/<Name>PackContracts.swift` (`PackConfig` + `PackResult`) |
| New workflow ingestion contracts | `Sources/SpinLabApp/Workbench/V3/<Name>IngestionContracts.swift` |
| Runtime workflow ID | `Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift` (`WorkbenchWorkflowID`) |
| Workspace view dispatch | `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift` |
| Search runtime mirror projection | `Sources/SpinLabApp/App/State/WorkbenchMainSearchRuntime.swift` |
| Canonical workflow alias, if needed | `Sources/SpinLabApp/Domain/Workflow/WorkflowID.swift` |
| Rules/config workflow definition, if needed | `Sources/SpinLabApp/config/workflow.json` or runtime rules book |

## Cross-Links

- [Shell Blocks](SHELL_BLOCKS.md)
- [Workflow Assembly](WORKFLOW_ASSEMBLY.md)
- [Module Boundaries](MODULE_BOUNDARIES.md)
- [Pack/Restore](modules/PACK_RESTORE.md)
- [Workbench Roadmap](WORKBENCH_ROADMAP.md)

## Code Map

- `Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift` - current Workbench runtime workflow identity enum, concrete workspace store ownership, vault/selection injection, denominator projection <!-- legitimate_cross_cutting -->
- `Sources/SpinLabApp/App/State/WorkbenchMainSearchRuntime.swift` - current Workbench main-search runtime; owns per-workflow search state and projects result mirrors into concrete workspace stores <!-- legitimate_cross_cutting -->
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift` - concrete workspace view dispatch for supported workflow IDs
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift` - shared Main Board workspace shell used by new workflow views
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift` - `WorkbenchWorkspaceProviding`, `ActiveChartProviding`, and related shell-facing workflow store contracts
- `Sources/SpinLabApp/Domain/Workflow/WorkflowID.swift` - Tier 1 canonical workflow identity enum with alias normalization; cross-region contract when opted in <!-- legitimate_cross_cutting -->
- `Sources/SpinLabApp/Domain/WorkflowSearchModels.swift` - shared workflow search query and search-hit model
- `Sources/SpinLabApp/Workflow/WorkflowDefinition.swift` - defines the workflow registration contract (ID, display name, condition fields)
- `Sources/SpinLabApp/Workflow/WorkflowDefinitionStore.swift` - stores registered workflow definitions; populated at app startup
- `Sources/SpinLabApp/Workflow/WorkflowRegistry.swift` - legacy/global registry mapping workflow IDs to definitions and capabilities
- `Sources/SpinLabApp/Extensions/ExtensionPoints.swift` - legacy extension points; do not confuse with the current Workbench Main Board workflow path
