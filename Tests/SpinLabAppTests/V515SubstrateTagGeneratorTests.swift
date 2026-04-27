import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.5 Substrate Tag Generator (v4)")
struct V515SubstrateTagGeneratorTests {

    private func makeRuleSet(config: String) throws -> FilenameRuleSet {
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
        return ruleSet
    }

    private static let standardConfig = """
    {
        "materials": [
            { "displayName": "STO", "matches": [
                { "type": "contains", "value": "STO" }
            ]},
            { "displayName": "NGO", "matches": [] }
        ],
        "treatments": [
            { "displayName": "HF", "matches": [
                { "type": "contains", "value": "hf" }
            ]},
            { "displayName": "o", "matches": [
                { "type": "contains", "value": "origin" },
                { "type": "contains", "value": "original" }
            ]}
        ],
        "orientations": [
            { "displayName": "001", "matches": [
                { "type": "equals", "value": "100" },
                { "type": "contains", "value": "STO001" }
            ]},
            { "displayName": "111", "matches": [
                { "type": "contains", "value": "STO111" }
            ]}
        ]
    }
    """

    @Test("STO111 composite token hits both material and orientation")
    func compositeTokenHitsBothMaterialAndOrientation() throws {
        let ruleSet = try makeRuleSet(config: Self.standardConfig)
        let tags = ruleSet.substrateTags(from: ["STO111"])
        #expect(tags.contains("STO"), "STO111 contains STO needle → material hit")
        #expect(tags.contains("111"), "STO111 contains STO111 needle → orientation 111 hit")
    }

    @Test("displayName itself is an implicit equals probe")
    func displayNameImplicitEqualsProbe() throws {
        let ruleSet = try makeRuleSet(config: Self.standardConfig)
        let tags = ruleSet.substrateTags(from: ["NGO"])
        #expect(tags.contains("NGO"), "NGO displayName → implicit equals probe hit")
    }

    @Test("tags are deduplicated when multiple tokens hit same entry")
    func tagsAreDeduplicatedAcrossTokens() throws {
        let ruleSet = try makeRuleSet(config: Self.standardConfig)
        // Both "STO" and "STO001" contain "STO"
        let tags = ruleSet.substrateTags(from: ["STO", "STO001"])
        #expect(tags.filter { $0 == "STO" }.count == 1)
    }

    @Test("group order is materials → treatments → orientations per config")
    func groupOrderFollowsConfigOrder() throws {
        let ruleSet = try makeRuleSet(config: Self.standardConfig)
        let tags = ruleSet.substrateTags(from: ["STO", "HF", "001"])
        let materialIdx = tags.firstIndex(of: "STO") ?? Int.max
        let treatmentIdx = tags.firstIndex(of: "HF") ?? Int.max
        let orientationIdx = tags.firstIndex(of: "001") ?? Int.max
        #expect(materialIdx < treatmentIdx, "materials appear before treatments")
        #expect(treatmentIdx < orientationIdx, "treatments appear before orientations")
    }

    @Test("normalize: token with spaces and dashes is matched")
    func normalizeSpacesAndDashes() throws {
        let config = """
        {
            "materials": [
                { "displayName": "Al2O3", "matches": [
                    { "type": "equals", "value": "AL2O3" }
                ]}
            ],
            "treatments": [],
            "orientations": []
        }
        """
        let ruleSet = try makeRuleSet(config: config)
        // "Al_2O3" normalized → "AL2O3" equals probe
        let tags = ruleSet.substrateTags(from: ["Al_2O3"])
        #expect(tags.contains("Al2O3"), "underscore-stripped token matches equals probe")
    }

    @Test("no match for unrelated token")
    func noMatchForUnrelatedToken() throws {
        let ruleSet = try makeRuleSet(config: Self.standardConfig)
        let tags = ruleSet.substrateTags(from: ["UNKNOWN_TOKEN"])
        #expect(tags.isEmpty)
    }
}
