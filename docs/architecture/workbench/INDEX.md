# Workbench Architecture - Dispatch Entry

> Status: workbench docs aligned to the final model. The stable model is Workflow -> Workflow Assembly -> Main Board -> Modules. `SHELL_BLOCKS.md` is the first-read overview.
> Source: `docs/architecture/INDEX.md` handles region-level dispatch; this file handles Workbench region dispatch.

## Directory Layout

**Root** - overview, authority, process, and status:

| File | Role | Scope |
|---|---|---|
| `INDEX.md` | Dispatch entry | Start here for routing |
| `SHELL_BLOCKS.md` | Overview | First-read conceptual model |
| `MAIN_BOARD_READINESS.md` | Readiness contract | Derived readiness ladder and consumers |
| `WORKFLOW_ASSEMBLY.md` | Workflow contract | Per-workflow integration contract |
| `MODULE_BOUNDARIES.md` | Ownership authority | Module ownership, read surfaces, forbidden mutations |
| `EXTENSION_BOUNDARIES.md` | Extension guide | Add-workflow and add-module routing/checklists |
| `WORKBENCH_ROADMAP.md` | Phase tracking | Current Workbench shell migration status |

**Implementation placement notes** - naming used by the live shell implementation, not formal architecture layers:

| File | Role | Scope |
|---|---|---|
| `MAIN_BOARD_LAYOUT.md` | Placement notes | Current shell placement names and mount points |

**`modules/`** - specialized docs for complex modules or module groups:

| File | Role | Scope |
|---|---|---|
| `modules/MEASUREMENT_SEARCH.md` | Search module details | Sidecar field consumption, condition projection, workflow ID aliases, search result semantics |
| `modules/SELECTION_DENOMINATOR_AUDIT.md` | Selection denominator audit | `isAllSelected` / `selectAll` ownership split and migration decision |
| `modules/PLOT_SYSTEM.md` | Plot system details | Workflow-independent plot shell, style params, legend, copy PNG, point label, curve reorder contract |
| `modules/PACK_RESTORE.md` | Pack / restore details | AnalysisPack / AnalysisVault, workspace vs Library save, restore as cross-module op, per-workflow pack contracts |

Base module ownership rules, forbidden mutations, and transition state live in [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md). Specialized docs cover complex module or module group details and supplement, not replace, `MODULE_BOUNDARIES.md`.

**`workflows/`** - workflow-specific references, physics notes, and implementation notes:

| File | Role | Scope |
|---|---|---|
| `workflows/*/ASSEMBLY.md` | Workflow assembly record | Specific workflow assembly specification and audit target |
| `workflows/three-omega/THREE_OMEGA_PHYSICS.md` | 3-Omega physics reference | 3-Omega physical model and derivation notes |

## Reading Order

1. [SHELL_BLOCKS.md](SHELL_BLOCKS.md) - first-read overview of the stable architecture model
2. [MAIN_BOARD_READINESS.md](MAIN_BOARD_READINESS.md) - readiness and gating projection
3. [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md) - per-workflow integration contract
4. [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md) - module ownership boundaries and forbidden mutations
5. [EXTENSION_BOUNDARIES.md](EXTENSION_BOUNDARIES.md) - workflow/module extension rules and checklists
6. [WORKBENCH_ROADMAP.md](WORKBENCH_ROADMAP.md) - gate status and completion notes
7. [MAIN_BOARD_LAYOUT.md](MAIN_BOARD_LAYOUT.md) - implementation-level placement notes only
8. [modules/MEASUREMENT_SEARCH.md](modules/MEASUREMENT_SEARCH.md) - search semantics and condition projection
9. [modules/SELECTION_DENOMINATOR_AUDIT.md](modules/SELECTION_DENOMINATOR_AUDIT.md) - selection denominator ownership
10. [modules/PLOT_SYSTEM.md](modules/PLOT_SYSTEM.md) - plot capabilities and shared plot shell details
11. [modules/PACK_RESTORE.md](modules/PACK_RESTORE.md) - pack / restore lifecycle and write boundaries
12. [workflows/three-omega/THREE_OMEGA_PHYSICS.md](workflows/three-omega/THREE_OMEGA_PHYSICS.md) - 3-Omega physical model

## Dispatch Rules

- If changing readiness, gating, or preflight behavior, read [MAIN_BOARD_READINESS.md](MAIN_BOARD_READINESS.md).
- If changing workflow assembly or registration, read [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md). Specific workflow assembly records live at `workflows/*/ASSEMBLY.md`.
- If changing module ownership, read [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md).
- If adding a workflow, read [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md) and [EXTENSION_BOUNDARIES.md](EXTENSION_BOUNDARIES.md).
- If checking gate status, read [WORKBENCH_ROADMAP.md](WORKBENCH_ROADMAP.md).
- If changing implementation placement details, read [MAIN_BOARD_LAYOUT.md](MAIN_BOARD_LAYOUT.md).

## Architecture Usage Rules

Before any non-trivial change, classify the task, record a routing note, and consult the relevant docs above. After implementation, report compliance briefly. If a planned change conflicts with `MAIN_BOARD_READINESS.md`, `WORKFLOW_ASSEMBLY.md`, or `MODULE_BOUNDARIES.md`, stop and report before implementing.

Full rules (routing note format, task routing table, compliance checklist, documentation sync table, deviation rule): [EXTENSION_BOUNDARIES.md](EXTENSION_BOUNDARIES.md#architecture-usage-rules).

## First-Read Files

| Task area | Start here | Then inspect |
|---|---|---|
| Workbench readiness or shell gating | `MAIN_BOARD_READINESS.md` | `Features/Workbench/WorkbenchView.swift`; `Features/Workbench/WorkbenchResultHeaderShell.swift` |
| Layout placement details | `MAIN_BOARD_LAYOUT.md` | `Features/Workbench/WorkflowWorkspaceShell.swift`; `Features/Workbench/WorkflowWorkspaceProvider.swift` |
| Workflow assembly / registration | `WORKFLOW_ASSEMBLY.md` | `Workflow/WorkflowID.swift`; `Workflow/WorkflowDefinition.swift`; `Workflow/WorkflowRegistry.swift`; `workflows/*/ASSEMBLY.md` |
| Module ownership or forbidden mutations | `MODULE_BOUNDARIES.md` | `Features/Workbench/WorkflowWorkspaceShell.swift`; relevant workflow store |
| Search measurements | `UseCases/SearchWorkflowMeasurementsUseCase.swift` | `Domain/WorkflowSearchModels.swift`; `Workflow/WorkflowID.swift`; `Library/SpinLabFileSidecar.swift` |
| Save chart / metrics to Library | `UseCases/SaveActiveChartToLibraryUseCase.swift` | `UseCases/PersistChartArtifactUseCase.swift`; `UseCases/PersistMeasurementDataUseCase.swift`; `Workbench/V3/WorkbenchResultContracts.swift` |
| Pack save / restore | `App/State/AnalysisVault.swift` | `Domain/AnalysisPack.swift`; `Workbench/V3/AnalysisPackProviding.swift`; `UseCases/RestoreAnalysisPackUseCase.swift` |

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

## Why Workbench Uses Its Own Terms

Inbox core verbs: parse/route/review/apply. Library core verbs: browse/select/edit/sync/preview. Workbench core verbs are Main Board lifecycle, workflow-independent plot capability, workflow-specific contract, and cross-region artifact persistence. Applying Inbox or Library layer names to Workbench would hide its distinct responsibilities: Main Board orchestration across all workflows, implementation-level layout placement inside the shell, a render pipeline that works across all workflows, per-workflow ingestion and pack contracts, and a persistence layer that writes into Library-owned storage.

## Cross-Domain Boundaries

This directory describes Workbench-internal behavior only. Cross-domain contracts live in:

- `specs/01_PRODUCT_RULES.md` - PO promises (core workflow, workflow registration invariants)
- `specs/02_DATA_RULES.md` - canonical domain entities (AnalysisPack, sidecar schema, measurement models)
- `specs/04_UI_RULES.md` - design tokens (fonts, spacing, buttons, AppColumnShell) consumed by Workbench UI
- `docs/architecture/inbox/OUTPUT_CONTRACTS.md` - sidecar schema canonical source of truth
- `docs/architecture/library/SIDECAR_AND_CONDITIONS.md` - sidecar display in Library view
- `docs/architecture/library/ARTIFACTS_AND_PREVIEWS.md` - Library view of chart/metric artifacts and preview
- `docs/architecture/workbench/SHELL_BLOCKS.md` - overview of the Workflow / Workflow Assembly / Main Board / Modules model
- `docs/architecture/workbench/MAIN_BOARD_LAYOUT.md` - implementation-level placement notes only
- `docs/architecture/workbench/WORKBENCH_ROADMAP.md` - phase progress for Workbench shell migration
