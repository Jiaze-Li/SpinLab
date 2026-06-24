# Gate 7.5 — Save to Library / Save Metadata Projection Audit

> Docs-only. No Swift runtime changes were made in this audit.

## Purpose

Audit the current boundary between the common save writer and the per-workflow metric/metadata assembly so that the next step (runtime projection extraction) starts from an accurate map rather than from assumptions.

Questions answered:

1. What does the common save writer currently own?
2. Where are metric definitions produced?
3. Where are units decided?
4. Where are overrides applied?
5. Where is active-chart metadata assembled?
6. Which parts are workflow/Assembly semantics vs. pure common artifact writing?
7. Which tests currently protect the AHE / XY / 3ω save paths?
8. What are the risks before runtime extraction?

---

## 1. What the common save writer currently owns

`SaveActiveChartToLibraryUseCase` (`UseCases/SaveActiveChartToLibraryUseCase.swift`) is the common writer. It owns:

- **Input validation**: empty library root, empty sample keys, missing `sourceRef` on series, metric `sampleKey` not in the declared key set.
- **Artifact writes**: delegates chart image + manifest write to `PersistChartArtifactUseCase`, metric record write to `PersistMeasurementDataUseCase`.
- **Condition normalization**: lowercases and trims all condition keys before constructing `WorkbenchMetricRecord`.
- **Trace construction**: calls `BuildRunTraceProjectionUseCase` after chart write; attaches trace to `PersistenceOutcome`.
- **Return value**: `PersistenceOutcome` (`.success`, `.partial`, `.failure`).

The common writer does **not** know which metrics exist, what they mean, what units to use, or how to handle overrides. It accepts whatever arrives in `SaveActiveChartInput.metrics: [PendingMetricEntry]` and writes it verbatim (after condition normalization).

`PersistChartArtifactUseCase` further owns:

- Multi-sample routing (single sample → `samples/{key}/charts/`, multiple samples → `_spinlab/multi-sample/charts/`).
- Chart identity key derivation from payload.
- Manifest construction from `WorkbenchPlotPayload` fields.
- `results_index.json` upsert and stale-path cleanup.
- `measurement_plot_index.json` upsert per source file.

---

## 2. Where metric definitions are produced

Each workflow store implements `ActiveChartProviding.buildActiveChartMetrics() -> [PendingMetricEntry]`.

| Workflow | File | Metrics produced | Tab gate |
|---|---|---|---|
| AHE | `AHEWorkspaceStore.swift` | `"Hc"`, `"R_AHE"` per sample key | always (all tabs produce same metrics) |
| 3ω | `ThreeOmegaWorkspaceStore+Plotting.swift` | `"alpha"`, `"beta"`, `"r_squared"` per scaling segment | only when `tabs.activeTab == .scaling` and `scalingResult` is non-empty; all other tabs return `[]` |
| XY | `XYRotationWorkspaceStore.swift` | none — returns `[]` always | deferred; comment says "Fourier fit will provide AMR/PHE metrics" |

Metric names are string literals inside `buildActiveChartMetrics()`. There is no shared metric-name registry.

---

## 3. Where units are decided

Units are hardcoded as string literals in `buildActiveChartMetrics()` in each workflow store:

| Workflow | Metric | `canonicalUnit` |
|---|---|---|
| AHE | Hc | `"T"` |
| AHE | R_AHE | `"Ω"` |
| 3ω | alpha | `"Ω·μm³·cm²·V⁻²·S⁻²"` |
| 3ω | beta | `"Ω·μm³·V⁻²"` |
| 3ω | r_squared | `""` (dimensionless) |
| XY | — | none yet |

**3ω unit scaling is baked into the entry values**, not stored as a conversion factor:

```swift
// ThreeOmegaWorkspaceStore+Plotting.swift
PendingMetricEntry(..., metric: "alpha", value: seg.alpha * 1e31, canonicalUnit: "Ω·μm³·cm²·V⁻²·S⁻²", ...)
PendingMetricEntry(..., metric: "beta",  value: seg.beta  * 1e20, canonicalUnit: "Ω·μm³·V⁻²", ...)
```

The common writer receives already-scaled values and writes them as-is. There is no conversion layer anywhere in the pipeline.

---

## 4. Where overrides are applied

Overrides exist only in AHE. They are applied **inside `buildActiveChartMetrics()`** before the common writer ever sees the entries.

AHE override state:
- `pendingMetricOverride: WorkbenchMetricOverrideCandidate?` — for Hc
- `pendingRAHEOverride: WorkbenchMetricOverrideCandidate?` — for R_AHE
- Both fields live in `AHEWorkspaceStore` and are save-time only.

Override application policy (AHE-specific):
- Applied **only when `isSingleSample == true`** (i.e., one sample key in the render).
- The original extracted value is preserved in `WorkbenchMetricOverrideInfo.oldValue`; the override value goes into `PendingMetricEntry.value`.
- Override candidates are cleared after a successful persist (`pendingMetricOverride = nil`, `pendingRAHEOverride = nil`) or by `clearPlot()`.

3ω and XY have no override mechanism.

---

## 5. Where active-chart metadata is assembled

Each workflow's `persistToLibrary()` constructs `SaveActiveChartInput` locally from three `ActiveChartProviding` properties:

```swift
// Same pattern in AHEWorkspaceStore, ThreeOmegaWorkspaceStore+Persistence, XYRotationWorkspaceStore
let input = SaveActiveChartInput(
    png:            activeChartPNG,         // tabs.activeImageData
    payload:        activeChartManifestPayload,  // tabs.activeManifestPayload
    sampleKeys:     activeChartSampleKeys,  // cachedSampleKeys / per-workflow
    libraryRootPath: lastLibraryRootPath,   // from vault or search root
    metrics:        buildActiveChartMetrics()
)
```

`WorkbenchPlotPayload` (the manifest payload) is assembled upstream during render, not at save time. It carries:
- `workflowID`, `workflowDisplayName`, `title` — workflow-owned
- `axisMapping` — workflow-owned axis field names
- `semanticParams` — workflow-assembled; includes `tabKey`, fit parameters, method choices
- `styleParams` — display overrides from `TabRenderManager`
- `series` — render output including `sourceRef` (identity key input)

The save writer reads `payload.semanticParams["tabKey"]` to populate `WorkbenchResultReference.tabKey`; this is the only case where the writer reads a semantic payload field.

### Conditions assembly (3ω only)

3ω conditions are assembled inside `buildActiveChartMetrics()` per scaling segment:

```swift
var segConditions: [String: String] = [
    "range": "\(Int(seg.tLo.rounded()))K–\(Int(seg.tHi.rounded()))K",
    "v3method": methodTag   // "HFE" or "WA"
]
// + optional "deviceMode", "devices", "device"
```

These condition keys are 3ω physics semantics and must remain Assembly-owned. AHE conditions come from `lastRenderedConditionsBySampleKey` (populated during analysis, keyed by sample key).

---

## 6. Boundary map: workflow/Assembly semantics vs. common artifact writing

### Common (Module-owned, safe to share)

| Concern | Owner | Notes |
|---|---|---|
| Input validation | `SaveActiveChartToLibraryUseCase` | Empty path, empty keys, missing sourceRef, metric key subset |
| Chart image + manifest write | `PersistChartArtifactUseCase` | Multi-sample routing, index upsert, stale cleanup |
| Metric record write | `PersistMeasurementDataUseCase` | Condition normalization, record construction |
| Trace construction | `BuildRunTraceProjectionUseCase` | From manifest + manifest path |
| `PersistenceOutcome` return type | `SaveActiveChartToLibraryUseCase` | Shared across all workflows |
| Identity key derivation | `WorkbenchChartIdentity.makeIdentityKey` | From payload fields, no physics |

### Assembly-owned (must stay per-workflow)

| Concern | Current owner | Risk if moved to common |
|---|---|---|
| Metric names (`"Hc"`, `"R_AHE"`, `"alpha"`, …) | `buildActiveChartMetrics()` per workflow | Common code would invent or interpret physics |
| Canonical unit strings | `buildActiveChartMetrics()` per workflow | Wrong units in saved Library artifacts |
| Unit scaling factors (`* 1e31`, `* 1e20`) | `buildActiveChartMetrics()` in 3ω | Physics constants embedded in common code |
| Override eligibility and policy | `AHEWorkspaceStore.buildActiveChartMetrics()` | Single-sample guard is AHE-specific; generic override would corrupt multi-sample results |
| Condition keys and structure | `buildActiveChartMetrics()` per workflow | `"range"`, `"v3method"`, `"device"` are 3ω semantics |
| Tab gate for metric production | `buildActiveChartMetrics()` per workflow | 3ω only produces metrics on `.scaling`; AHE produces on all |
| `activeChartSampleKeys` selection | Per-workflow `ActiveChartProviding` | Per-tab key filtering is workflow-dependent |
| Save message wording | Per-workflow `persistToLibrary()` | Currently hardcoded string literals; duplicated but not wrong |
| `persistenceOutcome` state | Per-workflow store | Currently workflow-local; Gate 7.5 target is common ownership |
| `saveMessage` state | Per-workflow store | Currently workflow-local; Gate 7.5 target is common ownership |

---

## 7. Current tests protecting the AHE / XY / 3ω save paths

| Test file | What it protects | Tier |
|---|---|---|
| `V537SaveModuleBoundaryTests` | nil-PNG guard, canonical search/selection preservation, trace assignment, message routing (save vs analysis), clearPlot, runAnalysis start clearing saveMessage, refreshRelatedCharts on success/partial | Boundary regression |
| `V4111SaveActiveChartToLibraryUseCaseTests` | Use case validation (empty path, missing sourceRef, empty keys, metric key subset), chart-only success, chart-with-metrics success, condition normalization | Use case unit |
| `V5111ExtractAHEMetricsUseCaseTests` | AHE metric extraction algorithm (zero-crossing Hc, plateau R_AHE, sampleKey parsing) | Algorithm unit |
| `V5114AHEMetricSourceTests` | Metric key comes from `sampleID`, not `label`; series without `sampleID` produces failure | Contract |
| `V341ManualOverrideCaptureTests` | Override capture, persisted `overrideInfo`, source `.manual`, `latestIndex` stores override value, clearPlot clears pending override, `OverrideSource` encode/decode | Override behavior |
| `V41216ThreeOmegaScalingUseCaseTests` | 3ω scaling result (protects source data for alpha/beta/r² entries) | Algorithm |
| `V413ThreeOmegaFitUseCaseTests` | 3ω fit (protects source data upstream of scaling) | Algorithm |
| `V420XYRotationTests` | XY analysis (no metrics yet; guards save-with-empty-metrics path implicitly) | Workflow |

### Coverage gaps relevant to Gate 7.5

Gap status updated after Gate 7.5A:

| Gap | Status | Covered by |
|---|---|---|
| 3ω `buildActiveChartMetrics()` metric names, unit strings, scaling factors from fixture | **Covered** | `V750SaveSemanticProtectionTests` — Suite 1 (20 tests) |
| 3ω non-scaling tabs produce empty metrics | **Covered** | `V750SaveSemanticProtectionTests` — "non-scaling tabs return empty entries" |
| AHE multi-sample override guard (`isSingleSample` blocks override) | **Covered** (source inspection) | `V750SaveSemanticProtectionTests` — Suite 2 (5 tests) |
| `tabKey` read path in `PersistChartArtifactUseCase` | **Covered** | `V750SaveSemanticProtectionTests` — Suite 3 (6 tests) |
| `persistenceOutcome` / `saveMessage` state transitions for 3ω | Still open — boundary tests use stubs; full behavioral test requires 3ω analysis round-trip |

The AHE override guard is covered through source inspection rather than a direct behavioral test (because `lastRenderedSampleKeys` is `private(set)` and requires a full analysis round-trip to populate). The source inspection tests are sufficient: they directly assert the structural guard that prevents multi-sample corruption and will fail if the guard is removed or restructured.

---

## 8. Risks before runtime extraction

| Risk | Description | Mitigation required |
|---|---|---|
| **Common code inventing metrics** | If `buildActiveChartMetrics()` is replaced by a generic metric scan, the common writer might infer metric names from field names or series labels. | Projection contract must be explicit; common writer must only accept pre-declared metrics. |
| **Override applied to multi-sample results** | AHE's `isSingleSample` guard is only in the workflow store. A generic override path at use-case level would apply it unconditionally. | Override must remain workflow-dispatched; the projection must carry per-sample override info already resolved. |
| **Unit scaling baked into values** | The `* 1e31` / `* 1e20` factors are physics constants in 3ω's `buildActiveChartMetrics()`. If the extraction step is moved generically, these factors could be lost, duplicated, or misapplied. | The scaling step must remain in Assembly code; the projection must carry already-scaled values. |
| **Condition structure is physics** | `"range"`, `"v3method"`, `"device"` are 3ω semantics. A generic projection that merges or re-keys conditions would corrupt the Library artifact. | Conditions must be opaque to the common writer; they are passed through as-is. This is already the case. |
| **`saveMessage` duplication** | Three identical string literals across three `persistToLibrary()` implementations. A partial extraction that moves only some paths creates inconsistency. | Extract `saveMessage` assignment together with `persistenceOutcome` or leave both workflow-local. |
| **`currentRunTrace` assignment** | All three `persistToLibrary()` implementations set `self.currentRunTrace = outcome.trace` identically. This is duplicated common behavior. | Can be moved into a common coordinator without touching Assembly code; low risk. |
| **`refreshRelatedCharts()` duplication** | Called on `.success` and `.partial` in all three implementations. | Low risk to centralize; must not be called on `.failure`. |
| **Tab-gate for metric production** | 3ω returns `[]` for non-scaling tabs at `buildActiveChartMetrics()` time. A generic save path that always calls a metric builder would need to know about the tab gate. | Tab gate must remain Assembly-dispatched; the projection itself can be empty. |
| **3ω metric projection tests** | ~~No test asserts 3ω `buildActiveChartMetrics()` correctness from a fixture.~~ Covered by `V750SaveSemanticProtectionTests` Suite 1 (Gate 7.5A). | Projection tests now exist; extraction can verify they stay green. |
| **`activeChartSampleKeys` policy** | Each workflow determines which sample keys correspond to the active chart. For multi-tab 3ω with overlays, the keys may differ per tab. Moving this into common code risks wrong key sets. | `activeChartSampleKeys` must remain per-workflow `ActiveChartProviding` output. |

---

## 9. Extraction readiness summary

| Component | Readiness | Notes |
|---|---|---|
| Common save writer (`SaveActiveChartToLibraryUseCase`) | Ready — already common | No physics knowledge; accepts opaque `PendingMetricEntry[]` |
| `PersistChartArtifactUseCase` | Ready — already common | No workflow knowledge |
| `PersistMeasurementDataUseCase` | Ready — already common | No workflow knowledge |
| `saveMessage` + `persistenceOutcome` extraction | Medium | Requires a common save coordinator; three identical call sites but different store shapes |
| `currentRunTrace` + `refreshRelatedCharts` extraction | Low risk | Identical in all three; can move to coordinator |
| `buildActiveChartMetrics()` → named projection | Blocked until contract defined | Must define `WorkbenchSaveMetadataProjection` first; then each Assembly implements it |
| Metric names / units / scaling factors | Assembly-owned, do not move | Physics constants; must stay per-workflow |
| Override policy | Assembly-owned, do not move | Single-sample guard is AHE-specific |
| Condition structure | Assembly-owned, do not move | 3ω physics semantics |

---

## 10. Recommended pre-extraction steps (not in scope for Gate 7.5 audit)

These are observations, not tasks. They will inform the Gate 7.5 extraction handoff.

1. **Add 3ω metric projection tests**: verify `buildActiveChartMetrics()` produces the correct metric names, unit strings, scaling-factor values, and condition structure from a fixture `ThreeOmegaScalingResult`.
2. **Add AHE multi-sample override guard test**: verify that `pendingMetricOverride` is ignored when `sampleKeys.count > 1`.
3. **Define `WorkbenchSaveMetadataProjection`**: explicit named type replacing the raw `[PendingMetricEntry]` bridge. Each workflow Assembly provides one; the common writer consumes it.
4. **Define save coordinator interface**: where `saveMessage`, `persistenceOutcome`, `currentRunTrace`, and `refreshRelatedCharts` land after extraction.

---

## Cross-links

- [Gate 7.5 entry in WORKBENCH_ROADMAP.md](../WORKBENCH_ROADMAP.md#gate-75---save-to-library--save-metadata-projection)
- [Save to Library boundary in MODULE_BOUNDARIES.md](../MODULE_BOUNDARIES.md#save-to-library)
- [Metric Extraction boundary in MODULE_BOUNDARIES.md](../MODULE_BOUNDARIES.md#metric-extraction--metric-override--save-metadata)
- Save use case: `Sources/SpinLabApp/UseCases/SaveActiveChartToLibraryUseCase.swift`
- Chart artifact writer: `Sources/SpinLabApp/UseCases/PersistChartArtifactUseCase.swift`
- AHE metric extraction: `Sources/SpinLabApp/UseCases/ExtractAHEMetricsUseCase.swift`
- AHE save: `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift`
- 3ω metric projection: `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Plotting.swift`
- 3ω save: `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Persistence.swift`
- XY save: `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift`
- Common contract: `Sources/SpinLabApp/Workbench/Modules/PlotSystem/Contracts/WorkbenchResultContracts.swift`
- Provider protocol: `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift`
