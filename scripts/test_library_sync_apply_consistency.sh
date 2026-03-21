#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/spinlab_library_sync_apply_consistency.XXXXXX)"
TMP_SWIFT="$TMP_DIR/main.swift"
TMP_BIN="$TMP_DIR/spinlab_library_sync_apply_consistency"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$TMP_SWIFT" <<'SWIFT'
import Foundation

enum LibraryRegistryParser {
    static func normalizeNumericKey(_ key: String) -> String? {
        let normalized = key.replacingOccurrences(of: " ", with: "").lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

func makeBatch(_ id: String, sampleKeys: [String]) -> LibraryBatch {
    LibraryBatch(
        id: id,
        displayName: id,
        sheetName: "Sheet",
        metadata: [:],
        numericTags: [:],
        numericDisplay: [:],
        sampleKeys: sampleKeys,
        updatedAt: Date()
    )
}

func makeSample(_ id: String, batchId: String, marker: String = "v") -> LibrarySample {
    LibrarySample(
        id: id,
        displayName: id,
        batchId: batchId,
        substrateRaw: "STO",
        substrateDisplay: "STO",
        substrateTokens: ["STO"],
        substrateTags: ["STO"],
        metadata: ["marker": marker],
        orderedMetadata: [],
        numericTags: [:],
        numericDisplay: [:],
        updatedAt: Date()
    )
}

func assertOrFail(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func makePreview(_ samples: [LibrarySample], _ batches: [LibraryBatch]) -> LibraryPreview {
    LibraryPreview(
        index: LibraryIndex(
            createdAt: Date(),
            updatedAt: Date(),
            registryInternalPath: nil,
            registrySourcePath: nil,
            metadataColumnOrder: ["marker"],
            batches: batches,
            samples: samples
        ),
        warnings: []
    )
}

let fm = FileManager.default
let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("spinlab_sync_apply_consistency_\(UUID().uuidString)", isDirectory: true)
let store = LibraryStore()
let diffEngine = LibraryDiffEngine()
let syncService = LibrarySyncService(libraryStore: store, libraryDiffEngine: diffEngine)
let settings = LibrarySettings.default

defer { try? fm.removeItem(at: root) }
store.ensureRoot(at: root)

// Flow 1: apply all should clear pending immediately.
let sampleA = makeSample("PN100-S001", batchId: "PN100", marker: "A")
let previewAll = makePreview([sampleA], [makeBatch("PN100", sampleKeys: [sampleA.id])])
let preDiffAll = syncService.diff(rootURL: root, previewIndex: previewAll.index).diff
assertOrFail(preDiffAll.newSamples.count == 1, "expected one pending sample before apply all")
syncService.applyAll(preview: previewAll, rootURL: root, settings: settings)
let postApplyIndex = store.syncIndexFromFilesystem(rootURL: root)
assertOrFail(postApplyIndex.samples.contains(where: { $0.id == sampleA.id }), "library existing not updated after apply all")
let postDiffAll = diffEngine.diff(current: postApplyIndex, updated: previewAll.index)
assertOrFail(postDiffAll.newSamples.isEmpty && postDiffAll.changedSamples.isEmpty && postDiffAll.removedSamples.isEmpty, "pending queue not cleared after apply all")

// Flow 2: apply selected(batch) should clear that batch and keep others pending.
let sampleB = makeSample("PN101-S001", batchId: "PN101", marker: "B")
let sampleC = makeSample("PN102-S001", batchId: "PN102", marker: "C")
let previewSelected = makePreview(
    [sampleA, sampleB, sampleC],
    [
        makeBatch("PN100", sampleKeys: [sampleA.id]),
        makeBatch("PN101", sampleKeys: [sampleB.id]),
        makeBatch("PN102", sampleKeys: [sampleC.id])
    ]
)
let preDiffSelected = syncService.diff(rootURL: root, previewIndex: previewSelected.index).diff
assertOrFail(preDiffSelected.newSamples.count == 2, "expected two pending samples before apply selected")
let selectedResult = syncService.applyBatch(
    batchId: "PN101",
    preview: previewSelected,
    rootURL: root,
    settings: settings
)
assertOrFail(selectedResult?.touchedSamples == 1, "apply selected did not touch expected sample count")
let postSelectedIndex = store.syncIndexFromFilesystem(rootURL: root)
assertOrFail(postSelectedIndex.samples.contains(where: { $0.id == sampleB.id }), "selected batch not reflected in existing library")
let postDiffSelected = diffEngine.diff(current: postSelectedIndex, updated: previewSelected.index)
assertOrFail(postDiffSelected.newSamples.count == 1, "pending queue count after apply selected is incorrect")
assertOrFail(postDiffSelected.newSamples.first?.id == sampleC.id, "wrong pending sample remained after apply selected")

print("PASS: library sync/apply consistency checks")
SWIFT

swiftc -O -o "$TMP_BIN" \
  "$TMP_SWIFT" \
  "$ROOT_DIR/Sources/SpinLabApp/Library/LibraryModels.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Library/LibrarySort.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Library/LibraryStore.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Library/LibraryXLSXSyncService.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Library/LibraryDiffEngine.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Library/LibrarySyncService.swift"

"$TMP_BIN"
