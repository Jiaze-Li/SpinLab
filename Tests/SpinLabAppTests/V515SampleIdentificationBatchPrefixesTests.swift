import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.5 SampleId Batch Prefixes")
struct V515SampleIdentificationBatchPrefixesTests {

    private func makeRuleSet(batchPrefixes: [String]) throws -> FilenameRuleSet {
        let matchesJSON = "[" + batchPrefixes.map { "{\"type\":\"starts-with\",\"value\":\"\($0)\"}" }.joined(separator: ",") + "]"
        let json = """
        {
            "version": 5,
            "tokenization": { "separators": "_", "caseFold": "preserve" },
            "sources": ["file"],
            "channel": { "aliases": {} },
            "sampleId": { "matches": \(matchesJSON) },
            "substrateConfig": { "materials": [], "treatments": [], "orientations": [] }
        }
        """
        var ruleSet = try JSONDecoder().decode(FilenameRuleSet.self, from: Data(json.utf8))
        ruleSet.loadWarnings = ruleSet.compile()
        return ruleSet
    }

    @Test("three prefixes each match their own IDs")
    func threePrefixesMatch() throws {
        let ruleSet = try makeRuleSet(batchPrefixes: ["PN", "PT", "SL"])
        #expect(ruleSet.sampleIDs(from: ["PN001"]) == ["PN001"])
        #expect(ruleSet.sampleIDs(from: ["PT123"]) == ["PT123"])
        #expect(ruleSet.sampleIDs(from: ["SL007"]) == ["SL007"])
    }

    @Test("unrecognized prefix is not matched")
    func unrecognizedPrefixNotMatched() throws {
        let ruleSet = try makeRuleSet(batchPrefixes: ["PN", "PT", "SL"])
        #expect(ruleSet.sampleIDs(from: ["PX001"]).isEmpty)
    }

    @Test("prefix without trailing digits is not matched")
    func prefixAloneNotMatched() throws {
        let ruleSet = try makeRuleSet(batchPrefixes: ["PN"])
        #expect(ruleSet.sampleIDs(from: ["PN"]).isEmpty)
    }

    @Test("empty batchPrefixes produces no matches")
    func emptyBatchPrefixesNoMatch() throws {
        let ruleSet = try makeRuleSet(batchPrefixes: [])
        #expect(ruleSet.sampleIDs(from: ["PN001", "PT123"]).isEmpty)
    }

    @Test("single prefix compiles correctly")
    func singlePrefixCompiles() throws {
        let ruleSet = try makeRuleSet(batchPrefixes: ["PN"])
        #expect(ruleSet.sampleIDs(from: ["PN1"]) == ["PN1"])
        #expect(ruleSet.sampleIDs(from: ["PN9999"]) == ["PN9999"])
    }

    @Test("fallback ruleset batchPrefixes PN PT SL match expected IDs")
    func fallbackBatchPrefixesMatch() throws {
        var ruleSet = FilenameRuleSet.fallback()
        ruleSet.loadWarnings = ruleSet.compile()
        #expect(ruleSet.sampleIDs(from: ["PN001"]) == ["PN001"])
        #expect(ruleSet.sampleIDs(from: ["PT123"]) == ["PT123"])
        #expect(ruleSet.sampleIDs(from: ["SL007"]) == ["SL007"])
    }
}
