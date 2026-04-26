import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.5 Shared Substrate Validation", .serialized)
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
        {"version":1,"sampleId":{"patterns":[]},"substrate":{"substrateTagRules":[],"shared":{"tokenSeparators":"_","originStandaloneTokens":[],"originContainsTokens":[],"treatmentKeywords":{},"materialTokens":["STO"],"materialAliases":{},"materialDisplayNames":{},"orientationTokens":["001"],"orientationAliases":{},"orientationPattern":"\\\\d{3}"}}}
        """.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)

        try """
        {"version":1,"workflows":[],"measurementTagRules":[]}
        """.data(using: .utf8)!.write(to: paths.workflowURL)

        let defs = conditionIDs.map { "{\"id\":\"\($0)\",\"label\":\"\($0)\",\"kind\":\"unit_suffix\",\"binding\":\"conditions.extraConditions.\($0)\"}" }.joined(separator: ",")
        let extras = conditionIDs.map { "\"\($0)\":\"^\\\\d+$\"" }.joined(separator: ",")
        try """
        {"version":1,"batch":{"preferSampleId":true,"fallbackPatterns":[]},"conditions":{"extraConditions":{\(extras)},"tokenMapRules":{},"displayLabels":{}},"conditionDefinitions":[\(defs)]}
        """.data(using: .utf8)!.write(to: paths.measuringConditionURL)

        let store = RulesManagementStore()
        store.present()
        return store
    }

    // MARK: - Tests

    @Test("orientationAlias pointing to nonexistent orientationToken fails")
    func orientationAliasUnknownTargetFails() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let store = try makeStore()

        var draft = try #require(store.sampleIdentificationDraft)
        // "111" is not in orientationTokens (only "001" is)
        draft.substrate.shared?.orientationAliases = ["badAlias": "111"]
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.field.contains("orientationAliases") }))
    }

    @Test("substrate with no shared block saves without error")
    func nilSharedConfigSavesSuccessfully() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let store = try makeStore()

        var draft = try #require(store.sampleIdentificationDraft)
        draft.substrate.shared = nil
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved when shared is nil"); return
        }
    }

    @Test("valid materialAlias pointing to existing token saves successfully")
    func validMaterialAliasSavesSuccessfully() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let store = try makeStore()

        var draft = try #require(store.sampleIdentificationDraft)
        // "STO" is already in materialTokens; alias pointing to it is valid
        draft.substrate.shared?.materialAliases = ["SrTiO3": "STO"]
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .saved = store.saveCurrent() else {
            Issue.record("Expected .saved for valid materialAlias"); return
        }
    }

    @Test("invalid orientationPattern regex fails")
    func invalidOrientationPatternFails() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let store = try makeStore()

        var draft = try #require(store.sampleIdentificationDraft)
        draft.substrate.shared?.orientationPattern = "([bad"
        store.updateSampleIdentification(draft)
        store.selectSection(.sampleIdentification)

        guard case .validationFailed(let errors) = store.saveCurrent() else {
            Issue.record("Expected validationFailed"); return
        }
        #expect(errors.contains(where: { $0.field.contains("orientationPattern") }))
    }
}
