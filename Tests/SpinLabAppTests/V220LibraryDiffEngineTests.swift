import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V2.2.0 Library Diff Engine", .serialized)
struct V220LibraryDiffEngineTests {
    @Test("numeric key normalization matches oxygen pressure only")
    func numericKeyNormalizationMatchesOxygenPressureOnly() {
        // LibraryRegistryParser.normalizeNumericKey(_:) is a static function that reads
        // SpinLabRuleProvider.shared / RuleLoader.shared global state directly — there is
        // no instance-level injection point (unlike LibraryRegistryParser's instance API),
        // so the bundled Rules Book's numericKeyAliases table must be applied by
        // reconfiguring the global RuleLoader for the duration of this test, then restored.
        let savedPaths = configureBundledRulesGlobally()
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }

        #expect(LibraryRegistryParser.normalizeNumericKey("氧压") == "氧压")
        #expect(LibraryRegistryParser.normalizeNumericKey("pressure") == "氧压")
        #expect(LibraryRegistryParser.normalizeNumericKey("压强") == nil)
    }

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
        // LibraryDiffEngine.fieldChanges(...) determines isNumeric via the static
        // LibraryRegistryParser.normalizeNumericKey(_:), which reads global RuleLoader
        // state — needs the bundled Rules Book's numericKeyAliases ("温度" -> [...]) active.
        let savedPaths = configureBundledRulesGlobally()
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }

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

    /// Points the global RuleLoader at the bundled dev-fixture Rules Book
    /// (Sources/SpinLabApp/config) for tests that exercise APIs with no instance-level
    /// rule-provider injection point (e.g. LibraryRegistryParser.normalizeNumericKey(_:),
    /// a static function reading SpinLabRuleProvider.shared directly). Returns the
    /// previously-configured book paths so callers can restore them in a `defer` — this
    /// mutates process-wide static state and MUST be paired with a restore so other tests
    /// in the same `swift test` process are not affected.
    @discardableResult
    private func configureBundledRulesGlobally() -> RulesConfigPaths? {
        let bundledDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SpinLabApp/config")
        let savedPaths = RuleLoader.currentBookPaths
        RuleLoader.configure(bookPaths: RulesConfigPaths(configDirectoryURL: bundledDir), internalPaths: AppInternalPaths())
        _ = RuleLoader.shared.reloadCached()
        return savedPaths
    }
}
