# Library Sidecar and Conditions

## Sidecar in Library Context

`SpinLabFileSidecar` is a cross-cutting file contract shared by Inbox (writes), Library (reads), and Workbench (reads). In Library context, it is the primary source of measurement metadata displayed to the user after archiving.

**Schema canonical source**: `docs/architecture/inbox/OUTPUT_CONTRACTS.md`. Library reads the sidecar but does not own the schema. Schema changes require migration and tests — not local UI-only edits.

**Library reads sidecar for**:
- Measurement conditions (`temperature`, `current`, `field`) displayed in detail view
- Normalized and raw tags for display and filtering
- Channel bindings for multi-channel measurements
- `applied_at` timestamp and `workflow` identifier

## Condition and Tag Display

`MeasurementConditionDetailView` renders the condition fields from the sidecar (`temperature`, `current`, `field`). It reads values directly from the deserialized `SpinLabFileSidecar`; it must not reinterpret, normalize, or transform the values beyond display formatting.

`MeasurementDataSectionView` renders the measurement data section including raw and normalized tags.

`LibraryMeasurementsDoneSection` and `LibraryExistingDrawerSampleSectionView` display measurement items within drawer context; they consume projected sidecar data from `LibraryFeatureStore+Projection`.

## Inbox / Workbench Shared Boundary

`SpinLabFileSidecar` is a `legitimate_cross_cutting` contract (`SP-006`). Treat it as a file contract, not a Library-internal model:

- Schema changes require migration/tests across all three consumers (Inbox, Library, Workbench).
- Library must not add Library-only fields to the sidecar schema; use `LibraryStore` index instead.
- Workbench reads sidecar for search and condition projection; changes to sidecar field names affect Workbench search.

## Invariants

- Library is a read-only consumer of the sidecar schema. Complete schema: `docs/architecture/inbox/OUTPUT_CONTRACTS.md`.
- Sidecar values are displayed as-is; views must not reinterpret or re-normalize them.
- `SpinLabFileSidecar` is a cross-cutting contract: schema changes cascade to Inbox write, Library display, and Workbench search.

## Tests

Start with `V250SidecarTests.swift`.

## Code Map

- `Sources/SpinLabApp/Library/SpinLabFileSidecar.swift` — sidecar schema, Codable model, field contracts (cross-cutting; schema canonical: `inbox/OUTPUT_CONTRACTS.md`)
- `Sources/SpinLabApp/Features/Library/MeasurementConditionDetailView.swift` — condition fields display (temperature, current, field) from sidecar
- `Sources/SpinLabApp/Features/Library/MeasurementDataSectionView.swift` — measurement data section with normalized/raw tags
- `Sources/SpinLabApp/Features/Library/LibraryMeasurementsDoneSection.swift` — measurements list section within drawer view
- `Sources/SpinLabApp/Features/Library/LibraryExistingDrawerSampleSectionView.swift` — existing drawer sample section; reads projected sidecar data
