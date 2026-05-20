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

- `Sources/SpinLabApp/Library/LibraryStore.swift` — owns library filesystem persistence and node caches
- `Sources/SpinLabApp/Library/LibraryStore+RootAndIndex.swift` — maintains root verification and index rebuild persistence
- `Sources/SpinLabApp/Library/LibraryStore+Drawers.swift` — writes and removes batch and sample drawer files
- `Sources/SpinLabApp/Library/LibraryStore+MeasurementSets.swift` — persists per-sample measurement set selections
- `Sources/SpinLabApp/Library/LibraryStore+Backup.swift` — mirrors library root contents into backup storage
- `Sources/SpinLabApp/Library/LibraryStore+ChangeLogs.swift` — records append-only sample and batch edit logs
- `Sources/SpinLabApp/Library/LibraryStore+RegistryLogs.swift` — proxies registry manual and metadata log persistence
- `Sources/SpinLabApp/Library/LibraryStore+PathsAndCache.swift` — resolves library paths and maintains node caches
- `Sources/SpinLabApp/Library/LibrarySyncService.swift` — filesystem scan and app-state sync (one-way: filesystem→state)
- `Sources/SpinLabApp/Library/LibrarySettingsStore.swift` — Library Root path and user preferences persistence
- `Sources/SpinLabApp/App/State/LibraryFeatureStore+Settings.swift` — library root/backup path updates, verification, and backup sync coordination
- `Sources/SpinLabApp/App/State/LibraryFeatureStore+PreviewSync.swift` — sync review preparation, incremental refresh, drawer mutation commits, and file sync orchestration
- `Sources/SpinLabApp/Library/LibraryLogger.swift` — audit log append writer (Library Root + App Support)
- `Sources/SpinLabApp/Library/Domain/LibraryDomainModels.swift` — Tier 2 Library domain entities (LibraryIndex, LibrarySample, LibraryBatch, AppliedMeasurement, LibraryWarning, change log types)
- `Sources/SpinLabApp/Library/LibraryModels.swift` — Tier 3 Library UI projections (LibraryPreview, LibraryDiff, LibraryRefreshReview, edit drafts, log entry display types)
- `Sources/SpinLabApp/Library/LibrarySort.swift` — sort key and direction logic for measurement list
- `Sources/SpinLabApp/Library/LibraryWriteTransaction.swift` — sole write interface for paired file + sidecar archive operations
- `Sources/SpinLabApp/App/LibraryDiskCleanupService.swift` — artifact directory cleanup on measurement deletion
- `Sources/SpinLabApp/UseCases/LibraryDestinationSubpath.swift` — root-relative destination subpath computation for archive writes
- `Sources/SpinLabApp/App/ArchivedRecordResolverService.swift` — resolves archived record paths and validates archive directory integrity
- `Sources/SpinLabApp/Repositories/DomainRepositories.swift` — AsyncStream-backed repositories for Library drawers and sidecar data
- `Sources/SpinLabApp/Storage/AtomicFileWriter.swift` — atomic file write utility ensuring no partial writes land on disk
- `Sources/SpinLabApp/Storage/LibraryArchiveScanService.swift` — registry install, measurements directory management, and managed-path detection
- `Sources/SpinLabApp/Storage/ContentFingerprintService.swift` — SHA-256 content fingerprint computation for duplicate detection
- `Sources/SpinLabApp/Storage/ManagedStorage.swift` — superseded; split into LibraryArchiveScanService, InboxImportFilterService, ContentFingerprintService (14c-c5)
- `Sources/SpinLabApp/Storage/RepositoryPointer.swift` — parses, validates, and auto-writes repository root pointers in App Support
