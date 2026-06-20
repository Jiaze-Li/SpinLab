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
