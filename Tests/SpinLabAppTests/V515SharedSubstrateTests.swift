import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.5 Substrate v2 Validation", .serialized)
struct V515SharedSubstrateTests {

    private struct IsolationContext {
        let dir: URL
        let paths: RulesConfigPaths
    }

    private func acquireIsolation() throws -> IsolationContext {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SL-substrate2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return IsolationContext(dir: dir, paths: RulesConfigPaths(configDirectoryURL: dir))
    }

    private func releaseIsolation(_ ctx: IsolationContext) {
        try? FileManager.default.removeItem(at: ctx.dir)
    }

    private func makeStore(_ ctx: IsolationContext, conditionIDs: [String] = ["temperature"]) throws -> RulesManagementStore {
        let paths = ctx.paths
        let fm = FileManager.default
        try? fm.removeItem(at: paths.configDirectoryURL)
        try fm.createDirectory(at: paths.configDirectoryURL, withIntermediateDirectories: true)

        try """
        {"version":1,"import":{"supportedFileExtensions":["csv"],"ignoredFileExtensions":[]}}
        """.data(using: .utf8)!.write(to: paths.importFiltersURL)

        try """
        {"version":1,"tokenization":{"separators":"_","caseFold":"preserve"},"sources":["file"],"channel":{"aliases":{}}}
        """.data(using: .utf8)!.write(to: paths.filenameTokenizationURL)

        try """
        {"version":4,"sampleId":{"batchPrefixes":[]},"substrate":{"materials":[{"displayName":"STO","matches":[{"type":"equals","value":"STO"}]}],"treatments":[],"orientations":[{"displayName":"001","matches":[{"type":"equals","value":"001"}]}]}}
        """.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)

        try """
        {"version":1,"workflows":[],"measurementTagRules":[]}
        """.data(using: .utf8)!.write(to: paths.workflowURL)

        let defs = conditionIDs.map { "{\"id\":\"\($0)\",\"label\":\"\($0)\",\"kind\":\"unit_suffix\",\"unitPattern\":\"^\\\\d+$\"}" }.joined(separator: ",")
        try """
        {"version":2,"conditionDefinitions":[\(defs)]}
        """.data(using: .utf8)!.write(to: paths.measuringConditionURL)

        let store = RulesManagementStore(rulesBookPaths: paths)
        store.present()
        return store
    }

    // MARK: - Tests

    @Test("duplicate material display name fails validation")
    func duplicateMaterialDisplayNameFails() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let store = try makeStore(ctx)

        var draft = try #require(store.sampleIdentificationDraft)
        let extra = SampleIdentificationFileDraft.SubstrateEntry(displayName: "STO", matches: [])
        draft.substrate.materials.append(extra)
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.message.contains("Duplicate") && $0.message.contains("STO") }))
    }

    @Test("duplicate orientation display name fails validation")
    func duplicateOrientationDisplayNameFails() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let store = try makeStore(ctx)

        var draft = try #require(store.sampleIdentificationDraft)
        let extra = SampleIdentificationFileDraft.SubstrateEntry(displayName: "001", matches: [])
        draft.substrate.orientations.append(extra)
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.message.contains("Duplicate") && $0.message.contains("001") }))
    }

    @Test("valid substrate config saves successfully")
    func validSubstrateConfigSavesSuccessfully() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }
        let store = try makeStore(ctx)

        var draft = try #require(store.sampleIdentificationDraft)
        let newMaterial = SampleIdentificationFileDraft.SubstrateEntry(
            displayName: "NGO",
            matches: [.init(type: "equals", value: "NGO")]
        )
        draft.substrate.materials.append(newMaterial)
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved for valid substrate config"); return
        }
    }
}
