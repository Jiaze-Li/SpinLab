# XY Rotation Workflow Assembly

> Implementation record for the XY Rotation workflow assembly.

## Reality Check

- Workflow ID: `xy`
- Runtime display name is loaded from `WorkflowDefinitionStore` / `config/workflow.json`; this record maps the runtime assembly that consumes it.
- The assembly is the concrete combination of registry dispatch, workspace view, workflow store, typed contracts, parsers, render helper, and tests.

## Contract-Field Audit

| Field | Current real implementation | Files | Explicit or implicit |
|---|---|---|---|
| Workflow Identity | Explicit registry key `xy`; also surfaced through `WorkbenchWorkflowID.xyRotation` and workflow definitions loaded from `config/workflow.json`. | `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift`; `Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift`; `Sources/SpinLabApp/Workflow/WorkflowDefinitionStore.swift`; `Sources/SpinLabApp/Workflow/WorkflowDefinition.swift` | Explicit at registry / workflow-ID level |
| Physics Function | Distributed across two parsers, the selection ingestion use case, series-order alignment, and the plot renderer. No dedicated XY physics contract object exists. | `Sources/SpinLabApp/UseCases/XYRotationLVMParser.swift`; `Sources/SpinLabApp/UseCases/XYRotationDATParser.swift`; `Sources/SpinLabApp/UseCases/IngestXYRotationSelectionsUseCase.swift`; `Sources/SpinLabApp/UseCases/AlignXYSeriesOrderUseCase.swift`; `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift` | Implicit and distributed |
| Workflow Parameters | Stack offset, gap fraction, baseline centering, detrending, 180-degree reference line, title template, and phi-offset overrides live directly on the store. | `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift`; `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift` | Implicit in store / view state |
| Plot Defaults | Default tab, default offset values, and plot-grid default are set by store initialization and `TabRenderManager` behavior rather than a separate assembly contract. | `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift`; `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift` | Implicit default behavior |
| Optional Panels / optional contributions | The view uses one optional contribution slot: `XYRotationPhiOffsetPanel` in the shell's left region. There is no distinct optional-panel contract type. | `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift`; `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift` | Explicit in view composition, implicit as contract |
| Save Metadata Provider | Save metadata is derived inside `XYRotationWorkspaceStore.persistToLibrary()` from the current render state and chart data. No separate metadata-provider object exists. | `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift`; `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift`; `Sources/SpinLabApp/Workbench/V3/XYRotationPackContracts.swift` | Implicit in store methods |
| Pack Metadata Provider | Pack data is explicit as `XYRotationPackConfig` / `XYRotationPackResult`, and the store implements build/restore directly. There is no dedicated pack-provider layer. | `Sources/SpinLabApp/Workbench/V3/XYRotationPackContracts.swift`; `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` | Explicit contracts, implicit provider boundary |
| Required Tests | Workflow-specific regression coverage is explicit, but spread across focused tests rather than a single assembly manifest. | `Tests/SpinLabAppTests/V420XYRotationTests.swift`; `Tests/SpinLabAppTests/V5111AlignXYSeriesOrderUseCaseTests.swift`; `Tests/SpinLabAppTests/V537XYSearchSnapshotConsumptionTests.swift`; `Tests/SpinLabAppTests/V537WorkflowShellPhase4Tests.swift`; `Tests/SpinLabAppTests/V563WorkflowStateBoundaryTests.swift` | Explicit test coverage, implicit manifest |

## Notes

- `XYRotationWorkspaceStore` currently keeps its pack / restore behavior inline with the workflow store.
- The workflow uses two parser surfaces (`LVM` and `DAT`) and one render helper; the assembly record should stay aligned with those files, not with a hypothetical merged parser.
