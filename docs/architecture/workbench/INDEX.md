# Workbench Architecture - Dispatch Entry

> Status: workbench docs aligned to the final model. The stable model is Workflow -> Workflow Assembly -> Main Board -> Modules. `SHELL_BLOCKS.md` is the first-read overview.
> Source: `docs/architecture/INDEX.md` handles region-level dispatch; this file handles Workbench region dispatch.

## Directory Layout

### Current Core Contracts

Active architecture contracts that must be read before making non-trivial changes.

| File | Role | Scope |
|---|---|---|
| `INDEX.md` | Dispatch entry | Start here for routing |
| `SHELL_BLOCKS.md` | Overview | First-read conceptual model |
| `MAIN_BOARD_READINESS.md` | Readiness contract | Derived readiness ladder and consumers |
| `WORKFLOW_ASSEMBLY.md` | Workflow contract | Per-workflow integration contract |
| `MODULE_BOUNDARIES.md` | Ownership authority | Module ownership, read surfaces, forbidden mutations |
| `ADDING_WORKFLOW.md` | Add-workflow entry | One-sentence model, do-not-change warning, five registration surfaces; links to WORKFLOW_EXTENSION.md for full checklist |
| `WORKFLOW_EXTENSION.md` | Workflow extension contract | Canonical workflow extension contract: implementation checklist, code placement, Plot System responsibilities, persistence rules, finalization rule |
| `STATE_OWNERSHIP.md` | Ownership contract | Shared plot defaults, per-tab state, packs, sidecar, and measurement set ownership |

Base module ownership rules, forbidden mutations, and transition state live in [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md). Specialized module docs supplement, not replace, `MODULE_BOUNDARIES.md`.

### Current Module Contracts

Active per-module contracts that supplement `MODULE_BOUNDARIES.md`.

| File | Role | Scope |
|---|---|---|
| `modules/MEASUREMENT_SEARCH.md` | Search module details | Sidecar field consumption, condition projection, workflow ID aliases, search result semantics |
| `modules/PLOT_SYSTEM.md` | Plot system details | Workflow-independent plot shell, style params, legend, copy PNG, point label, curve reorder contract |
| `modules/PACK_RESTORE.md` | Pack / restore details | AnalysisPack / AnalysisVault, workspace vs Library save, restore as cross-module op, per-workflow pack contracts |

### Current References

Up-to-date reference documents that are not full architecture contracts.

| File | Role | Scope |
|---|---|---|
| `WORKBENCH_ROADMAP.md` | Phase tracking | Current Workbench shell migration status and gate outcomes |
| `MAIN_BOARD_LAYOUT.md` | Placement notes | Current shell injection points and placement names |
| `PHYSICAL_MODULE_LAYOUT.md` | Physical layout plan | Target Swift file layout for Main Board / Modules / Workflows and the move-only migration gates |

### Workflow Records

Per-workflow assembly specs and physics references.

| File | Role | Scope |
|---|---|---|
| `workflows/ahe/ASSEMBLY.md` | AHE workflow record | AMR/PHE assembly specification |
| `workflows/iv/ASSEMBLY.md` | IV workflow record | IV assembly specification (Gate 8.1 dry-run workflow) |
| `workflows/three-omega/ASSEMBLY.md` | 3ω workflow record | 3-Omega assembly specification |
| `workflows/xy-rotation/ASSEMBLY.md` | XY workflow record | XY Rotation assembly specification |
| `workflows/three-omega/THREE_OMEGA_PHYSICS.md` | 3-Omega physics reference | 3-Omega physical model and derivation notes |
| `workflows/rsm/DRAFT_ASSEMBLY.md` | RSM future workflow draft | RSM adapter rules and CanonicalRSMDataset contract target (not yet implemented) |

### Historical / Audit Records

Completed gate audits and closeout records. Do not update these; they are read-only records of past work.

| File | Role | Scope |
|---|---|---|
| `history/gate7/GATE7_WORKBENCH_ARCHITECTURE_CLOSEOUT.md` | Gate 7.9 closeout | Final module map, Gates 7.1–7.8 outcomes, accepted bridges, deferred cleanup, non-candidates, and closeout rule |
| `history/gate7/GATE7_MAIN_SEARCH_HANDOFF.md` | Gate 7 preflight audit | Main Search extraction readiness, bridge inventory, and forbidden changes |
| `history/gate7/GATE7_PACK_RESTORE_AUDIT.md` | Gate 7.6 pack/restore audit | Schema, restore ownership, RT path, overlay, save interaction, test gaps |
| `history/gate7/SELECTION_DENOMINATOR_AUDIT.md` | Selection denominator audit | `isAllSelected` / `selectAll` ownership split and migration decision |
| `history/gate7/SEARCH_READ_SURFACE_AUDIT.md` | Search read surface audit | Phase 5A-3 audit of `cachedSearchResults` mirror usage |
| `history/gate6/READINESS_CONSUMPTION_AUDIT.md` | Gate 6 audit | Readiness consumption audit and closeout linkage |
| `history/gate4/LAYOUT_AUDIT.md` | Gate 4 audit / Gate 5 prep | Shell layout map, layout debts, and Gate 5-safe refactor targets |

### Superseded Stubs

Docs that have been replaced by a canonical successor. Kept for historical reference only.

| File | Status | Replaced by |
|---|---|---|
| `EXTENSION_BOUNDARIES.md` | Superseded stub | Workflow extension checklist moved to `WORKFLOW_EXTENSION.md`; module ownership rules moved to `MODULE_BOUNDARIES.md`; legacy extension-module import rules retained here |

## Reading Order

Covers current contracts and references only. For historical audit records, see Historical / Audit Records above.

1. [SHELL_BLOCKS.md](SHELL_BLOCKS.md) - first-read overview of the stable architecture model
2. [MAIN_BOARD_READINESS.md](MAIN_BOARD_READINESS.md) - readiness and gating projection
3. [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md) - per-workflow integration contract
4. [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md) - module ownership boundaries and forbidden mutations
5. [WORKFLOW_EXTENSION.md](WORKFLOW_EXTENSION.md) - canonical workflow extension contract: implementation checklist, code placement, and rules
6. [WORKBENCH_ROADMAP.md](WORKBENCH_ROADMAP.md) - gate status and completion notes
7. [MAIN_BOARD_LAYOUT.md](MAIN_BOARD_LAYOUT.md) - implementation-level placement notes only
8. [PHYSICAL_MODULE_LAYOUT.md](PHYSICAL_MODULE_LAYOUT.md) - target physical layout and move-only migration gates
9. [modules/MEASUREMENT_SEARCH.md](modules/MEASUREMENT_SEARCH.md) - search semantics and condition projection
10. [modules/PLOT_SYSTEM.md](modules/PLOT_SYSTEM.md) - plot capabilities and shared plot shell details
11. [modules/PACK_RESTORE.md](modules/PACK_RESTORE.md) - pack / restore lifecycle and write boundaries
12. [STATE_OWNERSHIP.md](STATE_OWNERSHIP.md) - state ownership contract for plot defaults, tabs, packs, sidecars, and measurement sets

## Dispatch Rules

- If changing readiness, gating, or preflight behavior, read [MAIN_BOARD_READINESS.md](MAIN_BOARD_READINESS.md).
- If reviewing the Gate 6 readiness closeout history, see `history/gate6/READINESS_CONSUMPTION_AUDIT.md` (historical audit record).
- If changing workflow assembly or registration, read [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md). Specific workflow assembly records live at `workflows/*/ASSEMBLY.md`.
- If changing module ownership, read [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md).
- If changing physical Swift file layout, start with [PHYSICAL_MODULE_LAYOUT.md](PHYSICAL_MODULE_LAYOUT.md) and keep the commit move-only unless a separate architecture gate authorizes behavior changes.
- If adding a workflow, start with [ADDING_WORKFLOW.md](ADDING_WORKFLOW.md), then [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md) and [WORKFLOW_EXTENSION.md](WORKFLOW_EXTENSION.md).
- If checking gate status, read [WORKBENCH_ROADMAP.md](WORKBENCH_ROADMAP.md).
- If changing implementation injection points or placement details, read [MAIN_BOARD_LAYOUT.md](MAIN_BOARD_LAYOUT.md). For historical Gate 4/5 layout audit, see `history/gate4/LAYOUT_AUDIT.md`.

## Architecture Usage Rules

Before any non-trivial change, classify the task, record a routing note, and consult the relevant docs above. After implementation, report compliance briefly. If a planned change conflicts with `MAIN_BOARD_READINESS.md`, `WORKFLOW_ASSEMBLY.md`, or `MODULE_BOUNDARIES.md`, stop and report before implementing.

Full rules (routing note format, task routing table, compliance checklist, documentation sync table, deviation rule): see the Architecture Usage Rules section in any workflow doc; the canonical task routing table now lives inline in [WORKFLOW_EXTENSION.md](WORKFLOW_EXTENSION.md).

## First-Read Files

| Task area | Start here | Then inspect |
|---|---|---|
| Workbench readiness or shell gating | `MAIN_BOARD_READINESS.md` | `Features/Workbench/WorkbenchView.swift`; `Features/Workbench/WorkbenchResultHeaderShell.swift` |
| Layout placement details | `MAIN_BOARD_LAYOUT.md` | `Features/Workbench/WorkflowWorkspaceShell.swift`; `Features/Workbench/WorkflowWorkspaceProvider.swift` |
| Physical file layout / move-only refactor | `PHYSICAL_MODULE_LAYOUT.md` | `MODULE_BOUNDARIES.md`; relevant module doc; current source path before moving |
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
- `docs/architecture/workbench/MAIN_BOARD_LAYOUT.md` - implementation-level injection points only
- `docs/architecture/workbench/WORKBENCH_ROADMAP.md` - phase progress for Workbench shell migration
- `docs/architecture/workbench/history/gate4/LAYOUT_AUDIT.md` - historical: Gate 4 layout audit and Gate 5 preparation
