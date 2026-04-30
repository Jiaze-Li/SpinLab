# Workbench Architecture — Dispatch Entry

> **Status**: 5.7.2 s3 首发。Workbench 功能区文档结构从「文档类型」维度切换到「功能区 × 层」维度，本目录包含 Workbench 所有层。
> **Source**: `docs/architecture/INDEX.md` 负责 region 级派发；本文件负责 Workbench region 内层级派发。

## Directory Layout

| File | Layer | Scope |
|---|---|---|
| `INDEX.md` | — | Dispatch entry (this file) |
| `SHELL_AND_LIFECYCLE.md` | Shell | WorkflowWorkspaceShell 协议、6 阶段 lifecycle、4 ViewBuilder 槽、3 条 [HARD] 不变式、WorkspaceStore contract |
| `MEASUREMENT_SEARCH.md` | Search | Sidecar 字段消费、condition projection、workflow ID alias、search 返回 file list 语义 |
| `PLOT_CANVAS.md` | Render | Workflow-independent plot shell、style params、legend dimension auto-inference、Copy PNG 倍率、point label、curve reorder opt-in |
| `WORKFLOW_CONTRACTS.md` | Workflow | 3-Omega AHE / AMR-PHE / XY Rotation 各自的 ingestion / pack / tag normalization / semantic identity |
| `ARTIFACT_PERSISTENCE.md` | Persistence | Pack save/load、`_spinlab/` 写入边界（Workbench owns generation；Library owns namespace 与 cleanup）、stale detection、Recompute UI 钩子 |
| `THREE_OMEGA_PHYSICS.md` | Domain | 3ω 物理推演（搬自 specs/three_omega_physics.md） |
| `EXTENSION_BOUNDARIES.md` | Extension | Adding-a-new-workflow 8 步清单、extension import rules、Domain / ExtensionPoints 依赖边界 |

## Reading Order

1. **SHELL_AND_LIFECYCLE.md** — shell-driven lifecycle and WorkspaceStore contract: how all workflows share one shell
2. **MEASUREMENT_SEARCH.md** — how measurements are searched and condition projections are built
3. **PLOT_CANVAS.md** — workflow-independent plot capabilities and opt-in extensions
4. **WORKFLOW_CONTRACTS.md** — each workflow's ingestion, pack, and tag normalization contracts
5. **ARTIFACT_PERSISTENCE.md** — how analysis results are saved to Library and how stale detection works
6. **THREE_OMEGA_PHYSICS.md** — 3ω physical model, Scaling Law, and RAHE derivation
7. **EXTENSION_BOUNDARIES.md** — how to add a new workflow and the module boundary rules

## First-Read Files

| Task area | Start here | Then inspect |
|---|---|---|
| Workbench state and condition projections | `App/State/WorkbenchFeatureStore.swift` | `Features/Workbench/WorkbenchView.swift`; `Features/Workbench/WorkflowRegistryView.swift` |
| Workflow shell / UI composition | `Features/Workbench/WorkflowWorkspaceShell.swift` | `Features/Workbench/WorkflowWorkspaceProvider.swift`; `Features/Workbench/WorkflowWorkspaceRegistry.swift` |
| 3-Omega workflow | `Features/Workbench/ThreeOmegaWorkspaceStore.swift` | `Features/Workbench/ThreeOmegaWorkspaceView.swift`; `UseCases/ThreeOmegaFitUseCase.swift`; `UseCases/ThreeOmegaPlotRenderer.swift` |
| XY Rotation workflow | `Features/Workbench/XYRotationWorkspaceStore.swift` | `Features/Workbench/XYRotationWorkspaceView.swift`; `UseCases/XYRotationDATParser.swift`; `UseCases/XYRotationPlotRenderer.swift` |
| AHE workflow | `Features/Workbench/AHEWorkspaceStore.swift` | `Features/Workbench/AHEWorkspaceView.swift`; `UseCases/AHEDataParser.swift`; `UseCases/AHEAxisDetector.swift` |
| Search measurements | `UseCases/SearchWorkflowMeasurementsUseCase.swift` | `Domain/WorkflowSearchModels.swift`; `Workflow/WorkflowID.swift`; `Library/SpinLabFileSidecar.swift` |
| Save chart / metrics to Library | `UseCases/SaveActiveChartToLibraryUseCase.swift` | `UseCases/PersistChartArtifactUseCase.swift`; `UseCases/PersistMeasurementDataUseCase.swift`; `Workbench/V3/WorkbenchResultContracts.swift` |

## Boundary Rules

| Shared point | Classification | Risk |
|---|---|---|
| Condition projection from Rules lives in Workbench store | `coordination_surface` (`SP-002`) | Verify rule reload path when editing condition definitions or Workbench condition options. |
| Workbench search reads Library sidecars and Import semantics | `coordination_surface` (`SP-009`) | Sample key semantics affect search, ingestion, and drawer matching together. |
| Workbench writes Library `_spinlab` artifacts/indexes | `coordination_surface` (`SP-007`) | Workbench owns generation; Library owns storage namespace and cleanup invariants. |
| `LibraryPathResolver` shared across Library and Workbench | `legitimate_cross_cutting` (`SP-008`) | Use it for root-relative paths. Avoid hand-built absolute/relative path logic. |
| Shared plot / workflow shells | shell candidates (`G-006`, `G-007`, `G-008`, `G-015`) | Do not extract more shell code without checking semantic equality across workflows. |

## Tests

Start with `V310WorkbenchFoundationTests.swift`, `V320WorkflowSearchAcrossDrawersTests.swift`, `V330WorkbenchShellContractTests.swift`, `V532WorkbenchRenderPipelineTests.swift`, `V4111SaveActiveChartToLibraryUseCaseTests.swift`, `V413ThreeOmegaFitUseCaseTests.swift`, `V321AHEIngestionAxisDetectionTests.swift`.

## Why Layer Names Differ from Inbox / Library

Inbox core verbs: parse/route/review/apply. Library core verbs: browse/select/edit/sync/preview. Workbench core verbs: **shell-driven lifecycle / workflow-independent plot capability / workflow-specific contract / cross-region artifact persistence**. Applying Inbox or Library layer names to Workbench would hide its distinct responsibilities: a shared shell that owns the full two-column layout, a render pipeline that works across all workflows, per-workflow ingestion and pack contracts, and a persistence layer that writes into Library-owned storage.

## Cross-Domain Boundaries

This directory describes Workbench-internal behavior only. Cross-domain contracts live in:

- `specs/01_PRODUCT_RULES.md` — PO promises (core workflow, workflow registration invariants)
- `specs/02_DATA_RULES.md` — Canonical domain entities (AnalysisPack, sidecar schema, measurement models)
- `specs/04_UI_RULES.md` — Design tokens (fonts, spacing, buttons, AppColumnShell) consumed by Workbench UI
- `docs/architecture/inbox/OUTPUT_CONTRACTS.md` — Sidecar schema canonical source of truth (Workbench search is read-only consumer)
- `docs/architecture/library/SIDECAR_AND_CONDITIONS.md` — Sidecar display in Library view (Workbench writes; Library reads and displays)
- `docs/architecture/library/ARTIFACTS_AND_PREVIEWS.md` — Library view of chart/metric artifacts and preview (Workbench writes generation; Library owns namespace and cleanup)
