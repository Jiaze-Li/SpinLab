# Workflow Extension Protocol

> This document formalizes the workflow extension lifecycle discovered through the RSM/Heatmap implementation. It is a reference for engineers adding or extending Workbench workflows. The protocol is **conditional** — not every workflow needs every phase.

See also: [WORKFLOW_ASSEMBLY.md](WORKFLOW_ASSEMBLY.md), [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md), [RSM first completed validation](workflows/rsm/DRAFT_ASSEMBLY.md).

---

## Ownership Axioms

These axioms govern every phase below. When in doubt, resolve ambiguity against them.

| Stakeholder | Owns |
|---|---|
| **Workflow Assembly** | Workflow-specific semantic contract: data interpretation, physics/analysis logic, plot semantics, metric definitions, unit conversions, workflow-specific warnings, and workflow-specific persistence semantics. |
| **Modules** | Reusable Workbench capabilities mounted and called by the Main Board. A module owns its own canonical state; it does not own workflow physics meaning. |
| **Main Board** | Mounts and coordinates modules and Workflow Assemblies. Stays generic. Does not parse raw files, does not own workflow physics, does not own module internals. |

### Reusable Capability Rule

**New reusable capability must not be hidden inside the first workflow that needs it.**

If a phase produces something a second workflow could use — a render pipeline, a save path, a slot mechanism — it must be designed as a module boundary from the start. The first workflow is a validation case, not an owner.

---

## Phase 0: Capability Classification

**Goal**: determine which capabilities the new workflow requires and which already exist.

Before writing any code, answer:

1. Does this workflow use an existing render path (Cartesian XY) or require a new one (e.g. heatmap)?
2. Does it require a new save path or can it reuse an existing one?
3. Does it require auxiliary file slots beyond the primary search?
4. Does any capability it needs not yet exist as a module?

**Output**: a capability map that declares which capabilities are new (require module design), which are reused, and which are Assembly-only.

**Invariant**: if a new shared capability is identified here, design its module boundary before implementing the workflow. Do not defer the boundary.

---

## Phase 1: Module Readiness

**Goal**: ensure every module the workflow depends on is ready to accept it.

For each module the workflow will use:

- If the module exists: confirm its read surface, state ownership, and pack/restore contract are documented in [MODULE_BOUNDARIES.md](MODULE_BOUNDARIES.md).
- If the module does not yet exist: design and document the module boundary in MODULE_BOUNDARIES.md before any workflow code is written.

**Output**: MODULE_BOUNDARIES.md updated with any new module sections; existing sections confirmed sufficient.

**Invariant**: Modules own reusable mechanisms. If implementation produces something reusable, it must be extracted to a module and documented before the workflow ships.

---

## Phase 2: Workflow Assembly

**Goal**: define the workflow's semantic contract.

Before any Swift changes, the workflow's Assembly record must declare:

- Workflow identity / search hints
- Input Adapter Contract (accepted file formats, parser entry point, column/index mapping, unit conversion, sidecar condition injection, adapter output type, warning policy) — see [WORKFLOW_ASSEMBLY.md § Input Adapter Contract](WORKFLOW_ASSEMBLY.md#input-adapter-contract)
- Analysis pipeline (parse → ingest → transform/fit/scale → render payload → metric)
- Plot semantics / overrides
- Validation / warning policy
- Persistence / pack-restore plan (even if deferred)
- Required behavior tests

**Output**: `workflows/<id>/ASSEMBLY.md` (or `DRAFT_ASSEMBLY.md`) with a complete or in-progress record covering the fields above.

**Invariant**: The Assembly record is a prerequisite to code, not a deliverable after code. The adapter output type must be named before the parser file exists.

---

## Phase 3: Main Board Wiring

**Goal**: mount the workflow in the Main Board shell so the workflow is reachable.

Typical deliverables:
- Registry dispatch entry for the new workflow
- Workspace view (shell composition with workflow-specific panels)
- Workspace store stub (conforms to required protocols, no analysis yet)

**Invariant**: Main Board wiring does not belong to any Workflow Assembly or module. Wiring code must stay in shell/registry files. No physics logic enters the shell.

---

## Phase 4: Minimal Pipeline

**Goal**: end-to-end data flow from file selection to a rendered output.

Deliverables:
- Input Adapter implementation producing the typed domain dataset
- Analysis/render pipeline from domain dataset to plot payload
- Render pipeline integration (existing module or new — per Phase 1)

For a workflow using an existing render path: integrate with the module's existing protocol surface. For a workflow requiring a new render path: the render pipeline is a module owned by Plot System, not by the workflow.

**Invariant**: Assembly-owned layers (parse → domain dataset → plot payload) are strictly separated from Plot System-owned layers (plot payload → rendered output). Workflow code must not implement colormap, colorbar, or canvas geometry.

---

## Phase 5: Pack / Restore

**Goal**: workspace state round-trips through save and restore without data loss or silent corruption.

Deliverables:
- Workflow-owned pack state model (source file identity, workflow-specific parameters, active view or equivalent)
- Plot System-owned display state codec (display overrides, not scientific semantics)
- Restore sequence verified by integration tests
- Forbidden persisted state documented (rendered pixels, layout objects, derived state that can be re-derived)

**Invariant**: restore re-derives rendered output from re-parsing the source, not from stored pixels or layout objects. Pack state carries workflow scientific identity; display overrides travel separately under Plot System ownership.

---

## Phase 6: Save to Library

**Goal**: the workflow can persist a chart artifact and metadata to the Library.

Deliverables:
- Assembly-owned save metadata projection (title, semantic params, source identity, axis labels)
- Save use case integration (either existing `SaveActiveChartToLibraryUseCase` for Cartesian XY or a workflow-specific use case for non-Cartesian paths)
- Boundary confirmed: Save use case must not infer metric names, units, or semantic identity — these come entirely from the Assembly projection

**Invariant**: The Cartesian XY save path and non-Cartesian save paths must not be merged. A workflow using a non-Cartesian render path must use a dedicated save use case; it must not conform to `ActiveChartProviding` or produce `WorkbenchPlotPayload`.

---

## Phase 7: Boundary Cleanup

**Goal**: verify that no module owns workflow semantics and no workflow owns module mechanics.

Checklist:
- [ ] Workflow Assembly does not implement colormap, colorbar, canvas geometry, or series reorder logic
- [ ] Plot System module does not contain physics assumptions about the workflow
- [ ] Save use case does not derive metric names or units
- [ ] Pack state does not serialize rendered pixels, layout objects, or canvas state
- [ ] Reusable capability identified in Phase 0 is fully extracted to a module (not hidden in the workflow store)
- [ ] MODULE_BOUNDARIES.md and WORKFLOW_ASSEMBLY.md accurately describe the boundary as implemented

**Output**: boundary audit notes in the Assembly doc; MODULE_BOUNDARIES.md updated to reflect final state.

---

## Phase 8: Documentation Closeout

**Goal**: architecture docs reflect the completed workflow.

Deliverables:
- Assembly record moved from `DRAFT_ASSEMBLY.md` to `ASSEMBLY.md` (or draft marked complete in-place)
- Gate status table in the Assembly record updated
- MODULE_BOUNDARIES.md updated with any new module sections or boundary corrections
- WORKFLOW_ASSEMBLY.md updated if the new workflow introduced a new Assembly contract pattern
- This protocol referenced in the Assembly record

**Invariant**: docs must state what is implemented, not what is planned. Future phases may be noted as deferred but must not be described as implemented.

---

## Lifecycle Summary

```
Phase 0  Capability Classification    → capability map, new module boundaries identified
Phase 1  Module Readiness             → MODULE_BOUNDARIES.md updated
Phase 2  Workflow Assembly            → ASSEMBLY.md (or DRAFT) complete
Phase 3  Main Board Wiring            → workflow reachable in shell
Phase 4  Minimal Pipeline             → end-to-end data flow verified
Phase 5  Pack / Restore               → workspace round-trip verified
Phase 6  Save to Library              → chart artifact persists to Library
Phase 7  Boundary Cleanup             → no cross-boundary ownership violations
Phase 8  Documentation Closeout       → docs reflect implementation
```

The lifecycle is **conditional**. A workflow that does not save to the Library skips Phase 6. A workflow that reuses an existing render path with no new module work skips most of Phase 1. A minimal workflow may proceed directly from Phase 3 to Phase 8 if Phases 4–7 apply trivially.

The phases are not always sequential. Phase 7 boundary work often runs in parallel with Phases 4–6. Phase 2 may be revisited during Phase 4 as implementation reveals gaps in the adapter contract.

---

## Validated Instance: RSM

RSM (Reciprocal Space Mapping) is the first workflow to complete this protocol for a **non-Cartesian render path**. It validates:

- Phase 0: Heatmap render path identified as new, requiring a Plot System module
- Phase 1: Heatmap render pipeline designed as a Plot System module (`HeatmapRenderPipeline`, `HeatmapRenderer`, `HeatmapTabRenderState`) before RSM code was written
- Phase 2: `CanonicalRSMDataset` contract declared in `DRAFT_ASSEMBLY.md` before parser implementation
- Phase 3: `RSMWorkspaceStore` registered and wired into the shell
- Phase 4: `RSMDataParser` → `CanonicalRSMDataset` → `RSMHeatmapPayloadBuilder` → `HeatmapPlotPayload` → `HeatmapRenderPipeline` → PNG
- Phase 5: `RSMPackState`, `HeatmapTabRenderState` codec, restore integration tests (Gates H1–H4)
- Phase 6: `RSMSaveProjection` + `SaveRSMChartToLibraryUseCase` (Gate H5)
- Phase 7: Boundary verified — RSM does not implement colormap or colorbar; Plot System does not contain RSM physics
- Phase 8: Architecture docs synced (Gate H6); this document is the protocol formalization (Gate H7)

**RSM is not a module.** It is a Workflow Assembly. The heatmap render path it motivated is the module.

Full details: [workflows/rsm/DRAFT_ASSEMBLY.md](workflows/rsm/DRAFT_ASSEMBLY.md).
