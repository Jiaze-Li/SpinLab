# Workbench — Extension Boundaries

> Extension layer: Adding-a-new-workflow 8 步清单、extension import rules、Domain / ExtensionPoints 依赖边界。

## Adding a New Workflow (8-step checklist)

1. Register workflow ID in `WorkbenchWorkflowID` enum (`Workflow/WorkflowID.swift`).
2. Create `<Name>IngestionContracts.swift` — domain result struct (`Codable`, `Hashable`, `Sendable`).
3. Create `Ingest<Name>SelectionsUseCase.swift` — stateless ingestion from search hits to result.
4. Create `<Name>PackContracts.swift` — `PackConfig` (UI state snapshot) + `PackResult` (must include `ingestionResult`).
5. Create `<Name>WorkspaceStore.swift` — `@MainActor @Observable final class` conforming `WorkbenchWorkspaceProviding`.
6. Create `<Name>WorkspaceView.swift` — thin view wrapping `WorkflowWorkspaceShell` with slot content.
7. Register store in `WorkbenchFeatureStore` and view in `WorkflowWorkspaceRegistry`.
8. Add search case in `WorkbenchFeatureStore.runWorkflowMeasurementSearch()`.

## [HARD] Shell Invariants (applies to all workflows)

These invariants are enforced at the shell level; all steps above must respect them:

- New workflows must use the shell. Do not build standalone two-column views.
- `runAnalysis()` is the sole entry point for trace commit. Restore and rerender paths must not commit trace.
- `PackResult` must include `ingestionResult` so that restore can rerender without re-ingestion.

Full shell contract: [`SHELL_AND_LIFECYCLE.md`](SHELL_AND_LIFECYCLE.md)

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

## Code Map

- `Sources/SpinLabApp/Workflow/WorkflowID.swift` — registers stable workflow IDs as an enum-like identifier type
- `Sources/SpinLabApp/Workflow/WorkflowDefinition.swift` — defines the workflow registration contract (ID, metadata, capabilities)
- `Sources/SpinLabApp/Extensions/ExtensionPoints.swift` — declares extension points for workflow opt-in capabilities
- `Sources/SpinLabApp/Workflow/WorkflowDefinitionStore.swift` — stores registered workflow definitions; populated at app startup
- `Sources/SpinLabApp/Workflow/WorkflowRegistry.swift` — global registry mapping workflow IDs to their definitions and capabilities
