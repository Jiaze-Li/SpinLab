# XY Rotation Workflow Assembly

> Implementation record for the XY Rotation workflow assembly.

## Reality Check

- Workflow ID: `xy`
- Runtime display name is loaded from `WorkflowDefinitionStore` / `config/workflow.json`; this record maps the runtime assembly that consumes it.
- The assembly is the concrete combination of registry dispatch, workspace view, workflow store, typed contracts, parsers, render helper, and tests.

## Code Map

- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift` - dispatches `"xy"` to `XYRotationWorkspaceView`.
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift` - hosts the shared workbench shell for the XY Rotation workspace.
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift` - composes the shell, standard plot controls, and XY-specific offset panel.
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` - owns XY selection, analysis, rendering, persistence, and pack restore state.
- `Sources/SpinLabApp/Workbench/V3/XYRotationIngestionContracts.swift` - defines XY Rotation ingestion and selection result contracts.
- `Sources/SpinLabApp/Workbench/V3/XYRotationPackContracts.swift` - defines the XY Rotation pack config and result snapshots.
- `Sources/SpinLabApp/UseCases/XYRotationLVMParser.swift` - parses XY Rotation LVM inputs.
- `Sources/SpinLabApp/UseCases/XYRotationDATParser.swift` - parses XY Rotation DAT inputs.
- `Sources/SpinLabApp/UseCases/IngestXYRotationSelectionsUseCase.swift` - converts selected hits into XY Rotation ingestion output.
- `Sources/SpinLabApp/UseCases/AlignXYSeriesOrderUseCase.swift` - aligns XY series ordering for the render pipeline.
- `Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift` - assembles the active XY Rotation plot payload.
- `Tests/SpinLabAppTests/V420XYRotationTests.swift` - covers the XY Rotation workflow path.
- `Tests/SpinLabAppTests/V5111AlignXYSeriesOrderUseCaseTests.swift` - covers series-order alignment.
- `Tests/SpinLabAppTests/V537XYSearchSnapshotConsumptionTests.swift` - covers search snapshot consumption.
- `Tests/SpinLabAppTests/V537WorkflowShellPhase4Tests.swift` - covers shell integration for the workflow phase.
- `Tests/SpinLabAppTests/V563WorkflowStateBoundaryTests.swift` - covers cross-workflow state boundaries involving XY Rotation.

## Notes

- `XYRotationWorkspaceStore` currently keeps its pack / restore behavior inline with the workflow store.
- The workflow uses two parser surfaces (`LVM` and `DAT`) and one render helper; the assembly record should stay aligned with those files, not with a hypothetical merged parser.
