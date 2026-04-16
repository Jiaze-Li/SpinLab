# SpinLab Project Architecture Reference

Status: active
Last updated: v5.5.0

This file contains SpinLab-specific architecture details: code placement, canonical implementations, module contracts, and project-specific checklists.

---

## Project Overview

SpinLab is a macOS research app for magnetic experiment workflow management.

Core structure: Inbox → Workbench → Library
Core workflow: Import → Confirm → Visualize → Analyze → Save → Archive

Core objects: Project, Batch, Sample, Device, Measurement, Dataset, Result, Comparison

Domain rules:
- Sample can belong to multiple projects.
- Batch is different from physical sample.
- Device is optional.
- Dataset maps to one measurement by default.
- Results can be rated.

Workflow ID mapping (v4.1.3+):

| Old ID | New ID | Workflow |
|--------|--------|----------|
| A      | ahe    | AMR/PHE (Anomalous Hall Effect) |
| B      | 3w     | 3 Omega |

If you encounter `"A"` or `"B"` as workflowID in sidecar files, persisted JSON, or logs, it is a pre-v4.1.3 artifact. Replace with the new ID. No backward-compatibility code exists.

---

## Code Placement

| Code shape | Destination |
|---|---|
| New observable feature state | FeatureStore in `Sources/SpinLabApp/App/State/` |
| Cross-feature coordination | `SpinLabAppState` methods |
| Complex operation within a single feature | FeatureStore method returning `Outcome` enum/result |
| Stateless business operation (Input -> Output) | `Sources/SpinLabApp/UseCases/` struct |
| Stateful domain service/orchestration | Service/Orchestrator in `Sources/SpinLabApp/App/` or domain module |
| External I/O (filesystem/persistence) | Repository/Store layer |
| Filename parsing/matching/routing rules | `Sources/SpinLabApp/Import/` pipeline layers |
| Pure UI interaction state (expand/collapse/filter text) | `FeatureViewModel` |
| New workflow workspace store | `Sources/SpinLabApp/Features/Workbench/<Name>WorkspaceStore.swift` conforming `WorkbenchWorkspaceProviding` |
| New workflow workspace view | `Sources/SpinLabApp/Features/Workbench/<Name>WorkspaceView.swift` wrapping `WorkflowWorkspaceShell` |
| New workflow ingestion UseCase | `Sources/SpinLabApp/UseCases/Ingest<Name>SelectionsUseCase.swift` |
| New workflow pack contracts | `Sources/SpinLabApp/Workbench/V3/<Name>PackContracts.swift` (`PackConfig` + `PackResult`) |
| New workflow ingestion contracts | `Sources/SpinLabApp/Workbench/V3/<Name>IngestionContracts.swift` |

---

## Canonical Implementations (reference)

- Feature Store pattern:
  - `Sources/SpinLabApp/App/State/InboxFeatureStore.swift`
  - `Sources/SpinLabApp/App/State/LibraryFeatureStore.swift`
- UseCase (sync flow):
  - `Sources/SpinLabApp/UseCases/ConfirmPendingImportUseCase.swift`
- UseCase (non-fatal error channel):
  - `Sources/SpinLabApp/UseCases/SaveLibrarySampleEditsUseCase.swift`
- Repository + AsyncStream projection:
  - `Sources/SpinLabApp/Repositories/DomainRepositories.swift`
- Routing pipeline boundary example:
  - `Sources/SpinLabApp/Import/Evaluate/PendingRoutingSnapshotEvaluator.swift`
- Projection drain and projection subscription handling:
  - `Sources/SpinLabApp/App/State/InboxFeatureStore.swift`
- Integration test scaffold:
  - `Tests/SpinLabAppTests/V223AppEnvironmentIntegrationTests.swift`
- Workbench Shell + WorkspaceStore pattern (v5.3.4):
  - Shell: `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift`
  - Protocol: `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift` (`WorkbenchWorkspaceProviding`)
  - Store: `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift` (most complete reference)
  - View: `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift` (shell slot usage reference)
  - Pack contracts: `Sources/SpinLabApp/Workbench/V3/ThreeOmegaPackContracts.swift`

---

## Workbench Shell Architecture (v5.3.4+)

All workflow workspaces share a single generic shell (`WorkflowWorkspaceShell`) that owns the full two-column layout. Workflow-specific content is injected via ViewBuilder slots.

Shell layout (fixed for all workflows):
- Left column: title bar → search section → plot controls slot → left extra slot → results list
- Right column: result header (save/update) → status area → plot canvas → right extra slot → trace panel → warning panel

Shell-driven behavior (uniform across all workflows):
- Search: shell renders search bar + action bar; `WorkbenchFeatureStore.runWorkflowMeasurementSearch()` executes search
- Analyze: shell renders Analyze button → calls `store.runAnalysis()` → store ingests + renders + calls `commitRunTrace()`
- Clear: shell renders Clear / Clear Plot buttons → calls `store.clearResults()` / `store.clearPlot()`
- Trace: `commitRunTrace()` is called only inside `runAnalysis()`, never on restore/rerender paths
- Save: shell renders Save to Library button → calls `store.persistToLibrary()`
- Pack load: shell renders Load Pack popover → calls `store.restoreFromPack()`; restore path uses `_rerenderActiveTab()` / `_rerenderAllTabs()`, not `runAnalysis()`

WorkspaceStore contract (`WorkbenchWorkspaceProviding`):
- Inherits: `WorkbenchPlottingStore`, `AnalysisPackProviding`, `ActiveChartProviding`
- Must implement: selection, execution, rerender, clear, trace, persistence
- Default implementations provided: `appendWarning()`, `commitRunTrace()`

Adding a new workflow checklist:
1. Register workflow ID in `WorkbenchWorkflowID` enum
2. Create `<Name>IngestionContracts.swift` — domain result struct (Codable, Hashable, Sendable)
3. Create `Ingest<Name>SelectionsUseCase.swift` — stateless ingestion from search hits to result
4. Create `<Name>PackContracts.swift` — `PackConfig` (UI state snapshot) + `PackResult` (must include ingestionResult)
5. Create `<Name>WorkspaceStore.swift` — `@MainActor @Observable final class` conforming `WorkbenchWorkspaceProviding`
6. Create `<Name>WorkspaceView.swift` — thin view wrapping `WorkflowWorkspaceShell` with slot content
7. Register store in `WorkbenchFeatureStore` and view in `WorkflowWorkspaceRegistry`
8. Add search case in `WorkbenchFeatureStore.runWorkflowMeasurementSearch()`

`[HARD][must]` New workflows must use the shell. Do not build standalone two-column views.
`[HARD][must]` `runAnalysis()` is the sole entry point for trace commit. Restore and rerender paths must not commit trace.
`[HARD][must]` `PackResult` must include `ingestionResult` so that restore can rerender without re-ingestion.

ViewBuilder slots reference:

| Slot | Purpose | Example |
|---|---|---|
| `searchExtra` | Additional search fields (e.g. RT file picker) | `ThreeOmegaRTSearchField` / `EmptyView` |
| `plotControls` | Tab picker, stack offset, grid toggle, style panel | `WorkbenchStandardPlotControls` or custom |
| `leftExtra` | Left column bottom panels (geometry, overrides) | `ThreeOmegaGeometryPanel` / `EmptyView` |
| `rightExtra` | Right column extra panels (scaling results) | `ThreeOmegaScalingResultPanel` / `EmptyView` |

---

## Import Pipeline (5-stage boundary)

- Parse/: filename tokenization only. No routing decisions.
- Route/: generate RoutePlan candidates only. No final verdict.
- Match/: library drawer matching only. No UI projection.
- Evaluate/: compute final RouteStatus verdict only. No direct UI output.
- Presentation/: convert routing data to UI structs only. No business logic.
- InboxRoutingState is the only facade connecting the routing pipeline to AppState.
- Filename matching rules live in filename_rules.json via RuleLoader.shared. Do not hard-code patterns.

---

## Extension Module Policy

- New workflow support must implement all four extension protocols:
  WorkflowExtension, MetadataExtension, AnalysisModuleExtension, ViewExtension.
- Register in WorkflowRegistry.registerBuiltins().
- Extension modules must NOT import Features/ or App/ modules.
  - They may only depend on Domain types and protocol contracts in Extensions/ExtensionPoints.swift.
- New measurement types: add to domain enum first, then implement in extension.

---

## Change Boundary Policy (strict)

UI-only tasks may modify only the feature directory corresponding to the requested change:
- `Sources/SpinLabApp/Features/Inbox/**` (for Inbox UI changes)
- `Sources/SpinLabApp/Features/Library/**` (for Library UI changes)
- `Sources/SpinLabApp/Features/Workbench/**` (for Workbench UI changes)
- `Sources/SpinLabApp/UI/**` (for shared UI components)

UI-only tasks must NOT modify parser/state/registry logic files.

If a request requires both UI and logic changes:
- Stop and explicitly split into two tasks first.
- Complete UI and logic in separate rounds.

---

## Pre-merge Architecture Checklist

- No new root passthrough property was added to AppState for single-domain state.
- Single-domain logic lives in its FeatureStore.
- Cross-domain logic lives in AppState.
- New/changed behavior has tests at matching version prefix.
- `./scripts/build_desktop_app.sh debug` succeeded after all source changes.

Anti-patterns (forbidden):
- Adding new `library*` / `inbox*` / `workbench*` state fields directly on AppState when a FeatureStore exists.
- Calling Repository/Store directly from Views.
- Mixing UI-only changes with parser/state/storage logic in one undifferentiated commit.

---

## Temporary Exceptions (as of v5.1.1)

- `SpinLabAppState` retains cross-store coordination methods (loadExistingDrawers, applyExistingIndex, commitLibraryMutation, etc.) that bridge Library ↔ Inbox.
  - Constraint: these are legitimate AppState responsibilities per architecture rules. Not migration debt.
- No Library-domain passthrough properties or methods remain on AppState.

Exit criteria:
- AppState only keeps: selected area, global alert/audit/navigation, cross-store orchestration, store references.
- Single-domain feature behavior fully owned by corresponding FeatureStore.

---

## Build and Version Policy

- Every functional change must bump `Sources/SpinLabApp/App/AppVersion.swift` (`AppVersion.library`), unless the user explicitly instructs otherwise.
- `[HARD][must]` Every round of code changes must end with executing `./scripts/build_desktop_app.sh debug` to rebuild and overwrite `/Users/jack/Desktop/SpinLab.app`. This is a sign-off gate.

---

## Cross-review Trigger Criteria (SpinLab-specific)

- Touches 2+ architectural modules or crosses layer boundaries
- Introduces a new pattern, protocol, or structural convention
- Changes persistence format or domain model shape
- Modifies CLAUDE.md rules or docs/ architecture specs
- Exception: purely mechanical and contained changes skip design review.
