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

    // MARK: - Compound-segment cross-path regression (glued material+orientation token)

    /// Regression: "MgO(STO111)" is a compound token — outer material "MgO" plus an
    /// orientation alias "STO111" that happens to embed a DIFFERENT material's `.contains`
    /// needle ("STO"). Both paths must tokenize the segment and apply equals-before-contains
    /// precedence identically, not just live in the same type.
    @Test("Registry and free-text paths agree on a glued material(orientation-alias) token")
    func compoundGluedTokenAgreesAcrossPaths() throws {
        try withBundledRules { provider in
            let compiled = provider.ruleSet().compiled

            let registryParser = LibrarySubstrateParser(classifier: SubstrateSemanticClassifier(compiled: compiled))
            let substrates = registryParser.parse("MgO(STO111)")
            let registrySubstrate = try #require(substrates.first)
            let registryKey = registryParser.sampleKey(batchId: "PN200", substrate: registrySubstrate)

            let freeTextKey = SampleKeyNormalizer(rules: FileRoutingRuleBook(ruleProvider: provider))
                .canonicalKey(from: "PN200-MgO(STO111)")

            #expect(registrySubstrate.material == "MgO")
            #expect(registrySubstrate.orientation == "111")
            #expect(registryKey == "PN200||MGO|111")
            #expect(freeTextKey == registryKey)
        }
    }

    /// Generic (non-MgO/STO) cross-entry precedence: within one compound segment, a material
    /// whose own display name is an exact token hit must win over a different, earlier-declared
    /// material whose `.contains` needle only matches as an embedded substring — on both paths.
    @Test("exact material token outranks an earlier contains-rule substring collision on both paths")
    func exactTokenOutranksContainsCollisionAcrossPaths() throws {
        let config = """
        {
            "materials": [
                { "displayName": "Sub", "matches": [
                    { "type": "contains", "value": "AAA" }
                ]},
                { "displayName": "Exact", "matches": [] }
            ],
            "treatments": [],
            "orientations": [
                { "displayName": "999", "matches": [
                    { "type": "equals", "value": "999" },
                    { "type": "equals", "value": "AAAEXACT" }
                ]}
            ]
        }
        """
        let provider = try makeProvider(config: config)
        let compiled = provider.ruleSet().compiled

        let registryParser = LibrarySubstrateParser(classifier: SubstrateSemanticClassifier(compiled: compiled))
        let substrates = registryParser.parse("Exact(AAAEXACT)")
        let registrySubstrate = try #require(substrates.first)
        let registryKey = registryParser.sampleKey(batchId: "PNX", substrate: registrySubstrate)

        let freeTextKey = normalizer(provider).canonicalKey(from: "PNX-Exact(AAAEXACT)")

        #expect(registrySubstrate.material == "Exact", "exact display-name token must win over Sub's embedded contains needle")
        #expect(registrySubstrate.orientation == "999")
        #expect(registryKey == "PNX||EXACT|999")
        #expect(freeTextKey == registryKey)
    }
}
