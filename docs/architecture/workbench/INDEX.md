# Workbench Architecture — Dispatch Entry

> **Status**: 5.7.2 s3 首发。Workbench 功能区文档结构从「文档类型」维度切换到「功能区 × 层」维度，本目录包含 Workbench 所有层。
> **Source**: `docs/architecture/INDEX.md` 负责 region 级派发；本文件负责 Workbench region 内层级派发。

## Directory Layout

**Root** — global architecture / process / boundary / roadmap:

| File | Role | Scope |
|---|---|---|
| `INDEX.md` | — | Dispatch entry (this file) |
| `SHELL_BLOCKS.md` | Architecture definitions | Canonical model: Main Board + Layout Host + Modules + Workflow Assembly. Start here. |
| `EXTENSION_BOUNDARIES.md` | Extension / onboarding process | New-workflow checklist, intake classification, extension import boundaries |
| `MODULE_BOUNDARIES.md` | Module-wide rules and boundaries | Per-module ownership, forbidden mutations, transition state for test enforcement |
| `WORKBENCH_ROADMAP.md` | Phase tracking | Canonical Workbench shell migration phase status |

**`modules/`** — specialized docs for complex modules or module groups:

| File | Role | Scope |
|---|---|---|
| `modules/MEASUREMENT_SEARCH.md` | Search module details | Sidecar 字段消费、condition projection、workflow ID alias、search 返回 file list 语义 |
| `modules/PLOT_SYSTEM.md` | Plot System Module Group details | Workflow-independent plot shell、style params、legend、Copy PNG、point label、curve reorder contract |
| `modules/PACK_RESTORE.md` | Pack/Restore module details | AnalysisPack/AnalysisVault、workspace vs Library save、restore as cross-module op、per-workflow pack contracts |

Base module ownership rules, forbidden mutations, and transition state live in [`MODULE_BOUNDARIES.md`](MODULE_BOUNDARIES.md). Specialized docs cover complex module or module group details and supplement, not replace, `MODULE_BOUNDARIES.md`.

**`workflows/`** — workflow-specific references, physics notes, and implementation notes:

| File | Role | Scope |
|---|---|---|
| `workflows/three-omega/THREE_OMEGA_PHYSICS.md` | 3ω physics reference | 3ω 物理推演（搬自 specs/three_omega_physics.md） |

## Reading Order

1. **SHELL_BLOCKS.md** — canonical architecture model: Main Board, Layout Host, Modules, Workflow Assembly
2. **EXTENSION_BOUNDARIES.md** — onboarding checklist and intake classification/routing for new workflows
3. **MODULE_BOUNDARIES.md** — module ownership boundaries and forbidden mutations enforceable by tests
4. **WORKBENCH_ROADMAP.md** — canonical shell migration phase status and completion rules
5. **modules/MEASUREMENT_SEARCH.md** — search semantics, condition projection, workflow ID aliases
6. **modules/PLOT_SYSTEM.md** — plot capabilities, style, legend, series reorder contract
7. **modules/PACK_RESTORE.md** — pack/restore lifecycle, workspace persistence, per-workflow pack contracts
8. **workflows/three-omega/THREE_OMEGA_PHYSICS.md** — 3ω physical model, Scaling Law, RAHE derivation

## Architecture Usage Rules

Before any non-trivial change, classify the task, record a routing note, and consult the relevant docs above. After implementation, report compliance briefly. If a planned change conflicts with `SHELL_BLOCKS.md` or `MODULE_BOUNDARIES.md`, stop and report before implementing.

Full rules (routing note format, task routing table, compliance checklist, documentation sync table, deviation rule): [`EXTENSION_BOUNDARIES.md` § Architecture Usage Rules](EXTENSION_BOUNDARIES.md#architecture-usage-rules).

## First-Read Files

| Task area | Start here | Then inspect |
|---|---|---|
| Workbench state and condition projections | `App/State/WorkbenchFeatureStore.swift` | `Features/Workbench/WorkbenchView.swift`; `Features/Workbench/WorkflowRegistryView.swift` |
| Workflow shell / UI composition | `Features/Workbench/WorkflowWorkspaceShell.swift` | `Features/Workbench/WorkflowWorkspaceProvider.swift`; `Features/Workbench/WorkflowWorkspaceRegistry.swift` |
| Result header shell | `Features/Workbench/WorkbenchResultHeaderShell.swift` | `Features/Workbench/WorkbenchReadAdapter.swift`; `Features/Workbench/WorkflowWorkspaceShell.swift` |
| 3-Omega workflow | `Features/Workbench/ThreeOmegaWorkspaceStore.swift` | `Features/Workbench/ThreeOmegaWorkspaceView.swift`; `UseCases/ThreeOmegaFitUseCase.swift`; `UseCases/ThreeOmegaPlotRenderer.swift` |
| XY Rotation workflow | `Features/Workbench/XYRotationWorkspaceStore.swift` | `Features/Workbench/XYRotationWorkspaceView.swift`; `UseCases/XYRotationDATParser.swift`; `UseCases/XYRotationPlotRenderer.swift` |
| AHE workflow | `Features/Workbench/AHEWorkspaceStore.swift` | `Features/Workbench/AHEWorkspaceView.swift`; `UseCases/AHEDataParser.swift`; `UseCases/AHEAxisDetector.swift` |
| Search measurements | `UseCases/SearchWorkflowMeasurementsUseCase.swift` | `Domain/WorkflowSearchModels.swift`; `Workflow/WorkflowID.swift`; `Library/SpinLabFileSidecar.swift` |
| Save chart / metrics to Library | `UseCases/SaveActiveChartToLibraryUseCase.swift` | `UseCases/PersistChartArtifactUseCase.swift`; `UseCases/PersistMeasurementDataUseCase.swift`; `Workbench/V3/WorkbenchResultContracts.swift` |
| Pack save / restore | `App/State/AnalysisVault.swift` | `Domain/AnalysisPack.swift`; `Workbench/V3/AnalysisPackProviding.swift`; `UseCases/RestoreAnalysisPackUseCase.swift` — see `modules/PACK_RESTORE.md` |

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

Inbox core verbs: parse/route/review/apply. Library core verbs: browse/select/edit/sync/preview. Workbench core verbs: **Main Board lifecycle / workflow-independent plot capability / workflow-specific contract / cross-region artifact persistence**. Applying Inbox or Library layer names to Workbench would hide its distinct responsibilities: a shared shell that owns the full two-column layout, a render pipeline that works across all workflows, per-workflow ingestion and pack contracts, and a persistence layer that writes into Library-owned storage.

## Cross-Domain Boundaries

This directory describes Workbench-internal behavior only. Cross-domain contracts live in:

- `specs/01_PRODUCT_RULES.md` — PO promises (core workflow, workflow registration invariants)
- `specs/02_DATA_RULES.md` — Canonical domain entities (AnalysisPack, sidecar schema, measurement models)
- `specs/04_UI_RULES.md` — Design tokens (fonts, spacing, buttons, AppColumnShell) consumed by Workbench UI
- `docs/architecture/inbox/OUTPUT_CONTRACTS.md` — Sidecar schema canonical source of truth (Workbench search is read-only consumer)
- `docs/architecture/library/SIDECAR_AND_CONDITIONS.md` — Sidecar display in Library view (Workbench writes; Library reads and displays)
- `docs/architecture/library/ARTIFACTS_AND_PREVIEWS.md` — Library view of chart/metric artifacts and preview (Workbench writes generation; Library owns namespace and cleanup)
- `docs/architecture/workbench/SHELL_BLOCKS.md` — Main Board / Layout Host / Module / Module Group / Workflow Assembly architecture model for Workbench
- `docs/architecture/workbench/WORKBENCH_ROADMAP.md` — Canonical phase progress for Workbench shell migration
