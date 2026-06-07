import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.12 RulesManagementStore setBatchPrefixes", .serialized)
struct V5112RulesManagementStoreBatchPrefixesTests {

    // MARK: - Isolation

    private struct IsolationContext {
        let dir: URL
        let paths: RulesConfigPaths
    }

    private func acquireIsolation() throws -> IsolationContext {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SL-batch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return IsolationContext(dir: dir, paths: RulesConfigPaths(configDirectoryURL: dir))
    }

    private func releaseIsolation(_ ctx: IsolationContext) {
        try? FileManager.default.removeItem(at: ctx.dir)
    }

    private func seedSampleIdentification(at url: URL, prefixes: [String]) throws {
        let matches = prefixes.map { ["type": "starts-with", "value": $0] }
        let json: [String: Any] = [
            "version": 1,
            "sampleId": ["matches": matches],
            "substrate": ["materials": [], "treatments": [], "orientations": []]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: url)
    }

    // MARK: - Tests

    @Test("setBatchPrefixes retains only startsWith specs and discards other types")
    func setBatchPrefixesFiltersToStartsWithOnly() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }

        try seedSampleIdentification(at: ctx.paths.sampleIdentificationURL, prefixes: ["PN", "PT"])

        let store = RulesManagementStore(rulesBookPaths: ctx.paths)
        store.present()

        let mixedSpecs: [FilenameRuleSet.MatchSpec] = [
            FilenameRuleSet.MatchSpec(type: .startsWith, value: "PN"),
            FilenameRuleSet.MatchSpec(type: .startsWith, value: "PT"),
            FilenameRuleSet.MatchSpec(type: .equals, value: "shouldBeDropped"),
            FilenameRuleSet.MatchSpec(type: .contains, value: "alsoDropped"),
        ]

        store.setBatchPrefixes(from: mixedSpecs)

        let result = store.sampleIdentificationDraft?.sampleId.batchPrefixes ?? []
        #expect(result == ["PN", "PT"])
        #expect(!result.contains("shouldBeDropped"))
        #expect(!result.contains("alsoDropped"))
    }

    @Test("setBatchPrefixes marks sampleIdentification section as dirty")
    func setBatchPrefixesMarksDirty() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }

        try seedSampleIdentification(at: ctx.paths.sampleIdentificationURL, prefixes: ["PN"])

        let store = RulesManagementStore(rulesBookPaths: ctx.paths)
        store.present()

        store.setBatchPrefixes(from: [FilenameRuleSet.MatchSpec(type: .startsWith, value: "PT")])

        #expect(store.dirtySections.contains(.sampleIdentification))
    }

    @Test("setBatchPrefixes with empty input clears all prefixes")
    func setBatchPrefixesClearsAll() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }

        try seedSampleIdentification(at: ctx.paths.sampleIdentificationURL, prefixes: ["PN", "PT"])

        let store = RulesManagementStore(rulesBookPaths: ctx.paths)
        store.present()

        store.setBatchPrefixes(from: [])

        let result = store.sampleIdentificationDraft?.sampleId.batchPrefixes ?? ["not-empty"]
        #expect(result.isEmpty)
    }
}
