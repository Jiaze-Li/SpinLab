import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.12 RulesManagementStore setBatchPrefixes", .serialized)
struct V5112RulesManagementStoreBatchPrefixesTests {

    // MARK: - Isolation (same strategy as V515RulesPanelStoreTests)

    private static let backupExtension = "v5112-batch-backup"

    private func acquireIsolation() throws -> (dir: URL, backup: URL?) {
        purgeStaleBackups()
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
        if fm.fileExists(atPath: dir.path) {
            try? fm.removeItem(at: dir)
        }
        if let backup, fm.fileExists(atPath: backup.path) {
            try? fm.moveItem(at: backup, to: dir)
        }
        _ = RuleLoader.shared.reloadCached()
    }

    private func purgeStaleBackups() {
        let dir = RulesConfigPaths().configDirectoryURL
        let parent = dir.deletingLastPathComponent()
        let prefix = dir.lastPathComponent + "." + Self.backupExtension
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: parent.path) else { return }
        for entry in entries where entry.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(entry, isDirectory: true))
        }
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
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }

        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let paths = RulesConfigPaths()
        try seedSampleIdentification(at: paths.sampleIdentificationURL, prefixes: ["PN", "PT"])

        let store = RulesManagementStore()
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
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }

        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let paths = RulesConfigPaths()
        try seedSampleIdentification(at: paths.sampleIdentificationURL, prefixes: ["PN"])

        let store = RulesManagementStore()
        store.present()

        store.setBatchPrefixes(from: [FilenameRuleSet.MatchSpec(type: .startsWith, value: "PT")])

        #expect(store.dirtySections.contains(.sampleIdentification))
    }

    @Test("setBatchPrefixes with empty input clears all prefixes")
    func setBatchPrefixesClearsAll() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }

        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let paths = RulesConfigPaths()
        try seedSampleIdentification(at: paths.sampleIdentificationURL, prefixes: ["PN", "PT"])

        let store = RulesManagementStore()
        store.present()

        store.setBatchPrefixes(from: [])

        let result = store.sampleIdentificationDraft?.sampleId.batchPrefixes ?? ["not-empty"]
        #expect(result.isEmpty)
    }
}
