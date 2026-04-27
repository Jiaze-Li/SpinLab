import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.5 FileRoutingSemanticRules v4 (no substrateTagRules)")
struct V515FileRoutingSemanticRulesV4Tests {

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
                version: ruleSet.version,
                sourceLabel: "test",
                sourcePath: "",
                contentHash: "test",
                loadedAt: .now
            )
        )
        return InlineRuleProvider(loadResult: loadResult)
    }

    private static let config = """
    {
        "materials": [
            { "displayName": "STO", "matches": [
                { "type": "equals", "value": "STO" },
                { "type": "contains", "value": "STO" }
            ]},
            { "displayName": "NGO", "matches": [
                { "type": "equals", "value": "NGO" }
            ]}
        ],
        "treatments": [
            { "displayName": "HF", "matches": [
                { "type": "contains", "value": "hf" }
            ]}
        ],
        "orientations": [
            { "displayName": "001", "matches": [
                { "type": "equals", "value": "001" },
                { "type": "equals", "value": "100" }
            ]},
            { "displayName": "111", "matches": [
                { "type": "equals", "value": "111" }
            ]}
        ]
    }
    """

    @Test("treatment needles produced from v4 config without substrateTagRules")
    func treatmentNeedlesProduced() throws {
        let provider = try makeProvider(config: Self.config)
        let rules = FileRoutingSemanticRules.load(ruleProvider: provider)
        // "HF" displayName is a needle
        let hfNeedle = rules.treatmentNeedles.keys.contains(where: { $0.contains("HF") || $0.contains("hf") })
        #expect(hfNeedle, "HF treatment needle must be present")
    }

    @Test("material needles produced for all entries")
    func materialNeedlesProduced() throws {
        let provider = try makeProvider(config: Self.config)
        let rules = FileRoutingSemanticRules.load(ruleProvider: provider)
        let hasSTO = rules.materialNeedles.values.contains("STO")
        let hasNGO = rules.materialNeedles.values.contains("NGO")
        #expect(hasSTO)
        #expect(hasNGO)
    }

    @Test("orientation aliases registered for non-canonical equals matches")
    func orientationAliasRegistered() throws {
        let provider = try makeProvider(config: Self.config)
        let rules = FileRoutingSemanticRules.load(ruleProvider: provider)
        // "100" is an equals match for "001" → should map to "001"
        #expect(rules.orientationAliases["100"] == "001", "'100' must alias to '001'")
    }

    @Test("canonical orientation not aliased to itself")
    func canonicalOrientationNotSelfAliased() throws {
        let provider = try makeProvider(config: Self.config)
        let rules = FileRoutingSemanticRules.load(ruleProvider: provider)
        // "001" → "001" should not appear in aliases (not an alias of itself)
        #expect(rules.orientationAliases["001"] == nil, "'001' must not alias to itself")
    }
}
