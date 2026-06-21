# Workbench — Sample Work Tracker

> Common Workbench read-model module. Provides a per-sample × per-workflow status
> summary derived from Library facts. Never writes to sidecars, never creates per-file
> status files, never mutates sibling modules.

---

## Purpose

The Sample Work Tracker answers the question "for each concrete sample identity, across
every known workflow, what is the processing state?" without requiring the user to open
individual workflow search panels.

Example target display:

```
PN70 B STO111
  3ω   │ todo     × 3 files
  IV   │ hasChart × 1 file
  AHE  │ noData
```

The tracker is a **read-only projection** of facts already present in the Library.
It does not run analysis, does not modify sidecars, and does not persist any derived
status to disk.

---

## Module Ownership

| Concern | Owner |
|---------|-------|
| Sample identity & sampleKey | `SampleKeyNormalizer` / `SampleSemanticDescriptor` (Import domain) — tracker consumes, never redefines |
| Sidecar facts | Inbox → Library write contract (tracker reads only) |
| Search hits | `SearchWorkflowMeasurementsUseCase` / `WorkbenchMainSearchRuntime` — tracker consumes hits as input |
| Plot index | `MeasurementPlotIndex` / `LoadMeasurementPlotIndexUseCase` — tracker reads, never writes |
| Workflow definitions | `WorkflowDefinitionStore` via `WorkbenchFeatureStore.workflowDefinitions` — tracker consumes, never modifies |
| Tracker read model | **This module** (`WorkbenchSampleWorkTrackerRuntime`) |
| Tracker UI | **This module** (`WorkbenchMeasurementsPanel` — replaces current placeholder) |
| Analysis invocation | Workflow workspace stores, reached through Main Board facade only |

---

## Data Sources

The tracker derives all status from existing Library facts. It never introduces new
persisted state in the MVP.

| Source | What it provides |
|--------|-----------------|
| `WorkflowMeasurementSearchHit[]` (from a full-library sidecar scan) | `sampleKey`, `workflowCanonicalID`, `workflowDisplayName`, `sourceFilePath` — the primary input for file counts and workflow membership |
| `MeasurementPlotIndex` (loaded per `sampleKey` on demand) | Which source files are chart-linked (i.e. have at least one saved chart) |
| `WorkflowDefinition[]` (from `WorkbenchFeatureStore.workflowDefinitions`) | Authoritative column list; drives display names for workflow columns |
| `LibraryPathResolver` | All artifact path construction; no hand-built paths permitted |

The tracker must be able to refresh from **all Library sidecars**, not only from the
current Workbench search results. It is a Workbench common module, not a feature of any
single workflow panel. Its data source is a full-library sidecar scan that it triggers
independently of the per-workflow search panels.

---

## Stable Keys

### Primary stable key — `sampleKey`

The canonical sample identity key as produced by `SampleKeyNormalizer` / written into
`WorkflowMeasurementSearchHit.sampleKey`.

Format: `"{batchID}|{processingTokens}|{material}|{orientation}"`
Example: `"PN70|B|STO|111"`

**Rule: never group by bare `batchID` alone.** One batch ID can contain multiple
substrate/treatment/sample identities. The tracker top-level row represents the concrete
sample identity, not the batch.

### Status unit key — `sampleKey × workflowID`

Status is computed per `(sampleKey, workflowCanonicalID)` pair. This is the atomic unit
the tracker displays, caches, and will later support manual override on.

### Unknown sampleKey handling

Hits whose `sampleKey` is empty or failed normalization are collected into a separate
"Unknown / Unmatched" bucket rendered at the bottom of the tracker. They are never merged
into a known-sampleKey row.

---

## Status Derivation

Status is derived from two counts per `(sampleKey, workflowCanonicalID)`:

| Term | Definition |
|------|-----------|
| `fileCount` | Distinct `sourceFilePath` values among hits for this `(sampleKey, workflowCanonicalID)` pair |
| `chartLinkedFileCount` | Number of those source files that appear in `MeasurementPlotIndex.entries` for this `sampleKey` |

Status rules (evaluated top-to-bottom, first match wins):

| Status | Condition |
|--------|-----------|
| `noData` | `fileCount == 0` |
| `todo` | `fileCount > 0` and `chartLinkedFileCount == 0` |
| `partial` | `fileCount > 0` and `0 < chartLinkedFileCount < fileCount` |
| `hasChart` | `fileCount > 0` and `chartLinkedFileCount == fileCount` |

**`fileCount` source:** grouped `WorkflowMeasurementSearchHit` values — not the plot
index. The plot index only proves chart linkage; it does not enumerate files.

**Missing plot index:** if `LoadMeasurementPlotIndexUseCase` returns `nil` (file absent
or corrupt), treat `chartLinkedFileCount = 0` for that sample. This is not an error; it
means no chart has been saved yet.

**Chart key enumeration:** `MeasurementPlotIndex.entries` maps source file name →
`[chartIdentityKey]`. The tracker does not need the chart identity keys themselves in the
MVP; it only needs to know whether a source file appears as a key in `entries`. Do not
call `allChartKeys()` if it does not already exist on the type. Compute
`chartLinkedFileCount` as `entries.keys.count` (after normalising file name to match
`hit.sourceFilePath` basename).

---

## Workflow Column List — Unknown Workflow Warning Strategy

Columns are driven exclusively by `workflowDefinitions`. They are never hardcoded.

If a hit carries a `workflowCanonicalID` that does not match any entry in
`workflowDefinitions`, the tracker must **not silently drop it**. Instead:

1. Collect all such unknown IDs per sampleKey into a separate "⚠ Unknown workflows"
   annotation on the sample row.
2. Log a warning once per unknown ID (deduplicated within a refresh cycle).
3. Do not create ad-hoc columns for unknown IDs — column set must remain stable and
   driven by definitions.

This ensures the user sees that data exists but cannot be categorised, rather than the
data silently disappearing from the tracker.

---

## Read Model Shape

```
SampleWorkSummary
  sampleKey: String                      — stable grouping key
  displayTitle: String                   — human-readable: "PN70 B STO111"
  workflowRows: [WorkflowWorkSummary]    — one entry per WorkflowDefinition
  unknownWorkflowIDs: [String]           — IDs in hits but absent from definitions
  lastRefreshedAt: Date

WorkflowWorkSummary
  workflowID: String                     — canonical ID (matches WorkflowDefinition.id)
  workflowDisplayName: String            — from WorkflowDefinition.displayName
  fileCount: Int                         — distinct sourceFilePath count from hits
  chartLinkedFileCount: Int              — from MeasurementPlotIndex.entries key coverage
  status: SampleWorkStatus

SampleWorkStatus                         — enum
  .noData                               — fileCount == 0
  .todo                                 — fileCount > 0, chartLinkedFileCount == 0
  .partial                              — 0 < chartLinkedFileCount < fileCount
  .hasChart                             — chartLinkedFileCount == fileCount
```

---

## Forbidden Mutations

The tracker must never:

- Write to any sidecar file (`SpinLabFileSidecar`)
- Create per-file or per-measurement status files
- Modify `MeasurementPlotIndex` or any other Library artifact
- Write to the canonical state of sibling modules (search, selection, plot, pack/restore)
- Call analysis or save use cases
- Bypass `LibraryPathResolver` for path construction

---

## UI Mount Point

The tracker UI replaces the existing empty Measurements placeholder in the Workbench
main board layout. It does not invent a new navigation shell or app window.

The panel lives in `WorkflowWorkspaceShell`'s Measurements injection point (or whichever
named slot `MAIN_BOARD_LAYOUT.md` designates for common capability panels). It must use
`WorkbenchUIStyle` tokens for spacing, typography, and colour — no custom design
language.

---

## Refresh Triggers

The tracker is a **Workbench common read-model module**, independent of any single
workflow search panel. It refreshes from all Library sidecars, not from a per-workflow
search result set.

Refresh is triggered by:

1. **Manual user action** — "Refresh" button in the tracker panel (primary MVP trigger)
2. **After chart save** — when a chart is saved to Library, the tracker is notified via
   the existing save-completion path and recomputes the affected `sampleKey × workflowID`
   status cell
3. **On module mount** — when the Measurements panel first becomes visible

The tracker does **not** auto-refresh on every search query in the workflow panels. Those
panels have independent state; their completion is not a tracker trigger.

---

## Analyze Selected — Cross-Module Boundary

The tracker may surface an "Analyze selected" action for a sample × workflow cell.
This must follow the correct boundary protocol:

1. Tracker passes the selected `WorkflowMeasurementSearchHit` slice to the **Main Board
   facade** (`WorkbenchFeatureStore`) via an explicit handoff method.
2. Main Board seeds the target workflow's Search module with the file list and seeds the
   Selection module with the hit IDs — through the existing `SelectionReading` / search
   seed APIs, not by directly writing to workflow stores.
3. Main Board then routes to the target workflow workspace.

The tracker must not:
- Directly call methods on `ThreeOmegaWorkspaceStore`, `AHEWorkspaceStore`, etc.
- Modify selection state directly
- Trigger analysis itself

---

## MVP Scope

- Domain models: `SampleWorkSummary`, `WorkflowWorkSummary`, `SampleWorkStatus`
- Builder use case: `BuildSampleWorkSummariesUseCase` (pure function, no side effects)
- Runtime: `WorkbenchSampleWorkTrackerRuntime` (`@MainActor @Observable`, holds summaries
  + refresh state, wired into `WorkbenchFeatureStore` as a lazy private var)
- UI: `WorkbenchMeasurementsPanel` (summary table; rows = samples, columns = workflow
  definitions; status badge + file count per cell)
- Refresh: manual refresh button + post-chart-save notification
- Unknown workflow warning annotation on sample rows
- Unknown sampleKey / empty-key bucket row

---

## Deferred Scope

- **Manual status overrides**: centralized override index, keyed primarily by
  `sampleKey::workflowID`; file-level overrides only for exceptions. Not in MVP.
- **Drilldown**: tapping a sample row expands to show per-workflow file list.
- **Analyze selected bridge**: full implementation (UI + Main Board handoff method).
- **Auto-refresh on Library file-system changes**: FSEvent-based invalidation.
- **Per-cell chart thumbnail preview**: once drilldown exists.
- **Export / reporting**: out of scope indefinitely until explicitly requested.

---

## Test Plan

Run targeted tests with `--filter SampleWorkTracker` before full `swift test`.

```
BuildSampleWorkSummariesUseCaseTests
  - empty hits → empty summaries
  - single sample, single workflow, no charts → status .todo
  - single sample, single workflow, all files chart-linked → status .hasChart
  - single sample, single workflow, partial coverage → status .partial
  - fileCount == 0 (no hits for workflow) → status .noData
  - two samples sharing same batchID but different sampleKey → two separate rows
  - hit with empty sampleKey → lands in unknown bucket, not in any sampleKey row
  - hit with workflowID absent from workflowDefinitions → unknownWorkflowIDs populated,
    no ad-hoc column created
  - nil plot index (file not found) → chartLinkedFileCount == 0 for all files

SampleWorkStatusTests
  - full derivation truth table: (fileCount, chartLinkedFileCount) → expected status
  - boundary: chartLinkedFileCount == fileCount - 1 → .partial not .hasChart
  - boundary: chartLinkedFileCount == fileCount → .hasChart not .partial
```

Use `withBundledRules` / `withTempRulesBook` harness helpers for any tests that touch
condition resolution. Do not run full `swift test` until all targeted tests pass.

---

## Code Map Placeholders

```
Domain/SampleWorkTracker/
  SampleWorkSummary.swift              — SampleWorkSummary, WorkflowWorkSummary structs
  SampleWorkStatus.swift               — SampleWorkStatus enum + derivation logic

UseCases/
  BuildSampleWorkSummariesUseCase.swift  — groups hits, loads plot indices, derives status
  LoadSampleWorkSummaryUseCase.swift     — per-sample refresh (post-chart-save path)

App/State/
  WorkbenchSampleWorkTrackerRuntime.swift  — @MainActor @Observable runtime, lazy var in
                                            WorkbenchFeatureStore

Features/Workbench/
  WorkbenchMeasurementsPanel.swift         — replaces current Measurements placeholder
  WorkbenchMeasurementsSampleRow.swift     — one sample row (title + workflow cells)
  WorkbenchMeasurementsWorkflowCell.swift  — one status badge + count cell

docs/architecture/workbench/modules/
  SAMPLE_WORK_TRACKER.md               — this file
```

---

No Swift code changed.  
Recommended next task: Step 2 — domain models (`SampleWorkSummary`, `WorkflowWorkSummary`, `SampleWorkStatus`).
