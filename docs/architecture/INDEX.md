# Architecture Index

> **Status**: 5.1.6 current architecture dispatch entry.
> **Source**: distilled from [`REGION_MAP.md`](REGION_MAP.md). Use REGION_MAP for scan evidence, line counts, TODOs, shell candidates, and shared-point proof table.
> **Code coverage**: 97/218 source files mapped. Last verified: 2026-04-30 by `scripts/verify_architecture_code_coverage.sh`.

## How To Use

For a change request, pick the region first, then read:

1. **First-read files**: start here to understand ownership and current behavior.
2. **Consumers / collaborators**: inspect when the change crosses boundaries.
3. **Shared risks**: check before editing fields, paths, stores, or runtime config.
4. **Tests**: run or extend these when behavior changes.

Do not infer ownership from physical directory alone. Some `App/`, `Import/`, and `UseCases/` files belong to a feature region by consumer.

## Region Summary

| Region | Owns | First-read files |
|---|---|---|
| Inbox | Import, parse, route, match, pending review, apply-to-library | [`architecture/inbox/INDEX.md`](inbox/INDEX.md) |
| Library | Archived measurement browsing/editing, library persistence, registry sync, sidecar viewing | [`architecture/library/INDEX.md`](library/INDEX.md) |
| Workbench | Measurement search, workflow analysis, plot shell, chart/metric persistence | `App/State/WorkbenchFeatureStore.swift`; `Features/Workbench/WorkflowWorkspaceShell.swift`; `Features/Workbench/WorkflowWorkspaceProvider.swift`; `UseCases/SearchWorkflowMeasurementsUseCase.swift`; workflow store for target workflow |
| Rules | Runtime rule config, rule loading/migration, RulesPanel UI | `Features/RulesPanel/RulesManagementStore.swift`; `Features/RulesPanel/RulesPanelView.swift`; `Import/Rules/RuleLoader.swift`; `Import/Rules/FilenameRuleSet.swift`; `Import/Rules/RulesBootstrapper.swift` |
| Cross-cutting | App shell, global DI/navigation/logging, Domain contracts, Registry bridge, shared UI/storage | `App/SpinLabAppState.swift`; `App/AppEnvironment.swift`; `Domain/Models.swift`; `Registry/SampleRegistry.swift`; `UI/AppColumnShell.swift` |

## Inbox

**First-Read**

| Task area | Start here | Then inspect |
|---|---|---|
| Pending import state / tasks | `App/State/InboxFeatureStore.swift` | `Features/Inbox/InboxView.swift`; `Features/Inbox/InboxOperationPanel.swift`; `Features/Inbox/InboxViewModel.swift` |
| Route state / draft edits | `App/State/InboxRoutingState.swift` | `Features/Inbox/InboxSelectionWorkbenchPanel.swift`; `Import/Evaluate/PendingRoutingSnapshotEvaluator.swift` |
| Parse/import pipeline | `Import/ImportPipeline.swift` | `Import/Parse/FilenameRuleParser.swift`; `Import/Route/RoutePlanner.swift`; `Import/Presentation/PendingRoutePresentation.swift` |
| Drawer matching | `Import/Match/DrawerMatchEngine.swift` | `Import/Parse/SampleKeyNormalizer.swift`; `Library/LibraryModels.swift` |
| Apply/archive to Library | `App/ApplyCoordinator.swift` | `App/InboxArchiveApplyService.swift`; `Library/LibraryWriteTransaction.swift`; `Library/SpinLabFileSidecar.swift`; `Library/LibraryStore.swift` |

**Boundary Rules**

| Shared point | Classification | Risk |
|---|---|---|
| Inbox apply writes Library files/sidecars | `coordination_surface` (`SP-010`) | Keep Inbox as workflow owner, Library as storage owner. Do not bypass `LibraryWriteTransaction` for paired file + sidecar writes. |
| Drawer matching uses Library sample shape and Import sample helpers | `coordination_surface` (`SP-012`) | Changes to sample key semantics can affect Inbox matching and Workbench search. |
| Inbox route semantics depend on Rules | `coordination_surface` | Check `RuleLoader`, `FileRoutingRuleBook`, and RulesPanel save behavior when changing route rules. |

**Tests**

Start with `V230ApplyTests.swift`, `V250SidecarTests.swift`, `V221DrawerMatchEngineTests.swift`, `V211RoutePlannerTests.swift`, `V221RoutePresentationTests.swift`.

## Library

**First-Read**

| Task area | Start here | Then inspect |
|---|---|---|
| Library state / selection / projections | `App/State/LibraryFeatureStore.swift` | `App/State/LibraryFeatureStore+Projection.swift`; `App/State/LibraryFeatureStore+SampleEdit.swift`; `Features/Library/LibraryView.swift` |
| Library repository / filesystem index | `Library/LibraryStore.swift` | `Library/LibrarySyncService.swift`; `Library/LibraryXLSXSyncService.swift`; `Library/LibrarySettingsStore.swift` |
| Registry sync / sample metadata edits | `App/LibraryMutationService.swift` | `UseCases/SaveLibrarySampleEditsUseCase.swift`; `Library/LibraryRegistryParser.swift`; `Library/LibraryDiffEngine.swift` |
| Measurement condition/sidecar UI | `Library/SpinLabFileSidecar.swift` | `Features/Library/MeasurementConditionDetailView.swift`; `Features/Library/MeasurementDataSectionView.swift` |
| Chart preview and stored artifacts | `Features/Library/MeasurementPlotPreviewPanel.swift` | `Library/LibraryPathResolver.swift`; `UseCases/LoadMeasurementPlotIndexUseCase.swift`; `UseCases/LoadRelatedChartsUseCase.swift` |

**Boundary Rules**

| Shared point | Classification | Risk |
|---|---|---|
| `SpinLabFileSidecar` shared by Library, Inbox, Workbench | `legitimate_cross_cutting` (`SP-006`) | Treat as file contract. Schema changes require migration/tests, not local UI-only edits. |
| Workbench writes Library `_spinlab` artifacts/indexes | `coordination_surface` (`SP-007`) | Workbench owns generation; Library owns storage namespace and cleanup invariants. |
| `LibraryPathResolver` shared across Library and Workbench | `legitimate_cross_cutting` (`SP-008`) | Use it for root-relative paths. Avoid hand-built absolute/relative path logic. |

**Tests**

Start with `V513LibraryFeatureStoreFacadeTests.swift`, `V220LibraryDiffEngineTests.swift`, `V260MeasurementsDisplayTests.swift`, `V416DeleteAppliedMeasurementTests.swift`, `V343DeleteWorkbenchResultTests.swift`, `V41217MeasurementPlotIndexTests.swift`.

## Workbench

**First-Read**

| Task area | Start here | Then inspect |
|---|---|---|
| Workbench state and common condition projections | `App/State/WorkbenchFeatureStore.swift` | `Features/Workbench/WorkbenchView.swift`; `Features/Workbench/WorkflowRegistryView.swift` |
| Workflow shell/UI composition | `Features/Workbench/WorkflowWorkspaceShell.swift` | `Features/Workbench/WorkflowWorkspaceProvider.swift`; `Features/Workbench/WorkflowWorkspaceRegistry.swift` |
| 3-Omega workflow | `Features/Workbench/ThreeOmegaWorkspaceStore.swift` | `Features/Workbench/ThreeOmegaWorkspaceView.swift`; `UseCases/ThreeOmegaFitUseCase.swift`; `UseCases/ThreeOmegaPlotRenderer.swift` |
| XY Rotation workflow | `Features/Workbench/XYRotationWorkspaceStore.swift` | `Features/Workbench/XYRotationWorkspaceView.swift`; `UseCases/XYRotationDATParser.swift`; `UseCases/XYRotationPlotRenderer.swift` |
| AHE workflow | `Features/Workbench/AHEWorkspaceStore.swift` | `Features/Workbench/AHEWorkspaceView.swift`; `UseCases/AHEDataParser.swift`; `UseCases/AHEAxisDetector.swift` |
| Search measurements | `UseCases/SearchWorkflowMeasurementsUseCase.swift` | `Domain/WorkflowSearchModels.swift`; `Workflow/WorkflowID.swift`; `Library/SpinLabFileSidecar.swift` |
| Save chart/metrics to Library | `UseCases/SaveActiveChartToLibraryUseCase.swift` | `UseCases/PersistChartArtifactUseCase.swift`; `UseCases/PersistMeasurementDataUseCase.swift`; `Workbench/V3/WorkbenchResultContracts.swift` |

**Boundary Rules**

| Shared point | Classification | Risk |
|---|---|---|
| Condition projection from Rules lives in Workbench store | `coordination_surface` (`SP-002`) | Verify rule reload path when editing condition definitions or Workbench condition options. |
| Workbench search reads Library sidecars and Import semantics | `coordination_surface` (`SP-009`) | Sample key semantics affect search, ingestion, and drawer matching together. |
| Shared plot/workflow shells | shell candidates (`G-006`, `G-007`, `G-008`, `G-015`) | Do not extract more shell code without checking semantic equality across workflows. |

**Tests**

Start with `V310WorkbenchFoundationTests.swift`, `V320WorkflowSearchAcrossDrawersTests.swift`, `V330WorkbenchShellContractTests.swift`, `V532WorkbenchRenderPipelineTests.swift`, `V4111SaveActiveChartToLibraryUseCaseTests.swift`, `V413ThreeOmegaFitUseCaseTests.swift`, `V321AHEIngestionAxisDetectionTests.swift`.

## Rules

**First-Read**

| Task area | Start here | Then inspect |
|---|---|---|
| Rule runtime loading/cache | `Import/Rules/RuleLoader.swift` | `Import/Rules/SpinLabRuleProvider.swift`; `Import/Rules/RulesConfigPaths.swift`; `Storage/RulesSyncEngine.swift` |
| Rule schema / matching semantics | `Import/Rules/FilenameRuleSet.swift` | `Import/Rules/RuleCanonicalizer.swift`; `Import/Rules/FileRoutingSemanticRules.swift`; `Import/Rules/ConditionFieldCatalog.swift` |
| Runtime migration | `Import/Rules/RulesBootstrapper.swift` | `Import/Rules/WorkflowRegistryRetirementService.swift` |
| RulesPanel state/save | `Features/RulesPanel/RulesManagementStore.swift` | `Features/RulesPanel/SectionPersistenceStrategy.swift`; `Features/RulesPanel/RulesSectionShell.swift` |
| RulesPanel UI sections | `Features/RulesPanel/RulesPanelView.swift` | `Features/RulesPanel/Sections/WorkflowSection.swift`; `Features/RulesPanel/Sections/MeasuringConditionSection.swift`; `Features/RulesPanel/Sections/SampleIdentificationSection.swift` |

**Boundary Rules**

| Shared point | Classification | Risk |
|---|---|---|
| `ConditionDefinition.tokenMap` carries two semantics | `suspect_coupling` (`SP-001`) | First structural debt. Do not build new behavior on this field shape. See 5.1.8 handoff seed. |
| RulesPanel save reloads runtime rules consumed by multiple regions | `coordination_surface` (`SP-003`) | Save/reload changes can affect Inbox route, Registry lookup, Workbench condition options. |
| `workflow.json` owned by Rules but consumed by Workbench | `coordination_surface` (`SP-004`) | Keep config ownership in Rules; Workbench is read/display consumer. |

**Tests**

Start with `V515RulesPanelStoreTests.swift`, `V515RulesPanelSaveValidationTests.swift`, `V515RulesPanelCrossSectionTests.swift`, `V515RulesSaveImmediateEffectTests.swift`, `V515RulesEngineRegressionTests.swift`, `V515RulesBootstrapperMigrationTests.swift`, `V515RulesSyncStartupTests.swift`.

## Cross-Cutting

**First-Read**

| Task area | Start here | Then inspect |
|---|---|---|
| App shell / global coordination | `App/SpinLabAppState.swift` | Feature stores under `App/State/`; `App/SpinLabDataActor.swift`; `App/AppEnvironment.swift` |
| Navigation/root UI | `App/RootSplitView.swift` | `App/State/AppRouter.swift`; `App/SidebarTreeView.swift`; `App/SpinLabSidebarMenuProvider.swift` |
| Shared Domain models | `Domain/Models.swift` | `Domain/WorkflowSearchModels.swift`; `Domain/AnalysisPack.swift`; `Domain/RecomputePreviewItem.swift` |
| Registry bridge | `Registry/SampleRegistry.swift` | `Registry/RegistryLookupRuleBook.swift`; `Import/RegistrySubstrateRuleBook.swift`; `App/RegistryCoordinator.swift` |
| Shared storage/UI infrastructure | `Storage/AtomicFileWriter.swift`; `UI/AppColumnShell.swift` | `Storage/RepositoryPointer.swift`; `UI/MetadataViews.swift`; `UI/HoverPopoverModifier.swift` |
| Workflow identity/config | `Workflow/WorkflowID.swift` | `Workflow/WorkflowDefinition.swift`; `Workflow/WorkflowDefinitionStore.swift`; `Workflow/WorkflowRegistry.swift` |

**Boundary Rules**

| Shared point | Classification | Risk |
|---|---|---|
| Registry serves Inbox + Library and reads Rules aliases | `coordination_surface` (`SP-005`) | Treat Registry as cross-cutting bridge, not a single-region feature. |
| Import sample helpers used outside Import | `migration_candidate` (`SP-013`, `SP-014`) | Future cleanup should move domain-like sample semantics out of `Import/Parse`. |
| Workflow identity aliases | `legitimate_cross_cutting` (`SP-015`) | Keep as shared Workflow config contract. |

## Structural Debt Queue

Only `suspect_coupling` and actionable `coordination_surface` items belong here.

| Priority | Item | Evidence | Target |
|---|---|---|---|
| 1 | Split `ConditionDefinition.tokenMap` semantics | `SP-001`; 5.1.8 seed | 5.1.8 condition kind decoupling |
| 2 | Clarify Rules save/reload propagation boundary | `SP-003`; `SP-002` | Future Rules/Workbench coordination cleanup |
| 3 | Formalize Workbench→Library artifact storage boundary | `SP-007`; `SP-009` | Future Workbench/Library persistence contract cleanup |
| 4 | Clarify Inbox→Library apply write invariants | `SP-010`; `SP-011` | Future apply/archive boundary hardening |
| 5 | Move sample semantic helpers out of Import placement | `SP-013`; `SP-014` | Future shared domain/parser cleanup |

## Maintenance Rule

When changing code:

- If a change touches a region first-read file, inspect that region's boundary table.
- If a change touches a shared point `SP-*`, update this index and the evidence in `REGION_MAP.md`.
- If a new cross-region dependency appears, classify it as `legitimate_cross_cutting`, `coordination_surface`, `suspect_coupling`, or `migration_candidate`.
- If a new shell/pattern repetition appears, add it to `REGION_MAP.md` Appendix G rather than extracting immediately.

## AG3 Dispatch Validation

> Validation date: 2026-04-29. Each task must resolve to first-read files, consumers/collaborators, and shared risks without reopening the full REGION_MAP.

| Task prompt | INDEX route | Result |
|---|---|---|
| "Inbox apply copied files but sidecar overrides are wrong" | Inbox → Apply/archive to Library: `App/ApplyCoordinator.swift`, `App/InboxArchiveApplyService.swift`, `Library/LibraryWriteTransaction.swift`, `Library/SpinLabFileSidecar.swift`; risks `SP-010`, `SP-011` | pass |
| "Library chart preview misses recently saved Workbench charts" | Library → Chart preview and stored artifacts; Workbench → Save chart/metrics to Library; risks `SP-007`, `SP-008` | pass |
| "Changing condition kind loses token-map entries" | Rules → Rule schema / RulesPanel state; risk `SP-001`; structure debt priority 1 / 5.1.8 seed | pass |
| "RulesPanel save does not affect Inbox routing until restart" | Rules → Rule runtime loading/cache + RulesPanel state/save; risks `SP-003`, `SP-002` | pass |
| "Workbench search cannot find sample by substrate alias" | Workbench → Search measurements; Cross-cutting → Import sample helpers; risks `SP-009`, `SP-013`, `SP-014` | pass |
| "Registry sheet aliases changed and Inbox routing regressed" | Cross-cutting → Registry bridge; Rules → Runtime rule config; risk `SP-005` | pass |
| "Add a new workflow workspace" | Workbench → Workflow shell/UI composition; then target workflow store pattern; shell candidates `G-006`, `G-008`, `G-015`; Workflow identity/config | pass |
| "Refactor large Library repository file" | Library → Library repository/filesystem index; structural debt queue + shell candidate `G-005`; boundary risks `SP-006`, `SP-007`, `SP-010` | pass |
| "Change sample key normalization" | Cross-cutting → Import sample helpers; Inbox drawer matching; Workbench search; risks `SP-012`, `SP-013`, `SP-014` | pass |
| "Audit UI components with no direct tests" | Region test sections plus REGION_MAP Appendix D; `UI/*`, `Features/*` UI components | pass with note: detailed blind-spot list remains in REGION_MAP, not duplicated here |

Miss cases: none in this 10-task sample. The only intentional fallback is detailed UI test blind spots, which remain in REGION_MAP Appendix D to avoid duplicating evidence tables in the current dispatch index.
