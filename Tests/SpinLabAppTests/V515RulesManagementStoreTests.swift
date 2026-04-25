import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.5 RulesManagementStore")
struct V515RulesManagementStoreTests {

    // MARK: - Setup helpers

    private func freshConfigDir() throws -> URL {
        let dir = RulesConfigPaths().configDirectoryURL
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func seedSampleID(at url: URL, patterns: [String] = ["[A-Z]{2}\\d+"]) throws {
        let json = """
        {"version": 1, "patterns": \(jsonArray(patterns))}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    private func seedFilenameParse(at url: URL) throws {
        let json = """
        {
          "version": 1,
          "tokenization": {"separators": "_- ", "caseFold": "preserve"},
          "sources": ["file"],
          "batch": {"preferSampleId": true, "fallbackPatterns": []},
          "channel": {"aliases": {}},
          "rotationHintRules": [],
          "measurementNameRules": [],
          "conditions": {"extraConditions": {}, "tokenMapRules": {}, "displayLabels": {}},
          "conditionDefinitions": []
        }
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    private func seedWorkflowMatch(at url: URL) throws {
        let json = """
        {"version": 1, "rules": []}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    private func seedSubstrate(at url: URL) throws {
        let json = """
        {
          "version": 1,
          "substrateTagRules": [],
          "sharedSubstrate": {
            "tokenSeparators": "_- ",
            "originStandaloneTokens": [],
            "originContainsTokens": [],
            "treatmentKeywords": {},
            "materialTokens": ["Si"],
            "materialAliases": {},
            "materialDisplayNames": {},
            "orientationTokens": ["100"],
            "orientationAliases": {},
            "orientationPattern": "\\\\d{3}"
          }
        }
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    private func seedAllSchemas() throws -> RulesConfigPaths {
        _ = try freshConfigDir()
        let paths = RulesConfigPaths()
        try seedSampleID(at: paths.sampleIDRulesURL)
        try seedFilenameParse(at: paths.filenameParsRulesURL)
        try seedWorkflowMatch(at: paths.workflowMatchRulesURL)
        try seedSubstrate(at: paths.substrateNormalizationRulesURL)
        return paths
    }

    private func jsonArray(_ values: [String]) -> String {
        let escaped = values.map { "\"\($0.replacingOccurrences(of: "\\", with: "\\\\"))\"" }
        return "[" + escaped.joined(separator: ",") + "]"
    }

    // MARK: - Tests

    @Test("save flow: successful save persists, fires hook, clears dirty")
    func saveFlowSuccess() throws {
        let paths = try seedAllSchemas()

        var hookCalls: [(String, URL, Int, String)] = []
        let store = RulesManagementStore()
        store.persistenceHook = RulesPersistenceHook(didPersist: { section, url, version, checksum in
            hookCalls.append((section, url, version, checksum))
        })
        store.present()

        var draft = try #require(store.sampleIDDraft)
        draft.patterns.append("ABC\\d+")
        store.updateSampleID(draft)
        #expect(store.dirtySections.contains(.sampleID))

        store.selectSection(.sampleID)
        let outcome = store.saveCurrent()
        guard case .saved = outcome else {
            Issue.record("Expected .saved, got \(outcome)")
            return
        }

        #expect(!store.dirtySections.contains(.sampleID))
        #expect(hookCalls.count == 1)
        #expect(hookCalls.first?.0 == "sampleID")
        #expect(hookCalls.first?.2 == 1)

        let writtenData = try Data(contentsOf: paths.sampleIDRulesURL)
        let written = try JSONDecoder().decode(SampleIDRulesFileDraft.self, from: writtenData)
        #expect(written.patterns.contains("ABC\\d+"))
    }

    @Test("validation failure: invalid regex blocks save and reports field error")
    func validationFailureRegex() throws {
        _ = try seedAllSchemas()
        let store = RulesManagementStore()
        store.present()

        var draft = try #require(store.sampleIDDraft)
        draft.patterns.append("[unterminated")
        store.updateSampleID(draft)
        store.selectSection(.sampleID)

        let outcome = store.saveCurrent()
        guard case .validationFailed(let errors) = outcome else {
            Issue.record("Expected .validationFailed, got \(outcome)")
            return
        }
        #expect(!errors.isEmpty)
        #expect(errors.contains(where: { $0.field == "patterns" }))
        #expect(store.dirtySections.contains(.sampleID))
    }

    @Test("validation failure: workflow_match cross-rule token conflict")
    func validationFailureWorkflowMatchConflict() throws {
        _ = try seedAllSchemas()
        let store = RulesManagementStore()
        store.present()

        var draft = try #require(store.workflowMatchDraft)
        draft.rules = [
            .init(workflowID: "alpha", scope: "tokens", type: "equals", matchValues: ["x"]),
            .init(workflowID: "beta",  scope: "tokens", type: "equals", matchValues: ["x"])
        ]
        store.updateWorkflowMatch(draft)
        store.selectSection(.workflowMatch)

        let outcome = store.saveCurrent()
        guard case .validationFailed(let errors) = outcome else {
            Issue.record("Expected .validationFailed, got \(outcome)")
            return
        }
        #expect(errors.contains(where: { $0.message.contains("alpha") && $0.message.contains("beta") }))
    }

    @Test("hash precondition: external mutation triggers .externalConflict")
    func hashPreconditionConflict() throws {
        let paths = try seedAllSchemas()
        let store = RulesManagementStore()
        store.present()

        var draft = try #require(store.sampleIDDraft)
        draft.patterns.append("XYZ\\d+")
        store.updateSampleID(draft)
        store.selectSection(.sampleID)

        // Out-of-band external mutation between open and save
        try seedSampleID(at: paths.sampleIDRulesURL, patterns: ["EXT\\d+"])

        let outcome = store.saveCurrent()
        guard case .externalConflict = outcome else {
            Issue.record("Expected .externalConflict, got \(outcome)")
            return
        }
        #expect(store.dirtySections.contains(.sampleID))
    }

    @Test("override after conflict: writes draft and refreshes hash")
    func overrideAfterConflict() throws {
        let paths = try seedAllSchemas()
        let store = RulesManagementStore()
        store.present()

        var draft = try #require(store.sampleIDDraft)
        draft.patterns = ["MINE\\d+"]
        store.updateSampleID(draft)
        store.selectSection(.sampleID)

        try seedSampleID(at: paths.sampleIDRulesURL, patterns: ["EXT\\d+"])
        _ = store.saveCurrent() // conflict

        let outcome = store.overrideWithCurrentDraft(section: .sampleID)
        guard case .saved = outcome else {
            Issue.record("Expected .saved on override, got \(outcome)")
            return
        }

        let writtenData = try Data(contentsOf: paths.sampleIDRulesURL)
        let written = try JSONDecoder().decode(SampleIDRulesFileDraft.self, from: writtenData)
        #expect(written.patterns == ["MINE\\d+"])
        #expect(!store.dirtySections.contains(.sampleID))
    }

    @Test("substrate alias reference must point at known token")
    func substrateAliasReferenceCheck() throws {
        _ = try seedAllSchemas()
        let store = RulesManagementStore()
        store.present()

        var draft = try #require(store.substrateDraft)
        draft.sharedSubstrate?.materialAliases = ["Silicon": "NotInTokens"]
        store.updateSubstrate(draft)
        store.selectSection(.substrate)

        let outcome = store.saveCurrent()
        guard case .validationFailed(let errors) = outcome else {
            Issue.record("Expected .validationFailed, got \(outcome)")
            return
        }
        #expect(errors.contains(where: { $0.field.contains("materialAliases") }))
    }
}
