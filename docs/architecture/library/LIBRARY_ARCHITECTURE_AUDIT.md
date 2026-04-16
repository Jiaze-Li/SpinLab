# Library Architecture Audit (v4.2.5)

Audited 2026-04-12. Covers the Library feature's data flow layers, state management, and service decomposition.

> **Post-audit progress (v5.4.0):** P1 completed in v5.1.1 (LibraryFacade + LibraryCommandCoordinator removed). P2 completed in v5.4.0 (LibraryMutationOrchestrator merged into LibrarySyncService). The layer map below reflects the pre-cleanup state.

---

## Current Layer Map

```
View (LibraryView 1252 lines)
  → ViewModel (LibraryViewModel 308 lines, pure proxy)
    → Actions closures
      → SpinLabAppState (11 passthrough methods)
        → LibraryFacade (153 lines, passthrough)
          → LibraryCommandCoordinator (56 lines, passthrough)
            → LibraryFeatureStore (1661 lines, 36 stored properties, 61+ methods)
              → LibraryMutationService (393 lines)
                → LibraryMutationOrchestrator (178 lines)
                → LibrarySyncService (136 lines)
                  → LibraryStore (filesystem I/O)
```

A single user action (e.g., "Apply All") passes through **12 method calls** across **6 classes** before reaching filesystem mutations.

---

## Problem Areas

### 1. Three empty-passthrough layers

| Layer | Lines | Value-add |
|-------|-------|-----------|
| LibraryViewModel | 308 | Zero logic; maps `appState.library.*` → `viewState.*`, forwards actions via closures |
| LibraryFacade | 153 | Dispatches to CommandCoordinator + invokes callback closures |
| LibraryCommandCoordinator | 56 | Every method is a one-liner forwarding to FeatureStore |

Combined: ~517 lines of pure indirection.

### 2. Diff/Review computation scattered across 3 locations

- `LibrarySyncService.diff()` — computes baseline + diff
- `LibraryMutationOrchestrator.diffAgainstExisting()` — computes diff
- `LibraryMutationOrchestrator.prepareLibrarySyncReview()` — calls `libraryDiffEngine.diff()` internally

No single source of truth for diff computation.

### 3. LibraryFeatureStore over-responsibility (1661 lines, 36 properties)

Owns: selection state, settings, preview state, sync review, sample editing, workbench projections (`workbenchResults`, `measurementPlotIndex`, `measurementData`), manual/metadata log management, drawer operations, condition alias book.

Cross-domain contamination: workbench/measurement properties belong to Workbench domain.

### 4. Three overlapping mutation services (707 lines total)

| Service | Lines | Role | Overlap |
|---------|-------|------|---------|
| LibraryMutationOrchestrator | 178 | Diff planning, review creation | Diff also in SyncService |
| LibraryMutationService | 393 | Mutation execution + wrapping | Calls both Orchestrator and SyncService; also calls LibraryStore directly |
| LibrarySyncService | 136 | Filesystem I/O + diff | Diff also in Orchestrator |

### 5. ViewModel inconsistently used

View sometimes calls `viewModel.method()`, sometimes reads `appState.library.*` directly. `viewState` computed property reads through `@ObservationIgnored appState`, breaking the SwiftUI observation chain (fixed in v4.2.5 for onChange handlers, but the pattern remains fragile).

---

## File Reference

| File | Lines | Role |
|------|-------|------|
| `Features/Library/LibraryView.swift` | 1252 | Main view |
| `Features/Library/LibraryViewModel.swift` | 308 | Pure proxy |
| `Features/Library/LibrarySelectionSync.swift` | 83 | Selection validation |
| `Features/Library/LibraryDetailSections.swift` | ~100 | Extracted view components |
| `Features/Library/LibraryWorkspaceSections.swift` | ~450 | Extracted view components |
| `App/State/LibraryFeatureStore.swift` | 1661 | State + coordination |
| `App/LibraryFacade.swift` | 153 | Passthrough facade |
| `App/LibraryCommandCoordinator.swift` | 56 | Passthrough coordinator |
| `App/LibraryMutationService.swift` | 393 | Mutation execution |
| `App/LibraryMutationOrchestrator.swift` | 178 | Diff planning |
| `App/LibraryPreviewComputationService.swift` | 58 | Preview group computation |
| `Library/LibrarySyncService.swift` | 136 | Filesystem sync |
| `Library/LibraryDiffEngine.swift` | 169 | Diff computation |
| `Library/LibraryStore.swift` | ~600 | Filesystem I/O |
