import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.5 RulesBootstrapper Migration", .serialized)
struct V515RulesBootstrapperMigrationTests {

    private func acquireIsolation() throws -> (dir: URL, paths: RulesConfigPaths, internalPaths: AppInternalPaths) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SL-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let paths = RulesConfigPaths(configDirectoryURL: dir)
        let internalPaths = AppInternalPaths(appSupportDirectoryURL: dir)
        return (dir, paths, internalPaths)
    }

    private func releaseIsolation(dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func seedV1MeasuringCondition(at url: URL, kind: String = "unit_suffix") throws {
        let json = """
        {"version":1,"batch":{"preferSampleId":true,"fallbackPatterns":[]},"conditions":{"extraConditions":{"temperature":"^-?\\\\d+(?:\\\\.\\\\d+)?(?:K)$"},"tokenMapRules":{},"displayLabels":{}},"conditionDefinitions":[{"id":"temperature","label":"Temperature","kind":"\(kind)","binding":"conditions.extraConditions.temperature"}]}
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

    private func seedV6MeasuringCondition(at url: URL) throws {
        let json = """
        {"version":6,"conditionDefinitions":[{"id":"temperature","displayName":"Temperature","matches":[{"match":{"type":"unit-suffix","value":"K"},"value":"$MATCH"}]}]}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    private func seedV7MeasuringCondition(at url: URL) throws {
        let json = """
        {"version":7,"conditionDefinitions":[{"id":"temperature","displayName":"Temperature","standardization":{"standardUnit":null,"precision":null},"matches":[{"match":{"type":"unit-suffix","value":"K"},"value":"$MATCH","transform":null}]}]}
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

    @Test("v1 → v4→v5 migration writes v5 sample + v4 measuring + state v6 + backup")
    func v1ToFullMigrationProducesExpectedArtifacts() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV1MeasuringCondition(at: paths.measuringConditionURL)
        try seedV1SampleIdentification(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL, separators: "_")

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let measuringData = try Data(contentsOf: paths.measuringConditionURL)
        let measuringObj = try JSONSerialization.jsonObject(with: measuringData) as? [String: Any]
        #expect(measuringObj?["version"] as? Int == 7, "measuring_condition must be v7 after full migration chain")
        #expect(measuringObj?["conditions"] == nil, "v6 measuring_condition must not have legacy 'conditions' key")
        let defs = measuringObj?["conditionDefinitions"] as? [[String: Any]]
        let firstDef = defs?.first
        #expect(firstDef?["unitPattern"] == nil, "unitPattern must not exist in v6 measuring_condition")
        let defMatches = firstDef?["matches"] as? [[String: Any]]
        #expect(defMatches?.contains(where: { ($0["match"] as? [String: String])?["type"] == "unit-suffix" && $0["value"] as? String == "$MATCH" }) == true, "v6 unit_suffix must use MapRule with $MATCH sentinel")
        #expect(firstDef?["displayName"] as? String == "Temperature", "label must be renamed to displayName")
        #expect(firstDef?["label"] == nil, "label key must not exist")

        let sampleData = try Data(contentsOf: paths.sampleIdentificationURL)
        let sampleObj = try JSONSerialization.jsonObject(with: sampleData) as? [String: Any]
        #expect(sampleObj?["version"] as? Int == 5, "sample_identification must be v5 after migration")
        let substrate = sampleObj?["substrate"] as? [String: Any]
        #expect(substrate?["shared"] == nil, "v5 substrate must not have legacy 'shared' key")
        #expect(substrate?["tokenSeparators"] == nil, "v5 substrate must not have 'tokenSeparators' key")
        let mats = substrate?["materials"] as? [[String: Any]]
        #expect(mats?.first?["displayName"] as? String == "STO", "materials must contain STO displayName")
        let sampleId = sampleObj?["sampleId"] as? [String: Any]
        #expect(sampleId?["batchPrefixes"] == nil, "v5 sampleId must not have batchPrefixes key")

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        #expect(FileManager.default.fileExists(atPath: stateURL.path), ".migration_state.json must exist")
        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateObj?["rules_schema_version"] as? Int == 7)

        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backupDirs = contents.filter { $0.hasPrefix(".backup-") }
        #expect(!backupDirs.isEmpty, "backup directory must be created during migration")
    }

    @Test("migration is idempotent: second call is a no-op")
    func migrationIsIdempotent() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV1MeasuringCondition(at: paths.measuringConditionURL)
        try seedV1SampleIdentification(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL, separators: "_")

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let measuringHash1 = try Data(contentsOf: paths.measuringConditionURL)
        let sampleHash1 = try Data(contentsOf: paths.sampleIdentificationURL)
        let contents1 = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backupCount1 = contents1.filter { $0.hasPrefix(".backup-") }.count

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let measuringHash2 = try Data(contentsOf: paths.measuringConditionURL)
        let sampleHash2 = try Data(contentsOf: paths.sampleIdentificationURL)
        let contents2 = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backupCount2 = contents2.filter { $0.hasPrefix(".backup-") }.count

        #expect(measuringHash1 == measuringHash2, "measuring_condition.json must not change on second migration call")
        #expect(sampleHash1 == sampleHash2, "sample_identification.json must not change on second migration call")
        #expect(backupCount1 == backupCount2, "no new backup directory should be created on second migration call")
    }

    @Test("v2 measuring + v3 sample: both migrated to v4/v5, state v6 written, backup created")
    func v2MeasuringV3SampleMigratedToTarget() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV2MeasuringCondition(at: paths.measuringConditionURL)
        try seedV3SampleIdentification(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL)

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        #expect(FileManager.default.fileExists(atPath: stateURL.path), "state file must be written")
        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateObj?["rules_schema_version"] as? Int == 7, "state must be v7 after migration")

        let measuringData = try Data(contentsOf: paths.measuringConditionURL)
        let measuringObj = try JSONSerialization.jsonObject(with: measuringData) as? [String: Any]
        #expect(measuringObj?["version"] as? Int == 7, "measuring must be migrated to v7 after full chain")
        let defs = measuringObj?["conditionDefinitions"] as? [[String: Any]]
        #expect(defs?.first?["displayName"] != nil, "v6 measuring must use displayName")
        #expect(defs?.first?["label"] == nil, "v6 measuring must not use label")
        #expect(defs?.first?["unitPattern"] == nil, "v6 measuring must not use unitPattern")

        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backupDirs = contents.filter { $0.hasPrefix(".backup-") }
        #expect(!backupDirs.isEmpty, "backup must be created because files changed")
    }

    @Test("v2 sample with state v2: re-migrates to v5 (state gate must allow re-entry)")
    func v2SampleWithStateV2ReMigratesToV5() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV2MeasuringCondition(at: paths.measuringConditionURL)
        try seedV2SampleIdentification(at: paths.sampleIdentificationURL, separators: "_")
        try seedFilenameTokenization(at: paths.filenameTokenizationURL, separators: "_")

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        let staleState = """
        {"rules_schema_version":2,"migrated_at":"2026-01-01T00:00:00+00:00","source_sha256":{},"target_sha256":{},"warnings":[]}
        """
        try staleState.data(using: .utf8)!.write(to: stateURL)

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let sampleData = try Data(contentsOf: paths.sampleIdentificationURL)
        let sampleObj = try JSONSerialization.jsonObject(with: sampleData) as? [String: Any]
        #expect(sampleObj?["version"] as? Int == 5, "v2 file with state v2 must be re-migrated to v5")
        let substrate = sampleObj?["substrate"] as? [String: Any]
        #expect(substrate?["tokenSeparators"] == nil, "tokenSeparators key must be stripped after v2→v3")
        let sampleId = sampleObj?["sampleId"] as? [String: Any]
        #expect(sampleId?["batchPrefixes"] == nil, "v5 sampleId must not have batchPrefixes")
        #expect(sampleId?["matches"] != nil, "v5 sampleId must have matches key")

        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateObj?["rules_schema_version"] as? Int == 7, "state must be bumped to v7")
    }

    @Test("v3 full schema → v5: materials/treatments/orientations converted, substrateTagRules discarded, batchPrefixes→matches")
    func v3ToV5FullSchemaMigration() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV2MeasuringCondition(at: paths.measuringConditionURL)
        try seedV3SampleIdentificationFull(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL)

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let sampleData = try Data(contentsOf: paths.sampleIdentificationURL)
        let sampleObj = try JSONSerialization.jsonObject(with: sampleData) as? [String: Any]
        #expect(sampleObj?["version"] as? Int == 5)

        let sampleId = sampleObj?["sampleId"] as? [String: Any]
        #expect(sampleId?["batchPrefixes"] == nil, "v5 sampleId must not have batchPrefixes")
        #expect(sampleId?["patterns"] == nil, "v5 sampleId must not have patterns")
        let sampleMatches = sampleId?["matches"] as? [[String: String]]
        #expect(sampleMatches?.contains(where: { $0["type"] == "starts-with" && $0["value"] == "PN" }) == true, "PN pattern must become starts-with match")
        #expect(sampleMatches?.contains(where: { $0["type"] == "starts-with" && $0["value"] == "PT" }) == true, "PT pattern must become starts-with match")

        let substrate = sampleObj?["substrate"] as? [String: Any]
        #expect(substrate?["substrateTagRules"] == nil, "substrateTagRules must be removed")
        #expect(substrate?["orientations"] is [[String: Any]], "orientations must be array")

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
        #expect(stateObj?["rules_schema_version"] as? Int == 7)

        let warnings = stateObj?["warnings"] as? [String] ?? []
        #expect(warnings.contains(where: { $0.contains("substrateTagRule") }), "substrateTagRules discard must be recorded in warnings")
        #expect(warnings.contains(where: { $0.contains("orientations.pattern") }), "dropped pattern field must be warned")
    }

    @Test("state gate >= 7: migration is skipped when state=7 and measuring file is already v7")
    func stateGateV7SkipsMigration() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        // Both state and measuring file must be v7 for the gate to skip — the gate
        // checks file version to prevent false-positive skips after partial migrations.
        try seedV7MeasuringCondition(at: paths.measuringConditionURL)
        try seedV3SampleIdentificationFull(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL)

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        let state7 = """
        {"rules_schema_version":7,"migrated_at":"2026-01-01T00:00:00+00:00","source_sha256":{},"target_sha256":{},"warnings":[]}
        """
        try state7.data(using: .utf8)!.write(to: stateURL)

        let sampleBefore = try Data(contentsOf: paths.sampleIdentificationURL)
        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)
        let sampleAfter = try Data(contentsOf: paths.sampleIdentificationURL)

        #expect(sampleBefore == sampleAfter, "file must not change when state gate is already v7 and measuring file is v7")
    }

    @Test("v3→v5: non-standard sampleId.patterns produce warnings and are discarded")
    func nonStandardPatternsDiscarded() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV2MeasuringCondition(at: paths.measuringConditionURL)
        let json = """
        {"version":3,"sampleId":{"patterns":["^PN\\\\d+$","^INVALID_PATTERN_WITH_NO_GROUP$"]},"substrate":{"substrateTagRules":[],"materials":[],"treatments":[],"orientations":{"pattern":"","rows":[]}}}
        """
        try json.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL)

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let sampleData = try Data(contentsOf: paths.sampleIdentificationURL)
        let sampleObj = try JSONSerialization.jsonObject(with: sampleData) as? [String: Any]
        let sampleId = sampleObj?["sampleId"] as? [String: Any]
        // v3→v4 migrates patterns→batchPrefixes; v4→v5 migrates batchPrefixes→matches
        let sampleMatches = sampleId?["matches"] as? [[String: String]]
        #expect(sampleMatches?.count == 1, "only valid pattern should be converted")
        #expect(sampleMatches?.first?["type"] == "starts-with", "converted match must be starts-with")
        #expect(sampleMatches?.first?["value"] == "PN", "PN must be converted to starts-with value")
        #expect(sampleId?["batchPrefixes"] == nil, "v5 must not have batchPrefixes")

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        let warnings = stateObj?["warnings"] as? [String] ?? []
        #expect(warnings.contains(where: { $0.contains("INVALID_PATTERN_WITH_NO_GROUP") }), "non-standard pattern must be warned")
    }

    @Test("v2→v3 migration: separator mismatch produces warning")
    func separatorMismatchProducesWarning() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV2MeasuringCondition(at: paths.measuringConditionURL)
        try seedV2SampleIdentification(at: paths.sampleIdentificationURL, separators: "_")
        try seedFilenameTokenization(at: paths.filenameTokenizationURL, separators: "_- ()")

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

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
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV2MeasuringCondition(at: paths.measuringConditionURL)
        try seedV2SampleIdentification(at: paths.sampleIdentificationURL, separators: "_- ()")
        try seedFilenameTokenization(at: paths.filenameTokenizationURL, separators: "_- ()")

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

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
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        let dirtyJSON = """
        {"version":1,"batch":{"preferSampleId":true,"fallbackPatterns":[]},"conditions":{"extraConditions":{},"tokenMapRules":{"temperature":[]},"displayLabels":{}},"conditionDefinitions":[{"id":"temperature","label":"Temperature","kind":"unit_suffix","binding":"conditions.tokenMapRules.temperature"}]}
        """
        try dirtyJSON.data(using: .utf8)!.write(to: paths.measuringConditionURL)
        try seedV1SampleIdentification(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL, separators: "_")

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        let stateData = try Data(contentsOf: stateURL)
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        let warnings = stateObj?["warnings"] as? [String] ?? []
        #expect(warnings.contains(where: { $0.contains("temperature") && $0.contains("mismatch") }),
                "migration_state.warnings must record the kind/binding mismatch for 'temperature'")
    }

    @Test("backup files are valid JSON after migration")
    func backupFilesAreValidJSON() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV1MeasuringCondition(at: paths.measuringConditionURL)
        try seedV1SampleIdentification(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL, separators: "_")

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

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

    // MARK: - s11 new tests

    private func seedV2MeasuringConditionWithTokenMap(at url: URL) throws {
        let json = """
        {"version":2,"conditionDefinitions":[{"id":"device","label":"Device","kind":"token_map","tokenMap":[{"match":{"scope":"tokens","type":"equals","matchValues":["wafer"]},"value":"wafer"}]},{"id":"temperature","label":"Temperature","kind":"unit_suffix","unitPattern":"^-?\\\\d+(?:\\\\.\\\\d+)?(?:K)$"}]}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    private func seedV1Workflow(at url: URL) throws {
        let json = """
        {"version":1,"workflows":[{"id":"MR","displayName":"MR","matchRules":[{"scope":"tokens","type":"equals","matchValues":["MR"]}],"conditionFieldIDs":["temperature"]}],"measurementTagRules":[{"match":{"scope":"tokens","type":"equals","matchValues":["AMR"]},"value":"AMR"}]}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    @Test("measuring_condition v2→v4: label→displayName, tokenMap→matches, unitPattern→matches, version bumped")
    func measuringConditionV2ToV4RoundTrip() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV2MeasuringConditionWithTokenMap(at: paths.measuringConditionURL)
        try seedV3SampleIdentificationFull(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL)

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let data = try Data(contentsOf: paths.measuringConditionURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["version"] as? Int == 7, "measuring_condition must be v7 after full migration chain")

        let defs = obj?["conditionDefinitions"] as? [[String: Any]]

        let deviceDef = defs?.first(where: { $0["id"] as? String == "device" })
        #expect(deviceDef?["displayName"] as? String == "Device", "label must become displayName")
        #expect(deviceDef?["label"] == nil, "label key must not exist")
        #expect(deviceDef?["tokenMap"] == nil, "tokenMap must not exist in v6")
        let deviceMatches = deviceDef?["matches"] as? [[String: Any]]
        let deviceMatch = deviceMatches?.first
        #expect(deviceMatch?["match"] as? [String: String] == ["type": "equals", "value": "wafer"], "match spec must be new format")
        #expect(deviceMatch?["value"] as? String == "wafer", "output value must be preserved")

        let tempDef = defs?.first(where: { $0["id"] as? String == "temperature" })
        #expect(tempDef?["displayName"] as? String == "Temperature", "temperature label→displayName")
        #expect(tempDef?["unitPattern"] == nil, "unitPattern must not exist in v6")
        let tempMatches = tempDef?["matches"] as? [[String: Any]]
        #expect(tempMatches?.contains(where: {
            ($0["match"] as? [String: String]) == ["type": "unit-suffix", "value": "K"] &&
            $0["value"] as? String == "$MATCH"
        }) == true, "temperature must have unit-suffix K match in MapRule format")

        let stateData = try Data(contentsOf: dir.appendingPathComponent(".migration_state.json"))
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateObj?["rules_schema_version"] as? Int == 7)
    }

    @Test("workflow v1→v3: scope stripped, matchValues→value, version bumped")
    func workflowV1ToV3RoundTrip() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV2MeasuringConditionWithTokenMap(at: paths.measuringConditionURL)
        try seedV3SampleIdentificationFull(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL)
        try seedV1Workflow(at: paths.workflowURL)

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let data = try Data(contentsOf: paths.workflowURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["version"] as? Int == 3, "workflow must be v3 after migration")

        let workflows = obj?["workflows"] as? [[String: Any]]
        let mrWorkflow = workflows?.first(where: { $0["id"] as? String == "MR" })
        let matchRules = mrWorkflow?["matchRules"] as? [[String: Any]]
        let firstRule = matchRules?.first
        #expect(firstRule?["scope"] == nil, "scope must not exist in v3")
        #expect(firstRule?["type"] as? String == "equals", "type must be preserved")
        #expect(firstRule?["value"] as? String == "MR", "value must use single-value field")
        #expect(firstRule?["matchValues"] == nil, "matchValues must not exist in v3")

        let tagRules = obj?["measurementTagRules"] as? [[String: Any]]
        let tagMatch = tagRules?.first?["match"] as? [String: Any]
        #expect(tagMatch?["scope"] == nil, "scope must not exist in v3")
        #expect(tagMatch?["type"] as? String == "equals", "type must be preserved")
        #expect(tagMatch?["value"] as? String == "AMR", "value must use single-value field")
        #expect(tagMatch?["matchValues"] == nil, "matchValues must not exist in v3")

        let stateData = try Data(contentsOf: dir.appendingPathComponent(".migration_state.json"))
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateObj?["rules_schema_version"] as? Int == 7)
    }

    @Test("workflow absent during migration: state still reaches v6")
    func workflowAbsentDoesNotBlockMigration() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV2MeasuringConditionWithTokenMap(at: paths.measuringConditionURL)
        try seedV3SampleIdentificationFull(at: paths.sampleIdentificationURL)
        try seedFilenameTokenization(at: paths.filenameTokenizationURL)
        // no workflow.json seeded

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let stateData = try Data(contentsOf: dir.appendingPathComponent(".migration_state.json"))
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateObj?["rules_schema_version"] as? Int == 7, "state must reach v7 even without workflow.json")
        #expect(!FileManager.default.fileExists(atPath: paths.workflowURL.path), "workflow.json must not be created")
    }

    // MARK: - s12 migration tests

    private func seedV4MeasuringCondition(at url: URL) throws {
        let json = """
        {"version":4,"conditionDefinitions":[{"id":"temperature","kind":"unit_suffix","displayName":"Temperature","matches":[{"type":"unit-suffix","value":"K"}]}]}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    private func seedV5SampleIdentification(at url: URL) throws {
        let json = """
        {"version":5,"sampleId":{"matches":[]},"substrate":{"materials":[],"treatments":[],"orientations":[]}}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    @Test("workflow v2→v3: equalsAny expands to individual equals rules")
    func equalsAnyExpandsToIndividualEqualsRules() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV4MeasuringCondition(at: paths.measuringConditionURL)
        try seedV5SampleIdentification(at: paths.sampleIdentificationURL)
        let workflowJSON = """
        {"version":2,"workflows":[{"id":"MR","displayName":"MR","matchRules":[{"type":"equalsAny","matchValues":["MR","MR2","MR3"]}],"conditionFieldIDs":[]}],"measurementTagRules":[]}
        """
        try workflowJSON.data(using: .utf8)!.write(to: paths.workflowURL)

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let data = try Data(contentsOf: paths.workflowURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["version"] as? Int == 3)

        let matchRules = ((obj?["workflows"] as? [[String: Any]])?.first)?["matchRules"] as? [[String: Any]]
        #expect(matchRules?.count == 3, "equalsAny with 3 values must produce 3 rules")
        #expect(matchRules?[0] as? [String: String] == ["type": "equals", "value": "MR"])
        #expect(matchRules?[1] as? [String: String] == ["type": "equals", "value": "MR2"])
        #expect(matchRules?[2] as? [String: String] == ["type": "equals", "value": "MR3"])

        let stateData = try Data(contentsOf: dir.appendingPathComponent(".migration_state.json"))
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateObj?["rules_schema_version"] as? Int == 7)
    }

    @Test("workflow v2→v3: containsAny expands to individual contains rules")
    func containsAnyExpandsToIndividualContainsRules() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV4MeasuringCondition(at: paths.measuringConditionURL)
        try seedV5SampleIdentification(at: paths.sampleIdentificationURL)
        let workflowJSON = """
        {"version":2,"workflows":[{"id":"Hall","displayName":"Hall","matchRules":[{"type":"containsAny","matchValues":["Hall","AMR"]}],"conditionFieldIDs":[]}],"measurementTagRules":[]}
        """
        try workflowJSON.data(using: .utf8)!.write(to: paths.workflowURL)

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let data = try Data(contentsOf: paths.workflowURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let matchRules = ((obj?["workflows"] as? [[String: Any]])?.first)?["matchRules"] as? [[String: Any]]
        #expect(matchRules?.count == 2, "containsAny with 2 values must produce 2 rules")
        #expect(matchRules?[0] as? [String: String] == ["type": "contains", "value": "Hall"])
        #expect(matchRules?[1] as? [String: String] == ["type": "contains", "value": "AMR"])
    }

    @Test("workflow v2→v3: equalsOrContainsAny preserves strict equals-first order")
    func equalsOrContainsAnyPreservesStrictOrder() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV4MeasuringCondition(at: paths.measuringConditionURL)
        try seedV5SampleIdentification(at: paths.sampleIdentificationURL)
        let workflowJSON = """
        {"version":2,"workflows":[{"id":"MR","displayName":"MR","matchRules":[{"type":"equalsOrContainsAny","matchValues":["A","B"]}],"conditionFieldIDs":[]}],"measurementTagRules":[]}
        """
        try workflowJSON.data(using: .utf8)!.write(to: paths.workflowURL)

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let data = try Data(contentsOf: paths.workflowURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let matchRules = ((obj?["workflows"] as? [[String: Any]])?.first)?["matchRules"] as? [[String: Any]]
        #expect(matchRules?.count == 4, "equalsOrContainsAny with 2 values must produce 4 rules")
        #expect(matchRules?[0] as? [String: String] == ["type": "equals", "value": "A"], "equals A must be first")
        #expect(matchRules?[1] as? [String: String] == ["type": "equals", "value": "B"], "equals B must be second")
        #expect(matchRules?[2] as? [String: String] == ["type": "contains", "value": "A"], "contains A must be third")
        #expect(matchRules?[3] as? [String: String] == ["type": "contains", "value": "B"], "contains B must be last")
    }

    @Test("workflow v2→v3: regex rule is dropped and warning recorded")
    func regexRuleIsDroppedWithWarning() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV4MeasuringCondition(at: paths.measuringConditionURL)
        try seedV5SampleIdentification(at: paths.sampleIdentificationURL)
        let workflowJSON = """
        {"version":2,"workflows":[{"id":"MR","displayName":"MR","matchRules":[{"type":"regex","matchValues":["^MR\\\\d+$"]}],"conditionFieldIDs":[]}],"measurementTagRules":[]}
        """
        try workflowJSON.data(using: .utf8)!.write(to: paths.workflowURL)

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let data = try Data(contentsOf: paths.workflowURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let matchRules = ((obj?["workflows"] as? [[String: Any]])?.first)?["matchRules"] as? [[String: Any]]
        #expect(matchRules?.isEmpty == true, "regex rule must be dropped")

        let stateData = try Data(contentsOf: dir.appendingPathComponent(".migration_state.json"))
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        let warnings = stateObj?["warnings"] as? [String] ?? []
        #expect(warnings.contains(where: { $0.contains("regex") && $0.contains("removed") }),
                "state warnings must record regex rule removal")
    }

    @Test("workflow v2→v3: scope=joined produces warning and rule is preserved as token-scoped")
    func scopeJoinedGeneratesWarning() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        try seedV4MeasuringCondition(at: paths.measuringConditionURL)
        try seedV5SampleIdentification(at: paths.sampleIdentificationURL)
        let workflowJSON = """
        {"version":2,"workflows":[{"id":"MR","displayName":"MR","matchRules":[{"scope":"joined","type":"equals","matchValues":["MR"]}],"conditionFieldIDs":[]}],"measurementTagRules":[]}
        """
        try workflowJSON.data(using: .utf8)!.write(to: paths.workflowURL)

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let data = try Data(contentsOf: paths.workflowURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let matchRules = ((obj?["workflows"] as? [[String: Any]])?.first)?["matchRules"] as? [[String: Any]]
        #expect(matchRules?.count == 1, "rule must be preserved after scope removal")
        #expect(matchRules?.first?["scope"] == nil, "scope must be absent after migration")
        #expect(matchRules?.first?["value"] as? String == "MR")

        let stateData = try Data(contentsOf: dir.appendingPathComponent(".migration_state.json"))
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        let warnings = stateObj?["warnings"] as? [String] ?? []
        #expect(warnings.contains(where: { $0.contains("joined") }),
                "state warnings must record scope=joined removal")
    }

    @Test("measuring_condition v3→v4: multi-unit unitPattern reverse-parses to unit-suffix matches")
    func unitPatternMultipleUnitsReverseParseToMatches() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        let measuringJSON = """
        {"version":3,"conditionDefinitions":[{"id":"current","kind":"unit_suffix","displayName":"Current","unitPattern":"^-?\\\\d+(?:\\\\.\\\\d+)?(?:mA|A|uA)$"}]}
        """
        try measuringJSON.data(using: .utf8)!.write(to: paths.measuringConditionURL)
        try seedV5SampleIdentification(at: paths.sampleIdentificationURL)

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let data = try Data(contentsOf: paths.measuringConditionURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["version"] as? Int == 7)

        let defs = obj?["conditionDefinitions"] as? [[String: Any]]
        let currentDef = defs?.first(where: { $0["id"] as? String == "current" })
        #expect(currentDef?["unitPattern"] == nil, "unitPattern must be absent after v6 migration")
        let matches = currentDef?["matches"] as? [[String: Any]]
        #expect(matches?.count == 3, "three units must produce three unit-suffix matches")
        #expect(matches?[0]["match"] as? [String: String] == ["type": "unit-suffix", "value": "mA"])
        #expect(matches?[0]["value"] as? String == "$MATCH")
        #expect(matches?[1]["match"] as? [String: String] == ["type": "unit-suffix", "value": "A"])
        #expect(matches?[1]["value"] as? String == "$MATCH")
        #expect(matches?[2]["match"] as? [String: String] == ["type": "unit-suffix", "value": "uA"])
        #expect(matches?[2]["value"] as? String == "$MATCH")

        let stateData = try Data(contentsOf: dir.appendingPathComponent(".migration_state.json"))
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        #expect(stateObj?["rules_schema_version"] as? Int == 7)
    }

    @Test("measuring_condition v3→v4: non-canonical unitPattern produces empty matches and warning")
    func unitPatternNonCanonicalProducesEmptyMatchesWithWarning() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        let measuringJSON = """
        {"version":3,"conditionDefinitions":[{"id":"temperature","kind":"unit_suffix","displayName":"Temperature","unitPattern":"^[0-9]+K$"}]}
        """
        try measuringJSON.data(using: .utf8)!.write(to: paths.measuringConditionURL)
        try seedV5SampleIdentification(at: paths.sampleIdentificationURL)

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let data = try Data(contentsOf: paths.measuringConditionURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["version"] as? Int == 7)

        let defs = obj?["conditionDefinitions"] as? [[String: Any]]
        let tempDef = defs?.first(where: { $0["id"] as? String == "temperature" })
        #expect(tempDef != nil, "condition must be preserved even with non-canonical pattern")
        let matches = tempDef?["matches"] as? [[String: Any]]
        #expect(matches?.isEmpty == true, "non-canonical unitPattern must produce empty matches")

        let stateData = try Data(contentsOf: dir.appendingPathComponent(".migration_state.json"))
        let stateObj = try JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        let warnings = stateObj?["warnings"] as? [String] ?? []
        #expect(warnings.contains(where: { $0.contains("temperature") && $0.contains("unitPattern") }),
                "warning must reference the condition id and unitPattern field")
    }

    @Test("measuring_condition v3→v4: tokenMap equalsAny expansion replicates output value to all rows")
    func tokenMapEqualsAnyExpansionPreservesOutputValue() throws {
        let (dir, paths, internalPaths) = try acquireIsolation()
        defer { releaseIsolation(dir: dir) }

        let measuringJSON = """
        {"version":3,"conditionDefinitions":[{"id":"device","kind":"token_map","displayName":"Device","tokenMap":[{"match":{"type":"equalsAny","matchValues":["wafer","chip"]},"value":"semiconductor"}]}]}
        """
        try measuringJSON.data(using: .utf8)!.write(to: paths.measuringConditionURL)
        try seedV5SampleIdentification(at: paths.sampleIdentificationURL)

        RulesBootstrapper.migrateRulesBookIfNeeded(paths: paths, internalPaths: internalPaths)

        let data = try Data(contentsOf: paths.measuringConditionURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["version"] as? Int == 7)

        let defs = obj?["conditionDefinitions"] as? [[String: Any]]
        let deviceDef = defs?.first(where: { $0["id"] as? String == "device" })
        #expect(deviceDef?["tokenMap"] == nil, "tokenMap must be absent after v6 migration")
        let matches = deviceDef?["matches"] as? [[String: Any]]
        #expect(matches?.count == 2, "equalsAny with 2 values must expand to 2 MapRules")
        #expect(matches?[0]["match"] as? [String: String] == ["type": "equals", "value": "wafer"])
        #expect(matches?[0]["value"] as? String == "semiconductor", "output value must be replicated")
        #expect(matches?[1]["match"] as? [String: String] == ["type": "equals", "value": "chip"])
        #expect(matches?[1]["value"] as? String == "semiconductor", "output value must be replicated")
    }
}
