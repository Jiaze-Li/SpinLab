# Library Browse and Selection

## Column Shell

Library uses `AppColumnShell` (two-column layout shell). Never use raw `HSplitView` with hardcoded frames in Library views.

- Left column width is persisted via `@AppStorage`.
- The right column is the inspector/output panel: details, measurement conditions, sidecar data, artifact previews.

## Selection

Selection state is owned by `LibraryFeatureStore` and projected via `LibraryFeatureStore+Projection.swift`. The projection maps the current selected drawer and measurement item to view-facing models.

`LibrarySelectionSync` bridges Library selection state with ViewModel-level interaction state. Sync uses explicit `restoreInteractionState()` / `persistInteractionState()` — no reactive auto-sync.

## Search and Filter

Search is presented in `LibraryView+Search.swift`. The ViewModel owns transient filter text; the FeatureStore applies it to the projected item list.

## Detail Section Ordering

The detail column (`LibraryView+DetailColumn.swift`) renders sections in a fixed order defined by `LibraryWorkspaceSections.swift`. Section order must not vary by selection state or be driven by individual view logic.

Visual rules (spacing, fonts, AppColumnShell usage): `specs/04_UI_RULES.md`.

## Invariants

- All Library views use `AppColumnShell`, never raw `HSplitView`.
- Left column width persists across sessions.
- Detail section order is fixed and driven by `LibraryWorkspaceSections`; views must not reorder it locally.

## Tests

Start with `V513LibraryFeatureStoreFacadeTests.swift`, `V260MeasurementsDisplayTests.swift`.

## Code Map

- `Sources/SpinLabApp/App/State/LibraryFeatureStore.swift` — Library feature store: stored state, init, and configureFacade wiring
- `Sources/SpinLabApp/App/State/LibraryFeatureStoreOutcomes.swift` — outcome enums and result structs for library feature store operations
- `Sources/SpinLabApp/App/State/LibraryFeatureStore+Facade.swift` — public facade API wrapping detailed methods with injected cross-store callbacks
- `Sources/SpinLabApp/App/State/LibraryFeatureStore+DrawerSelection.swift` — selection state changes, deferred selection guard, and selection normalization
- `Sources/SpinLabApp/App/State/LibraryFeatureStore+Projection.swift` — selection-driven projection load + measurement set CRUD + cascade deletion
- `Sources/SpinLabApp/App/State/LibraryState.swift` — raw Library state model (drawers, measurements, selection IDs)
- `Sources/SpinLabApp/Features/Library/LibraryView.swift` — root Library view; composes column shell and subviews
- `Sources/SpinLabApp/Features/Library/LibraryView+DetailColumn.swift` — right-column detail view composition
- `Sources/SpinLabApp/Features/Library/LibraryView+Panels.swift` — panel layout helpers
- `Sources/SpinLabApp/Features/Library/LibraryView+Search.swift` — search field and filter UI
- `Sources/SpinLabApp/Features/Library/LibraryView+State.swift` — view-local state bindings
- `Sources/SpinLabApp/Features/Library/LibraryViewModel.swift` — AppState action forwarder + interaction state binding for LibraryView
- `Sources/SpinLabApp/Features/Library/LibrarySelectionSync.swift` — bridges FeatureStore selection into ViewModel interaction state
- `Sources/SpinLabApp/Features/Library/LibraryWorkspaceSections.swift` — defines and orders detail column sections
- `Sources/SpinLabApp/Features/Library/LibraryViewSupport.swift` — shared view helpers and modifiers
- `Sources/SpinLabApp/Features/Library/LibrarySampleDetailHeaderView.swift` — sample detail header (name, drawer, status badges)
- `Sources/SpinLabApp/UI/MetadataViews.swift` — shared metadata display views (condition chips, tag badges) used in Library panels
