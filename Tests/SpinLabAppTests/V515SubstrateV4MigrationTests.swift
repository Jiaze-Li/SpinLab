import Foundation
import Testing
@testable import SpinLabApp

// Verifies that v3 JSON (old material/treatment/orientation structure + substrateTagRules)
// is inline-converted to v4 on load, producing correct compiled substrate entries.

@MainActor
@Suite("V5.1.5 Substrate v3→v4 Inline Migration", .serialized)
struct V515SubstrateV4MigrationTests {

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

    private func writeConfig(sampleIdentJSON: String) throws -> RuleLoader.LoadResult {
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
        try sampleIdentJSON.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)
        try """
        {"version":1,"workflows":[],"measurementTagRules":[]}
        """.data(using: .utf8)!.write(to: paths.workflowURL)
        try """
        {"version":2,"conditionDefinitions":[]}
        """.data(using: .utf8)!.write(to: paths.measuringConditionURL)
        return RuleLoader.shared.reloadCached()
    }

    private static let v3Fixture = """
    {
        "version": 3,
        "sampleId": { "patterns": ["^[A-Z]{2}\\\\d+$"] },
        "substrate": {
            "substrateTagRules": [],
            "materials": [
                { "id": "STO", "tokens": ["STO", "STRONTIUM"], "aliases": ["SrTiO3"], "displayName": "STO" },
                { "id": "NGO", "tokens": ["NGO"], "aliases": [], "displayName": "NGO" }
            ],
            "treatments": [
                { "id": "HF", "displayName": "HF", "keywords": ["HF", "hf-etch"],
                  "standaloneTokens": [], "containsTokens": [] }
            ],
            "orientations": {
                "pattern": "\\\\d{3}",
                "rows": [
                    { "id": "001", "tokens": ["001"], "aliases": ["100"] },
                    { "id": "111", "tokens": ["111"], "aliases": [] }
                ]
            }
        }
    }
    """

    @Test("v3 fixture produces compiled material entries")
    func v3ProducesCompiledMaterials() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let result = try writeConfig(sampleIdentJSON: Self.v3Fixture)
        let materialNames = result.ruleSet.compiled.substrateMaterialEntries.map(\.displayName)
        #expect(materialNames.contains("STO"))
        #expect(materialNames.contains("NGO"))
    }

    @Test("v3 fixture produces compiled treatment entries")
    func v3ProducesCompiledTreatments() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let result = try writeConfig(sampleIdentJSON: Self.v3Fixture)
        let treatmentNames = result.ruleSet.compiled.substrateTreatmentEntries.map(\.displayName)
        #expect(treatmentNames.contains("HF"))
    }

    @Test("v3 fixture produces compiled orientation entries")
    func v3ProducesCompiledOrientations() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let result = try writeConfig(sampleIdentJSON: Self.v3Fixture)
        let orientationNames = result.ruleSet.compiled.substrateOrientationEntries.map(\.displayName)
        #expect(orientationNames.contains("001"))
        #expect(orientationNames.contains("111"))
    }

    @Test("v3 material tokens become equals probes in compiled entry")
    func v3MaterialTokensBeEqualsProbes() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let result = try writeConfig(sampleIdentJSON: Self.v3Fixture)
        let stoEntry = result.ruleSet.compiled.substrateMaterialEntries.first(where: { $0.displayName == "STO" })
        let equalsKeys = stoEntry?.equalsKeysNormalized ?? []
        #expect(equalsKeys.contains("STO"))
        #expect(equalsKeys.contains("STRONTIUM"))
    }

    @Test("v3 orientation alias 100 maps to 001 as equals probe")
    func v3OrientationAliasConverted() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let result = try writeConfig(sampleIdentJSON: Self.v3Fixture)
        let entry001 = result.ruleSet.compiled.substrateOrientationEntries.first(where: { $0.displayName == "001" })
        let equalsKeys = entry001?.equalsKeysNormalized ?? []
        #expect(equalsKeys.contains("100"), "alias '100' must become an equals probe for '001'")
    }

    @Test("v3 loading is idempotent across two reloads")
    func v3LoadingIsIdempotent() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let result1 = try writeConfig(sampleIdentJSON: Self.v3Fixture)
        let result2 = RuleLoader.shared.reloadCached()
        let names1 = result1.ruleSet.compiled.substrateMaterialEntries.map(\.displayName).sorted()
        let names2 = result2.ruleSet.compiled.substrateMaterialEntries.map(\.displayName).sorted()
        #expect(names1 == names2)
    }

    @Test("v4 fixture loads directly without inline conversion")
    func v4FixtureLoadsDirectly() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }
        let v4JSON = """
        {"version":4,"sampleId":{"batchPrefixes":["PN"]},"substrate":{"materials":[{"displayName":"STO","matches":[{"type":"equals","value":"STO"}]}],"treatments":[],"orientations":[]}}
        """
        let result = try writeConfig(sampleIdentJSON: v4JSON)
        let materialNames = result.ruleSet.compiled.substrateMaterialEntries.map(\.displayName)
        #expect(materialNames.contains("STO"))
        #expect(result.ruleSet.sampleId.batchPrefixes == ["PN"])
    }
}
