# Library Browse and Selection

## Column Shell

Library uses `AppColumnShell` (two-column layout shell). Never use raw `HSplitView` with hardcoded frames in Library views.

- Left column width is persisted via `@AppStorage`.
- The right column is the inspector/output panel: details, measurement conditions, sidecar data, artifact previews.

## Selection

Browser Preview and the Existing Drawer are distinct UI concepts and each owns an **independent
full selection triple** on `LibraryFeatureStore`:

- `librarySelectedPrefix` / `librarySelectedBatchId` / `librarySelectedSampleId` — drawer selection.
  Detail editing/mutations (sample edit draft, measurement-set CRUD, applied-measurement cascade
  delete) always act on this triple, never on the browser triple.
- `libraryBrowserSelectedPrefix` / `libraryBrowserSelectedBatchId` / `libraryBrowserSelectedSampleId`
  — browser/preview-tree selection. Registry/preview navigation writes only this triple.

`libraryActiveSelectionSource` (`.browser` / `.drawer`) is **not** an ownership marker for a shared
selection — it is Detail-pane presentation/focus state: which of the two independent triples the
Detail pane currently displays. `LibraryFeatureStore.currentSelectionSampleId` resolves the
Detail-facing sample id from whichever triple is focused, so read-only Detail projections
(Workbench Results, Measurement Data, Measurement Plot Index) follow focus while mutations stay
drawer-only.

Selection state is owned by `LibraryFeatureStore` and projected via `LibraryFeatureStore+Projection.swift`. The projection maps the current selection and measurement item to view-facing models.

`LibrarySelectionSync` provides two pure reconciliation functions — `syncBrowserSelection` (validates
against preview-derived groups) and `syncDrawerSelection` (validates against existing/drawer
groups). `LibraryPrimaryView` calls both independently whenever their respective backing data
changes, regardless of which pane is currently focused, so the unfocused pane's selection never
goes stale. Neither function reads or writes the other triple.

Interaction-state persistence (`SpinLabInteractionSnapshot` top-level fields, restored via
`InteractionSnapshotCoordinator`, and the parallel `LibraryInteractionState` under
`snapshot.libraryView`, restored via `LibraryViewModel.persistInteractionState` /
`restoredInteractionState()`) each carry both triples independently. Legacy on-disk snapshots
written before the split decode the new browser fields as `nil` (see
`Tests/SpinLabAppTests/V570LibraryBrowserDrawerSelectionSplitTests.swift` for the decode-compatibility
regression test) — this is expected, not a bug: a legacy snapshot never persisted a distinct browser
selection to begin with.

## Search and Filter

Search is presented in `LibraryView+Search.swift`. The ViewModel owns transient filter text; the FeatureStore applies it to the projected item list.

## Detail Section Ordering

The detail column (`LibraryDetailView.swift`) renders sections in a fixed order defined by `LibraryWorkspaceSections.swift`. Section order must not vary by selection state or be driven by individual view logic.

Visual rules (spacing, fonts, AppColumnShell usage): `specs/04_UI_RULES.md`.

## Invariants

- All Library views use `AppColumnShell`, never raw `HSplitView`.
- Left column width persists across sessions.
- Detail section order is fixed and driven by `LibraryWorkspaceSections`; views must not reorder it locally.

## Tests

Start with `V513LibraryFeatureStoreFacadeTests.swift`, `V260MeasurementsDisplayTests.swift`,
`V226LibrarySelectionSyncTests.swift` (pure sync-function coverage), and
`V570LibraryBrowserDrawerSelectionSplitTests.swift` (browser/drawer independence regression coverage).

## Code Map

- `Sources/SpinLabApp/App/State/LibraryFeatureStore.swift` — Library feature store: stored state, init, and configureFacade wiring
- `Sources/SpinLabApp/App/State/LibraryFeatureStoreOutcomes.swift` — outcome enums and result structs for library feature store operations
- `Sources/SpinLabApp/App/State/LibraryFeatureStore+Facade.swift` — public facade API wrapping detailed methods with injected cross-store callbacks
- `Sources/SpinLabApp/App/State/LibraryFeatureStore+DrawerSelection.swift` — selection state changes, deferred selection guard, and selection normalization
- `Sources/SpinLabApp/App/State/LibraryFeatureStore+Projection.swift` — selection-driven projection load + measurement set CRUD + cascade deletion
- `Sources/SpinLabApp/App/State/LibraryState.swift` — raw Library state model (drawers, measurements, selection IDs)
- `Sources/SpinLabApp/Features/Library/LibraryPrimaryView.swift` — Primary-pane content (Registry/Preview browser, Existing Drawer, search); current split-view replacement for the retired `LibraryView*.swift` family — see `Tests/SpinLabAppTests/V538CrossPaneStateOwnershipTests.swift`
- `Sources/SpinLabApp/Features/Library/LibraryDetailView.swift` — Detail pane; resolves the displayed sample from whichever selection triple is currently focused
- `Sources/SpinLabApp/Features/Library/LibraryWorkspaceState.swift` — cross-pane UI state shared between Primary and Detail (dialogs, disclosure state, preview-derived data, `selectionEntry`/`resolveSelectedSample`)
- `Sources/SpinLabApp/Features/Library/LibraryViewModel.swift` — AppState action forwarder + interaction state binding for the Library panes
- `Sources/SpinLabApp/Features/Library/LibrarySelectionSync.swift` — pure browser/drawer selection reconciliation functions (`syncBrowserSelection` / `syncDrawerSelection`)
- `Sources/SpinLabApp/App/State/InteractionStateModels.swift` — `LibrarySelectionSource`, `LibraryInteractionState`, and the `SpinLabInteractionSnapshot` fields that persist both selection triples
- `Sources/SpinLabApp/Features/Library/LibraryWorkspaceSections.swift` — defines and orders detail column sections
- `Sources/SpinLabApp/Features/Library/LibraryViewSupport.swift` — shared view helpers and modifiers
- `Sources/SpinLabApp/Features/Library/LibrarySampleDetailHeaderView.swift` — sample detail header (name, drawer, status badges)
- `Sources/SpinLabApp/UI/MetadataViews.swift` — shared metadata display views (condition chips, tag badges) used in Library panels
