# AHE Workflow Assembly

> Implementation record for the AHE workflow assembly.

## Reality Check

- Workflow ID: `ahe`
- Runtime display name is loaded from `WorkflowDefinitionStore` / `config/workflow.json`; this record maps the runtime assembly that consumes it.
- The assembly is not a single object. It is the composition of registry dispatch, the workspace view, the workflow store, typed pack / ingestion contracts, and tests.

## Code Map

- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift` - dispatches `"ahe"` to `AHEWorkspaceView`.
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift` - hosts the shared workbench shell for the AHE workspace.
- `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift` - composes the shell and AHE-specific control panels.
- `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` - owns AHE selection, analysis, render, persistence, and pack restore state.
- `Sources/SpinLabApp/Workbench/V3/AHEIngestionContracts.swift` - defines the AHE ingestion and selection result contracts.
- `Sources/SpinLabApp/Workbench/V3/AHEPackContracts.swift` - defines the AHE pack config and result snapshots.
- `Sources/SpinLabApp/UseCases/AHEAxisDetector.swift` - derives candidate axes for AHE plots and metric extraction.
- `Sources/SpinLabApp/UseCases/AHEDataParser.swift` - parses AHE measurement inputs.
- `Sources/SpinLabApp/UseCases/IngestAHESelectionsUseCase.swift` - converts selected hits into AHE ingestion output.
- `Sources/SpinLabApp/UseCases/BuildAHEPlotPayloadUseCase.swift` - assembles the active AHE plot payload.
- `Sources/SpinLabApp/UseCases/ExtractAHEMetricsUseCase.swift` - extracts coercive field and related AHE metrics.
- `Tests/SpinLabAppTests/V321AHEIngestionAxisDetectionTests.swift` - covers AHE axis detection behavior.
- `Tests/SpinLabAppTests/V331AHEWorkspaceViewExtractionTests.swift` - covers workspace view extraction and shell composition.
- `Tests/SpinLabAppTests/V333AHEWorkspaceStoreIsolationTests.swift` - covers store isolation and state ownership.
- `Tests/SpinLabAppTests/V413AHEMultiSeriesExtractionTests.swift` - covers multi-series AHE extraction.
- `Tests/SpinLabAppTests/V5111ExtractAHEMetricsUseCaseTests.swift` - covers metric extraction use cases.
- `Tests/SpinLabAppTests/V5114AHEMetricSourceTests.swift` - covers metric source selection.
- `Tests/SpinLabAppTests/V537AHESearchSnapshotConsumptionTests.swift` - covers search snapshot consumption.
- `Tests/SpinLabAppTests/V563WorkflowStateBoundaryTests.swift` - covers cross-workflow state boundaries involving AHE.

## Notes

- `AHEWorkspaceStore` currently owns the pack / restore path directly; there is no separate workflow-pack module in this branch.
- The registry key and the workspace view are the authoritative assembly entry points for this workflow.
