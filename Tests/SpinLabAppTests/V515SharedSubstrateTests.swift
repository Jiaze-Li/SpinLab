import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.5 Substrate v2 Validation", .serialized)
struct V515SharedSubstrateTests {

    private static let backupExtension = "v515-substrate-backup"

    private func acquireIsolation() throws -> (dir: URL, backup: URL?) {
        let dir = RulesConfigPaths().configDirectoryURL
        let fm = FileManager.default
        var backup: URL? = nil
        if fm.fileExists(atPath: dir.path) {
            let candidate = dir.appendingPathExtension("\(Self.backupExtension).\(UUID().uuidString)")
            try fm.moveItem(at: dir, to: candidate)
            backup = candidate
        }
        return (dir, backup)
    }

    private func releaseIsolation(dir: URL, backup: URL?) {
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        if let backup, fm.fileExists(atPath: backup.path) {
            try? fm.moveItem(at: backup, to: dir)
        }
        _ = RuleLoader.shared.reloadCached()
    }

    private func makeStore(conditionIDs: [String] = ["temperature"]) throws -> RulesManagementStore {
        let paths = RulesConfigPaths()
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
        {"version":3,"sampleId":{"patterns":[]},"substrate":{"substrateTagRules":[],"materials":[{"id":"STO","tokens":["STO"],"aliases":[],"displayName":"STO"}],"treatments":[],"orientations":{"pattern":"\\\\d{3}","rows":[{"id":"001","tokens":["001"],"aliases":[]}]}}}
        """.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)

        try """
        {"version":1,"workflows":[],"measurementTagRules":[]}
        """.data(using: .utf8)!.write(to: paths.workflowURL)

        let defs = conditionIDs.map { "{\"id\":\"\($0)\",\"label\":\"\($0)\",\"kind\":\"unit_suffix\",\"unitPattern\":\"^\\\\d+$\"}" }.joined(separator: ",")
        try """
        {"version":2,"conditionDefinitions":[\(defs)]}
        """.data(using: .utf8)!.write(to: paths.measuringConditionURL)

        let store = RulesManagementStore()
        store.present()
        return store
    }

    // MARK: - Tests

    @Test("duplicate material ID fails validation")
    func duplicateMaterialIDFails() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let store = try makeStore()

        var draft = try #require(store.sampleIdentificationDraft)
        let extra = SampleIdentificationFileDraft.MaterialDefinition(
            id: "STO", tokens: ["STRONTIUM"], aliases: [], displayName: "STO duplicate"
        )
        draft.substrate.materials.append(extra)
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.message.contains("Duplicate") && $0.message.contains("STO") }))
    }

    @Test("duplicate orientation row ID fails validation")
    func duplicateOrientationRowIDFails() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let store = try makeStore()

        var draft = try #require(store.sampleIdentificationDraft)
        let extra = SampleIdentificationFileDraft.OrientationConfig.Row(
            id: "001", tokens: ["001"], aliases: []
        )
        draft.substrate.orientations.rows.append(extra)
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.message.contains("Duplicate") && $0.message.contains("001") }))
    }

    @Test("valid substrate config saves successfully")
    func validSubstrateConfigSavesSuccessfully() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let store = try makeStore()

        var draft = try #require(store.sampleIdentificationDraft)
        let newMaterial = SampleIdentificationFileDraft.MaterialDefinition(
            id: "NGO", tokens: ["NGO"], aliases: ["NdGaO3"], displayName: "NGO"
        )
        draft.substrate.materials.append(newMaterial)
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved for valid substrate config"); return
        }
    }

    @Test("invalid orientation pattern regex fails validation")
    func invalidOrientationPatternFails() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let store = try makeStore()

        var draft = try #require(store.sampleIdentificationDraft)
        draft.substrate.orientations.pattern = "([bad"
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.field.contains("orientations.pattern") }))
    }
}
