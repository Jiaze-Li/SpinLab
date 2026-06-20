# Workbench — Extension Boundaries

> **Superseded 2026-06.** Workflow extension checklist, code placement table, and Main Board invariants have moved to [WORKFLOW_EXTENSION.md](WORKFLOW_EXTENSION.md). Module ownership and forbidden mutations are in [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md).

## Extension Module Import Rules

- Extension modules must NOT import `Features/` or `App/` modules.
- Extensions may only depend on:
  - `Domain/` types
  - Protocol contracts in `Extensions/ExtensionPoints.swift`
- New measurement types: add to domain enum first, then implement in extension.
- New workflow support must implement all four extension protocols: `WorkflowExtension`, `MetadataExtension`, `AnalysisModuleExtension`, `ViewExtension`.
- Register in `WorkflowRegistry.registerBuiltins()`.

## Code Map

- `Sources/SpinLabApp/Domain/Workflow/WorkflowID.swift` - Tier 1 canonical workflow identity enum with alias normalization; cross-region contract <!-- legitimate_cross_cutting -->
- `Sources/SpinLabApp/Domain/Workflow/WorkflowDefinitionProviding.swift` - capability protocol for loading workflow definitions; WorkflowDefinitionStore conforms
- `Sources/SpinLabApp/Workflow/WorkflowDefinition.swift` - defines the workflow registration contract (ID, metadata, capabilities)
- `Sources/SpinLabApp/Extensions/ExtensionPoints.swift` - declares extension points for workflow opt-in capabilities
- `Sources/SpinLabApp/Workflow/WorkflowDefinitionStore.swift` - stores registered workflow definitions; populated at app startup
- `Sources/SpinLabApp/Workflow/WorkflowRegistry.swift` - global registry mapping workflow IDs to their definitions and capabilities
- `Sources/SpinLabApp/Workbench/V3/IVIngestionContracts.swift` - IV domain result types: IVSweep, IVIngestionResult, IVWorkbenchTab <!-- gate8.1 -->
- `Sources/SpinLabApp/UseCases/IngestIVSelectionsUseCase.swift` - stateless ingestion from search hits to IVIngestionResult (Gate 8 stub) <!-- gate8.1 -->
- `Sources/SpinLabApp/Workbench/V3/IVPackContracts.swift` - IVPackConfig + IVPackResult for IV workspace pack/restore <!-- gate8.1 -->
- `Sources/SpinLabApp/Features/Workbench/IVWorkspaceStore.swift` - WorkbenchWorkspaceProviding conformance for IV workflow <!-- gate8.1 -->
- `Sources/SpinLabApp/Features/Workbench/IVWorkspaceView.swift` - IV workspace view wrapping WorkflowWorkspaceShell <!-- gate8.1 -->
- Gate 8 finding: common series-order key resolution had been hidden in `ThreeOmegaWorkspaceStore.seriesOrderKey`; it is now extracted to `WorkbenchSeriesOrderKeyResolver`, which is owned by the Plot System and consumed by the shared series-order/rename path. <!-- gate8.1 -->
