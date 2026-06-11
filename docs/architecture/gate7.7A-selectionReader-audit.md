# Gate 7.7A — selectionReader Bridge Audit

## 1. Current Ownership

`selectionReader: (() -> Set<String>)?` is a closure-typed property declared on three workspace stores and assigned by `WorkbenchFeatureStore` at init time. It is the only path by which workspace stores read current selection state.

| Store | File |
|---|---|
| `XYRotationWorkspaceStore` | `Features/Workbench/XYRotationWorkspaceStore.swift:16` |
| `AHEWorkspaceStore` | `Features/Workbench/AHEWorkspaceStore.swift:17` |
| `ThreeOmegaWorkspaceStore` | `Features/Workbench/ThreeOmegaWorkspaceStore.swift:19` |

Assignment (all three in `WorkbenchFeatureStore.swift` ~L235–237):

```swift
aheWorkspace.selectionReader       = { [weak self] in self?.selectionRuntime.selectedIDs(for: .ahe) ?? [] }
xyRotationWorkspace.selectionReader = { [weak self] in self?.selectionRuntime.selectedIDs(for: .xyRotation) ?? [] }
threeOmegaWorkspace.selectionReader = { [weak self] in self?.selectionRuntime.selectedIDs(for: .threeOmega) ?? [] }
```

---

## 2. Remaining Bridge Surfaces

### 2a. Read sites (12 total)

| Store | Site | Purpose |
|---|---|---|
| XYRotation | `XYRotationWorkspaceStore.swift:283` | Pack config serialization |
| XYRotation | `XYRotationWorkspaceStore.swift:474` | Analysis hit filtering — conditional branch |
| XYRotation | `XYRotationWorkspaceStore.swift:486` | Analysis hit filtering — snapshot fallback |
| AHE | `AHEWorkspaceStore.swift:321–322` | Selection item building — conditional branch |
| AHE | `AHEWorkspaceStore.swift:456` | Pack config serialization |
| ThreeOmega | `ThreeOmegaWorkspaceStore+Analysis.swift:18–20` | Analysis hit filtering — conditional branch |
| ThreeOmega | `ThreeOmegaWorkspaceStore+Analysis.swift:31` | Analysis hit filtering — snapshot fallback |
| ThreeOmega | `ThreeOmegaWorkspaceStore+Pack.swift:64` | Pack config serialization |
| ThreeOmega | `ThreeOmegaWorkspaceStore+ManifestCache.swift:185` | Manifest payload caching post-restore |

All call sites are safe: they use `selectionReader?() ?? []`, treating a nil reader as an empty selection.

### 2b. Call pattern variants

- **`if let reader = selectionReader { ... }`** — 3 sites (analysis filtering on all three stores). Only filters hits when a reader is present; otherwise treats everything as unselected.
- **`selectionReader?() ?? []`** — 6 sites (pack serialization, snapshot fallbacks, manifest cache). Silent empty-set default.

### 2c. Test injection sites

| Test | File | Line | What it seeds |
|---|---|---|---|
| `V537PackRestoreModuleBoundaryTests` | `Tests/…/V537PackRestoreModuleBoundaryTests.swift:376` | `store.selectionReader = { seededIDs }` | Mutable set, populated via `seedSelection` callback |
| `V537AHESearchSnapshotConsumptionTests` | `Tests/…/V537AHESearchSnapshotConsumptionTests.swift:106` | `store.selectionReader = { [hitA.id] }` | Fixed single-ID set |

Both tests bypass `WorkbenchFeatureStore` and inject the closure directly — they will break if the property is removed without a replacement injection point.

---

## 3. Proposed Removal Plan

The bridge exists because workspace stores cannot hold a strong reference to `WorkbenchSelectionRuntime` (ownership would cycle through `WorkbenchFeatureStore`). The closure is the indirection that breaks that cycle.

There are two clean replacement paths:

### Option A — Pass `WorkbenchSelectionRuntime` as a typed dependency at init
Each workspace store receives a weak reference to `WorkbenchSelectionRuntime` and calls `selectionRuntime.selectedIDs(for: workflow)` directly. Removes the closure entirely. Requires `WorkbenchSelectionRuntime` to be a reference type the stores can hold weakly.

### Option B — Introduce a `SelectionReading` protocol
Define `protocol SelectionReading { func selectedIDs(for workflow: Workflow) -> Set<String> }`. Pass a protocol-typed weak reference into each store at init. Stores call through the protocol. Tests implement a lightweight fake; no closure injection needed.

**Recommendation: Option B.** It is testable without closures, names the dependency explicitly, and mirrors the pattern already used for `WorkbenchSaveCoordinating`. The protocol can be declared in the same file as `WorkbenchSelectionRuntime`.

### Step-by-step (for the removal PR)

1. Declare `SelectionReading` protocol on `WorkbenchSelectionRuntime`.
2. Add `weak var selectionReading: (any SelectionReading)?` to each workspace store (replaces `selectionReader`).
3. Migrate all 9 read sites to call `selectionReading?.selectedIDs(for: .workflow) ?? []`.
4. In `WorkbenchFeatureStore.init`, assign `selectionReading = selectionRuntime` on each store; remove the three closure assignments.
5. Remove `selectionReader` declarations.
6. Update the two test files to inject a `SelectionReadingFake` conformance instead of a closure.

---

## 4. Tests That Must Protect the Change

These two test files exercise `selectionReader` directly and must be updated (not just re-run) as part of the removal PR:

- `Tests/SpinLabAppTests/V537PackRestoreModuleBoundaryTests.swift` — line 376
- `Tests/SpinLabAppTests/V537AHESearchSnapshotConsumptionTests.swift` — line 106

Both should replace closure injection with a `SelectionReadingFake` conformance. After migration they must continue to pass without behavior changes — selection filtering logic in the stores does not change, only the injection mechanism does.

No other test files reference `selectionReader`.

---

## 5. Out of Scope (Gate 7.7A)

This audit does not touch:
- Pack/Restore paths
- `overlayRuntime`
- `fileSampleKey` / `sampleId`
- `cachedRTFilePath`
- Save Coordinator
- Rendering or metrics logic

---

## 6. Decision

### 6a. All read sites

| File | Function / context | Workflow | Category | Fallback when nil |
|---|---|---|---|---|
| `XYRotationWorkspaceStore.swift:474` | `runAnalysis(searchSnapshot:)` — conditional branch | XYRotation | Analysis filtering | No filtering; all hits treated as unselected |
| `XYRotationWorkspaceStore.swift:486` | `runAnalysis(selectedHitsSnapshot:)` — snapshot fallback | XYRotation | Analysis filtering | Empty set → no hits pass filter; guard fires |
| `XYRotationWorkspaceStore.swift:283` | `_buildPackConfig()` | XYRotation | Pack serialization | Serializes empty `selectedSearchResultIDs` array |
| `AHEWorkspaceStore.swift:321–322` | `buildAHESelections(from:)` — conditional branch | AHE | Analysis filtering | No filtering; hits not narrowed to selection |
| `AHEWorkspaceStore.swift:456` | `buildPackConfig()` | AHE | Pack serialization | Serializes empty `selectedSearchResultIDs` array |
| `ThreeOmegaWorkspaceStore+Analysis.swift:18–20` | `runAnalysis(searchSnapshot:)` — conditional branch | ThreeOmega | Analysis filtering | No filtering; all hits treated as unselected |
| `ThreeOmegaWorkspaceStore+Analysis.swift:31` | `runAnalysis(selectedHitsSnapshot:)` — snapshot fallback | ThreeOmega | Analysis filtering | Empty set → no hits pass filter; guard fires |
| `ThreeOmegaWorkspaceStore+Pack.swift:64` | `_buildPackConfig()` | ThreeOmega | Pack serialization | Serializes empty `selectedSearchResultIDs` array |
| `ThreeOmegaWorkspaceStore+ManifestCache.swift:185` | `_snapshotAndCacheManifestPayloads()` | ThreeOmega | Manifest cache | Empty set → manifests built with no selection context |

### 6b. Tests that inject selectionReader

| Test file | Test name | Why it injects | Gate 7.7B migration plan |
|---|---|---|---|
| `V537PackRestoreModuleBoundaryTests.swift:376` | `aheRestoreNilIngestionActivatesRunAnalysis` | Needs to seed selection IDs *after* `restoreFromPack` calls `seedSelection`, so the reader captures a mutable local variable that the `seedSelection` callback populates mid-restore | Replace closure with `SelectionReadingFake`; fake exposes a mutable `selectedIDs` set that the test populates the same way |
| `V537AHESearchSnapshotConsumptionTests.swift:106` | `nilSelectedSnapshotFallsBackToCache` | Needs `selectionReader` to return `hitA.id` so the cache-fallback path selects a hit that is absent from `cachedSearchResults`, triggering the guard | Replace closure with `SelectionReadingFake` seeded with `hitA.id`; identical observable behavior |

### 6c. Option comparison

| Option | Description | Test surface | Retain cycle risk | Scope |
|---|---|---|---|---|
| **A — keep closure bridge** | Leave `selectionReader: (() -> Set<String>)?` as-is | Direct closure injection (current) | Mitigated by `[weak self]` in assignments, but untyped | No change |
| **B — typed `SelectionReading` protocol** | Define `protocol SelectionReading`; stores hold `weak var selectionReading: (any SelectionReading)?`; inject at init | `SelectionReadingFake` conformance; no closure needed | Mitigated by weak reference, typed | Replaces closure in 3 stores + 3 WFS assignments + 2 tests |
| **C — move selection-dependent ops out of stores** | Analysis filtering, pack serialization, and manifest caching that read selection move to a coordinator / use case layer; stores become selection-unaware | No injection needed in stores; coordinator tested independently | No cycle; stores no longer touch selection | Much larger; touches analysis, pack, and manifest subsystems |

### 6d. Recommendation

**Option B is the chosen path for Gate 7.7B.**

It removes the untyped closure bridge, makes the selection dependency explicit and testable via a named protocol, and mirrors the existing `WorkbenchSaveCoordinating` pattern already in this codebase. The change is localized to three store files, `WorkbenchFeatureStore` init wiring, and two test files. No observable behavior changes.

### 6e. Limitation of Option B

Option B does **not** fully remove the selection dependency from workspace stores. It converts the dependency from an untyped closure bridge to a typed selection-runtime bridge — the stores still call into selection state at analysis time, pack-build time, and manifest-cache time.

Complete removal of selection coupling from workspace stores would require moving those responsibilities (analysis hit filtering, pack serialization of selected IDs, manifest payload caching with selection context) into a coordinator or use-case layer. That is a significantly larger refactor that touches the analysis, pack, and manifest subsystems and is out of scope for Gate 7.7.
