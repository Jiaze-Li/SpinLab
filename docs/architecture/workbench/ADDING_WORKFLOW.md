# Adding a New Workflow — Checklist

> Start here before writing any code. Read [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md) for the contract model, then [EXTENSION_BOUNDARIES.md](EXTENSION_BOUNDARIES.md) for the full implementation checklist.

---

## The Model in One Sentence

The **Workflow Assembly** is the workflow's contract: it declares what this workflow contributes. Common modules own every shared mechanism. Adding a workflow means adding a new Assembly and wiring it into a fixed set of registration surfaces — nothing in the common architecture changes.

---

## What Each Side Owns

### Common modules own mechanism

The shell, search, plot, pack/restore, and save modules are workflow-independent. They implement the mechanism once and apply it uniformly across all workflows. They must not be changed to accommodate a new workflow.

| Common shell / module | What it owns |
|---|---|
| Main Board shell (`WorkflowWorkspaceShell`) | Two-column layout, readiness gating, Analysis Lifecycle, module mounting |
| Search module | File search, sidecar query, result list, selection state |
| Plot shell | Canvas, legend, copy-PNG, point labels, tab switching, style params |
| Pack / restore shell | AnalysisPack identity, vault write/read, workspace snapshot lifecycle |
| Save / export shell | Chart artifact write, metric persistence, Library artifact path |

### Workflow Assembly owns content

The Assembly is the workflow's declaration of what it contributes to each shell. It does not redeclare any mechanism the shell already provides.

| Assembly field | What the workflow declares |
|---|---|
| Workflow Identity / Search Hints | Stable workflow ID, search aliases, optional secondary input slots |
| Input Adapter Contract | File formats accepted, parser entry point, column/index mapping, unit conversion, adapter output type |
| Data / Physics Mapping | Domain dataset fields, derived quantities, invalid-data behavior |
| Analysis Pipeline | Fit, scale, render-payload, metric, warning, and failure stages |
| Plot Semantics / Overrides | Default axes, units, tabs, stacking, normalization, annotations, metrics, legends that differ from the shell default |
| Optional Contributions | Workflow-specific panels or content slots mounted by the shell |
| Persistence / Pack-Restore | Workflow-specific `PackConfig` (UI state) and `PackResult` (must include `ingestionResult`) |
| Validation / Warning Policy | Warnings for missing input, skipped series, ambiguous units, data-quality failures |
| Required Behavior Tests | Regression suites that protect the workflow contract |

---

## Do Not Change Common Workbench Architecture for a New Workflow

Adding a workflow is a content addition, not an architecture change. The following must not change when adding a workflow:

- Main Board shell layout or readiness logic
- Common search module behavior or result model
- Common plot shell geometry, legend mechanics, or copy-PNG behavior
- Pack / restore shell schema or vault write path
- Save / export shell artifact path logic or metric persistence structure
- Any module boundary in [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md)

If the new workflow seems to require a change to common architecture, stop and classify the request using the Intake Pipeline in [EXTENSION_BOUNDARIES.md](EXTENSION_BOUNDARIES.md). The change belongs either in the workflow's Assembly (workflow-owned content) or in a separate architecture Gate (new module or shell extension). Do not merge workflow content into shared mechanism.

---

## Registration Surfaces

Adding a workflow requires touching exactly these surfaces. Each surface serves a distinct purpose; none is optional.

| Surface | What it registers | File |
|---|---|---|
| Workflow identity enum | Stable ID and alias normalization | `Domain/Workflow/WorkflowID.swift` |
| Workflow definition | Display name, condition-field definitions | `Workflow/WorkflowDefinitionStore.swift` + `config/workflow.json` |
| Workspace registry | Maps workflow ID to the concrete workspace view | `Features/Workbench/WorkflowWorkspaceRegistry.swift` |
| Feature store search dispatch | Adds workflow-ID case to measurement search routing | `Features/Workbench/WorkbenchFeatureStore.swift` |
| Feature store workspace store | Registers the workflow's workspace store | `Features/Workbench/WorkbenchFeatureStore.swift` |

These are five distinct files. There is no plugin or single-file registration mechanism — each surface is explicit.

---

## Implementation Checklist (Abbreviated)

Full checklist with file-placement table: [EXTENSION_BOUNDARIES.md §Adding a New Workflow](EXTENSION_BOUNDARIES.md).

1. **Write the Assembly first.** Create `docs/architecture/workbench/workflows/<name>/ASSEMBLY.md` before any code. Declare the Input Adapter Contract (adapter output type must be named before the parser file exists).
2. Register the workflow ID (`WorkflowID.swift`).
3. Create ingestion contracts (`<Name>IngestionContracts.swift`).
4. Create ingestion use case (`Ingest<Name>SelectionsUseCase.swift`).
5. Create pack contracts (`<Name>PackContracts.swift` — `PackConfig` + `PackResult` including `ingestionResult`).
6. Create workspace store (`<Name>WorkspaceStore.swift`) conforming to `WorkbenchWorkspaceProviding`.
7. Create workspace view (`<Name>WorkspaceView.swift`) wrapping `WorkflowWorkspaceShell`.
8. Register view in `WorkflowWorkspaceRegistry` and store + search dispatch in `WorkbenchFeatureStore`.
9. Add required behavior tests declared in the Assembly.
10. Run `./scripts/check_required_actions.sh` — must be clean before commit.

---

## Cross-Links

- [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md) — contract model and field definitions
- [EXTENSION_BOUNDARIES.md](EXTENSION_BOUNDARIES.md) — full implementation checklist, intake pipeline, code placement table
- [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md) — common module ownership and forbidden mutations
- `workflows/*/ASSEMBLY.md` — per-workflow Assembly records (AHE, 3ω, XY-Rotation)
