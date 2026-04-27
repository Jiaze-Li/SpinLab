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

    private func seedV2SampleIdentification(at url: URL) throws {
        let json = """
        {"version":2,"sampleId":{"patterns":[]},"substrate":{"tokenSeparators":"_","substrateTagRules":[],"materials":[{"id":"STO","tokens":["STO"],"aliases":[],"displayName":"STO"}],"treatments":[],"orientations":{"pattern":"\\\\d{3}","rows":[{"id":"001","tokens":["001"],"aliases":[]}]}}}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    // MARK: - Tests

    @Test("v1 → v2 migration writes v2 files + state + backup")
    func v1ToV2MigrationProducesExpectedArtifacts() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        try seedV1MeasuringCondition(at: paths.measuringConditionURL)
        try seedV1SampleIdentification(at: paths.sampleIdentificationURL)

        RulesBootstrapper.migrateRuntimeRulesToV2IfNeeded()

        // measuring_condition.json must be v2
        let measuringData = try Data(contentsOf: paths.measuringConditionURL)
        let measuringObj = try JSONSerialization.jsonObject(with: measuringData) as? [String: Any]
        #expect(measuringObj?["version"] as? Int == 2, "measuring_condition must be v2 after migration")
        #expect(measuringObj?["conditions"] == nil, "v2 measuring_condition must not have legacy 'conditions' key")
        let defs = measuringObj?["conditionDefinitions"] as? [[String: Any]]
        #expect(defs?.first?["unitPattern"] as? String == "^\\d+K$", "unitPattern must be inlined from extraConditions")

        // sample_identification.json must be v2
        let sampleData = try Data(contentsOf: paths.sampleIdentificationURL)
        let sampleObj = try JSONSerialization.jsonObject(with: sampleData) as? [String: Any]
        #expect(sampleObj?["version"] as? Int == 2, "sample_identification must be v2 after migration")
        let substrate = sampleObj?["substrate"] as? [String: Any]
        #expect(substrate?["shared"] == nil, "v2 substrate must not have legacy 'shared' key")
        #expect((substrate?["materials"] as? [[String: Any]])?.count == 1, "materials must contain STO")

        // migration_state.json must exist with version 2
        let stateURL = dir.appendingPathComponent(".migration_state.json")
        #expect(FileManager.default.fileExists(atPath: stateURL.path), ".migration_state.json must exist")
        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateObj?["rules_schema_version"] as? Int == 2)

        // backup directory must exist
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

        // First migration
        RulesBootstrapper.migrateRuntimeRulesToV2IfNeeded()

        let measuringHash1 = try Data(contentsOf: paths.measuringConditionURL)
        let sampleHash1 = try Data(contentsOf: paths.sampleIdentificationURL)
        let contents1 = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backupCount1 = contents1.filter { $0.hasPrefix(".backup-") }.count

        // Second migration — must be no-op
        RulesBootstrapper.migrateRuntimeRulesToV2IfNeeded()

        let measuringHash2 = try Data(contentsOf: paths.measuringConditionURL)
        let sampleHash2 = try Data(contentsOf: paths.sampleIdentificationURL)
        let contents2 = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backupCount2 = contents2.filter { $0.hasPrefix(".backup-") }.count

        #expect(measuringHash1 == measuringHash2, "measuring_condition.json must not change on second migration call")
        #expect(sampleHash1 == sampleHash2, "sample_identification.json must not change on second migration call")
        #expect(backupCount1 == backupCount2, "no new backup directory should be created on second migration call")
    }

    @Test("already-v2 files: state file written, no backup created")
    func alreadyV2FilesWriteStateButNoBackup() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        try seedV2MeasuringCondition(at: paths.measuringConditionURL)
        try seedV2SampleIdentification(at: paths.sampleIdentificationURL)

        RulesBootstrapper.migrateRuntimeRulesToV2IfNeeded()

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        #expect(FileManager.default.fileExists(atPath: stateURL.path), "state file must be written even for already-v2 files")

        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backupDirs = contents.filter { $0.hasPrefix(".backup-") }
        #expect(backupDirs.isEmpty, "no backup should be created when files are already v2")
    }

    @Test("dirty data: kind/binding mismatch produces warning in migration_state")
    func dirtyDataKindBindingMismatchGeneratesWarning() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        // unit_suffix bound to tokenMapRules path instead of extraConditions → mismatch
        let dirtyJSON = """
        {"version":1,"batch":{"preferSampleId":true,"fallbackPatterns":[]},"conditions":{"extraConditions":{},"tokenMapRules":{"temperature":[]},"displayLabels":{}},"conditionDefinitions":[{"id":"temperature","label":"Temperature","kind":"unit_suffix","binding":"conditions.tokenMapRules.temperature"}]}
        """
        try dirtyJSON.data(using: .utf8)!.write(to: paths.measuringConditionURL)
        try seedV1SampleIdentification(at: paths.sampleIdentificationURL)

        RulesBootstrapper.migrateRuntimeRulesToV2IfNeeded()

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

        RulesBootstrapper.migrateRuntimeRulesToV2IfNeeded()

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
