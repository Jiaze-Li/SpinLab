# AHE Workflow Assembly

> Implementation record for the AHE workflow assembly.

## Reality Check

- Workflow ID: `ahe`
- Runtime display name is loaded from `WorkflowDefinitionStore` / `config/workflow.json`; this record maps the runtime assembly that consumes it.
- The assembly is not a single object. It is the composition of registry dispatch, the workspace view, the workflow store, typed pack / ingestion contracts, and tests.

## Contract-Field Audit

| Field | Current real implementation | Files | Explicit or implicit |
|---|---|---|---|
| Workflow Identity | Explicit registry key `ahe`; also surfaced through `WorkbenchWorkflowID.ahe` and workflow definitions loaded from `config/workflow.json`. | `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift`; `Sources/SpinLabApp/App/State/WorkbenchFeatureStore.swift`; `Sources/SpinLabApp/Workflow/WorkflowDefinitionStore.swift`; `Sources/SpinLabApp/Workflow/WorkflowDefinition.swift` | Explicit at registry / workflow-ID level |
| Physics Function | Distributed across ingestion, axis detection, payload assembly, and metric extraction. No single AHE physics contract object exists in this branch. | `Sources/SpinLabApp/UseCases/AHEAxisDetector.swift`; `Sources/SpinLabApp/UseCases/AHEDataParser.swift`; `Sources/SpinLabApp/UseCases/IngestAHESelectionsUseCase.swift`; `Sources/SpinLabApp/UseCases/BuildAHEPlotPayloadUseCase.swift`; `Sources/SpinLabApp/UseCases/ExtractAHEMetricsUseCase.swift` | Implicit and distributed |
| Workflow Parameters | Plot axis overrides, title template, grid toggle, metric override candidates, and selection state live directly on the workflow store and its panels. There is no separate parameter contract type. | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift`; `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift` | Implicit in store / view state |
| Plot Defaults | Default tab state, title template, and grid default come from store initialization and `TabRenderManager` defaults, not from a dedicated assembly record. | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift`; `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift` | Implicit default behavior |
| Optional Panels / optional contributions | The view explicitly injects optional panels through shell slots: plot controls, metric override, and RAHE override panels. There is no standalone optional-contribution abstraction. | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift`; `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift` | Explicit in view composition, implicit as contract |
| Save Metadata Provider | Save metadata is produced inside `AHEWorkspaceStore.persistToLibrary()` from the active render state and `buildActiveChartMetrics()`. No separate metadata-provider object exists. | `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift`; `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift`; `Sources/SpinLabApp/Workbench/V3/AHEPackContracts.swift` | Implicit in store methods |
| Pack Metadata Provider | Pack data is explicit as `AHEPackConfig` / `AHEPackResult`, and restoration is implemented directly on the store. There is no dedicated pack-provider layer. | `Sources/SpinLabApp/Workbench/V3/AHEPackContracts.swift`; `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` | Explicit contracts, implicit provider boundary |
| Required Tests | Workflow-specific regression coverage is explicit, but the suite is a set of focused tests rather than a single assembly test manifest. | `Tests/SpinLabAppTests/V321AHEIngestionAxisDetectionTests.swift`; `Tests/SpinLabAppTests/V331AHEWorkspaceViewExtractionTests.swift`; `Tests/SpinLabAppTests/V333AHEWorkspaceStoreIsolationTests.swift`; `Tests/SpinLabAppTests/V413AHEMultiSeriesExtractionTests.swift`; `Tests/SpinLabAppTests/V5111ExtractAHEMetricsUseCaseTests.swift`; `Tests/SpinLabAppTests/V5114AHEMetricSourceTests.swift`; `Tests/SpinLabAppTests/V537AHESearchSnapshotConsumptionTests.swift`; `Tests/SpinLabAppTests/V563WorkflowStateBoundaryTests.swift` | Explicit test coverage, implicit manifest |

## Notes

- `AHEWorkspaceStore` currently owns the pack / restore path directly; there is no separate workflow-pack module in this branch.
- The registry key and the workspace view are the authoritative assembly entry points for this workflow.
