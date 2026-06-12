# Gate 7.9: Workbench Architecture Closeout

> Verdict: the Workbench architecture refactor is closed after Gate 7.9. Remaining work is runtime validation and stabilization, not new module extraction.

## What This Document Is

A point-in-time record of the state of the Workbench architecture after Gates 7.1–7.8. It captures the final module map, extraction outcomes, accepted compatibility bridges, deferred runtime cleanup, and explicit non-candidates.

Future work after Gate 7.9 should be runtime validation or bug fix unless a new workflow proves a real shared-module need that cannot be served by the existing module contracts.

---

## Final Module Map

| Module | Owner | Classification | Status |
|---|---|---|---|
| Main Board Layout | `WorkflowWorkspaceShell`, left/right column views | Shell — outside all module groups | Stable. Shell passes plot controls as a ViewBuilder slot; does not own module state. |
| Main Search | `WorkbenchMainSearchRuntime` via `WorkbenchFeatureStore` facade | Common module | Runtime extracted. `cachedSearchResults` retained as compatibility bridge. |
| Selection | `WorkbenchSelectionRuntime` | Common module | Runtime extracted (Gate 7.2). Workflow-local `selectionReading` typed bridge is a non-canonical read surface (migrated from closure to typed protocol in Gate 7.7B). |
| Secondary Input Search | `WorkbenchSecondaryInputSearchRuntime` (slot state), `ThreeOmegaWorkspaceStore` (workflow semantics) | Optional module candidate | Runtime extracted (Gate 7.3). Current live instance: 3ω `rt` slot. |
| Analysis Overlay | `WorkbenchAnalysisOverlayRuntime` (overlay IDs, chip labels), `ThreeOmegaWorkspaceStore` (snapshot content, rendering) | Optional module candidate | Runtime extracted (Gate 7.4). Session-only; no pack persistence. |
| Save to Library | `WorkbenchSaveCoordinating` (coordinator), workflow stores (metric projection) | Boundary debt — save writer common, semantics Assembly-owned | Coordinator extracted (Gate 7.5). Raw `PendingMetricEntry` bridge retained. |
| Pack / Restore | `RestoreAnalysisPackUseCase`, `AnalysisVault`, workflow store pack methods | Boundary debt — contracts documented, implementation per-workflow | Audited and protected (Gate 7.6). Full coordinator extraction deferred. |
| Warning Display / Run Trace | `WorkbenchRunTraceProviding`, `WorkbenchStatusArea`, `WorkbenchTracePanel`, workflow store fields | Boundary debt — display exists, runtime ownership distributed | `currentRunTrace` removed from plot protocol (Gate 7.8D). Full extraction deferred. |
| Plot System | `TabRenderManager` (Plot Preservation + Display), `WorkbenchPlotControlsPanel` / `WorkbenchStandardPlotControls` (Plot Controls), `WorkbenchPlotCanvas` (interaction/display surface) | Common module group | Boundaries clarified (Gate 7.8). Structural guards added. |
| Workflow Assembly-owned non-modules | Per-workflow stores and views (AHE, XY Rotation, 3ω) | Assembly-owned — not module extraction targets | Stable. Physics semantics, title token defaults, stacking parameters, and workflow-specific controls remain Assembly-owned. |

---

## Gates 7.1–7.8 Outcome Summary

| Sub-gate | Scope | Outcome |
|---|---|---|
| 7.0 | Main Search extraction handoff audit | Docs-only. Bridge inventory and forbidden-change map recorded. |
| 7.1 | Main Search | `WorkbenchMainSearchRuntime` is canonical owner. `cachedSearchResults` retained as compatibility bridge. |
| 7.2 | Selection | `WorkbenchSelectionRuntime` is canonical owner. Workflow-local `selectionReading` typed bridge (`weak var selectionReading: (any SelectionReading)?`) is the non-canonical read surface. |
| 7.3 | Secondary Input Search | `WorkbenchSecondaryInputSearchRuntime` owns all slot state for the `rt` slot. `ThreeOmegaWorkspaceStore` retains workflow semantics. |
| 7.4 | Analysis Overlay | `WorkbenchAnalysisOverlayRuntime` owns overlay IDs and chip display labels. Workflow retains snapshot content and rendering semantics. |
| 7.5 | Save to Library / Save Metadata Projection | `WorkbenchSaveCoordinating` protocol extracts shared async orchestration. Metric definitions and override policy remain Assembly-owned. |
| 7.6 | Pack / Restore | Restore write map audited and protected (34 tests). `_overlayPackIDs` standalone fallback removed. `cachedRTFilePath` overwrite sequence pinned. |
| 7.7 | Warning Display / Run Trace | Boundary debt documented. `currentRunTrace` now surfaced exclusively through `WorkbenchRunTraceProviding`. Full runtime extraction deferred. |
| 7.8 | Plot System module group audit and structural guards | Module group boundaries clarified. Main Board layout confirmed outside Plot System. `WorkbenchPlotCanvas` is interaction/display surface only. `TabRenderManager` / `TabRenderState` own Plot Preservation. `currentRunTrace` removed from `WorkbenchPlottingStore`. Structural boundary tests added. Assembly-owned display semantics (title defaults, stacking parameters, AHE single-tab specialization) remain in workflow stores. |

---

## Accepted Compatibility Bridges

These are intentionally retained. They are not debt to eliminate before Gate 8.

| Bridge | Location | Why retained |
|---|---|---|
| `cachedSearchResults` mirror | Workflow stores | Selection denominator; pack compatibility. Rename deferred pending `CodingKey` handling. |
| Workflow-local `selectionReading` typed bridge | AHE / XY / 3ω workspace stores | `weak var selectionReading: (any SelectionReading)?` injected by `WorkbenchFeatureStore`; `WorkbenchSelectionRuntime` conforms to `SelectionReading`. Non-canonical read surface for pack serialization and analysis denomination. Removal awaits Save / Pack Module cleanup. |
| Workflow-local Assembly-owned plot binding endpoints | Workflow stores (title defaults, `stackOffsetMultiplier`, `minGapFraction`, AHE controls) | Assembly-owned semantics intentionally in workflow stores per Gate 7.8 audit. |
| Raw `PendingMetricEntry` save metadata bridge | `buildActiveChartMetrics()` per workflow | Untyped bridge to common save writer. Typed projection is the deferred target. |
| Secondary input restore bridge (`cachedRTFilePath` derivation) | `ThreeOmegaWorkspaceStore` restore path | Derived from `selectedRTHit`; standalone rebuild not implemented; restore path confirmed correct. |
| Active-tab overlay rerender trigger (workflow-driven) | `ThreeOmegaWorkspaceStore.addOverlay` / `removeOverlay` | Moving trigger into runtime would require observable counter; no boundary value justifies the indirection in the current cut. |

---

## Deferred Runtime Cleanup

These are legitimate deferred items, not stale audit orphans. They are not blocking Gate 8.

| Item | Recorded in | Notes |
|---|---|---|
| Full Pack/Restore coordinator extraction | `MODULE_BOUNDARIES.md` § Pack / Restore | Contracts and tests in place; per-workflow restore implementation remains. |
| Full Warning Display / Run Trace runtime extraction | `MODULE_BOUNDARIES.md` § Warning Display / Run Trace | Display components exist; runtime ownership distributed. Awaits explicit coordinator gate. |
| Typed save metadata projection replacing raw `PendingMetricEntry` | `MODULE_BOUNDARIES.md` § Save to Library | Typed semantic projection is the target; raw bridge retained for now. |
| Search/Rules alias integration | `modules/MEASUREMENT_SEARCH.md` § Deferred Boundary Debt | Rules Book-defined workflow IDs do not auto-participate in alias resolution. Not blocking current workflows. |
| `legendAnchor` pack coverage gap (AHE/XY) | `MODULE_BOUNDARIES.md` § Title / Style / Legend Controls | Documentation and coverage gap only; no pack schema change required at this gate. |
| `titleTemplate` extraction to common Plot Controls | `MODULE_BOUNDARIES.md` § Title / Style / Legend Controls | Blocked on boundary tests + backward-compatible `CodingKeys` in all three pack configs. |

---

## Non-Candidates

The following surfaces are Assembly-owned. They must not be extracted into common modules unless a future workflow proves a real shared semantic contract.

- AHE Hc / R_AHE extraction as a common module.
- XY phi offset / detrend / centering as a common module.
- 3ω geometry / fit range / scaling as a common module.
- Workflow physics panels becoming common Plot System controls.

---

## Closeout Rule

> **Future work after Gate 7.9 should be runtime validation or bug fix.** New module extraction is only justified when a new workflow (e.g., SOT) demonstrates a real shared-module need that cannot be served by the existing module contracts. Do not extract for its own sake.
