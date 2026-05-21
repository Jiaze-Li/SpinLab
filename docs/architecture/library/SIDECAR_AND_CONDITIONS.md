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

- `Sources/SpinLabApp/Domain/Sidecar/SpinLabFileSidecar.swift` — Tier 1 sidecar schema and Codable contract shared by Inbox, Library, and Workbench <!-- legitimate_cross_cutting -->
- `Sources/SpinLabApp/Library/LibrarySidecarService.swift` — sidecar recompute and dry-run diff business logic extracted from LibraryStore
- `Sources/SpinLabApp/Library/LibrarySidecarCapability.swift` — capability protocol abstracting sidecar read/write/recompute operations for injectable testing
- `Sources/SpinLabApp/Library/LibrarySidecarReader.swift` — reads and decodes SpinLabFileSidecar from disk; injectable via LibrarySidecarReaderCapability
- `Sources/SpinLabApp/Library/LibrarySidecarWriter.swift` — encodes and atomically writes SpinLabFileSidecar to disk; injectable via LibrarySidecarWriterCapability
- `Sources/SpinLabApp/Library/LibraryRootAccess.swift` — activates scoped library-root traversal and enumerates measurement sidecars for search
- `Sources/SpinLabApp/Library/LibraryStore+Measurements.swift` — copies measurement files and loads applied sidecar projections
- `Sources/SpinLabApp/Library/LibraryStore+SidecarEnumeration.swift` — enumerates sidecar URLs, snapshots, and decodes applied sidecars
- `Sources/SpinLabApp/Features/Library/MeasurementConditionDetailView.swift` — condition fields display (temperature, current, field) from sidecar
- `Sources/SpinLabApp/Features/Library/MeasurementDataSectionView.swift` — measurement data section with normalized/raw tags
- `Sources/SpinLabApp/Features/Library/LibraryMeasurementDataPresenter.swift` — groups WorkbenchMeasurementDataStore records into device/method/range hierarchy for display
- `Sources/SpinLabApp/Features/Library/LibraryMeasurementsDoneSection.swift` — measurements list section within drawer view
- `Sources/SpinLabApp/Features/Library/LibraryExistingDrawerSampleSectionView.swift` — existing drawer sample section; reads projected sidecar data
- `Sources/SpinLabApp/App/State/LibraryFeatureStore+AppliedMeasurements.swift` — applied measurement projection, sidecar loading, and condition override persistence
- `Sources/SpinLabApp/App/State/LibraryFeatureStore+Recompute.swift` — stale sidecar detection, recompute preview, and bulk recompute apply
