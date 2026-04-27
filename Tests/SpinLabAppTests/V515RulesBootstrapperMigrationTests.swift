import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.5 RulesBootstrapper Migration", .serialized)
struct V515RulesBootstrapperMigrationTests {

    private static let backupExtension = "v515-migration-backup"

    private func acquireIsolation() throws -> (dir: URL, backup: URL?) {
        let dir = RulesConfigPaths().configDirectoryURL
        let fm = FileManager.default
        var backup: URL? = nil
        if fm.fileExists(atPath: dir.path) {
            let candidate = dir.appendingPathExtension("\(Self.backupExtension).\(UUID().uuidString)")
            try fm.moveItem(at: dir, to: candidate)
            backup = candidate
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
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

    private func seedV1MeasuringCondition(at url: URL, kind: String = "unit_suffix") throws {
        let json = """
        {"version":1,"batch":{"preferSampleId":true,"fallbackPatterns":[]},"conditions":{"extraConditions":{"temperature":"^\\\\d+K$"},"tokenMapRules":{},"displayLabels":{}},"conditionDefinitions":[{"id":"temperature","label":"Temperature","kind":"\(kind)","binding":"conditions.extraConditions.temperature"}]}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    private func seedV1SampleIdentification(at url: URL) throws {
        let json = """
        {"version":1,"sampleId":{"patterns":["^[A-Z]{2}\\\\d+$"]},"substrate":{"substrateTagRules":[],"shared":{"tokenSeparators":"_","materialTokens":["STO"],"materialAliases":{},"materialDisplayNames":{"STO":"STO"},"treatmentKeywords":{"HF":["hf"]},"originStandaloneTokens":[],"originContainsTokens":[],"orientationTokens":["001"],"orientationAliases":{},"orientationPattern":"\\\\d{3}"}}}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    private func seedV2MeasuringCondition(at url: URL) throws {
        let json = """
        {"version":2,"batch":{"preferSampleId":true,"fallbackPatterns":[]},"conditionDefinitions":[{"id":"temperature","label":"Temperature","kind":"unit_suffix","unitPattern":"^\\\\d+K$"}]}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    private func seedV2SampleIdentification(at url: URL, separators: String = "_") throws {
        let json = """
        {"version":2,"sampleId":{"patterns":[]},"substrate":{"tokenSeparators":"\(separators)","substrateTagRules":[],"materials":[{"id":"STO","tokens":["STO"],"aliases":[],"displayName":"STO"}],"treatments":[],"orientations":{"pattern":"\\\\d{3}","rows":[{"id":"001","tokens":["001"],"aliases":[]}]}}}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    private func seedV3SampleIdentification(at url: URL) throws {
        let json = """
        {"version":3,"sampleId":{"patterns":[]},"substrate":{"substrateTagRules":[],"materials":[{"id":"STO","tokens":["STO"],"aliases":[],"displayName":"STO"}],"treatments":[],"orientations":{"pattern":"\\\\d{3}","rows":[{"id":"001","tokens":["001"],"aliases":[]}]}}}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    private func seedFilenameTokenization(at url: URL, separators: String = "_") throws {
        let json = """
        {"version":1,"tokenization":{"separators":"\(separators)","caseFold":"preserve"},"sources":["file"],"channel":{"aliases":{}}}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    // MARK: - Tests

    @Test("v1 → v3 migration writes v3 sample + v2 measuring + state + backup")
    func v1ToV3MigrationProducesExpectedArtifacts() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        try seedV1MeasuringCondition(at: paths.measuringConditionURL)
        try seedV1SampleIdentification(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL, separators: "_")

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let measuringData = try Data(contentsOf: paths.measuringConditionURL)
        let measuringObj = try JSONSerialization.jsonObject(with: measuringData) as? [String: Any]
        #expect(measuringObj?["version"] as? Int == 2, "measuring_condition must be v2 after migration")
        #expect(measuringObj?["conditions"] == nil, "v2 measuring_condition must not have legacy 'conditions' key")
        let defs = measuringObj?["conditionDefinitions"] as? [[String: Any]]
        #expect(defs?.first?["unitPattern"] as? String == "^\\d+K$", "unitPattern must be inlined from extraConditions")

        let sampleData = try Data(contentsOf: paths.sampleIdentificationURL)
        let sampleObj = try JSONSerialization.jsonObject(with: sampleData) as? [String: Any]
        #expect(sampleObj?["version"] as? Int == 3, "sample_identification must be v3 after migration")
        let substrate = sampleObj?["substrate"] as? [String: Any]
        #expect(substrate?["shared"] == nil, "v3 substrate must not have legacy 'shared' key")
        #expect(substrate?["tokenSeparators"] == nil, "v3 substrate must not have 'tokenSeparators' key")
        #expect((substrate?["materials"] as? [[String: Any]])?.count == 1, "materials must contain STO")

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        #expect(FileManager.default.fileExists(atPath: stateURL.path), ".migration_state.json must exist")
        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateObj?["rules_schema_version"] as? Int == 3)

        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backupDirs = contents.filter { $0.hasPrefix(".backup-") }
        #expect(!backupDirs.isEmpty, "backup directory must be created during migration")
    }

    @Test("migration is idempotent: second call is a no-op")
    func migrationIsIdempotent() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        try seedV1MeasuringCondition(at: paths.measuringConditionURL)
        try seedV1SampleIdentification(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL, separators: "_")

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let measuringHash1 = try Data(contentsOf: paths.measuringConditionURL)
        let sampleHash1 = try Data(contentsOf: paths.sampleIdentificationURL)
        let contents1 = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backupCount1 = contents1.filter { $0.hasPrefix(".backup-") }.count

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let measuringHash2 = try Data(contentsOf: paths.measuringConditionURL)
        let sampleHash2 = try Data(contentsOf: paths.sampleIdentificationURL)
        let contents2 = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backupCount2 = contents2.filter { $0.hasPrefix(".backup-") }.count

        #expect(measuringHash1 == measuringHash2, "measuring_condition.json must not change on second migration call")
        #expect(sampleHash1 == sampleHash2, "sample_identification.json must not change on second migration call")
        #expect(backupCount1 == backupCount2, "no new backup directory should be created on second migration call")
    }

    @Test("already-v3 files: state file written, no backup created")
    func alreadyV3FilesWriteStateButNoBackup() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        try seedV2MeasuringCondition(at: paths.measuringConditionURL)
        try seedV3SampleIdentification(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL)

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        #expect(FileManager.default.fileExists(atPath: stateURL.path), "state file must be written even for already-v3 files")

        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backupDirs = contents.filter { $0.hasPrefix(".backup-") }
        #expect(backupDirs.isEmpty, "no backup should be created when files are already v3")
    }

    @Test("v2 sample with state v2: re-migrates to v3 (state gate must allow re-entry)")
    func v2SampleWithStateV2ReMigratesToV3() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        try seedV2MeasuringCondition(at: paths.measuringConditionURL)
        try seedV2SampleIdentification(at: paths.sampleIdentificationURL, separators: "_")
        try seedFilenameTokenization(at: paths.filenameTokenizationURL, separators: "_")

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        let staleState = """
        {"rules_schema_version":2,"migrated_at":"2026-01-01T00:00:00+00:00","source_sha256":{},"target_sha256":{},"warnings":[]}
        """
        try staleState.data(using: .utf8)!.write(to: stateURL)

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let sampleData = try Data(contentsOf: paths.sampleIdentificationURL)
        let sampleObj = try JSONSerialization.jsonObject(with: sampleData) as? [String: Any]
        #expect(sampleObj?["version"] as? Int == 3, "v2 file with state v2 must be re-migrated to v3")
        let substrate = sampleObj?["substrate"] as? [String: Any]
        #expect(substrate?["tokenSeparators"] == nil, "tokenSeparators key must be stripped after v2→v3")

        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateObj?["rules_schema_version"] as? Int == 3, "state must be bumped to v3")
    }

    @Test("v2→v3 migration: separator mismatch produces warning")
    func separatorMismatchProducesWarning() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        try seedV2MeasuringCondition(at: paths.measuringConditionURL)
        try seedV2SampleIdentification(at: paths.sampleIdentificationURL, separators: "_")
        try seedFilenameTokenization(at: paths.filenameTokenizationURL, separators: "_- ()")

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        let warnings = stateObj?["warnings"] as? [String] ?? []
        #expect(warnings.contains(where: {
            $0.contains("substrate.tokenSeparators") && $0.contains("differs")
        }), "migration_state.warnings must record the separator mismatch")
    }

    @Test("v2→v3 migration: matching separators produce no mismatch warning")
    func matchingSeparatorsProduceNoWarning() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        try seedV2MeasuringCondition(at: paths.measuringConditionURL)
        try seedV2SampleIdentification(at: paths.sampleIdentificationURL, separators: "_- ()")
        try seedFilenameTokenization(at: paths.filenameTokenizationURL, separators: "_- ()")

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        let warnings = stateObj?["warnings"] as? [String] ?? []
        #expect(!warnings.contains(where: {
            $0.contains("substrate.tokenSeparators") && $0.contains("differs")
        }), "no mismatch warning when separators agree")
    }

    @Test("dirty data: kind/binding mismatch produces warning in migration_state")
    func dirtyDataKindBindingMismatchGeneratesWarning() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        let dirtyJSON = """
        {"version":1,"batch":{"preferSampleId":true,"fallbackPatterns":[]},"conditions":{"extraConditions":{},"tokenMapRules":{"temperature":[]},"displayLabels":{}},"conditionDefinitions":[{"id":"temperature","label":"Temperature","kind":"unit_suffix","binding":"conditions.tokenMapRules.temperature"}]}
        """
        try dirtyJSON.data(using: .utf8)!.write(to: paths.measuringConditionURL)
        try seedV1SampleIdentification(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL, separators: "_")

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        let warnings = stateObj?["warnings"] as? [String] ?? []
        #expect(warnings.contains(where: { $0.contains("temperature") && $0.contains("mismatch") }),
                "migration_state.warnings must record the kind/binding mismatch for 'temperature'")
    }

    @Test("backup files are valid JSON after migration")
    func backupFilesAreValidJSON() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        try seedV1MeasuringCondition(at: paths.measuringConditionURL)
        try seedV1SampleIdentification(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL, separators: "_")

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backupDirName = try #require(contents.first(where: { $0.hasPrefix(".backup-") }),
                                         "backup directory must exist")
        let backupDir = dir.appendingPathComponent(backupDirName, isDirectory: true)

        for filename in ["measuring_condition.json", "sample_identification.json"] {
            let fileURL = backupDir.appendingPathComponent(filename)
            #expect(FileManager.default.fileExists(atPath: fileURL.path), "\(filename) must exist in backup")
            let data = try Data(contentsOf: fileURL)
            let obj = try JSONSerialization.jsonObject(with: data)
            #expect(obj is [String: Any], "\(filename) backup must be valid JSON object")
        }
    }
}
