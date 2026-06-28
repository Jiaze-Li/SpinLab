# Stage 2A — Payload Semantics Closeout

**Branch:** gate8.5A  
**Closed at:** 9aac059 fix(display-payload): use export-safe workflow payloads

---

## What Stage 2A covered

Two-part cleanup of payload contract violations surfaced after Gate 8.5A.

---

## Stage 2A-1 — manifestPayload purity (8dc97d7)

`ThreeOmega manifestPayload` was being polluted by UI display overrides — title, axis labels, and series labels — during manifest refresh / render output updates.

**Fixed:** `_refreshManifestPayloads` no longer writes title, axis-label, or series-label overrides into `manifestPayload`. `renderThreeOmegaTab` also preserves the existing clean `manifestPayload` from `TabRenderOutput` instead of replacing it with post-pipeline output. `TabRenderState` remains the sole source of truth for display-layer overrides. `manifestPayload` is now safe for persistence and library indexing.

---

## Stage 2A-2 — displayPayload export correctness (9aac059)

`ThreeOmega` and `XYRotation` render helpers were returning/storing the post-pipeline `manifestPayload` as `displayPayload`. `WorkbenchPlotExportService` re-ran the pipeline on that, applying `reverseSeriesForLegend` a second time — producing a mirrored legend order in Copy PNG vs. the visible chart.

**Fixed:** All render helpers now snapshot `displayPayload = payload` before the pipeline call. The pipeline still runs to completion for the visible render; only the stored `displayPayload` source changes.

---

## Semantic contracts (stable as of this closeout)

| Payload | Role | Invariants |
|---|---|---|
| `manifestPayload` | Persistence / library indexing | No UI overrides. Not used as Copy PNG source. |
| `displayPayload` | Export rerender input | Workflow-transformed, pre-pipeline. `reverseSeriesForLegend` not yet applied. |
| `TabRenderState` | Display state source of truth | Title, axis labels, series labels, legend, range, point tags. |
| `WorkbenchPlotExportService` | Export seam | Re-renders `displayPayload` + `TabRenderState`. Unchanged during Stage 2A. |

---

## Validation (both stages)

All tests passed at clean point. `swift build` clean. `/Applications/SpinLab.app` rebuilt. `check_required_actions.sh`: no further action required.

Suites covered: WorkbenchPlotExportServiceTests · V563WorkflowStateBoundaryTests · Stage2A1ManifestPayloadPurityTests · V750SaveSemanticProtectionTests · V78CPlotControlsSpecializationTests · V85APackPersistenceGapTests · V710PlotControlsMigrationTests

---

## Remaining backlog (not part of Stage 2A)

- ThreeOmegaRAHEVsDeviceManifestTests workflowID baseline failure
- V5 IV x-axis migration policy
- AHE title hybrid cleanup
- PointTag file physical location cleanup
- Long-term PlotSystem API hardening
