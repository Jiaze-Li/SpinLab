# Workbench — Main Board, Layout Host, Modules, and Workflow Assembly

> Architecture model: one Main Board + Layout Host + reusable Modules + per-workflow Workflow Assembly + Regression Gates.

## Purpose

This document defines the canonical Workbench architecture model and the boundaries between its top-level concepts:

- **Main Board** — the single persistent shell that hosts all workflows
- **Layout Host** — the Main Board's internal UI mounting infrastructure; owns region assignment and physical placement
- **Module** — a reusable functional capability mounted by the Layout Host; owns its own functionality and state
- **Module Group** — an organizational grouping of related modules within the Main Board; no functional authority
- **Workflow Assembly** — per-workflow configuration consumed by the Main Board; does not own layout

It is intentionally narrower than `modules/PLOT_SYSTEM.md`, `modules/PACK_RESTORE.md`, and `EXTENSION_BOUNDARIES.md`.

## Architecture Model

```
Main Board
├── Layout Host (UI mounting infrastructure)
│   ├── Search Region
│   ├── Selection Region
│   ├── Analysis Controls Region
│   ├── Plot Region
│   ├── Plot Controls Region
│   ├── Warning Region
│   ├── Status Region
│   └── Save/Pack Region
├── Default Modules (always loaded)
│   ├── Search
│   ├── Selection
│   ├── Analyze Lifecycle
│   ├── Result Header
│   ├── Plot Display
│   ├── Plot Controls
│   ├── Plot Preservation
│   ├── Save
│   ├── Pack/Restore
│   ├── Trace
│   ├── Warning
│   └── Status
└── reads → Workflow Assembly (per workflow)
    ├── Workflow Identity
    ├── Physics Function
    ├── Workflow Parameters
    ├── Plot Defaults
    ├── Optional Modules
    ├── Save Metadata Provider
    ├── Pack Metadata Provider
    └── Required Tests
```

## One Main Board

There is exactly one Main Board.

Switching workflows does NOT switch boards. The Main Board:

- stays loaded across workflow switches
- reads the selected workflow's Assembly to configure itself
- keeps all default modules loaded at all times
- mounts/unmounts optional modules declared by the active Workflow Assembly
- switches Physics Function, Workflow Parameters, Plot Defaults, and metadata providers when the active workflow changes
- detects region/order/exclusive conflicts between mounted modules

This is the central constraint that distinguishes the model from a "per-workflow board" approach.

## Why One Main Board

Workbench workflows are similar in shell structure but not in scientific meaning.

One Main Board is preferred because:

- AHE, XY Rotation, and 3ω share lifecycle shape but differ in analysis semantics.
- UI reuse is useful at the module level, not at the domain-logic level.
- A per-workflow board would force duplicated shell scaffolding and make future workflow onboarding harder.
- The Main Board stays readable as a composition layer; it does not absorb domain logic from any workflow.

The goal is reuse by module, not by centralizing every workflow behavior behind one orchestrator.

## Main Board Lifecycle

The Main Board drives a 6-stage lifecycle that is uniform across all workflows:

| Stage | Main Board action | Store call |
|---|---|---|
| Search | Renders search bar + action bar; executes search | `WorkbenchFeatureStore.runWorkflowMeasurementSearch()` |
| Select | User selects results from list | (selection state in store) |
| Analyze | Renders Analyze button | `store.runAnalysis()` → ingests + renders + calls `commitRunTrace()` |
| Save | Renders Save to Library button | `store.persistToLibrary()` |
| Pack load | Renders Load Pack popover | `store.restoreFromPack()` → uses `_rerenderActiveTab()` / `_rerenderAllTabs()` |
| Clear | Renders Clear / Clear Plot buttons | `store.clearResults()` / `store.clearPlot()` |

## Core Definitions

### Main Board

The Main Board is the single persistent shell that owns module composition and hosts the Layout Host as its internal UI mounting infrastructure.

Responsibilities:

- hosts the Layout Host, which owns the two-column UI mounting infrastructure
- reads the active Workflow Assembly to configure per-workflow behavior
- mounts/unmounts optional modules declared by the Assembly on workflow switch
- merges workflow Physics Function output with module-level user overrides into the active plot surface
- detects region/order/exclusive conflicts
- enforces module isolation boundaries

The Main Board does not interpret scientific data.

Current implementation: `WorkflowWorkspaceShell`.

#### WorkspaceStore Protocol Contract

Each workflow store conforms to `WorkbenchWorkspaceProviding`, which inherits:
- `WorkbenchPlottingStore` — plot display state and rendering surface
- `AnalysisPackProviding` — pack save/restore lifecycle
- `ActiveChartProviding` — Save Metadata Provider surface

Must implement: selection, execution, rerender, clear, trace, persistence.  
Default implementations provided by the protocol: `appendWarning()`, `commitRunTrace()`.

Warning panel: `WorkbenchWarningLog` coalesces identical (source, message) pairs. Reruns of analyze / load / scaling never stack duplicate entries.

### Module

A Module is a reusable functional capability that the Layout Host mounts on the Main Board. Modules own their functionality and state. No sibling module may read or mutate another module's owned state directly.

Module classification:
- **Default modules**: always loaded by the Main Board, regardless of active workflow.
- **Optional modules**: declared by a specific Workflow Assembly; the Main Board mounts/unmounts them on workflow switch.

A module may declare layout metadata:
- **defaultRegion**: the layout region where it prefers to mount
- **order**: its preferred position within the region
- **exclusive**: whether it occupies the region exclusively or shares it
- **layoutMode**: how the module sizes itself within the region (e.g., compact, expanded, fill)
- **sizePolicy**: preferred minimum/maximum size constraints

A module is not classified as "common" or "workflow-specific" in its own definition. The default/optional distinction belongs to the mounting decision, not the module definition.

### Module Group

A Module Group is an organizational grouping of related modules within the Main Board.

Module Groups have no functional authority. They do not own state, execute logic, or gate behavior. Their only purpose is to control presentation order and visual grouping within the Main Board.

A Module Group is not a Module. It cannot appear in a Workflow Assembly's optional module list and cannot be addressed as a communication surface.

### Layout Host

The Layout Host is the Main Board's internal UI mounting infrastructure. It owns the physical placement of all modules on screen.

The Layout Host is not a feature. Modules provide features; the Layout Host provides the regions where modules are mounted.

Responsibilities:
- owns the two-column layout regions
- receives each module's declared layout metadata (`defaultRegion`, `order`, `exclusive`, `layoutMode`, `sizePolicy`)
- assigns modules to regions and detects conflicts
- is authoritative over all physical placement decisions

The Workflow Assembly does not override region assignments. The Layout Host is the sole authority over UI mounting.

Layout regions:
- Search Region
- Selection Region
- Analysis Controls Region
- Plot Region
- Plot Controls Region
- Warning Region
- Status Region
- Save/Pack Region

#### Layout Region Injection

The Layout Host exposes four injectable layout regions where the Workflow Assembly places optional module content via `WorkflowWorkspaceShell`:

| Injection point | Region | Example content |
|---|---|---|
| `searchExtra` | Search Region extra | RT file picker (3ω) / empty |
| `plotControls` | Plot Controls Region | `WorkbenchStandardPlotControls` or workflow-specific |
| `leftExtra` | Analysis Controls Region bottom | Geometry panel (3ω) / empty |
| `rightExtra` | Plot Region right panels | Scaling results panel (3ω) / empty |

These are the concrete injection interface; the Layout Host owns the region structure around them.

### Workflow Assembly

A Workflow Assembly is the per-workflow configuration consumed by the Main Board.

A Workflow Assembly is **not** a separate board. It is a configuration the Main Board reads to adapt itself for the active workflow.

**A Workflow Assembly does not own layout.** It declares which optional modules the Main Board should mount — not where those modules are placed. Layout placement is owned exclusively by the Layout Host.

| Component | Responsibility |
|---|---|
| Workflow Identity | stable workflow ID and registration metadata |
| Physics Function | scientific/physical analysis: parsing, calculations, payload, metrics, pack content |
| Workflow Parameters | workflow-specific UI parameters (fit ranges, geometry, RT selection, etc.) |
| Plot Defaults | display parameter subset — answers "how should this workflow's result be displayed by default?" |
| Optional Modules | modules the Main Board should mount for this workflow |
| Save Metadata Provider | answers "how should a saved result/chart be interpreted later?" |
| Pack Metadata Provider | answers "how should the whole workflow workspace be restored later?" |
| Required Tests | regression gates the workflow must pass |

### Physics Function

The Physics Function belongs **inside** Workflow Assembly.

It owns:
- parsing and ingestion
- scientific calculations and inference
- payload construction
- metrics and warnings
- workflow-specific pack content

The Physics Function does not own:
- shell UI (search area, selection area, save button, plot controls, pack UI)
- plot canvas interaction
- tab override state
- Save Metadata Provider or Pack Metadata Provider (those are separate Assembly components)

Shell modules may present Physics Function output, but must not own its semantics.

#### Physics Function Handoff to Analysis Lifecycle Module

| Physics Function output | Consumed by |
|---|---|
| `*IngestionResult` | Analysis Lifecycle Module → workflow output caches |
| computed result caches (fits, scaling, renders) | Analysis Lifecycle Module → plot-ready projection |
| warnings | Analysis Lifecycle Module → `WorkbenchWarningLog` |
| trace data | Analysis Lifecycle Module → `currentRunTrace` (committed on `runAnalysis()` success only) |
| plot payload / manifest | Analysis Lifecycle Module → Plot Display Module / Plot Preservation Module |
| pack-relevant result state | Analysis Lifecycle Module → Save / Pack modules via stable post-analysis state |

Save Metadata Provider protocol surface: `ActiveChartProviding` (defined in `WorkflowWorkspaceProvider.swift`). All three workflow stores conform.

### Plot Defaults

Plot Defaults belong **inside** Workflow Assembly.

Plot Defaults are the display parameter subset of Workflow Parameters. They answer: "how should this workflow's result be displayed by default?"

Plot Defaults are consumed by plot-related modules:
- Plot Display
- Plot Controls
- Preservation
- Multi-tab
- Overlay
- Shift
- Scaling

Plot Defaults are not Save Metadata and not Pack Metadata.

### Save Metadata Provider

The Save Metadata Provider belongs **inside** Workflow Assembly.

It answers: "how should a saved result/chart be interpreted later?"

It is not a top-level peer of Main Board or Module.

### Pack Metadata Provider

The Pack Metadata Provider belongs **inside** Workflow Assembly.

It answers: "how should the whole workflow workspace be restored later?"

It is not a top-level peer of Main Board or Module.

### Standard Result

Standard Result is the shell-facing contract that lets a Physics Function's output be rendered, saved, restored, and traced without the Main Board needing to know the workflow's physics.

Minimum responsibilities:

- carry the ingestion snapshot needed for restore
- expose renderable payload / layout state
- carry warnings and trace data
- carry pack config / result data
- allow tab-level rerender and save/restore flows

Standard Result is an envelope, not a domain model replacement.

### Active Plot Surface

Active Plot Surface is the shell-facing projection consumed by plot and save surfaces.

It includes:

- active image data
- active layout
- active manifest payload
- active override projections for the active tab

Ownership rule:

- `TabRenderManager` owns canonical render state and outputs.
- Modules consume projections; they do not own canonical render outputs.

### Regression Gate

A Regression Gate is a test-backed boundary that must stay true while shell extraction progresses.

Each gate must include:

- explicit contract statement
- ownership boundary
- regression tests bound to that boundary

Canonical phase progress for regression gates is tracked in [`WORKBENCH_ROADMAP.md`](WORKBENCH_ROADMAP.md).

## Module Inventory

Default modules are always loaded by the Main Board. Optional modules are mounted per Workflow Assembly declaration.

### Default Module Inventory

| Module | Current Implementation | Purpose |
|---|---|---|
| Search | `SearchShell` | measurement search surface and query presentation |
| Selection | `SelectionShell` | selection state presentation and selection actions |
| Analyze Lifecycle | `AnalyzeLifecycleShell` | analyze / rerun / lifecycle gating |
| Result Header | `WorkbenchResultHeaderShell` | result action header, clear/save/pack entry points |
| Plot Display | `PlotShell` | shared plot canvas surface and render presentation |
| Plot Controls | `PlotControlsShell` | controls affecting plot presentation or tab rendering |
| Plot Preservation | `TabRenderManager` | user override persistence and render output consistency across all rerender paths |
| Save | `SaveShell` | save-to-library presentation and entry points |
| Pack/Restore | `PackRestoreShell` | pack load / restore presentation and restore entries |
| Trace | `TraceShell` | last-run trace presentation |
| Warning | `WarningShell` | warning presentation and warning log display |
| Status | `StatusShell` | current status and lightweight progress |

### Optional Module Examples

| Module | Workflow | Purpose |
|---|---|---|
| Scaling | 3ω | scaling law computation |
| Overlay | 3ω | chart overlay for multi-run comparison |
| Shift | 3ω (optional) | per-curve stack offset |
| Multi-tab | 3ω | multi-tab render semantics |

### Module Groups

| Module Group | Members |
|---|---|
| Plot System | Plot Display, Plot Controls, Plot Preservation |

Module Groups control presentation grouping only and have no functional authority. Full Plot System Module Group details: [`modules/PLOT_SYSTEM.md`](modules/PLOT_SYSTEM.md).

### Search Module

Owns the shared measurement search surface and query presentation.

#### Search Module Contract (Phase 5A)

The Search module owns workflow-keyed search lifecycle state in the shell layer:

- `queryText`
- `searchResults`
- `isRunning`
- `statusMessage`
- workflow-keyed partitioning of all four state classes

The Search module does not own:

- `selectedSearchResultIDs` (Selection module state)
- workflow scientific analysis state
- plot payload/layout/image output
- title/legend/axis overrides
- rerender/preservation state (`TabRenderState` / `TabRenderOutput`)

Reset and lifecycle rules:

- route switch preserves search state by workflow key by default
- canonical clear entry is `clearSearch` (resets query/results/message/running)
- workflow-local `clearResults` is not canonical Search module clear

Forbidden dependencies:

- Plot controls/title/legend/rerender must not read or write Search module state
- Search module must not depend on tab render state, manifest payload, or image/layout output

Current migration note:

- `searchResults` is still mirrored into workflow-local `cachedSearchResults`
- this bridge is temporary for workflow ingestion/pack flows
- future extraction should replace mirrored caches with one shell-facing adapter/read surface

### Selection Module

Owns selection state presentation and selection actions.

#### Selection Module Contract (Phase 5C-1A)

The Selection module owns workflow-keyed selection lifecycle state in the shell layer:

- `selectedSearchResultIDs`
- `toggleSearchHitSelection`
- `selectAll` / `deselectAll`
- `selectedCount` and `isAllSelected` projection
- run-scoped `selectedHitsSnapshot` consumed at analysis entry

Selection module boundary with Search module:

- Search module owns hit-list/query lifecycle
- Selection module owns selected IDs
- Selection module consumes hit identities from `WorkbenchSearchSnapshot`
- Selection module must not mutate query/results/running/message except through explicit Search module API

Selection module does not own:

- search query text
- search result generation
- search running/loading/message state
- plot payload/layout/image output
- title/legend/axis override state
- rerender/preservation state (`TabRenderState` / `TabRenderOutput`)
- workflow scientific calculation

Select All denominator rule:

- Selection module must define one explicit denominator source per run/path.
- Current transition behavior still uses workflow-local `cachedSearchResults` as the denominator.
- Migration target is canonical `WorkbenchSearchSnapshot.results` or an explicit selection source surface.

Clear semantics:

- `clearSelection` clears selected IDs only.
- `clearSearch` belongs to Search module.
- current workflow-local `clearResults` is legacy mixed behavior and not the Selection module clear contract.
- 3ω `clearResults` includes RT-side cleanup; this is workflow-specific cleanup, not generic Selection module behavior.

Current transition note:

- `selectedSearchResultIDs` still lives in workflow stores for AHE / XY / 3ω.
- `cachedSearchResults` still acts as local mirror / selection denominator / pack compatibility.
- this split is temporary until Selection module extraction and Pack/Restore contract stabilization.

### Analyze Lifecycle Module

Owns the generic run lifecycle for all workflows on the Main Board.

#### Analysis Lifecycle Module Contract (Phase 5D)

**Inputs:**

- `WorkbenchSelectedHitsSnapshot` — run-scoped selected-hit snapshot consumed at analysis entry
- Workflow Assembly parameters — workflow-specific parameters passed into the Physics Function
- Plot Defaults — consumed where needed for initial display configuration
- Legacy nil-snapshot fallback for restore/compatibility paths only

**Outputs:**

- Running / loading state (`isAnalyzing`, `isPlotRendering`, task handles)
- User-facing message / error state (`analysisMessage`, `plotMessage`)
- Warning log (via `WorkbenchWarningLog`)
- Run trace (`currentRunTrace`)
- Workflow result / output state (`ingestionResult` and workflow-specific result caches)
- Plot-ready output projection (consumed by Plot Display Module and Preservation Module)
- Save/pack-ready handoff data (stable post-analysis state consumed by Save Module and Pack/Restore Module)

**Allowed mutations:**

- analysis running / message state
- warning log through `WorkbenchWarningLog`
- trace after successful analysis
- workflow output caches (ingestion result, computed caches)
- tab render outputs and manifest payloads
- active pack / save bookkeeping when tied to a new analysis result

**Forbidden mutations:**

- canonical Search Module state (`queryText`, `searchResults`, `isRunning`, `statusMessage`)
- selected IDs except through explicit selection actions
- tab override ownership except through the Preservation Module
- save-to-library writes during analysis
- pack vault writes during analysis
- trace commits from rerender or restore paths

#### Clear / Reset Semantics

- `clearSearch` belongs to Search Module
- `clearSelection` belongs to Selection Module
- `clearAnalysis` / `clearPlot` belong to Analysis Lifecycle Module
- workflow-specific extras (e.g., 3ω RT search cleanup on `clearResults`) are workflow-owned behavior inside the Physics Function; not generic Analysis Lifecycle Module behavior

#### Handoff Rules

- Analysis Lifecycle Module outputs plot-ready state to Plot Display Module and Preservation Module
- Save Module consumes stable post-analysis output only; must not re-trigger analysis
- Pack/Restore Module target: consume a stable analysis-result envelope rather than ad hoc workflow store internals (deferred; see current note below)

#### Current Implementation Note

- AHE, XY Rotation, and 3ω still implement lifecycle logic inside workflow stores (`AHEWorkspaceStore`, `XYRotationWorkspaceStore`, `ThreeOmegaWorkspaceStore`)
- Phase 5D-1 boundary tests lock current cross-module behavior at these boundaries
- Future work may introduce `AnalysisRunContext` / `AnalysisResultSnapshot` as a stable handoff envelope; extraction deferred until contract and tests are stable

### Result Header Module

Owns the shared result action header, including clear, save, and load-pack entry points.

### Plot Display Module

Owns the shared plot canvas surface and render presentation.

### Plot Controls Module

Owns controls that affect plot presentation or tab rendering.

This module is common infrastructure, not workflow semantics. It hosts shared plot configuration patterns but must not absorb workflow-specific meaning.

The Plot Controls module must not mutate Search module query/result/running/message state.

### Save Module

Owns the generic save-to-library flow for all workflows on the Main Board.

#### Save Module Contract (Phase 5E)

**Inputs:**

| Input | Source |
|---|---|
| Active chart PNG | Preservation Module — `TabRenderManager.activeImageData` projection |
| Active manifest payload | Preservation Module — `TabRenderManager.activeManifestPayload` projection |
| Active sample keys | Workflow Assembly Save Metadata Provider (`activeChartSampleKeys`) |
| Active metrics | Workflow Assembly Save Metadata Provider (`buildActiveChartMetrics()`) |
| Library root path | Infrastructure — set by search flow; read by Save Module as write target |

**Outputs / allowed mutations:**

- `persistenceOutcome` — set after every `persistToLibrary()` call; nil on `clearPlot()`
- Save status / message — save result written to a status field (current: `plotMessage` for AHE, `analysisMessage` for XY / 3ω; target: dedicated `saveMessage` field — deferred to Phase 5E-3)
- `currentRunTrace` — updated from `outcome.trace` after save; this is the save-side trace update, distinct from the analysis-side `commitRunTrace()` call
- `refreshRelatedCharts()` — called after successful or partial save to refresh related charts sidebar (current: present in XY + 3ω; missing in AHE — tracked as Phase 5E-3 fix)
- Workflow-specific post-save cleanup — permitted only inside the Workflow Assembly Save Metadata Provider (example: AHE `pendingMetricOverride` / `pendingRAHEOverride` clearing after save)

**Forbidden mutations:**

- canonical Search Module state (`queryText`, `searchResults`, `isRunning`, `statusMessage`)
- `selectedSearchResultIDs` or `cachedSearchResults`
- tab override state (`TabRenderState` / `tabStates`) owned by Preservation Module
- `ingestionResult` or any workflow output cache
- pack vault state (`activePackID`, vault contents)
- analysis trigger or plot re-render
- `commitRunTrace()` — this is analysis-side only; Save Module writes `currentRunTrace` directly from `outcome.trace`

**Relation to Preservation Module:**

- Save Module reads PNG and manifest payload exclusively through `TabRenderManager` projections (`activeImageData`, `activeManifestPayload`).
- Save must not bypass `TabRenderManager` to obtain render output.
- The Preservation Module's output consistency invariant guarantees PNG and manifest payload are coherent within the same `TabRenderOutput`; Save Module relies on this invariant.

**Relation to Analysis Lifecycle Module:**

- Save Module reads stable post-analysis caches (`activeChartSampleKeys`, metric caches) set during analysis.
- Save must not re-trigger analysis.
- `currentRunTrace` is shared between Analysis Lifecycle and Save Module, but each writes at a different lifecycle point:
  - Analysis Lifecycle writes via `commitRunTrace()` after `runAnalysis()` success.
  - Save Module writes from `outcome.trace` after `persistToLibrary()` success.
  - Both writes are intentional and ordered; the trace reflects the last persisted artifact after a save.

**Relation to Workflow Assembly Save Metadata Provider:**

The Save Metadata Provider is the per-workflow component inside the Workflow Assembly that answers "how should a saved result be interpreted later?" It supplies:

- `activeChartSampleKeys` — workflow-specific; example: 3ω overlay tabs merge overlay pack sample keys into `cachedSampleKeys`
- `buildActiveChartMetrics()` — workflow-specific; example: AHE returns Hc + R_AHE entries with user override info; 3ω returns scaling metrics (alpha, beta, r²) when on the scaling tab; XY returns empty (deferred)
- workflow-specific post-save cleanup hooks (example: AHE clears `pendingMetricOverride` / `pendingRAHEOverride` on save success)

This logic stays inside the Workflow Assembly and must not be promoted into the generic Save Module.

Current protocol surface for the Save Metadata Provider: `ActiveChartProviding` (defined in `WorkflowWorkspaceProvider.swift`). All three workflow stores conform.

**Relation to Pack / Restore Module:**

- Save writes chart + metric artifacts to the Library (`persistenceOutcome`).
- Pack / Restore saves and restores full workspace state to the vault (`activePackID`, vault contents).
- These are distinct operations that must not mutate each other's canonical state.

**Current implementation note:**

- `persistToLibrary()` still lives in each workflow store (`AHEWorkspaceStore`, `XYRotationWorkspaceStore`, `ThreeOmegaWorkspaceStore+Persistence`).
- `SaveActiveChartToLibraryUseCase` is already a generic, workflow-agnostic write path.
- Phase 5E-2 boundary tests will lock current save-boundary behavior before any extraction.
- Shared save coordinator / `SaveRequest` extraction is deferred until tests are stable (Phase 5E-3+).

### Pack/Restore Module

Owns pack load / restore presentation and restore entry points.

### Trace Module

Owns last-run trace presentation.

### Warning Module

Owns warning presentation and warning log display.

### Status Module

Owns current status and lightweight progress presentation.

## Plot Controls Module vs Workflow-specific Optional Modules

The Plot Controls module is for controls that are structurally common across workflows.

Workflow-specific optional modules (declared in the Workflow Assembly) are for controls that are semantically tied to one workflow.

Examples:

- Plot Controls module: tab switcher, legend-related display control, generic plot style toggles
- Workflow-specific optional module: AHE metric override, XY phi offset / detrend, 3ω RT and fit-range control

The rule:

- if the control changes generic plot presentation → Plot Controls module
- if the control changes workflow meaning → workflow-specific optional module declared in the Workflow Assembly

## Module Mounting Rules

1. Default modules are loaded by the Main Board automatically.
2. Workflow Assembly does not repeat default modules in its optional module list.
3. Workflow Assembly only declares optional modules it needs. Layout placement is owned by the Layout Host, not the Assembly.
4. Optional modules use their declared `defaultRegion`. The Layout Host is authoritative over all region assignments.
5. The Main Board must detect and report region/order/exclusive conflicts.

## New Workflow Onboarding

When adding a new workflow (e.g., SOT), classify as New Workflow / Workflow Assembly creation and follow these steps:

1. **Draft Physics Function**: define physical model, inputs, outputs.
2. **Confirm with user**: physical definition, measurement inputs, expected outputs.
3. **Default modules attach automatically**: no action needed for Search, Selection, Analyze Lifecycle, Result Header, Plot Display, Plot Controls, Plot Preservation, Save, Pack/Restore, Trace, Warning, Status.
4. **Select optional modules**: determine which optional modules the workflow needs (e.g., Shift, Scaling, Overlay, Multi-tab).
5. **Define Plot Defaults**: how should this workflow's result be displayed by default?
6. **Define Save Metadata Provider**: how should a saved chart be interpreted later?
7. **Define Pack Metadata Provider**: how should the whole workspace be restored later?
8. **Add Required Tests**: what regression gates must the workflow pass?
9. **Implement**: see [`EXTENSION_BOUNDARIES.md`](EXTENSION_BOUNDARIES.md) for the implementation checklist.

## Plot Preservation Module (Phase 4)

The Plot Preservation Module is part of the **Plot System Module Group**.

Phase 4 is one concrete module contract. It is not a full workflow protocol and does not define Search, Selection, or Save contracts.

### What it owns

- `titleOverride`, `xLabelOverride`, `yLabelOverride` — per-tab display label overrides
- `seriesLabelOverrides` — per-series display name renames keyed by sampleID
- `legendPoint` — user-dragged legend position
- `seriesOrder` — user-specified bottom-to-top curve order
- Consistency of `imageData` / `layout` / `manifestPayload` within a single `TabRenderOutput`

All of the above are stored in `TabRenderState` (keyed per tab) inside `TabRenderManager`. That is the single source of truth.

### The rule

1. **No override drop** — user overrides survive all rerender paths. Only `clearPlot()` may wipe them.
2. **No cross-tab bleed** — a rerender of tab A must not alter overrides or outputs for tab B.
3. **Output consistency** — `imageData`, `layout`, and `manifestPayload` must reflect the same render call. A stale manifest with a fresh PNG is a violation.

### Ownership split

The Main Board owns preservation. The Physics Function owns scientific output.

- **Main Board**: reads overrides from `TabRenderState`, applies them in the pipeline input, writes the unified result to `TabRenderOutput`. Never calls `clearStates()` from a rerender or analysis path.
- **Physics Function**: produces the default plot payload from ingestion data. Does not own or mutate override state. Does not hand-roll manifest/payload rewriting outside the `TabRenderManager` / pipeline path.

### New-workflow requirements

Any new workflow added to Workbench must:

1. Use `TabRenderManager` as the single owner of override state and render output.
2. Never call `clearStates()` from `runAnalysis()` or any automatic rerender path.
3. Apply overrides from `tabStates` in every rerender path — `rerenderForStyleChange()`, pack restore, and any workflow-specific rerender variant.
4. Add or extend preservation tests covering override survival, cross-tab isolation, and output consistency. Follow the pattern in `V537WorkflowShellPhase4Tests` and `V563WorkflowStateBoundaryTests`.

Canonical phase status: [`WORKBENCH_ROADMAP.md`](WORKBENCH_ROADMAP.md).

## Module Isolation (Phase 3)

Modules are siblings inside the Main Board. They must be independent.

**Rule:** Sibling modules must not directly depend on each other's outputs or mutate each other's state. Cross-module composition belongs exclusively in the Main Board.

### Specific Constraints

- Title controls must not read or affect search/selection state.
- Legend controls must not read or affect title state.
- Axis label controls must not read or affect legend or title state.
- Search/selection state must not be reset or modified by any plot-control change.
- No sibling module should rebuild or replace another sibling module's state.

### Composition Model

Physics Function output and user overrides are maintained separately:

- `defaultPlotPayload` — produced by the Physics Function; carries computed chart content.
- `titleOverride` — owned by the title module; carries user-specified title text.
- `legendOverride` — owned by the legend module; carries user-specified legend position/visibility.
- `axisLabelOverride` — owned by the axis-label module; carries user-specified axis label text.
- `seriesOrder` — owned by the series-order module; carries user-specified series ordering.

The **Main Board** is the only place where these are merged into a single display payload. No sibling module should merge them itself.

### Forbidden Patterns

- Legend module reads `searchQueryTexts` or triggers a search reset.
- Title module subscribes to legend state or canvas layout output.
- Plot-controls change clears `selectedSearchResultIDs`.
- Any module constructs the merged display payload that another module should own.
- Save module mutates canonical Search or Selection state.
- Analysis module mutates canonical search state (`queryText`, `searchResults`, `isRunning`, `statusMessage`).
- Selection module mutates plot payload.
- Optional modules directly read or write each other's internal state.
- Pack / Restore silently overwrites module state without an explicit restore contract.

### Canonical Communication Surfaces

All cross-module coordination must flow through one of:

- **Main Board orchestration** — the Main Board reads both modules' state and constructs the cross-module handoff (example: `WorkbenchSelectedHitsSnapshot` is built by the shell from canonical search + selection state)
- **Explicit snapshots** — `WorkbenchSearchSnapshot`, `WorkbenchSelectedHitsSnapshot`
- **Provider protocols** — `ActiveChartProviding` (Save Module reads chart data through this protocol; Preservation Module output is the conforming surface)
- **Single-owner render surface** — `TabRenderManager` (one instance per workflow store; no cross-workflow access; modules consume read projections only)
- **Future handoff envelopes** — `AnalysisResultSnapshot`, `SaveRequest`, `PackRestoreSnapshot` if introduced

### Allowed Transitional Writes / Exceptions

These writes cross module state boundaries by design and are permitted:

- **Pack / Restore**: may restore multiple module states (analysis, selection, preservation, search mirror) — but only through an explicit restore contract; not through ad hoc field writes scattered across modules
- **Analysis → Save/Pack bookkeeping**: analysis may clear `saveMessage` and `activePackID` when a new run starts to invalidate stale save and pack references
- **Save Module**: may write `saveMessage`, `persistenceOutcome`, and save-side `currentRunTrace`; the `currentRunTrace` write is distinct from the analysis-side `commitRunTrace()` call and is ordered after `persistToLibrary()` success
- **Preservation Module**: may write tab render outputs and override-owned state only through its own surface (`TabRenderManager`); other modules consume read projections

### Testing Implication

Module boundary tests are required before any module extraction or behavior change in that module.

Boundary tests currently in place:

- Search / Selection boundary — Phase 5A, Phase 5C
- Analysis Lifecycle boundary — Phase 5D-1

Pending:

- Save Module boundary — Phase 5E-2 (not yet written)
- Pack / Restore boundary — Phase 5F (not yet started)

New boundary tests must lock current behavior before extraction begins, not after.

### See Also

- Module-specific forbidden mutation lists: [`MODULE_BOUNDARIES.md`](MODULE_BOUNDARIES.md)
- New-workflow onboarding and routing rules: [`EXTENSION_BOUNDARIES.md`](EXTENSION_BOUNDARIES.md)
- Per-workflow pack/ingestion contracts: [`modules/PACK_RESTORE.md`](modules/PACK_RESTORE.md)

## What Stays Inside Physics Function

### AHE

Must stay inside AHE Physics Function:

- channel inference
- axis override
- metric extraction
- AHE-specific override panels (declared as optional modules in the AHE Workflow Assembly)
- AHE-specific pack content (via Save Metadata + Pack Metadata Providers)

### XY Rotation

Must stay inside XY Physics Function:

- phi offset
- center / detrend
- dual-tab semantics
- XY-specific control panels (declared as optional modules in the XY Workflow Assembly)
- XY-specific pack content (via Save Metadata + Pack Metadata Providers)

### 3ω

Must stay inside 3ω Physics Function:

- RT selection
- geometry
- fit ranges
- scaling law
- RAHE method
- overlays
- multi-tab render semantics
- 3ω-specific pack content (via Save Metadata + Pack Metadata Providers)

These behaviors define scientific meaning and should not be absorbed into shell modules.

## Search vs Physics Function Boundary (Phase 5A)

Physics Function relationship to Search module:

- workflow consumes a selected-hit snapshot at analysis entry
- workflow must not own top-level search query/results/running/message
- analysis and rerender paths must not mutate Search module lifecycle state

## Future SOT

Future SOT should plug into the same Main Board + Workflow Assembly model.

That means:

- the Main Board should not learn SOT physics
- SOT Physics Function adapts its output into Standard Result
- SOT-specific controls are declared as optional modules in the SOT Workflow Assembly
- default modules render lifecycle, save, restore, trace, warning, and status concerns automatically

If SOT needs a special representation, it should add an adapter or workflow-specific result layer inside the Physics Function, not expand the Main Board into domain logic.

## Migration Path

The migration direction is incremental:

1. Keep `WorkflowWorkspaceShell` as the Main Board implementation.
2. Extract or formalize modules one by one.
3. Keep workflow-specific optional modules separate from default modules.
4. Standardize the shell-facing result surface.
5. Preserve Physics Functions as the scientific owner for AHE, XY Rotation, 3ω, and future SOT.

The immediate design goal is to make composition explicit without forcing a monolithic runtime abstraction.

## Incremental Migration Rule

Future refactors should stay incremental instead of jumping straight into one large runtime or one giant `Standard Result`.

1. Extract one shell-facing boundary at a time.
2. Test after each extraction before moving to the next one.
3. Prefer read/adaptor surfaces before execution lifecycle helpers.
4. Do not introduce one giant `Standard Result` struct.
5. Scientific logic must remain inside each workflow's Physics Function.

Canonical extraction sequence and current status: [`WORKBENCH_ROADMAP.md`](WORKBENCH_ROADMAP.md).

## Cross-Links

- [Module Boundaries](MODULE_BOUNDARIES.md)
- [Plot System](modules/PLOT_SYSTEM.md)
- [Pack/Restore](modules/PACK_RESTORE.md)
- [Extension Boundaries](EXTENSION_BOUNDARIES.md)
- [Workbench Roadmap](WORKBENCH_ROADMAP.md)

## Code Map

- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceShell.swift` — composes shared workflow shell layout and injects workflow slots
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceProvider.swift` — defines the workspace provider contract for shell composition
- `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift` — owns AHE workflow workspace state and rendering lifecycle
- `Sources/SpinLabApp/Features/Workbench/AHEWorkspaceView.swift` — renders the AHE workflow workspace shell
- `Sources/SpinLabApp/Features/Workbench/OverlaySnapshot.swift` — stores detached overlay state for restored Workbench packs
- `Sources/SpinLabApp/Features/Workbench/PlotCanvasMouseTracker.swift` — tracks mouse position for the shared plot canvas
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaRenderedPlots.swift` — carries rendered 3ω plot data and layouts
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkbenchTab.swift` — defines the 3ω workflow tab identity set
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore.swift` — owns 3ω workflow workspace state and orchestration
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Analysis.swift` — runs 3ω ingestion analysis and trace commit
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+FitRanges.swift` — manages 3ω fit range editing state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+ManifestCache.swift` — snapshots 3ω manifest payloads and input identities
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift` — builds and restores 3ω analysis pack state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Persistence.swift` — saves 3ω charts and metrics to library artifacts
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Plotting.swift` — exposes 3ω plot editing and chart access
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+RTSelection.swift` — manages 3ω RT search and restore state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+RelatedCharts.swift` — loads 3ω related result references
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Rendering.swift` — rerenders 3ω tabs from stored tab state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Scaling.swift` — computes 3ω scaling results from frozen ingestion state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Selection.swift` — manages 3ω measurement selection and clearing state
- `Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceView.swift` — renders the 3ω workflow workspace shell
- `Sources/SpinLabApp/Features/Workbench/UnitTagEditor.swift` — edits unit-tag values in Workbench forms
- `Sources/SpinLabApp/Features/Workbench/WorkbenchEnvironment.swift` — supplies Workbench-specific environment capabilities
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotCanvas.swift` — renders the shared Workbench plot canvas
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlotControlsPanel.swift` — hosts shared plot controls for Workbench
- `Sources/SpinLabApp/Features/Workbench/WorkbenchSeriesOrderPanel.swift` — coordinates sourceRef-based series reordering for stacked plots
- `Sources/SpinLabApp/Features/Workbench/WorkbenchPlottingStore.swift` — defines the shared Workbench plotting contract
- `Sources/SpinLabApp/Features/Workbench/WorkbenchReadAdapter.swift` — snapshots shell-facing result state for workflow read paths
- `Sources/SpinLabApp/Features/Workbench/WorkbenchResultHeaderShell.swift` — presents shared result actions and save/load entry points
- `Sources/SpinLabApp/Features/Workbench/WorkbenchSharedComponents.swift` — groups shared Workbench component declarations
- `Sources/SpinLabApp/Features/Workbench/WorkbenchStandardPlotControls.swift` — renders standard shared plot controls
- `Sources/SpinLabApp/Features/Workbench/WorkbenchStatusArea.swift` — presents shared status content for workflow workspaces
- `Sources/SpinLabApp/Features/Workbench/WorkbenchTitleTemplateField.swift` — provides the Workbench title template field
- `Sources/SpinLabApp/Features/Workbench/WorkbenchTracePanel.swift` — presents last-run trace content for workflow workspaces
- `Sources/SpinLabApp/Features/Workbench/WorkbenchView.swift` — routes Workbench region content by selected section
- `Sources/SpinLabApp/Features/Workbench/WorkflowHitRow.swift` — renders a measurement search hit row
- `Sources/SpinLabApp/Features/Workbench/WorkflowRegistryView.swift` — renders the workflow registry selection view
- `Sources/SpinLabApp/Features/Workbench/WorkflowWorkspaceRegistry.swift` — maps workflow IDs to workspace view factories
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift` — owns XY Rotation workflow workspace state and orchestration
- `Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceView.swift` — renders the XY Rotation workflow workspace shell
