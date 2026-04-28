import Foundation
import Testing
@testable import SpinLabApp

// Verifies that origin treatment detection does not depend on a hardcoded id == "o".
// The entry whose displayName normalizes to "O" (or any match value normalizes to "O")
// is recognized as the origin treatment and excluded from the constraint when substrate tags
// do not indicate origin context.

@Suite("V5.1.5 Origin Treatment Semantics (v4)")
struct V515OriginTreatmentSemanticTests {

    private func makeProvider(config: String) throws -> InlineRuleProvider {
        let json = """
        {
            "version": 4,
            "tokenization": { "separators": "_", "caseFold": "preserve" },
            "sources": ["file"],
            "channel": { "aliases": {} },
            "sampleId": { "batchPrefixes": [] },
            "substrateConfig": \(config)
        }
        """
        var ruleSet = try JSONDecoder().decode(FilenameRuleSet.self, from: Data(json.utf8))
        ruleSet.loadWarnings = ruleSet.compile()
        let loadResult = RuleLoader.LoadResult(
            ruleSet: ruleSet,
            warnings: ruleSet.loadWarnings,
            metadata: RuleLoader.RuleMetadata(
                schemaVersion: ruleSet.version,
                sourceLabel: "test",
                sourcePath: "",
                contentHash: "test",
                loadedAt: .now
            )
        )
        return InlineRuleProvider(loadResult: loadResult)
    }

    private static let configWithOrigin = """
    {
        "materials": [],
        "treatments": [
            { "displayName": "HF", "matches": [
                { "type": "contains", "value": "hf" }
            ]},
            { "displayName": "o", "matches": [
                { "type": "contains", "value": "origin" },
                { "type": "contains", "value": "original" }
            ]}
        ],
        "orientations": []
    }
    """

    @Test("'o' displayName is detected as origin treatment")
    func displayNameOIsOrigin() throws {
        let provider = try makeProvider(config: Self.configWithOrigin)
        let compiled = provider.ruleSet().compiled
        #expect(compiled.originTreatmentDisplayNames.contains("o"))
    }

    @Test("hasStandaloneOriginToken returns true for 'origin' token in filename")
    func hasStandaloneOriginTokenForOrigin() throws {
        let provider = try makeProvider(config: Self.configWithOrigin)
        let ruleBook = RegistrySubstrateRuleBook(ruleLoadResult: RuleLoader.LoadResult(
            ruleSet: provider.ruleSet(),
            warnings: [],
            metadata: RuleLoader.RuleMetadata(
                schemaVersion: 4, sourceLabel: "test", sourcePath: "", contentHash: "test",
                loadedAt: .now
            )
        ))
        #expect(ruleBook.hasStandaloneOriginToken(fileName: "PN001_origin_STO001", originalFilePath: .some("")))
    }

    @Test("hasStandaloneOriginToken returns true for 'original' token in filename")
    func hasStandaloneOriginTokenForOriginal() throws {
        let provider = try makeProvider(config: Self.configWithOrigin)
        let ruleBook = RegistrySubstrateRuleBook(ruleLoadResult: RuleLoader.LoadResult(
            ruleSet: provider.ruleSet(),
            warnings: [],
            metadata: RuleLoader.RuleMetadata(
                schemaVersion: 4, sourceLabel: "test", sourcePath: "", contentHash: "test",
                loadedAt: .now
            )
        ))
        #expect(ruleBook.hasStandaloneOriginToken(fileName: "PN001_original_STO001", originalFilePath: .some("")))
    }

    @Test("entry with match value normalizing to O is also detected as origin")
    func matchValueNormalizesToOIsOrigin() throws {
        let config = """
        {
            "materials": [],
            "treatments": [
                { "displayName": "original", "matches": [
                    { "type": "equals", "value": "O" }
                ]}
            ],
            "orientations": []
        }
        """
        let provider = try makeProvider(config: config)
        let compiled = provider.ruleSet().compiled
        #expect(compiled.originTreatmentDisplayNames.contains("original"),
                "entry with match value 'O' normalizing to O is origin treatment")
    }

    @Test("HF treatment is never in originTreatmentDisplayNames")
    func hfIsNotOrigin() throws {
        let provider = try makeProvider(config: Self.configWithOrigin)
        let compiled = provider.ruleSet().compiled
        #expect(!compiled.originTreatmentDisplayNames.contains("HF"))
    }
}
