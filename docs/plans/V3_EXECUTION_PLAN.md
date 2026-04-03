# SpinLab V3 Execution Plan

Status: done
Plan version: v3.0 (revised)

Owner intent: Workbench becomes the real data workbench, while Library remains the source-of-truth archive.

---

## 0. One-line Goal

Build a durable V3 architecture where each workflow owns its data-processing pipeline, all workflows converge to a unified plotting exit, and analysis outcomes are written back to Library in a sample-centric, traceable, read-optimized model.

---

## 1. Design Philosophy (North Star)

### 1.1 Functional Layering Is Non-negotiable

V3 is not a "feature pile". It is a layering exercise:

1. Workflow processing layer decides what to compute.
2. Unified plotting layer decides how to render.
3. Persistence layer decides how to store traceable outcomes.
4. Read-model layer decides how UI reads and displays.

No layer should absorb responsibilities from another layer.

### 1.2 Stable Keys + Evolvable Names

Internally, all joins and routing use stable IDs.
UI always prefers human-readable display names.

Why:

- IDs guarantee referential integrity.
- Display names can evolve without breaking storage joins.
- This directly supports future renaming needs.

### 1.3 Raw Data Is Immutable

Raw measurement files are never modified by Workbench pipelines.
All processing artifacts are derived outputs.

Why:

- Protect reproducibility.
- Preserve scientific auditability.
- Prevent hidden corruption by accidental write-back.

### 1.4 Write-path and Read-path Must Be Decoupled

Workbench writes structured outcomes.
Library UI only reads projections.

Why:

- Keep UI fast and clean.
- Keep business logic out of view layer.
- Reduce accidental side effects in UI interaction.

### 1.5 Keep UI Clean, Keep Audit Deep

Frontend shows latest useful values by default.
Backend preserves full history and override details.

Why:

- Research UI must stay high-signal.
- Traceability still exists when needed.

---

## 2. Product Framing for V3

### 2.1 What V3 Is

- A structural architecture milestone.
- A workflow-specific compute + unified render + sample-centric persistence milestone.
- The first real operational Workbench generation.

### 2.2 What V3 Is Not

- Not a full multi-workflow analytics suite in one round.
- Not a batch-level aggregate writeback system.
- Not a redesign of Library as an editable analysis console.

### 2.3 First Workflow in Scope

AHE only for first closed loop.
MR/RT are follow-on onboarding targets once architecture is validated.

---

## 3. Architecture Blueprint

### 3.1 Layer A: Workflow Processing Pipelines

Each workflow implements its own processing pipeline.

Input:

- raw measurement references (from Library)
- user-selected filters
- workflow-specific processing params

Output:

- standardized plotting payload (normalized series)
- structured metric records
- warnings/errors

Rules:

- no rendering in pipeline layer
- no direct UI logic
- no direct mutation of raw files

### 3.2 Layer B: Unified Plot Engine

Single rendering exit for all workflows.

Input contract:

- standardized plot payload only

Responsibilities:

- title/font/grid/layout/style handling
- export format handling (V3 first: PNG)
- deterministic output path and naming

Rules:

- no workflow-specific math
- no raw file parsing
- no condition inference
- chart identity uses semantic payload hash, never rendered image binary hash

### 3.3 Layer C: Persistence & Indexing

Writes 3 artifact types:

1. plot image
2. per-chart run manifest
3. sample-level measurement data updates

Storage strategy:

- chart assets centralized under Library root analysis tree
- per-sample JSON index references chart assets
- per-sample measurement_data.json stores metrics

### 3.4 Layer D: Read Models for Library UI

Library reads only projections:

1. Measurements Done (existing)
2. Workbench Results (new)
3. Measurement Data (new)

Rules:

- UI is read-only in Library
- no compute in Library view layer
- no write-path from Library UI

---

## 4. Core Data Contracts

### 4.1 Plot Payload (Unified Input)

Use multi-series structure, not hardcoded x1/x2/y1/y2 fields.

```json
{
  "schemaVersion": 1,
  "workflowID": "A",
  "workflowDisplayName": "AHE",
  "title": "AHE PN20 STO001",
  "axisMapping": {
    "xField": "field",
    "yField": "rxy"
  },
  "series": [
    {
      "label": "PN20 80K 30deg",
      "x": [0.0, 0.1],
      "y": [1.2, 1.3],
      "sourceRef": "batches/PN20/samples/PN20_STO001/measurements/A/...dat"
    }
  ],
  "semanticParams": {
    "normalization": "none"
  },
  "styleParams": {
    "grid": "on",
    "theme": "default"
  }
}
```

### 4.2 Metric Record

Metric records are sample-centric and condition-aware.

```json
{
  "recordID": "uuid",
  "sampleKey": "sid_7f8c3a...",
  "displayKey": "PN20||STO|001",
  "workflowID": "A",
  "metric": "Hc",
  "value": 1.0,
  "canonicalUnit": "T",
  "displayUnitHint": "mT",
  "conditions": {
    "device": "30deg",
    "temperature": "80K"
  },
  "generatedAt": "2026-04-03T14:00:00Z",
  "runID": "run_...",
  "overrideInfo": {
    "oldValue": 0.95,
    "newValue": 1.0,
    "reason": "manual correction after visual check",
    "at": "2026-04-03T14:01:00Z"
  }
}
```

### 4.3 Per-chart Run Manifest

Lightweight trace document per chart output.

```json
{
  "schemaVersion": 1,
  "manifestID": "manifest_...",
  "runID": "run_...",
  "workflowID": "A",
  "inputFiles": [
    "batches/PN20/samples/PN20_STO001/measurements/A/a.dat",
    "batches/PN20/samples/PN20_STO001/measurements/A/b.lvm"
  ],
  "filters": {
    "sampleID": "sid_7f8c3a...",
    "sampleDisplayKey": "PN20||STO|001",
    "temperature": "80K"
  },
  "axisMapping": {
    "xField": "field",
    "yField": "rxy"
  },
  "semanticParams": {
    "normalization": "none"
  },
  "outputImagePath": "analysis/workflows/A/charts/...png",
  "generatedAt": "2026-04-03T14:00:00Z",
  "appVersion": "3.0.0"
}
```

Path rule:

- JSON payload/manifests/index store Library-root-relative paths only.
- `LibraryPathResolver` performs relative <-> absolute translation at runtime boundaries.

### 4.4 Measurement Data Store (Per Sample)

One file per sample drawer:

`<sampleDrawer>/analysis/measurement_data.json`

Contains full history and latest index.

```json
{
  "schemaVersion": 1,
  "records": [],
  "latestIndex": {
    "A|Hc|device=30deg|temperature=80K": {
      "recordID": "...",
      "value": 1.0,
      "canonicalUnit": "T",
      "generatedAt": "..."
    }
  }
}
```

---

## 5. Identity, De-duplication, and Overwrite Rules

### 5.1 Chart Identity Key

A chart is identified by:

`workflowID + normalizedInputFileSet + axisMapping + semanticParams`

Identity implementation rule:

- identity key is derived from semantic payload hash
- image binary hash is not used for identity

Style changes (title font/color/grid toggle) are not semantic identity changes.

### 5.2 Overwrite Rule

If identity key matches existing chart:

- overwrite chart image
- overwrite manifest
- remove stale previous asset references

Why:

- avoid storage bloat from meaningless style-only variants
- preserve one canonical visual output per semantic chart definition

### 5.3 Metric Identity Key

Metric latest pointer key:

`sample + workflow + metric + normalizedConditions`

Where:

- `sample` means opaque stable `sampleKey` only
- human-readable sample string is `displayKey` and must not be used in joins

Why:

- prevents cross-condition collisions
- preserves device + temperature specificity

---

## 6. Condition Rename Compatibility Strategy

### 6.1 No Forced Full Migration in V3

Do not batch-rewrite all historical files in V3.

### 6.2 Compatibility Mapping Is Runtime-enforced

Add canonical alias mapping config (program-readable JSON).

Example mapping:

```json
{
  "schemaVersion": 1,
  "conditionAliases": {
    "angle": ["device"]
  }
}
```

Read rule:

- unknown `schemaVersion` in alias config must fail with explicit error (no silent fallback).

### 6.3 UI Must Expose Alias Context

Show canonical with alias badge:

`angle (alias: device)`

Why:

- user should never need backend inspection to understand renamed fields

---

## 7. Write and Read Responsibilities

### 7.1 Workbench Writes

Workbench can:

- run processing
- apply manual pre-write correction
- produce assets + metrics + manifests
- commit to Library persistence

### 7.2 Library UI Reads

Library can:

- display Workbench Results
- display Measurement Data latest values
- mark overridden values with lightweight indicator (`*`)

Library cannot:

- edit metric values
- trigger workflow computation logic from read models

---

## 8. File/Directory Layout (V3)

### 8.1 Centralized Workflow Result Assets

`<LibraryRoot>/analysis/workflows/<workflowID>/charts/*.png`

`<LibraryRoot>/analysis/workflows/<workflowID>/manifests/*.json`

### 8.2 Sample-local Index

`<sampleDrawer>/analysis/index/workbench_results_index.json`

Contains references to centralized assets relevant to this sample.

Ownership rule:

- write path records reference relationships (sample -> chart/manifest)
- read-model maintenance job owns orphan sweep for centralized assets
- orphan sweep triggers: sample delete, workflow recompute overwrite, periodic maintenance run

### 8.3 Sample-local Metric Store

`<sampleDrawer>/analysis/measurement_data.json`

---

## 9. Phase Plan (Detailed)

## V3.1 Architecture Skeleton + Schemas

Deliverables:

1. define and version data contracts (`PlotPayload`, `MetricRecord`, `RunManifest`, sample measurement store)
2. define chart identity and metric identity key generators
3. define condition alias mapping loader
4. define persistence interfaces (no UI coupling)
5. define atomic write interface (`temp-write -> fsync -> commit`) and require all write paths to use it
6. define `LibraryPathResolver` for relative-path persistence

Acceptance:

1. schemas are documented and code-mirrored
2. serialization/deserialization round-trip tests pass
3. identity keys deterministic under same input
4. write interfaces support atomic commit contract before any V3.2 write implementation starts

## V3.2 AHE Pipeline + Unified Plot Engine

Deliverables:

1. AHE file ingestion for `.dat` and `.lvm`
2. default axis mapping + manual mapping override
3. standardized payload emission from AHE pipeline
4. unified plotting entry renders PNG
5. per-chart manifest emission
6. overwrite-on-same-identity behavior
7. all V3.2 file writes use V3.1 atomic write interface (no direct non-atomic write path)

Acceptance:

1. batch AHE charts render from Library-origin files
2. style-only change overwrites, semantic change creates new chart
3. manifests can replay source/params provenance
4. persisted source/output paths are Library-root-relative and resolvable via `LibraryPathResolver`

## V3.3 Library Writeback + Read Models

Deliverables:

1. sample index generation pointing to centralized assets
2. measurement_data write path with history append + latestIndex update
3. manual override capture (`old/new/reason/at`) in backend
4. Library sections: `Workbench Results` and `Measurement Data` read-only display
5. alias badge display in UI for renamed condition fields
6. all V3.3 file writes use V3.1 atomic write interface

Acceptance:

1. from sample drawer UI, user can access prior Workbench charts
2. measurement data displayed as latest-only in UI
3. overridden metrics visually marked without clutter
4. sample joins use stable `sampleKey`; `displayKey` changes do not break linking

## V3.4 Reliability Hardening

Deliverables:

1. atomic write transactions across chart + manifest + sample index + measurement data (hardening + recovery validation on top of V3.1 interface)
2. per-sample write lock to prevent concurrent JSON corruption
3. crash-safe temp-file commit strategy

Acceptance:

1. interruption does not produce half-written references
2. concurrent runs on same sample do not corrupt files

---

## 10. Testing Strategy

### 10.1 Contract Tests

1. schema round-trip tests for all artifact types
2. backward compatibility tests for alias mapping reads

### 10.2 Pipeline Tests

1. AHE `.dat/.lvm` parse coverage
2. axis mapping fallback + manual override behavior

### 10.3 Plot Tests

1. same semantic payload -> same identity
2. style-only mutation -> overwrite path
3. axis/semantic mutation -> new artifact path
4. same payload across repeated runs keeps same identity even if PNG bytes differ by render environment

### 10.4 Persistence Tests

1. sample measurement_data append + latestIndex update
2. index reference validity checks
3. orphan cleanup tests after overwrite
4. relative-path artifacts resolve correctly after Library root relocation

### 10.5 Read-model Tests

1. Library `Workbench Results` displays referenced charts
2. Library `Measurement Data` renders latest-only values
3. override marker shown; raw override details hidden in default view

---

## 11. Non-goals in V3

1. cross-sample aggregate writeback models
2. full migration of all legacy condition keys
3. full workflow onboarding beyond AHE
4. editable metric values directly in Library UI

---

## 12. Risks and Mitigations

### Risk 1: Workflow pipelines leak plotting behavior

Mitigation:

- enforce plot layer interface boundaries in code review and tests

### Risk 2: JSON growth over long-term use

Mitigation:

- per-sample store instead of global store
- latestIndex for fast reads
- optional archival policy in future version

### Risk 3: Rename confusion for users

Mitigation:

- runtime alias mapping
- visible alias badge in UI

### Risk 4: Duplicate artifact explosion

Mitigation:

- strict chart identity key
- overwrite policy for style-only changes

### Risk 5: Broken references after Library relocation

Mitigation:

- persist Library-root-relative paths only
- resolve absolute paths via `LibraryPathResolver` at runtime

---

## 13. Documentation Structure (Source of Truth)

Primary spec:

- `docs/specs/measurement_data_schema.md`

Supporting specs:

- `docs/specs/workbench_result_schema.md`
- `docs/specs/library_read_models.md`
- `docs/specs/condition_alias_schema.md`

Rule:

- measurement data schema is authoritative
- other docs reference, never redefine core keys
- alias config is versioned schema artifact; unknown schema version must fail explicitly

---

## 14. Decision Log (Current)

1. internal workflow match uses ID; UI uses displayName
2. AHE v3 first; MR/RT later
3. Workbench reads raw from Library only; no raw duplication
4. chart assets centralized, sample-level index references
5. per-chart manifest kept lightweight
6. same semantic chart overwrites old output
7. measurement data is sample-level, not batch-level
8. history retained in backend; UI shows latest only
9. manual correction allowed pre-write in Workbench only
10. Library metric editing disabled in V3
11. condition rename handled by compatibility mapping + UI badge
12. no cross-sample aggregate writeback in V3

---

## 15. V3 Completion Criteria

V3 is complete only when all are true:

1. AHE workflow can produce chart assets through unified plot layer.
2. All outputs are traceable via run manifests and run IDs.
3. Library can read Workbench results and sample measurement data without compute coupling.
4. Raw measurement files remain immutable.
5. Overwrite behavior prevents style-only artifact inflation.
6. Alias/rename semantics are visible in UI and safe in runtime reads.
