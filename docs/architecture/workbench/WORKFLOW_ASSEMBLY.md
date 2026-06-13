# Workbench - Workflow Assembly

> Workflow Assembly is the workflow-owned semantic contract consumed by the Main Board and implemented across workflow code.

## Core Principle

Workflow declares the analysis title / analysis type.
The workflow itself is not the Main Board and not a module.

Workflow Assembly declares workflow-specific semantic differences, overrides, contracts, and ownership.
Main Board stays generic and mounts common modules.
Common modules execute default shell/module behavior and should not be repeated in every Assembly record.

Adding a workflow means adding a new Workflow Assembly.

## What It Defines

| Contract field | Meaning |
|---|---|
| Workflow Identity / Search Hints | Stable workflow identity plus workflow-specific search aliases, prefixes, or optional secondary input search slots |
| **Input Adapter Contract** | **The adapter surface that converts raw instrument files into the workflow-domain dataset consumed by analysis. See Input Adapter Contract section below.** |
| Data / Physics Mapping | Raw-file formats, parser entry points, required fields, column/index mapping, unit conversion, derived quantities, and invalid-data behavior |
| Analysis Pipeline | Workflow-specific parse, ingest, transform/fit/scale, render-payload, metric, warning, and failure stages |
| Optional Contributions | Workflow-specific panels or module contributions mounted by the shell |
| Analysis Overlay | Workflow-specific display-only overlays from existing saved analysis packs; the workflow declares eligible tabs, pack/result requirements, labels, warnings, and saved-artifact policy |
| Plot Semantics / Overrides | Plot meanings that differ from common plot shell behavior: default axes, units, tabs, stacking, normalization, annotations, metrics, titles, and legends |
| Validation / Warning Policy | Workflow-specific warnings/errors for missing input, skipped series, ambiguous units, and data-quality failures |
| Persistence / Pack-Restore | Workflow-specific state required to interpret restored workspaces and saved results |
| Required Behavior Tests | Behavior classes that protect the workflow contract |

## What It Does Not Own

- Main Board layout
- Readiness
- Common search logic
- Selection logic
- Analyze lifecycle logic
- Save / Pack implementation
- Plot module internals
- Default module ownership
- Common module behavior and default shell behavior
- Scientific logic belongs inside the workflow's Physics Function contract, not inside the Main Board or default modules.
- **Raw file parsing** — the Main Board does not own raw file parsing. It mounts a workflow whose adapter handles file format differences before any common module or analysis pipeline stage sees the data.
- **Lab-specific column mapping** — instrument-specific column names, positional column indices, unit prefixes, and lab conventions must not leak into the Main Board, common plot shell, or common save module. All such mapping belongs inside the workflow's Input Adapter surface.

## Input Adapter Contract

Every Workflow Assembly must declare an Input Adapter surface. The adapter is the boundary between raw instrument files and the workflow-domain dataset. Workflow analysis (fit, scale, render, save) must only consume the adapter's output — not raw file bytes, raw column names, or instrument-specific units.

### Adapter Surface Fields

| Field | Meaning |
|---|---|
| Accepted file formats | File extensions and format variants the adapter recognizes. Unrecognized formats produce adapter warnings, not silent fallback. |
| Parser entry point | The parser type and function signature that converts a raw file to a typed parsed-file value. |
| Column / index mapping | How raw column names or positional indices map to workflow-domain semantic names. This mapping is adapter-owned. It must not be re-derived inside the ingestion use case or analysis stages. |
| Unit conversion | Unit transforms applied at the adapter boundary (e.g. Oe → T, nm → m). The workflow-domain dataset carries post-conversion values in declared units. Common plot and save modules must not perform or assume any additional unit transform. |
| Sidecar condition injection | How sidecar metadata (temperature override, file-kind override, shift, device) is applied at ingestion, before the workflow-domain dataset is finalized. |
| Adapter output type | The typed workflow-domain dataset produced by the adapter. This is the contract value consumed by all downstream analysis stages. |
| Warning policy | How parse errors, ambiguous columns, missing required fields, and fallback paths are surfaced. Adapter warnings must not silently succeed; they must reach the workflow's warning surface. |

### Invariants

1. **Main Board does not parse.** The Main Board mounts an assembly; it never reads raw instrument file bytes.
2. **Common modules consume adapter output only.** Common plot, common save, and common pack modules consume the workflow-domain dataset, not the parsed file or intermediate adapter state.
3. **Column mapping is adapter-owned.** The adapter declares the column mapping once. No other stage re-derives column names from raw headers.
4. **Unit conversion is adapter-owned.** The adapter emits values in declared workflow-domain units. Downstream stages must not re-apply or assume conversion.
5. **Warning policy is complete.** Every adapter failure path either produces a typed warning or throws a parse error; silent fallback to a different semantic meaning is forbidden.

### Adding a New Workflow

Adding a new workflow means adding an Input Adapter Contract section to its ASSEMBLY.md before any code is written. The adapter output type (the workflow-domain dataset struct) must be named and described in the ASSEMBLY.md before the parser file exists.

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

## Contract Reality

The contract below is idealized. The current repository implementation splits that contract across registry dispatch, workflow views, workflow stores, typed contracts, use cases, and regression tests.

| Layer | What it means |
|---|---|
| Ideal assembly contract | The abstract per-workflow fields listed above. |
| Current implementation surface | The concrete files that currently realize the workflow: registry, view, store, contracts, use cases, and tests. |
| Implicit current behavior | Fields that exist only as conventions or distributed behavior, not as a dedicated provider object or single contract type. |

## Current Implementation Surface

In this repository, the current implementation surface is realized across a small set of files:

- `Sources/SpinLabApp/Workflow/WorkflowDefinitionStore.swift` and `config/workflow.json` provide workflow display names and condition-field definitions.
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift` maps workflow IDs to concrete workspace views.
- `Sources/SpinLabApp/Features/Workbench/*WorkspaceView.swift` composes the shared shell with workflow-specific panels.
- `Sources/SpinLabApp/Features/Workbench/*WorkspaceStore.swift` and related extensions own analysis, rendering, persistence, and pack restore.
- `Sources/SpinLabApp/Workbench/V3/*PackContracts.swift` and `*IngestionContracts.swift` provide typed workflow snapshots and restore payloads.
- `Sources/SpinLabApp/UseCases/*` contains workflow-specific parsing, ingestion, rendering, fitting, and scaling helpers.
- `Tests/SpinLabAppTests/*` carries the workflow-specific regression coverage.

The per-workflow records under `workflows/*/ASSEMBLY.md` map those surfaces to concrete files and call out where the contract is explicit versus implicit.

## Secondary Input Search Slots

A Workflow Assembly may declare optional secondary input search slots. These are auxiliary file selectors that contribute to analysis but are not the Main Search result set. The slot contract is workflow-owned; the module only owns generic auxiliary slot mechanics and UI.

Current runtime behavior:
- `rtQuery` is passed through the generic `searchWorkflowMeasurements` path.
- Returned hits are assigned to `rtSearchResults` directly.
- Restore can rebuild or accept auxiliary sidecars whose workflow is currently `3w` or `rt`.

Target/future contract:
- A slot may declare allowed workflow IDs, file kinds, and search hints.
- The 3ω `rt` slot's semantic target is RT/Rxx(T), but runtime filtering and validation are not yet fully enforced.
- If future extraction depends on strict allowed-kind filtering, add explicit runtime guards and tests first.

| Contract field | Meaning |
|---|---|
| Slot ID | Stable workflow-owned key for the auxiliary slot. The module treats it as an opaque identifier. |
| Display label | User-facing label owned by the Workflow Assembly. The module must not invent a default semantic label. |
| Query default / search hint / workflow filter | Workflow-owned query prefix, hint text, and file/workflow filter rules that shape the auxiliary search. Current runtime does not yet enforce a strict RT-only whitelist for the 3ω instance. |
| Allowed workflow IDs / file kinds | Target contract uses an explicit whitelist of auxiliary hits the slot may accept; current 3ω behavior is still generic and must not be described as already RT-only filtered. |
| Selection mode | Single-select or multi-select, as declared by the Workflow Assembly. |
| Requiredness | Optional by default, or required only for workflow tabs/results that depend on the slot. |
| Analysis contribution | The selected auxiliary hit contributes input data only. It does not trigger analysis by itself and it does not define physics meaning. |
| Pack fingerprint | Whether auxiliary file identity participates in pack identity. This is workflow-specific and may be false for purely cosmetic auxiliary inputs. |
| Persisted fields | The slot may persist query text plus selected hit identity or stable sidecar/file identity. Session-only search results, messages, and running flags remain non-persistent unless the workflow explicitly says otherwise. |
| Restore bridge behavior | Restore may rebind the slot from a saved sidecar/file bridge. If the identity does not resolve, restore leaves the slot unbound and emits a workflow warning. |
| Warning behavior | Missing or invalid auxiliary input only warns through dependent workflow surfaces. It must not mutate Main Search state or silently fall back to a different semantic role. |
| Multiple-slot support | A workflow may declare zero, one, or many auxiliary slots. Each slot must remain independent and slot-scoped. |

Current concrete instance: 3ω declares one slot with `slot ID = rt`, `display label = RT / Rxx(T)`, single selection, and auxiliary RT file identity participation in pack fingerprint. This is the current runtime-compatible instance of the general optional Secondary Input Search pattern; runtime filtering is still generic and not yet an RT-only whitelist.

Current implementation surface for the 3ω instance lives in `ThreeOmegaWorkspaceStore.swift`, `ThreeOmegaWorkspaceStore+RTSelection.swift`, `ThreeOmegaWorkspaceView.swift`, `ThreeOmegaPackContracts.swift`, and `ThreeOmegaWorkspaceStore+Pack.swift`. The concrete runtime fields remain `rtQuery`, `rtSearchResults`, `rtSearchMessage`, `isRTSearching`, `selectedRTHit`, `pendingRTSidecarPath`, and `cachedRTFilePath`.

## Assembly Boundary

A Workflow Assembly is the workflow-owned semantic contract for the active workflow. The Main Board uses workflow declarations to mount or call modules, but common module behavior remains outside Assembly. Assembly should name only workflow-specific identity/search hints, data mapping, analysis behavior, optional contributions, plot overrides, persistence metadata, validation policy, and required behavior tests.

The current implementation does not have runtime Assembly objects. A valid Assembly record may therefore point to distributed implementation files instead of a single provider type. If code contradicts the ideal model, the record should state the contradiction rather than inventing a framework.

## Analysis Overlays

A Workflow Assembly may declare optional analysis overlays. Overlays are display-only contributions from existing saved analysis packs. They do not mutate the primary analysis result, do not create a combined pack, and remain session-only in the first version unless the workflow explicitly declares persistence.

| Contract field | Meaning |
|---|---|
| Supported tabs | Workflow-owned list of tabs that may show overlay chips or overlay series. |
| Eligible packs / result requirements | Workflow-owned whitelist of pack workflow IDs and result prerequisites. Packs missing required results are disabled or rejected clearly. |
| Snapshot-to-series mapping | Workflow-owned mapping from overlay result snapshots to plot series, fit lines, or other rendered plot artifacts. |
| Overlay labels | User-facing labels for overlay chips and series are workflow-owned. |
| Missing / invalid warnings | Workflow-owned warning policy for absent, invalid, or stale overlay packs. |
| Saved manifest / sample keys policy | Workflow/tab-specific provenance policy for saved chart artifacts. The Assembly decides whether overlay series or sample provenance participate in the saved artifact/manifest, and future overlay types must declare that policy explicitly before implementation. |
| Metric persistence policy | Workflow-owned decision on whether overlay-derived metrics are excluded from metric persistence. |

Current 3ω instance: RAHE tabs use the existing "Add Analysis" overlay surface. Target next instance: Scaling Law overlays that draw scaling data points and fit line(s) from saved 3ω packs with `scalingResult`; packs without that result should be disabled or rejected clearly.
