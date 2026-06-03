# 3-Omega Workflow Assembly

> Implementation record for the 3-Omega workflow assembly.

## Reality Check

- Workflow ID: `3w`
- Runtime display name is loaded from `WorkflowDefinitionStore` / `config/workflow.json`; this record maps the runtime assembly that consumes it.
- The assembly is the concrete combination of registry dispatch, workspace view, workflow store, typed contracts, parsers, render / fit / scaling helpers, and tests.

## Code Map

- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift` - dispatches `"3w"` to `ThreeOmegaWorkspaceView`.
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift` - hosts the shared workbench shell for the 3-Omega workspace.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift` - composes the shell, RT search field, plot controls, geometry panel, and scaling result panel.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift` - owns 3-Omega selection, analysis, rendering, scaling, persistence, and pack restore state.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Analysis.swift` - drives 3-Omega ingestion and fit analysis.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Rendering.swift` - builds the 3-Omega render state.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Scaling.swift` - computes the 3-Omega scaling workflow output.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift` - serializes and restores the 3-Omega pack state.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+ManifestCache.swift` - maintains manifest payload caching.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Persistence.swift` - persists 3-Omega charts and metrics to the Library.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Selection.swift` - owns field-sweep selection state.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+RTSelection.swift` - owns RT selection state.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+FitRanges.swift` - manages scaling fit ranges.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+RelatedCharts.swift` - tracks related chart references.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Plotting.swift` - adapts the workflow store to the shared plot shell.
- `Sources/SpinLabApp/Workbench/Domain/ThreeOmegaIngestionDomain.swift` - defines the 3-Omega ingestion domain types.
- `Sources/SpinLabApp/Workbench/V3/ThreeOmegaPackContracts.swift` - defines the 3-Omega pack config and result snapshots.
- `Sources/SpinLabApp/Domain/ThreeOmegaFieldSweepResult.swift` - carries the derived field-sweep result model.
- `Sources/SpinLabApp/Domain/ThreeOmegaGeometry.swift` - carries the geometry contract used by scaling.
- `Sources/SpinLabApp/Domain/ThreeOmegaScalingResult.swift` - carries the scaling-law result model.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkbenchTab.swift` - defines the 3-Omega tab model.
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaRenderedPlots.swift` - defines the rendered-plot projection model.
- `Sources/SpinLabApp/UseCases/ThreeOmegaLVMParser.swift` - parses 3-Omega LVM inputs.
- `Sources/SpinLabApp/UseCases/IngestThreeOmegaSelectionsUseCase.swift` - converts selected hits into 3-Omega ingestion output.
- `Sources/SpinLabApp/UseCases/ThreeOmegaFitUseCase.swift` - fits the 3-Omega AHE and RAHE outputs.
- `Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift` - assembles the active 3-Omega plot payload.
- `Sources/SpinLabApp/UseCases/ThreeOmegaScalingUseCase.swift` - computes the scaling-law projection.
- `Sources/SpinLabApp/UseCases/ThreeOmegaStackOffsetUseCase.swift` - derives the stack-offset helper used by the shell.
- `Tests/SpinLabAppTests/V400ThreeOmegaTests.swift` - covers the baseline 3-Omega workflow path.
- `Tests/SpinLabAppTests/V4110ThreeOmegaStackOffsetUseCaseTests.swift` - covers stack-offset behavior.
- `Tests/SpinLabAppTests/V4112ThreeOmegaV3MethodTests.swift` - covers V(3ω) method selection.
- `Tests/SpinLabAppTests/V4116ThreeOmegaRAHETests.swift` - covers RAHE extraction behavior.
- `Tests/SpinLabAppTests/V41216ThreeOmegaPlotRendererTests.swift` - covers plot rendering behavior.
- `Tests/SpinLabAppTests/V41216ThreeOmegaScalingUseCaseTests.swift` - covers scaling-law computation.
- `Tests/SpinLabAppTests/V413ThreeOmegaFitUseCaseTests.swift` - covers fit behavior.
- `Tests/SpinLabAppTests/V5115ThreeOmegaWorkspaceStoreCharacterizationTests.swift` - covers store characterization.
- `Tests/SpinLabAppTests/V537ThreeOmegaSearchSnapshotConsumptionTests.swift` - covers search snapshot consumption.
- `Tests/SpinLabAppTests/V563ThreeOmegaFieldSweepSeriesOrderTests.swift` - covers field-sweep ordering behavior.
- `Tests/SpinLabAppTests/V563WorkflowStateBoundaryTests.swift` - covers cross-workflow state boundaries involving 3-Omega.

## Notes

- `ThreeOmegaWorkspaceStore` currently keeps the workflow's pack / restore, manifest cache, scaling, and plotting behaviors inside one store plus extensions.
- The 3-Omega record should stay aligned with the split store extensions and the typed domain / contract files above; do not collapse it into an abstract "workflow module" that does not exist in the codebase.
