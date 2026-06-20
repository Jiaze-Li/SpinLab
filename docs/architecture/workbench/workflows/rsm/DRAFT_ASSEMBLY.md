# RSM Workflow — Draft Assembly Record

> **Status: future / not yet implemented.** This file captures the adapter rules and CanonicalRSMDataset contract target that must be satisfied before any RSM implementation begins. No RSM Swift code exists yet.

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
