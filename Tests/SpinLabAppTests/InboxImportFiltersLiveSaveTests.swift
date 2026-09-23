import Foundation
import Testing
@testable import SpinLabApp

/// End-to-end regression: a Rules Panel save of Import Filters must change what the SAME
/// long-lived pipeline lets through Inbox scanning + Pending Import on the very next import.
@MainActor
@Suite("Inbox import filters follow Rules save immediately", .serialized)
struct InboxImportFiltersLiveSaveTests {

    private func writeBook(to paths: RulesConfigPaths, supported: [String], ignored: [String]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.configDirectoryURL, withIntermediateDirectories: true)
        let list = { (xs: [String]) in xs.map { "\"\($0)\"" }.joined(separator: ",") }
        try #"{"version":1,"import":{"supportedFileExtensions":[\#(list(supported))],"ignoredFileExtensions":[\#(list(ignored))]}}"#
            .data(using: .utf8)!.write(to: paths.importFiltersURL)
        try #"{"version":1,"tokenization":{"separators":"_","caseFold":"preserve"},"sources":["file"],"channel":{"aliases":{}}}"#
            .data(using: .utf8)!.write(to: paths.filenameTokenizationURL)
        try #"{"version":4,"sampleId":{"batchPrefixes":["PN"]},"substrate":{"materials":[],"treatments":[],"orientations":[]}}"#
            .data(using: .utf8)!.write(to: paths.sampleIdentificationURL)
        try #"{"version":1,"workflows":[{"id":"MR","displayName":"MR","matchRules":[{"scope":"tokens","type":"equals","value":"MR"}],"conditionFieldIDs":["temperature"]}],"measurementTagRules":[]}"#
            .data(using: .utf8)!.write(to: paths.workflowURL)
        try #"{"version":2,"conditionDefinitions":[{"id":"temperature","label":"Temperature","kind":"unit_suffix","unitPattern":"^\\d+K$"}]}"#
            .data(using: .utf8)!.write(to: paths.measuringConditionURL)
    }

    /// Runs the production Inbox scan + pipeline with the pipeline's CURRENT extension sets.
    private func pending(
        _ pipeline: SpinLabImportPipeline, urls: [URL]
    ) -> [SpinLabDomain.PendingImport] {
        let filter = InboxImportFilterService()
        let files = filter.importMeasurementFiles(
            from: urls,
            allowedFileExtensions: pipeline.supportedFileExtensions,
            ignoredFileExtensions: pipeline.ignoredFileExtensions
        )
        return pipeline.importFiles(files)
    }

    private func save(_ store: RulesManagementStore, supported: [String], ignored: [String]) throws {
        var draft = try #require(store.importFiltersDraft)
        draft.config.supportedFileExtensions = supported
        draft.config.ignoredFileExtensions = ignored
        store.updateImportFilters(draft)
        store.selectSection(.importFilters)
        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved"); return
        }
    }

    @Test("Rules save adds/removes/ignores an extension on the same long-lived pipeline")
    func saveAffectsNextImport() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SL-inbox-live-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = RulesConfigPaths(configDirectoryURL: dir)
        try writeBook(to: paths, supported: ["csv", "txt", "dat", "lvm"], ignored: ["gph"])

        let savedPaths = RuleLoader.currentBookPaths
        RuleLoader.configure(bookPaths: paths, internalPaths: AppInternalPaths())
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }

        // Long-lived production-style pipeline, built ONCE with the default live provider.
        let pipeline = SpinLabImportPipeline(
            workflowExtension: AMRPHEWorkflowExtension(),
            metadataExtension: AMRPHEMetadataExtension()
        )

        let inbox = dir.appendingPathComponent("inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        var counter = 0
        // Fresh path/name/content each time so dedupe never masks extension behavior.
        func sample(_ ext: String) throws -> URL {
            counter += 1
            let url = inbox.appendingPathComponent("PN\(counter)_MR_new\(counter).\(ext)")
            try "data-\(UUID().uuidString)".write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        let store = RulesManagementStore(rulesBookPaths: paths)
        store.present()

        // 1. unsupported → rejected
        #expect(pending(pipeline, urls: [try sample("ibw")]).isEmpty)
        // 5. existing formats unchanged
        for ext in ["csv", "txt", "dat", "lvm"] {
            #expect(pending(pipeline, urls: [try sample(ext)]).count == 1, "\(ext) must still import")
        }
        #expect(pending(pipeline, urls: [try sample("gph")]).isEmpty)

        // 2. save into Supported → accepted immediately
        try save(store, supported: ["csv", "txt", "dat", "lvm", "ibw"], ignored: ["gph"])
        #expect(pending(pipeline, urls: [try sample("ibw")]).count == 1)

        // 4. move to Ignored via the Rules save path → rejected immediately
        try save(store, supported: ["csv", "txt", "dat", "lvm"], ignored: ["gph", "ibw"])
        #expect(pending(pipeline, urls: [try sample("ibw")]).isEmpty)

        // AC3. the Rules Panel refuses overlap, but a hand-edited Rule Book can still have it:
        // Ignored must win on the next import.
        try writeBook(to: paths, supported: ["csv", "ibw"], ignored: ["ibw"])
        _ = RuleLoader.shared.reloadCached()
        #expect(pending(pipeline, urls: [try sample("ibw")]).isEmpty)
        try writeBook(to: paths, supported: ["csv", "txt", "dat", "lvm", "ibw"], ignored: ["gph"])
        _ = RuleLoader.shared.reloadCached()
        store.present()
        #expect(pending(pipeline, urls: [try sample("ibw")]).count == 1)

        // 3. removed → rejected
        try save(store, supported: ["csv", "txt", "dat", "lvm"], ignored: ["gph"])
        #expect(pending(pipeline, urls: [try sample("ibw")]).isEmpty)
    }
}
