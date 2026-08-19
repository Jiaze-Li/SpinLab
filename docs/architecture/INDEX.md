# Architecture Index

> **Status**: 5.1.6 current architecture dispatch entry.
> **Source**: distilled from [`REGION_MAP.md`](REGION_MAP.md). Use REGION_MAP for scan evidence, line counts, TODOs, shell candidates, and shared-point proof table.
> **Code coverage**: 55/55 source files mapped. Last verified: 2026-07-01 by `scripts/verify_architecture_code_coverage.sh`.

## How To Use

### Adding new Swift code

新增 `Sources/**/*.swift` → 走 4 步 SOP（`CLAUDE.md > Adding New Swift Code` 段为唯一权威）：

1. 写代码 →
2. 按 region/layer 判定树（见 SOP）选目标 `docs/architecture/<region>/<layer>.md` →
3. 在该 md 的 `## Code Map` 段加一行 `` - `Sources/...swift` — <一句职责> `` →
4. `git commit`（pre-commit hook 自举：`scripts/install_git_hooks.sh`；报 unmapped/missing 时按 SOP 第 2-3 步修复）

不在此处复制 SOP 全文（避免双索引漂移）；Code coverage 行由 `verify_architecture_code_coverage.sh --write-index` 自动写回。

### Reading the index

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
| Workbench | Measurement search, workflow analysis, shell blocks, plot shell, chart/metric persistence | [`architecture/workbench/INDEX.md`](workbench/INDEX.md) |
| Rules | Runtime rule config, rule loading/migration, RulesPanel UI | `Features/RulesPanel/RulesManagementStore.swift`; `Features/RulesPanel/RulesPanelView.swift`; `Import/Rules/RuleLoader.swift`; `Import/Rules/FilenameRuleSet.swift`; `Import/Rules/RulesBootstrapper.swift` |
| Cross-cutting | App shell, global DI/navigation/logging, Domain contracts, Registry bridge, shared UI/storage | `App/SpinLabAppState.swift`; `App/AppEnvironment.swift`; `Domain/Models.swift`; `Registry/SampleRegistry.swift`; `UI/AppColumnShell.swift` |

## Inbox

Dispatch entry: [`architecture/inbox/INDEX.md`](inbox/INDEX.md)

Key risks: `SP-010` (Inbox apply writes Library files/sidecars), `SP-012` (drawer matching uses Library sample shape), `SP-006` (sidecar as shared file contract).

## Library

Dispatch entry: [`architecture/library/INDEX.md`](library/INDEX.md)

Key risks: `SP-006` (sidecar shared by Library/Inbox/Workbench), `SP-007` (Workbench writes Library `_spinlab`), `SP-008` (`LibraryPathResolver` shared).

## Workbench

Dispatch entry: [`architecture/workbench/INDEX.md`](workbench/INDEX.md)

Key risks: `SP-002` (condition projection from Rules), `SP-009` (search reads Library sidecars), `SP-007` (Workbench writes Library `_spinlab`); shell candidates `G-006`, `G-007`, `G-008`, `G-015`.

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
| `ConditionDefinition.tokenMap` carried two semantics | `suspect_coupling` (`SP-001`) — resolved | Field removed in 5.1.8; kept for history only. `ConditionDefinition.matches` / `ConditionStandardization` now carry the split semantics. |
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
| 1 | Clarify Rules save/reload propagation boundary | `SP-003`; `SP-002` | Future Rules/Workbench coordination cleanup |
| 2 | Move sample semantic helpers out of Import placement | `SP-013`; `SP-014` | Future shared domain/parser cleanup |
| 3 | Dynamic workspace store ownership — remove `WorkspaceWorkflowIDResolver` bootstrap adapter; let route entry ID flow directly into store creation | [`workbench/TECH_DEBT_DYNAMIC_WORKSPACE_STORE_OWNERSHIP.md`](workbench/TECH_DEBT_DYNAMIC_WORKSPACE_STORE_OWNERSHIP.md); Phase 6 closeout | Phase 7 |

Resolved: `Split ConditionDefinition.tokenMap semantics` (was priority 1, `SP-001`) — closed as stale; field removed and semantics split in 5.1.8. See `docs/handoff/archive/2026-04-30-5.1.8-s1-design.md`.

Resolved: `Formalize Workbench→Library artifact storage boundary` (was priority 2, `SP-007`/`SP-009`) — closed in 5.1.17. Library now owns artifact/index on-disk layout (`LibraryArtifactLayout`) and index codec + missing-vs-corrupt read policy (`LibraryChartIndexStore`, `LibraryMeasurementDataStore`); Workbench UseCases (`PersistChartArtifactUseCase`, `SaveRSMChartToLibraryUseCase`, `PersistMeasurementDataUseCase`, the `Load*UseCase` family, `BackfillMeasurementPlotIndexUseCase`) keep chart identity, overwrite/stale-file semantics, and domain orchestration. `LibraryDiskCleanupService` and `ChartAssetAuditService` migrated to the same strict/audit read paths. Same change also fixed a corrupt-index → orphan-misclassification safety bug in `ChartAssetAuditService.audit` and made `BackfillMeasurementPlotIndexUseCase`'s index write atomic via `AtomicFileWriter`.

Resolved: `Clarify Inbox→Library apply write invariants` (was priority 2, `SP-010`/`SP-011`) — closed in 5.1.17. An audit against HEAD found the original boundary question already resolved: `LibraryWriteTransaction` is confirmed as the sole, exclusive canonical write path for Inbox apply (measurement + sidecar staged together, moved together on commit); no production caller bypasses it. Remaining hardening gaps were closed in the same change: `LibraryWriteTransaction.rollback()` no longer silently swallows cleanup failures (`try?`) — it now returns a `RollbackFailure` describing any surviving destination/temp artifact, continues attempting the rest of the cleanup instead of stopping at the first failure, and `commit()` wraps an incomplete rollback in `CommitFailure` so the original error and the rollback outcome are both visible instead of one hiding the other; `InboxArchiveApplyService` logs and audits (`import_audit.log`) rollback-incomplete distinctly from a clean failure. Apply now fails closed (no overwrite, no delete) when a destination measurement file and its sidecar disagree on existence (`InboxArchiveApplyError.destinationArtifactMismatch`), instead of silently accepting an inconsistent pair as "already applied". Added regression coverage: real partial-commit-then-rollback and rollback-delete-failure via deterministic fault injection (`Tests/SpinLabAppTests/LibraryWriteTransactionRollbackTests.swift`), duplicate/re-apply, both asymmetric pre-existing-artifact cases, and failed-apply-then-successful-retry (`Tests/SpinLabAppTests/V230ApplyTests.swift`). Scope was deliberately not expanded: `LibraryWriteTransaction` still only owns the measurement+sidecar pair; index/registry refresh, the Inbox pending queue, and the audit log remain outside it, as before.

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
