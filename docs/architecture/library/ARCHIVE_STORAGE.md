# Library Archive Storage

## Archive Canonical

The internal archive under App Support is the canonical source of truth for all archived measurements. The Library Root directory (user-chosen) is a mirror/working location; App Support is authoritative for index reconstruction.

- Once archived, records must not be silently modified by any automated process.
- `LibraryWriteTransaction` is the only permitted write interface for paired file + sidecar writes. Do not bypass it.

## Filesystem Sync Direction

Sync is one-way: **filesystem → app state**, never the reverse. `LibrarySyncService` reads the filesystem and rebuilds the in-memory index; it never writes back to disk except through `LibraryWriteTransaction`.

`LibraryStore` owns the persistent drawer index and measurement list. It exposes an `AsyncStream<LibraryState>` for FeatureStore consumption.

## Drawer and Settings

`LibrarySettingsStore` persists Library Root path and user preferences. Settings are separate from the measurement index; changes to Library Root trigger a re-sync via `LibrarySyncService`.

`LibrarySort` owns sort key and direction logic for the measurement list. Sort state is persisted separately from index data.

## Audit Log

The audit log is append-only and maintained under both Library Root and App Support. If the log file exists but cannot be read, the write is skipped to prevent overwrite. Full PO promise: `specs/01_PRODUCT_RULES.md` (Audit and traceability).

Logging is routed through `LibraryLogger`.

## Inbox → Library Write Boundary

`LibraryWriteTransaction` is the sole entry point for Inbox apply writes (file archiving + sidecar generation). Time sequence: see `docs/architecture/inbox/CONFIRM_AND_APPLY.md`. Risk: `SP-010`.

`LibraryDiskCleanupService` handles `_spinlab` artifact directory cleanup when measurements are deleted. It must not interfere with active Workbench result writes.

## Invariants

- `LibraryWriteTransaction` is the only write path into the archive. No view or FeatureStore writes directly to disk.
- Filesystem sync is always `filesystem → app state`; the reverse direction must not occur.
- Audit log is append-only; a non-readable existing log blocks the write (does not overwrite).

## Tests

Start with `V416DeleteAppliedMeasurementTests.swift`, `V343DeleteWorkbenchResultTests.swift`.

## Code Map

- `Sources/SpinLabApp/Library/LibraryStore.swift` — drawer index persistence, AsyncStream emission, and index loading
- `Sources/SpinLabApp/Library/LibrarySyncService.swift` — filesystem scan and app-state sync (one-way: filesystem→state)
- `Sources/SpinLabApp/Library/LibrarySettingsStore.swift` — Library Root path and user preferences persistence
- `Sources/SpinLabApp/Library/LibraryLogger.swift` — audit log append writer (Library Root + App Support)
- `Sources/SpinLabApp/Library/LibraryModels.swift` — Library domain models (DrawerItem, MeasurementItem, LibraryIndex)
- `Sources/SpinLabApp/Library/LibrarySort.swift` — sort key and direction logic for measurement list
- `Sources/SpinLabApp/Library/LibraryWriteTransaction.swift` — sole write interface for paired file + sidecar archive operations
- `Sources/SpinLabApp/App/LibraryDiskCleanupService.swift` — artifact directory cleanup on measurement deletion
- `Sources/SpinLabApp/UseCases/LibraryDestinationSubpath.swift` — root-relative destination subpath computation for archive writes
