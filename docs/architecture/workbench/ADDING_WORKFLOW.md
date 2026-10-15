# Adding a New Workflow — Checklist

> Start here before writing any code. Read [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md) for the contract model, then [WORKFLOW_EXTENSION.md](WORKFLOW_EXTENSION.md) for the full implementation checklist.

---

## The Model in One Sentence

The **Workflow Assembly** is the workflow's contract: it declares what this workflow contributes. Common modules own every shared mechanism. Adding a workflow means adding a new Assembly and wiring it into a fixed set of registration surfaces — nothing in the common architecture changes.

---

## Do Not Change Common Workbench Architecture for a New Workflow

Adding a workflow is a content addition, not an architecture change. The following must not change when adding a workflow:

- Main Board shell layout or readiness logic
- Common search module behavior or result model
- Common plot shell geometry, legend mechanics, or copy-PNG behavior
- Pack / restore shell schema or vault write path
- Save / export shell artifact path logic or metric persistence structure
- Any module boundary in [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md)

If the new workflow seems to require a change to common architecture, stop and classify the request using the Dispatch Rules in the Workbench [INDEX.md](INDEX.md). The change belongs either in the workflow's Assembly (workflow-owned content) or in a separate architecture Gate (new module or shell extension). Do not merge workflow content into shared mechanism.

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

## Implementation Checklist

Full checklist with file-placement table and persistence rules: [WORKFLOW_EXTENSION.md](WORKFLOW_EXTENSION.md).

---

## Controls

> **Controls layout, composition and ownership** (Common / Plot / Workflow Specific, responsive rules, extension rules) are defined solely in [`specs/06_WORKBENCH_CONTROLS_UI.md`](../../../specs/06_WORKBENCH_CONTROLS_UI.md). This document does not restate them; where it disagrees, that spec wins.

Normal flow: declare Plot Mode → provide the workflow adapter → provide Specific controls → Common/Plot are assembled by `WorkbenchControlsSurface` → pass the Controls Contract tests and `scripts/check_controls_contract.sh`.

1. Add the case to `WorkbenchWorkflowKind`; the compiler then requires `controlsPlotModes` (a non-empty set of `WorkbenchPlotMode`) and a `controlsDescriptor` adapter in `WorkbenchControlsRegistry.swift`; there is no legacy mount and no allow-list.
2. In the workflow's `…WorkspaceView`, mount with `WorkflowWorkspaceLeftColumn(…, controls: store.controlsDescriptor(…), …)`. Cartesian XY workflows reuse `standardControlsDescriptor` (`WorkbenchStandardControlsAdapter.swift`) and Heatmap workflows `heatmapControlsDescriptor` (`WorkbenchHeatmapControlsAdapter.swift`), adding only their Specific content; the closures carry the workflow's re-render and snapshot-flush policy.
3. Put workflow-only inputs into `WorkbenchSpecificContent` (groups → rows → typed inputs, or a `WorkbenchLeafInput` view). Do not place containers or measure width.
4. A new Plot Mode needs its own shared Plot component and contract tests first (spec CS-14).

---

## Cross-Links

- [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md) — contract model and field definitions
- [WORKFLOW_EXTENSION.md](WORKFLOW_EXTENSION.md) — full implementation checklist, code placement table, persistence rules
- [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md) — common module ownership and forbidden mutations
- `workflows/*/ASSEMBLY.md` — per-workflow Assembly records (AHE, 3ω, XY-Rotation)
