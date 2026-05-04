import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.15 RulesBootstrapper Characterization", .serialized)
struct V5115RulesBootstrapperCharacterizationTests {

    private static let backupExtension = "v5115-rb-char-backup"

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

    private func seedV4MeasuringCondition(at url: URL) throws {
        let json = """
        {"version":4,"conditionDefinitions":[{"id":"temperature","displayName":"Temperature","matches":[{"match":{"type":"unit-suffix","value":"K"},"value":"$MATCH"}]}]}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    private func seedV4MeasuringConditionWithInvalidMatchType(at url: URL) throws {
        // "custom-invalid-type" survives v5→v6 and v6→v7 migrations unchanged
        // and causes FilenameRuleSetSchema.Operation decoding to throw at verify step.
        let json = """
        {"version":4,"conditionDefinitions":[{"id":"temperature","displayName":"Temperature","matches":[{"match":{"type":"custom-invalid-type","value":"K"},"value":"$MATCH"}]}]}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    private func seedV5SampleIdentification(at url: URL) throws {
        let json = """
        {"version":5,"sampleId":{"matches":[{"type":"starts-with","value":"AB"}]},"substrate":{"materials":[{"displayName":"STO","matches":[{"type":"equals","value":"STO"}]}],"treatments":[],"orientations":[]}}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    private func seedV6MeasuringCondition(at url: URL) throws {
        let json = """
        {"version":6,"conditionDefinitions":[{"id":"temperature","displayName":"Temperature","matches":[{"match":{"type":"unit-suffix","value":"K"},"value":"$MATCH"}]}]}
        """
        try json.data(using: .utf8)!.write(to: url)
    }

    // MARK: - Tests

    @Test("state=v7 but measuring_condition.json at v6: re-runs migration and upgrades to v7")
    func stateV7ButMeasuringV6TriggersReMigration() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        try seedV6MeasuringCondition(at: paths.measuringConditionURL)
        try seedV5SampleIdentification(at: paths.sampleIdentificationURL)

        let stateURL = dir.appendingPathComponent(".migration_state.json")
        let state7 = """
        {"rules_schema_version":7,"migrated_at":"2026-01-01T00:00:00+00:00","source_sha256":{},"target_sha256":{},"warnings":[]}
        """
        try state7.data(using: .utf8)!.write(to: stateURL)

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let measData = try Data(contentsOf: paths.measuringConditionURL)
        let measObj = try JSONSerialization.jsonObject(with: measData) as? [String: Any]
        #expect(measObj?["version"] as? Int == 7, "measuring_condition must be upgraded from v6 to v7 even when state already claims v7")
        let defs = measObj?["conditionDefinitions"] as? [[String: Any]]
        let firstDef = defs?.first
        #expect(firstDef?["standardization"] != nil, "v7 must have standardization block")
        let matches = firstDef?["matches"] as? [[String: Any]]
        let firstMatch = matches?.first
        #expect(firstMatch?.keys.contains("transform") == true, "v7 match rules must carry transform key")
    }

    @Test("v6 → v7: standardization and transform injected for every definition and every match rule")
    func v6ToV7InjectsStandardizationAndTransformOnAllDefs() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        let measuringJSON = """
        {"version":6,"conditionDefinitions":[
          {"id":"temperature","displayName":"Temperature","matches":[{"match":{"type":"unit-suffix","value":"K"},"value":"$MATCH"}]},
          {"id":"device","displayName":"Device","matches":[{"match":{"type":"equals","value":"wafer"},"value":"wafer"},{"match":{"type":"contains","value":"chip"},"value":"chip"}]}
        ]}
        """
        try measuringJSON.data(using: .utf8)!.write(to: paths.measuringConditionURL)
        try seedV5SampleIdentification(at: paths.sampleIdentificationURL)

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let data = try Data(contentsOf: paths.measuringConditionURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["version"] as? Int == 7)
        let defs = obj?["conditionDefinitions"] as? [[String: Any]]
        #expect(defs?.count == 2)

        for def in defs ?? [] {
            let id = def["id"] as? String ?? "?"
            let std = def["standardization"] as? [String: Any]
            #expect(std != nil, "[\(id)] must have standardization block after v6→v7")
            #expect(std?.keys.contains("standardUnit") == true, "[\(id)].standardization must have standardUnit key")
            #expect(std?.keys.contains("precision") == true, "[\(id)].standardization must have precision key")
            let matches = def["matches"] as? [[String: Any]] ?? []
            for match in matches {
                #expect(match.keys.contains("transform") == true, "[\(id)] every match rule must carry transform key after v6→v7")
            }
        }
    }

    @Test("user-defined condition id preserved verbatim through full migration chain")
    func migrationPreservesUserDefinedConditionId() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        let customId = "my-special-condition-2024"
        let measuringJSON = """
        {"version":6,"conditionDefinitions":[{"id":"\(customId)","displayName":"My Special","matches":[{"match":{"type":"unit-suffix","value":"pA"},"value":"$MATCH"}]}]}
        """
        try measuringJSON.data(using: .utf8)!.write(to: paths.measuringConditionURL)
        try seedV5SampleIdentification(at: paths.sampleIdentificationURL)

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let data = try Data(contentsOf: paths.measuringConditionURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let defs = obj?["conditionDefinitions"] as? [[String: Any]]
        #expect(defs?.first?["id"] as? String == customId, "user-defined condition id must survive migration verbatim — no normalization permitted")
    }

    @Test("user-defined displayName preserved verbatim through v6→v7 migration")
    func migrationPreservesUserDefinedDisplayName() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        let customDisplayName = "Temperature (Kelvin) — Custom Label"
        let measuringJSON = """
        {"version":6,"conditionDefinitions":[{"id":"temp","displayName":"\(customDisplayName)","matches":[]}]}
        """
        try measuringJSON.data(using: .utf8)!.write(to: paths.measuringConditionURL)
        try seedV5SampleIdentification(at: paths.sampleIdentificationURL)

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let data = try Data(contentsOf: paths.measuringConditionURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let defs = obj?["conditionDefinitions"] as? [[String: Any]]
        #expect(defs?.first?["displayName"] as? String == customDisplayName, "user-defined displayName must survive migration verbatim — no normalization or capitalization changes permitted")
    }

    @Test("user-defined match value and output value preserved verbatim through v6→v7 migration")
    func migrationPreservesUserDefinedMatchAndOutputValues() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        let matchValue = "Hall_Effect"
        let outputValue = "Hall Effect Measurement"
        let measuringJSON = """
        {"version":6,"conditionDefinitions":[{"id":"technique","displayName":"Technique","matches":[{"match":{"type":"equals","value":"\(matchValue)"},"value":"\(outputValue)"}]}]}
        """
        try measuringJSON.data(using: .utf8)!.write(to: paths.measuringConditionURL)
        try seedV5SampleIdentification(at: paths.sampleIdentificationURL)

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let data = try Data(contentsOf: paths.measuringConditionURL)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let defs = obj?["conditionDefinitions"] as? [[String: Any]]
        let matches = defs?.first?["matches"] as? [[String: Any]]
        let firstMatch = matches?.first
        let matchSpec = firstMatch?["match"] as? [String: Any]
        #expect(matchSpec?["value"] as? String == matchValue, "match spec value must survive migration verbatim")
        #expect(firstMatch?["value"] as? String == outputValue, "output value must survive migration verbatim")
    }

    @Test("decode verify failure: .migration_failed.json written, originals unchanged, no backup created")
    func decodeVerifyFailurePreservesOriginalsAndWritesFailureFile() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let paths = RulesConfigPaths()

        // v4 file with invalid match type → migration chain succeeds but Codable verify throws
        try seedV4MeasuringConditionWithInvalidMatchType(at: paths.measuringConditionURL)
        try seedV5SampleIdentification(at: paths.sampleIdentificationURL)

        let measuringBefore = try Data(contentsOf: paths.measuringConditionURL)
        let sampleBefore = try Data(contentsOf: paths.sampleIdentificationURL)

        RulesBootstrapper.migrateRuntimeRulesIfNeeded()

        let failedURL = dir.appendingPathComponent(".migration_failed.json")
        #expect(FileManager.default.fileExists(atPath: failedURL.path), ".migration_failed.json must be written when Codable verify step fails")

        let failedData = try Data(contentsOf: failedURL)
        let failedObj = try JSONSerialization.jsonObject(with: failedData) as? [String: Any]
        #expect(failedObj?["reason"] != nil, ".migration_failed.json must contain a reason field")
        #expect(failedObj?["failed_at"] != nil, ".migration_failed.json must contain a failed_at timestamp")

        let measuringAfter = try Data(contentsOf: paths.measuringConditionURL)
        let sampleAfter = try Data(contentsOf: paths.sampleIdentificationURL)
        #expect(measuringBefore == measuringAfter, "measuring_condition.json must be byte-identical before and after decode verify failure")
        #expect(sampleBefore == sampleAfter, "sample_identification.json must be byte-identical before and after decode verify failure")

        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backupDirs = contents.filter { $0.hasPrefix(".backup-") }
        #expect(backupDirs.isEmpty, "backup directory must NOT be created — decode verify failure occurs before the backup write step")
    }
}
