import Foundation
import Testing
@testable import SpinLabApp

/// F4 regression coverage: the free-text/filename path (`FileRoutingRuleBook`, exercised here
/// through `SampleKeyNormalizer`) must honor each substrate rule's declared `match.type`
/// (`equals` vs `contains`) the same way the Registry substrate-cell path does — not silently
/// degrade every rule to substring containment. Originally this suite asserted on
/// `FileRoutingSemanticRules`'s internal flattened needle dictionaries (the type that caused
/// the drift); it now asserts on caller-visible canonical-key behavior instead.
@Suite("V5.1.5/5.4.3 FileRoutingRuleBook honors match.type (equals vs contains)")
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
                schemaVersion: ruleSet.version,
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

    private func normalizer(_ provider: InlineRuleProvider) -> SampleKeyNormalizer {
        SampleKeyNormalizer(rules: FileRoutingRuleBook(ruleProvider: provider))
    }

    // NOTE: free-text substrate tokens are split on " /|,;+" (not parens), so "STO(111)"
    // stays one glued token "STO(111)" — production config anticipates this by declaring
    // "STO111"/"STO001"-style equals aliases. These tests use space-separated substrate
    // text ("STO 111") instead, which the Registry substrate-cell path (parenthesized,
    // tokenized on all non-alphanumeric) does not need.

    @Test("contains-type treatment rule matches substring in free text")
    func containsTreatmentMatches() throws {
        let provider = try makeProvider(config: Self.config)
        let key = normalizer(provider).canonicalKey(from: "PN32-HF STO 111")
        #expect(key == "PN32|HF|STO|111")
    }

    @Test("equals-type orientation alias resolves to its canonical display name")
    func equalsOrientationAliasResolves() throws {
        let provider = try makeProvider(config: Self.config)
        // "100" is an equals-only alias for orientation "001" — must resolve to "001", not "100".
        let key = normalizer(provider).canonicalKey(from: "PN32-STO 100")
        #expect(key == "PN32||STO|001")
    }

    @Test("canonical orientation value round-trips to itself")
    func canonicalOrientationRoundTrips() throws {
        let provider = try makeProvider(config: Self.config)
        let key = normalizer(provider).canonicalKey(from: "PN32-STO 111")
        #expect(key == "PN32||STO|111")
    }

    @Test("equals-only material rule does NOT match as a substring of an unrelated token")
    func equalsOnlyMaterialRejectsSubstringFalsePositive() throws {
        let config = """
        {
            "materials": [
                { "displayName": "Si", "matches": [
                    { "type": "equals", "value": "SI" }
                ]}
            ],
            "treatments": [],
            "orientations": []
        }
        """
        let provider = try makeProvider(config: config)
        // "SILICATE" contains "SI" as a substring, but the rule is equals-only — must NOT match.
        let key = normalizer(provider).canonicalKey(from: "PN32-SILICATE")
        #expect(key != "PN32||SI|UNKNOWN", "equals-only rule must not degrade to substring containment")
    }

    @Test("equals-only rule still matches when the token equals it exactly")
    func equalsOnlyMaterialMatchesExactToken() throws {
        let config = """
        {
            "materials": [
                { "displayName": "Si", "matches": [
                    { "type": "equals", "value": "SI" }
                ]}
            ],
            "treatments": [],
            "orientations": []
        }
        """
        let provider = try makeProvider(config: config)
        let key = normalizer(provider).canonicalKey(from: "PN32-Si")
        #expect(key == "PN32||SI|UNKNOWN")
    }

    @Test("Registry substrate-cell path and free-text path agree on the same equals/contains config")
    func registryAndFreeTextPathsAgree() throws {
        let provider = try makeProvider(config: Self.config)
        let compiled = provider.ruleSet().compiled

        let registryParser = LibrarySubstrateParser(
            classifier: SubstrateSemanticClassifier(compiled: compiled)
        )
        let substrates = registryParser.parse("HF STO 111")
        let registryKey = substrates.first.map { registryParser.sampleKey(batchId: "PN32", substrate: $0) }

        let freeTextKey = normalizer(provider).canonicalKey(from: "PN32-HF STO 111")

        #expect(registryKey == freeTextKey)
        #expect(registryKey == "PN32|HF|STO|111")
    }
}
