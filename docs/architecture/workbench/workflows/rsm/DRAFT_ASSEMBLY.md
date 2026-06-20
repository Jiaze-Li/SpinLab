# RSM Workflow — Draft Assembly Record

> **Status: draft / partially implemented.** This file captures the adapter rules and CanonicalRSMDataset contract target that must be satisfied before any RSM implementation begins. Gate H1 now has a Swift pack-state model; full restore remains deferred.

---

## RSM Workflow Architecture Rules

These rules apply to the future RSM (Raman Spectral Mapping or equivalent multi-instrument mapping) workflow and any workflow that ingests multi-lab or multi-instrument file formats.

### Adapter Rules

1. **All lab-specific and instrument-specific column mapping belongs in the RSM Input Adapter.** This includes: lab-specific column naming conventions, positional vs. named column schemes for different instruments, and unit prefixes that differ by instrument vendor.
2. **The RSM Input Adapter produces a `CanonicalRSMDataset`.** The dataset is the typed contract consumed by RSM analysis, RSM plot rendering, and RSM save. Its fields are in declared, stable workflow-domain units.
3. **Lab-specific column mapping must not enter the Main Board.** The Main Board mounts the RSM assembly; it does not branch on lab name, instrument vendor, or column variant.
4. **Lab-specific column mapping must not enter common plot modules.** Common plot shell, common legend, and common axis labels consume `CanonicalRSMDataset` field names and units, not raw instrument column names.
5. **Lab-specific column mapping must not enter common save modules.** Common save persists chart artifacts and the metric projection provided by the RSM Assembly; it must not read raw column names or infer RSM semantics.
6. **Multi-instrument format dispatch belongs inside the RSM Input Adapter.** If the RSM workflow accepts files from multiple instrument vendors, the adapter selects the appropriate parser based on file format signals (extension, header, sidecar kind). This dispatch is adapter-internal.

### CanonicalRSMDataset Contract (Target)

The `CanonicalRSMDataset` does not yet exist. Before any RSM parser is written, the Assembly must declare:

| Field | Meaning |
|---|---|
| Accepted file formats | RSM-specific formats per instrument vendor. |
| Parser entry points | One parser type per format variant; the adapter selects the appropriate parser. |
| Column / index mapping | Per-instrument mapping to canonical dataset fields. |
| Canonical field names and units | Declared stable names and units in `CanonicalRSMDataset`. |
| Adapter output type | `CanonicalRSMDataset` |
| Warning policy | Missing columns, unknown instrument format, ambiguous units — all surfaced as adapter warnings. |

---

## Stage 2 — Canonical Dataset Contract

**Pilot schema:** HKL Detector table (`H`, `K`, `L`, `Detector` columns).

**Status:** Contract accepted. Defines the stable domain representation that all downstream RSM layers (analysis, plot rendering, save) must build on.

---

### CanonicalRSMDataset — Field Definitions

| Field | Domain name | Mandatory | Notes |
|---|---|---|---|
| `h` | Miller index H | Yes | Dimensionless integer reciprocal lattice coordinate. Raw file column: `H`. |
| `k` | Miller index K | Yes | Dimensionless integer reciprocal lattice coordinate. Raw file column: `K`. |
| `l` | Miller index L | Yes | Dimensionless integer reciprocal lattice coordinate. Raw file column: `L`. |
| `intensity` | Diffracted intensity | Yes | Scalar count or detector signal. Derived from raw file column `Detector`. See Intensity Policy. |

No other fields are defined in v1. Future schemas (e.g. Q-space formats) must be evaluated separately before any new fields are added. Do not introduce speculative fields for axes not present in the pilot schema.

---

### Units Policy

- `h`, `k`, `l` are dimensionless. No unit conversion is applied. Values are stored as-is from the source file.
- `intensity` is stored in raw detector units (counts or detector signal). No normalisation is applied at ingestion time. Display scaling, if needed, belongs in the workflow renderer.
- The adapter must not perform any unit conversion beyond what is required to produce the fields above.

---

### Intensity Policy

- `intensity` is sourced from the `Detector` column of the HKL Detector table.
- The `Detector` column is the sole supported intensity source for the v1 schema.
- No derived intensity (e.g. log-scale, normalised) may be stored in `CanonicalRSMDataset`. Derived representations are computed at render time.
- If the `Detector` column is absent or unparseable, the adapter must emit a warning and must not produce a dataset.

---

### Supported Views

Three 2D slice views are supported in v1. Each view fixes one Miller index and plots the remaining two.

| View | Fixed index | Plot axes |
|---|---|---|
| HL | K fixed | H (x-axis), L (y-axis) |
| KL | H fixed | K (x-axis), L (y-axis) |
| HK | L fixed | H (x-axis), K (y-axis) |

**Default view:** HL (K fixed).

Q-space views (Qx/Qy/Qz) are explicitly out of scope for v1. Do not introduce axis abstractions (e.g. `axis1`/`axis2`/`axis3`) to pre-empt Q-space. If a real Q-space file format is introduced later, the CanonicalRSMDataset design will be revisited at that point.

---

### Warning Policy

The adapter must surface the following conditions as warnings. Warnings must not be silently swallowed:

| Condition | Warning |
|---|---|
| `Detector` column absent | "Intensity column 'Detector' not found — dataset cannot be produced." |
| Any mandatory column (`H`, `K`, `L`) absent | "Required column '\<name\>' not found — dataset cannot be produced." |
| Unknown or unsupported file schema | "File schema not recognised — no adapter matched." |
| Ambiguous column units or unexpected value range | "Column '\<name\>' has unexpected values — verify source file." |
| Rows with non-numeric values in mandatory columns | "Rows with non-numeric values in '\<name\>' were skipped." |

Warnings that prevent dataset production must halt ingestion. Warnings that affect data quality (e.g. skipped rows) allow ingestion to complete with the warning surfaced.

---

### Adapter Output Contract

Every RSM Input Adapter must:

1. Accept a raw file and produce exactly one `CanonicalRSMDataset` or fail with a structured warning.
2. Map raw file columns to the canonical field names defined above. The mapping is adapter-internal; it must not leak raw column names to any downstream layer.
3. Perform no analysis, no intensity normalisation, and no coordinate transformation. The adapter's only job is column mapping and type conversion.
4. Treat instrument vendor and lab identity as provenance metadata only. Provenance may be attached as opaque metadata on the dataset but must not influence the field values or the field set.
5. Dispatch on file schema (column names, header structure, file extension) — not on instrument vendor name.

The `CanonicalRSMDataset` is the sole output type. No adapter may produce an intermediate or vendor-specific representation for consumption by downstream layers.

---

## Gate H0 - RSM Heatmap Save/Pack/Restore Boundary Plan

This gate documents the boundary plan for saving, packing, and restoring the RSM heatmap workflow. It is docs-only and does not authorize Swift changes.

### 1. RSM Workflow-Owned Pack State

Gate H1 is implemented in `Sources/SpinLabApp/Workbench/V3/Heatmap/RSM/RSMPackState.swift`. The model carries only:

- `schemaVersion`
- `sourceFileIdentity` / `importedFileReference`
- `detectorColumnName`
- `activeView`

It intentionally omits renderer internals, layout, PNG bytes, heatmap tab overrides, and XY `TabRenderState` fields.

RSM owns the following persisted workflow state:

- `sourceFileIdentity` or `importedFileReference`
  - Opaque provenance for the source that produced the canonical dataset.
  - May be a filesystem identity, imported file reference, or other stable lookup token.
  - Pack stores the reference, not the file contents, parsed rows, or rendered output.
- `detectorColumnName`
  - The raw detector column name used by the adapter for the active schema.
  - This is persisted so restore can validate that the source schema still matches the saved workflow intent.
- `activeView`
  - One of `HL`, `KL`, or `HK`.
  - Default is `HL`.
  - The saved view determines which fixed index is restored for the heatmap projection.
- `parseOptions`
  - Any future RSM-specific parse knobs that affect adapter output.
  - V1 has no additional parse options beyond the schema contract above.
- `canonicalDatasetRestoreStrategy`
  - Restore must recover the canonical dataset by reopening the source or imported reference and re-running the RSM input adapter.
  - The canonical dataset itself is not the primary persisted artifact when it can be derived again.
  - If the source cannot be reopened, restore fails rather than inventing a replacement dataset.
- `rsmSpecificWarningsAndErrors`
  - Persist only normalized, workflow-owned restore diagnostics that explain why a pack restore may have degraded or failed.
  - Do not persist renderer exceptions, stack traces, or transient UI messages.
  - These diagnostics are informational only and must not alter renderer behavior.

### 2. Plot System Heatmap-Owned Display State

Heatmap display state is owned by Plot System and should live in a dedicated heatmap tab state, not in RSM semantics:

- `titleOverride`
- `xLabelOverride`
- `yLabelOverride`
- `zLabelOverride`
- `colorScaleMode`
- `colormapKey`
- `zRangeOverride`

These fields are display overrides only. They may be serialized for pack/restore, but they must not carry scientific meaning, file provenance, or adapter behavior.

### 3. Forbidden Persisted State

The following state must not be persisted for RSM heatmap save/pack/restore:

- Rendered PNG bytes.
- `HeatmapPlotLayout`.
- Any `CGContext` or other CoreGraphics render artifact.
- `WorkbenchPlotCanvas` transient UI state.
- XY `TabRenderState` fields.
- Duplicate copies of derived state unless a field is explicitly justified as primary workflow state.

If a value can be re-derived from the source file or canonical dataset, it should be re-derived on restore instead of duplicated in the pack.

### 4. Restore Sequence

Restore must follow this order:

1. Restore the RSM workflow state.
2. Recover or re-parse the canonical dataset from the saved source reference.
3. Rebuild `HeatmapPlotPayload`.
4. Apply `HeatmapTabRenderState` display overrides.
5. Call `HeatmapRenderPipeline`.
6. Produce `imageData`.
7. Show the result in `WorkbenchPlotCanvas` with `layout: nil`.

This sequence keeps scientific semantics in the workflow layer and display semantics in Plot System while ensuring the canvas remains a PNG shell only.

### 5. Failure Behavior

Restore and re-render failures must be explicit and non-silent:

- Missing source file
  - Fail restore with a clear missing-source error.
  - Do not synthesize placeholder data or a placeholder heatmap.
- Incompatible RSM file schema
  - Surface a schema mismatch warning or error.
  - Do not coerce the file into the saved view.
- Irregular grid after restore
  - Reject the restore result if the recovered data no longer forms a valid rectangular heatmap grid.
  - Surface a validation warning and do not render a partial grid.
- Invalid color scale or z-range
  - Ignore invalid display overrides.
  - Fall back to the default colormap and auto-derived z-range.
  - If the override cannot be normalized safely, fail only the heatmap render for that tab and surface a warning.
- Unsupported saved view
  - Treat the saved view as invalid if it is not one of `HL`, `KL`, or `HK`.
  - Fall back to `HL` only when the recovered dataset can still be projected safely.
  - Otherwise fail restore with a view-compatibility warning.

### 6. Ownership Rule

- RSM workflow must not serialize heatmap renderer internals, layout internals, or canvas internals.
- Heatmap display state must not serialize RSM scientific semantics such as adapter logic, detector resolution, or view-selection policy.
- Cartesian XY render path state and XY `TabRenderState` must not be reused for heatmap.

### 7. Next Implementation Gates

- Gate H1: RSM pack state model.
- Gate H2: `HeatmapTabRenderState` pack codec.
- Gate H3: restore integration tests.
- Gate H4: save-to-library bridge if needed.
