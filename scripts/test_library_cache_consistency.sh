#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/spinlab_library_cache_consistency.XXXXXX)"
TMP_SWIFT="$TMP_DIR/main.swift"
TMP_BIN="$TMP_DIR/spinlab_library_cache_consistency"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$TMP_SWIFT" <<'SWIFT'
import Foundation

func makeBatch(_ id: String) -> LibraryBatch {
    LibraryBatch(
        id: id,
        displayName: id,
        sheetName: "Sheet",
        metadata: [:],
        numericTags: [:],
        numericDisplay: [:],
        sampleKeys: [],
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

let fm = FileManager.default
let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("spinlab_cache_consistency_\(UUID().uuidString)", isDirectory: true)
let store = LibraryStore()
store.ensureRoot(at: root)

defer { try? fm.removeItem(at: root) }

// Probe 1: new batch should be discoverable immediately after create
for i in 0..<50 {
    _ = store.syncIndexFromFilesystem(rootURL: root)
    let batchId = "PN\(String(format: "%03d", i))"
    let sampleId = "\(batchId)-S001"
    store.createDrawer(for: makeSample(sampleId, batchId: batchId), batch: makeBatch(batchId), rootURL: root)
    let after = store.syncIndexFromFilesystem(rootURL: root)
    assertOrFail(after.batches.contains(where: { $0.id == batchId }), "new batch \(batchId) not visible immediately")
    assertOrFail(after.samples.contains(where: { $0.id == sampleId }), "new sample \(sampleId) not visible immediately")
}

// Probe 2: update should be visible immediately
let updateBatch = "PN900"
let updateSample = "\(updateBatch)-S001"
store.createDrawer(for: makeSample(updateSample, batchId: updateBatch, marker: "before"), batch: makeBatch(updateBatch), rootURL: root)
_ = store.syncIndexFromFilesystem(rootURL: root)
store.updateSample(makeSample(updateSample, batchId: updateBatch, marker: "after"), rootURL: root)
let afterUpdate = store.syncIndexFromFilesystem(rootURL: root)
let updatedMarker = afterUpdate.samples.first(where: { $0.id == updateSample })?.metadata["marker"]
assertOrFail(updatedMarker == "after", "updated sample marker not visible immediately")

// Probe 3: delete should be visible immediately
let deleteBatch = "PN901"
let deleteSample = "\(deleteBatch)-S001"
store.createDrawer(for: makeSample(deleteSample, batchId: deleteBatch), batch: makeBatch(deleteBatch), rootURL: root)
_ = store.syncIndexFromFilesystem(rootURL: root)
store.deleteSampleDrawer(for: makeSample(deleteSample, batchId: deleteBatch), rootURL: root)
let afterDelete = store.syncIndexFromFilesystem(rootURL: root)
assertOrFail(!afterDelete.samples.contains(where: { $0.id == deleteSample }), "deleted sample still visible")

print("PASS: library cache consistency checks")
SWIFT

swiftc -O -o "$TMP_BIN" \
  "$TMP_SWIFT" \
  "$ROOT_DIR/Sources/SpinLabApp/Library/LibraryModels.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Library/LibrarySort.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Library/LibraryStore.swift"

"$TMP_BIN"
