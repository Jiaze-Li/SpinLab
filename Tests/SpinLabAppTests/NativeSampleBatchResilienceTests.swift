import Foundation
import Testing
@testable import SpinLabApp

@Suite("Native Sample Protection - Batch Resilience")
struct NativeSampleBatchResilienceTests {
    private func makeTempLibrary() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-native-resilience-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func registrySample(id: String, batch: String, target: String) -> LibrarySample {
        LibrarySample(
            id: id, displayName: "Registry \(id)", batchId: batch, substrateRaw: "STO", substrateDisplay: "STO",
            substrateTokens: ["sto"], substrateTags: [], metadata: ["Target": target], orderedMetadata: [],
            numericTags: [:], numericDisplay: [:], sourceSheetName: "Sheet1", sourceRowNumber: 2,
            updatedAt: Date()
        )
    }

    private func registryBatch(id: String, sampleKeys: [String]) -> LibraryBatch {
        LibraryBatch(
            id: id, displayName: id, sheetName: "Sheet1", metadata: [:], numericTags: [:], numericDisplay: [:],
            sampleKeys: sampleKeys, updatedAt: Date()
        )
    }

    private func preview(batch: LibraryBatch, samples: [LibrarySample]) -> LibraryPreview {
        LibraryPreview(
            index: LibraryIndex(
                createdAt: Date(), updatedAt: Date(), registryInternalPath: nil, registrySourcePath: nil,
                batches: [batch], samples: samples
            ),
            warnings: []
        )
    }

    private func makeNative(root: URL, store: LibraryStore) throws -> LibrarySample {
        let draft = CreateNativeSampleDraft(
            batchId: "RB", substrateIdentity: "S1", substrateDescription: "STO",
            displayName: "Native One", metadata: ["Target": "Native"]
        )
        let outcome = NativeSampleCreationService().createSample(
            draft: draft, rootURL: root, libraryStore: store, settings: .default
        )
        guard case let .success(sample, _, _) = outcome else {
            throw CocoaError(.fileWriteUnknown)
        }
        return sample
    }

    @Test("A native conflict skips only that sample; the others are still created (preview and selection)")
    func nativeConflictDoesNotBlockOtherSamples() throws {
        let root = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let native = try makeNative(root: root, store: store)
        let service = LibraryMutationService()

        let conflicting = registrySample(id: native.id, batch: "RB", target: "WRONG")
        let clean1 = registrySample(id: "RB_REG1", batch: "RB", target: "A")
        let clean2 = registrySample(id: "RB_REG2", batch: "RB", target: "B")
        let batch = registryBatch(id: "RB", sampleKeys: [native.id, clean1.id, clean2.id])
        let prev = preview(batch: batch, samples: [conflicting, clean1, clean2])

        let fromPreview = service.createDrawersFromPreview(
            preview: prev, rootPath: root.path, libraryStore: store, settings: .default
        )
        guard case let .partial(_, _, created, message) = fromPreview else {
            Issue.record("Expected partial outcome, got \(fromPreview)")
            return
        }
        #expect(created == 2)
        #expect(message.contains("Cannot overwrite existing native sample"))

        let index = try store.readOnlyCompleteIndex(rootURL: root)
        #expect(index.samples.contains { $0.id == "RB_REG1" })
        #expect(index.samples.contains { $0.id == "RB_REG2" })
        #expect(index.samples.first { $0.id == native.id }?.metadata["Target"] == "Native")

        // Selection path (whole batch): same behaviour on a fresh library.
        let root2 = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: root2) }
        let store2 = LibraryStore()
        try store2.ensureRootDirectories(at: root2)
        let native2 = try makeNative(root: root2, store: store2)
        let conflicting2 = registrySample(id: native2.id, batch: "RB", target: "WRONG")
        let prev2 = preview(batch: batch, samples: [conflicting2, clean1, clean2])
        let fromSelection = service.createDrawersForSelection(
            preview: prev2, rootPath: root2.path, batchId: "RB", sampleId: nil,
            libraryStore: store2, settings: .default
        )
        guard case let .partial(_, _, created2, _) = fromSelection else {
            Issue.record("Expected partial outcome, got \(fromSelection)")
            return
        }
        #expect(created2 == 2)
        let index2 = try store2.readOnlyCompleteIndex(rootURL: root2)
        #expect(index2.samples.contains { $0.id == "RB_REG1" })
        #expect(index2.samples.first { $0.id == native2.id }?.metadata["Target"] == "Native")
    }

    @Test("A deferred numeric change is skipped when a native sample now owns the id")
    func deferredNumericChangeRechecksNativeConflict() throws {
        let root = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore()
        try store.ensureRootDirectories(at: root)
        let native = try makeNative(root: root, store: store)
        let service = LibraryMutationService()

        let stale = registrySample(id: native.id, batch: "RB", target: "STALE")
        let change = LibrarySampleChange(sample: stale, fieldChanges: [], requiresConfirm: true)
        let review = LibraryRefreshReview(
            generatedAt: Date(), newSamples: [], changedSamples: [], removedSamples: [],
            changedBatches: [], removedBatches: [], autoAppliedChanges: [], deferredNumericChanges: [change]
        )
        let prev = preview(batch: registryBatch(id: "RB", sampleKeys: [native.id]), samples: [stale])

        let outcome = service.confirmNumericRefreshChanges(
            review: review, preview: prev, rootPath: root.path, settings: .default, libraryStore: store
        )
        guard case let .success(updatedReview, appliedCount, _) = outcome else {
            Issue.record("Expected success outcome, got \(outcome)")
            return
        }
        #expect(appliedCount == 0)
        #expect(updatedReview.deferredNumericChanges.count == 1)
        let reloaded = try store.readOnlyCompleteIndex(rootURL: root)
        #expect(reloaded.samples.first { $0.id == native.id }?.metadata["Target"] == "Native")
    }

    @Test("Applying to a Library Root that does not exist yet creates it instead of failing")
    func applyAllCreatesMissingRoot() throws {
        let parent = try makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appending(path: "NotYetCreated", directoryHint: .isDirectory)
        let store = LibraryStore()
        let sync = LibrarySyncService(libraryStore: store, libraryDiffEngine: LibraryDiffEngine())
        let prev = preview(batch: registryBatch(id: "RB", sampleKeys: []), samples: [])

        #expect(!FileManager.default.fileExists(atPath: root.path))
        _ = try sync.applyAll(preview: prev, rootURL: root, settings: .default)
        #expect(FileManager.default.fileExists(atPath: root.path))
    }
}
