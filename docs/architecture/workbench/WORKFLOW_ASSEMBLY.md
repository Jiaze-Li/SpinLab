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
| Saved manifest / sample keys policy | Workflow-owned decision on whether overlays affect saved chart manifests or sample keys. |
| Metric persistence policy | Workflow-owned decision on whether overlay-derived metrics are excluded from metric persistence. |

Current 3ω instance: RAHE tabs use the existing "Add Analysis" overlay surface. Target next instance: Scaling Law overlays that draw scaling data points and fit line(s) from saved 3ω packs with `scalingResult`; packs without that result should be disabled or rejected clearly.
