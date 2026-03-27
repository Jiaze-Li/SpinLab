import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.2.0 Library Diff Engine")
struct V220LibraryDiffEngineTests {
    @Test("empty-like values do not produce pending changes")
    func emptyLikeValuesAreIgnored() {
        let engine = LibraryDiffEngine()
        let sampleID = "PN17|o|STO|111"
        let oldIndex = makeIndex(
            sample: makeSample(
                id: sampleID,
                batchId: "PN17",
                metadata: ["温度": ""]
            )
        )
        let newIndex = makeIndex(
            sample: makeSample(
                id: sampleID,
                batchId: "PN17",
                metadata: ["温度": "   "]
            )
        )

        let diff = engine.diff(current: oldIndex, updated: newIndex)

        #expect(diff.changedSamples.isEmpty)
    }

    @Test("hidden key prefix is normalized and does not create fake change")
    func hiddenPrefixInMetadataKeyIsNormalized() {
        let engine = LibraryDiffEngine()
        let sampleID = "PN17|o|STO|111"
        let oldIndex = makeIndex(
            sample: makeSample(
                id: sampleID,
                batchId: "PN17",
                metadata: ["\u{FEFF}厚度": "12"]
            )
        )
        let newIndex = makeIndex(
            sample: makeSample(
                id: sampleID,
                batchId: "PN17",
                metadata: ["厚度": "12"]
            )
        )

        let diff = engine.diff(current: oldIndex, updated: newIndex)

        #expect(diff.changedSamples.isEmpty)
    }

    @Test("real metadata change remains visible after normalization")
    func realMetadataChangeStillDetected() {
        let engine = LibraryDiffEngine()
        let sampleID = "PN17|o|STO|111"
        let oldIndex = makeIndex(
            sample: makeSample(
                id: sampleID,
                batchId: "PN17",
                metadata: ["\u{FEFF}温度": "700"]
            )
        )
        let newIndex = makeIndex(
            sample: makeSample(
                id: sampleID,
                batchId: "PN17",
                metadata: ["温度": "750"]
            )
        )

        let diff = engine.diff(current: oldIndex, updated: newIndex)

        #expect(diff.changedSamples.count == 1)
        #expect(diff.changedSamples[0].fieldChanges.count == 1)
        #expect(diff.changedSamples[0].fieldChanges[0].key == "温度")
        #expect(diff.changedSamples[0].fieldChanges[0].oldValue == "700")
        #expect(diff.changedSamples[0].fieldChanges[0].newValue == "750")
        #expect(diff.changedSamples[0].fieldChanges[0].isNumeric)
    }

    @Test("non-empty to empty still reports change")
    func nonEmptyToEmptyReportsChange() {
        let engine = LibraryDiffEngine()
        let sampleID = "PN17|o|STO|111"
        let oldIndex = makeIndex(
            sample: makeSample(
                id: sampleID,
                batchId: "PN17",
                metadata: ["备注": "changed"]
            )
        )
        let newIndex = makeIndex(
            sample: makeSample(
                id: sampleID,
                batchId: "PN17",
                metadata: ["备注": " "]
            )
        )

        let diff = engine.diff(current: oldIndex, updated: newIndex)

        #expect(diff.changedSamples.count == 1)
        #expect(diff.changedSamples[0].fieldChanges.count == 1)
        #expect(diff.changedSamples[0].fieldChanges[0].key == "备注")
        #expect(diff.changedSamples[0].fieldChanges[0].oldValue == "changed")
        #expect(diff.changedSamples[0].fieldChanges[0].newValue == nil)
    }

    private func makeIndex(sample: LibrarySample) -> LibraryIndex {
        let batch = LibraryBatch(
            id: sample.batchId,
            displayName: sample.batchId,
            sheetName: "Sheet1",
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            sampleKeys: [sample.id],
            updatedAt: .now
        )
        return LibraryIndex(
            createdAt: .now,
            updatedAt: .now,
            registryInternalPath: nil,
            registrySourcePath: nil,
            metadataColumnOrder: [],
            batches: [batch],
            samples: [sample]
        )
    }

    private func makeSample(id: String, batchId: String, metadata: [String: String]) -> LibrarySample {
        LibrarySample(
            id: id,
            displayName: "\(batchId) - test",
            batchId: batchId,
            substrateRaw: "STO(111)",
            substrateDisplay: "test STO(111)",
            substrateTokens: ["test", "STO", "111"],
            substrateTags: ["test", "STO111"],
            metadata: metadata,
            orderedMetadata: metadata
                .keys
                .sorted()
                .map { LibraryMetadataItem(key: $0, value: metadata[$0] ?? "") },
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: "Sheet1",
            sourceRowNumber: 2,
            updatedAt: .now
        )
    }
}
