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

    private func seedV3SampleIdentificationFull(at url: URL) throws {
        let json = """
        {"version":3,"sampleId":{"patterns":["^PN\\\\d+$","^PT\\\\d+$"]},"substrate":{"substrateTagRules":[{"tag":"STO 111","matches":[{"type":"equalsAny","values":["STO111"]}]}],"materials":[{"id":"STO","tokens":["STO"],"aliases":[],"displayName":"STO"},{"id":"NGO","tokens":["NGO"],"aliases":[],"displayName":"NGO"}],"treatments":[{"id":"HF","displayName":"HF","keywords":["hf"],"standaloneTokens":[],"containsTokens":[]},{"id":"o","displayName":"o","keywords":[],"standaloneTokens":["o"],"containsTokens":["origin","original"]}],"orientations":{"pattern":"\\\\d{3}","rows":[{"id":"001","tokens":["001"],"aliases":["100"]},{"id":"111","tokens":["111"],"aliases":[]}]}}}
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

    @Test("v1 → v3→v4 migration writes v4 sample + v2 measuring + state + backup")
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
        #expect(sampleObj?["version"] as? Int == 4, "sample_identification must be v4 after migration")
        let substrate = sampleObj?["substrate"] as? [String: Any]
        #expect(substrate?["shared"] == nil, "v3 substrate must not have legacy 'shared' key")
        #expect(substrate?["tokenSeparators"] == nil, "v3 substrate must not have 'tokenSeparators' key")
        let mats = substrate?["materials"] as? [[String: Any]]
        #expect(mats?.first?["displayName"] as? String == "STO", "materials must contain STO displayName")

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        #expect(FileManager.default.fileExists(atPath: stateURL.path), ".migration_state.json must exist")
        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateObj?["rules_schema_version"] as? Int == 4)

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
        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateObj?["rules_schema_version"] as? Int == 4, "state must be v4 after v3→v4 sample migration")

        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backupDirs = contents.filter { $0.hasPrefix(".backup-") }
        #expect(backupDirs.isEmpty, "no backup should be created when files are already v3")
    }

    @Test("v2 sample with state v2: re-migrates to v4 (state gate must allow re-entry)")
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
        #expect(sampleObj?["version"] as? Int == 4, "v2 file with state v2 must be re-migrated to v4")
        let substrate = sampleObj?["substrate"] as? [String: Any]
        #expect(substrate?["tokenSeparators"] == nil, "tokenSeparators key must be stripped after v2→v3")

        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateObj?["rules_schema_version"] as? Int == 4, "state must be bumped to v4")
    }

    @Test("v3 full schema → v4: materials/treatments/orientations converted, substrateTagRules discarded")
    func v3ToV4FullSchemaMigration() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        try seedV2MeasuringCondition(at: paths.measuringConditionURL)
        try seedV3SampleIdentificationFull(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL)

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let sampleData = try Data(contentsOf: paths.sampleIdentificationURL)
        let sampleObj = try JSONSerialization.jsonObject(with: sampleData) as? [String: Any]
        #expect(sampleObj?["version"] as? Int == 4)

        let sampleId = sampleObj?["sampleId"] as? [String: Any]
        let batchPrefixes = sampleId?["batchPrefixes"] as? [String]
        #expect(batchPrefixes?.contains("PN") == true, "PN pattern should extract to batchPrefix PN")
        #expect(batchPrefixes?.contains("PT") == true, "PT pattern should extract to batchPrefix PT")
        #expect(sampleId?["patterns"] == nil, "patterns key must not exist in v4")

        let substrate = sampleObj?["substrate"] as? [String: Any]
        #expect(substrate?["substrateTagRules"] == nil, "substrateTagRules must be removed in v4")
        #expect(substrate?["orientations"] is [[String: Any]], "orientations must be array in v4")

        let mats = substrate?["materials"] as? [[String: Any]]
        #expect(mats?.count == 2)
        #expect(mats?.first?["displayName"] as? String == "STO")
        let stoMatches = mats?.first?["matches"] as? [[String: String]]
        #expect(stoMatches?.contains(where: { $0["type"] == "equals" && $0["value"] == "STO" }) == true)

        let treats = substrate?["treatments"] as? [[String: Any]]
        let hfTreat = treats?.first(where: { $0["displayName"] as? String == "HF" })
        let hfMatches = hfTreat?["matches"] as? [[String: String]]
        #expect(hfMatches?.contains(where: { $0["type"] == "contains" && $0["value"] == "hf" }) == true, "HF keyword maps to contains match")

        let oTreat = treats?.first(where: { $0["displayName"] as? String == "o" })
        let oMatches = oTreat?["matches"] as? [[String: String]]
        #expect(oMatches?.contains(where: { $0["type"] == "equals" && $0["value"] == "o" }) == true, "standaloneToken 'o' maps to equals")
        #expect(oMatches?.contains(where: { $0["type"] == "contains" && $0["value"] == "origin" }) == true, "containsToken 'origin' maps to contains")

        let oris = substrate?["orientations"] as? [[String: Any]]
        let ori001 = oris?.first(where: { $0["displayName"] as? String == "001" })
        let ori001Matches = ori001?["matches"] as? [[String: String]]
        #expect(ori001Matches?.contains(where: { $0["type"] == "equals" && $0["value"] == "100" }) == true, "alias '100' maps to equals match")
        #expect(ori001Matches?.contains(where: { $0["value"] == "001" }) == false, "displayName '001' must NOT be in matches (implicit)")

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateObj?["rules_schema_version"] as? Int == 4)

        let warnings = stateObj?["warnings"] as? [String] ?? []
        #expect(warnings.contains(where: { $0.contains("substrateTagRule") }), "substrateTagRules discard must be recorded in warnings")
        #expect(warnings.contains(where: { $0.contains("orientations.pattern") }), "dropped pattern field must be warned")
    }

    @Test("state gate >= 4: migration is skipped when rules_schema_version is 4")
    func stateGateV4SkipsMigration() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        try seedV2MeasuringCondition(at: paths.measuringConditionURL)
        try seedV3SampleIdentificationFull(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL)

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        let state4 = """
        {"rules_schema_version":4,"migrated_at":"2026-01-01T00:00:00+00:00","source_sha256":{},"target_sha256":{},"warnings":[]}
        """
        try state4.data(using: .utf8)!.write(to: stateURL)

        let sampleBefore = try Data(contentsOf: paths.sampleIdentificationURL)
        RulesBootstrapper.migrateRuntimeRulesIfNeeded()
        let sampleAfter = try Data(contentsOf: paths.sampleIdentificationURL)

        #expect(sampleBefore == sampleAfter, "file must not change when state gate is already v4")
    }

    @Test("v3→v4: non-standard sampleId.patterns produce warnings and are discarded")
    func nonStandardPatternsDiscarded() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        try seedV2MeasuringCondition(at: paths.measuringConditionURL)
        let json = """
        {"version":3,"sampleId":{"patterns":["^PN\\\\d+$","^INVALID_PATTERN_WITH_NO_GROUP$"]},"substrate":{"substrateTagRules":[],"materials":[],"treatments":[],"orientations":{"pattern":"","rows":[]}}}
        """
        try json.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL)

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let sampleData = try Data(contentsOf: paths.sampleIdentificationURL)
        let sampleObj = try JSONSerialization.jsonObject(with: sampleData) as? [String: Any]
        let sampleId = sampleObj?["sampleId"] as? [String: Any]
        let batchPrefixes = sampleId?["batchPrefixes"] as? [String]
        #expect(batchPrefixes == ["PN"], "only valid pattern should be converted")

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        let warnings = stateObj?["warnings"] as? [String] ?? []
        #expect(warnings.contains(where: { $0.contains("INVALID_PATTERN_WITH_NO_GROUP") }), "non-standard pattern must be warned")
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
