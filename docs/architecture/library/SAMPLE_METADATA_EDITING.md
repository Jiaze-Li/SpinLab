# Library Sample Metadata Editing

## Edit Transaction Model

All sample metadata writes go through `LibrarySampleEditService`. Views must never write directly to the repository or domain models. The edit path is:

```
View → LibraryFeatureStore+SampleEdit → LibraryMutationService → SaveLibrarySampleEditsUseCase → LibrarySampleEditService → LibraryStore
```

`LibraryMutationService` coordinates the edit across FeatureStore, UseCase, and service layers. `SaveLibrarySampleEditsUseCase` validates and persists the changes atomically.

`LibraryFeatureStore+Logs` maintains the edit history visible in the UI audit panel.

## Display Name Protection

User-defined display names must never be renamed by AI or automated processes. This is a PO commitment (`specs/01_PRODUCT_RULES.md`) and must be enforced at the service layer, not just the UI.

Execution detail: `LibrarySampleEditService` enforces that any rename attempt is explicit and user-initiated. No normalization, cleanup, or AI-triggered renaming is permitted.

## Registry Sync

Registry sync aligns Library drawer tags with the XLSX registry. The sync is:

- **One-way**: XLSX registry → Library drawers (tag alignment only, never destructive replacement of archived data).
- **Atomic with rollback**: `LibraryXLSXSyncService` applies changes via a transaction; on failure, all changes are rolled back.
- **Diff-driven**: `LibraryDiffEngine` computes the delta between registry state and Library state before any write. `LibraryRegistryParser` parses the XLSX file into the diff input.

## Invariants

- Edits go through `LibrarySampleEditService`; no direct repository writes from views.
- User-defined display names must never be renamed by automated processes.
- Registry sync is one-way (XLSX → drawers) and atomic with rollback.

## Tests

Start with `V220LibraryDiffEngineTests.swift`.

## Code Map

- `Sources/SpinLabApp/App/State/LibraryFeatureStore+SampleEdit.swift` — FeatureStore edit surface: initiates, validates, and applies sample edits
- `Sources/SpinLabApp/App/State/LibraryFeatureStore+Logs.swift` — FeatureStore edit history log for the UI audit panel
- `Sources/SpinLabApp/Library/LibrarySampleEditService.swift` — edit transaction execution; enforces display name protection
- `Sources/SpinLabApp/Library/LibraryRegistryParser.swift` — parses XLSX registry file into diff-engine input
- `Sources/SpinLabApp/Library/LibraryDiffEngine.swift` — computes delta between XLSX registry state and Library drawer state
- `Sources/SpinLabApp/Library/LibraryXLSXSyncService.swift` — atomic XLSX→Library sync with rollback
- `Sources/SpinLabApp/Library/LibraryRegistrySyncService.swift` — registry XLSX write-back for edited samples; metadata + numeric log dispatch
- `Sources/SpinLabApp/App/LibraryMutationService.swift` — cross-layer coordinator for metadata edit and registry sync operations
- `Sources/SpinLabApp/UseCases/SaveLibrarySampleEditsUseCase.swift` — validates and persists sample edit batch atomically
