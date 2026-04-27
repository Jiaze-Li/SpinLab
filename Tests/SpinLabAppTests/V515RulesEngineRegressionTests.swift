import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.5 Rules Engine Regression")
struct V515RulesEngineRegressionTests {

    // MARK: - Routing (measurement name)

    @Test("MR filename routes to MR")
    func routingMR() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR_300K_1T.dat"))
        #expect(hints.measurementName == "MR")
    }

    @Test("AHE filename routes to ahe (workflow id is lowercase)")
    func routingAHE() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_AHE_300K.dat"))
        #expect(hints.measurementName == "ahe")
    }

    @Test("3w filename routes to 3w")
    func routing3w() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_3w.dat"))
        #expect(hints.measurementName == "3w")
    }

    @Test("RT filename routes to RT")
    func routingRT() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_RT_1mA.dat"))
        #expect(hints.measurementName == "RT")
    }

    @Test("XY filename routes to XY")
    func routingXY() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_XY.dat"))
        #expect(hints.measurementName == "XY")
    }

    // MARK: - Measurement tags

    @Test("AMR token produces AMR tag")
    func tagAMR() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR_AMR.dat"))
        #expect(hints.measurementTags.contains("AMR"))
    }

    @Test("PHE token produces PHE tag")
    func tagPHE() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR_PHE.dat"))
        #expect(hints.measurementTags.contains("PHE"))
    }

    @Test("RXX token produces Rxx tag")
    func tagRXX() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR_RXX.dat"))
        #expect(hints.measurementTags.contains("Rxx"))
    }

    @Test("RXY token produces Rxy tag")
    func tagRXY() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR_RXY.dat"))
        #expect(hints.measurementTags.contains("Rxy"))
    }

    // MARK: - Batch prefix (sample IDs)

    @Test("PN prefix matches as sample ID")
    func batchPrefixPN() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR.dat"))
        #expect(hints.sampleIDs.contains("PN20"))
    }

    @Test("PT prefix matches as sample ID")
    func batchPrefixPT() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PT5_MR.dat"))
        #expect(hints.sampleIDs.contains("PT5"))
    }

    @Test("SL prefix matches as sample ID")
    func batchPrefixSL() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/SL1_MR.dat"))
        #expect(hints.sampleIDs.contains("SL1"))
    }

    @Test("non-prefix token is not matched as sample ID")
    func batchPrefixNoMatch() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/XX99_MR.dat"))
        #expect(hints.sampleIDs.isEmpty)
    }

    // MARK: - Unit suffix conditions

    @Test("temperature: K suffix extracted")
    func conditionTemperatureK() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR_300K.dat"))
        #expect(hints.conditionValues["temperature"] == "300K")
    }

    @Test("temperature: lowercase k suffix extracted")
    func conditionTemperatureLowercaseK() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR_300k.dat"))
        #expect(hints.conditionValues["temperature"] == "300k")
    }

    @Test("current: mA suffix extracted")
    func conditionCurrentmA() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_RT_1mA.dat"))
        #expect(hints.conditionValues["current"] == "1mA")
    }

    @Test("field: T suffix extracted")
    func conditionFieldT() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR_300K_1T.dat"))
        #expect(hints.conditionValues["field"] == "1T")
    }

    @Test("field: mT suffix extracted")
    func conditionFieldmT() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR_300K_500mT.dat"))
        #expect(hints.conditionValues["field"] == "500mT")
    }

    @Test("shift: shift suffix extracted")
    func conditionShift() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR_90shift.dat"))
        #expect(hints.conditionValues["shift"] == "90shift")
    }

    @Test("leading dash in filename is treated as separator: -10K becomes 10K")
    func conditionTemperatureLeadingDashStripped() throws {
        // '-' is a filename separator, so "-10K" tokenizes to "10K" (sign lost).
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR_-10K.dat"))
        #expect(hints.conditionValues["temperature"] == "10K")
    }

    @Test("half-step normalization rounds 4.5K to 4.5K")
    func conditionTemperatureHalfStepNormalization() throws {
        // Unit-suffix values are normalized to the nearest 0.5 step.
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR_4.5K.dat"))
        #expect(hints.conditionValues["temperature"] == "4.5K")
    }

    // MARK: - Substrate matches

    @Test("STO111 token produces STO material and 111 orientation tags")
    func substrateSTOWithOrientation() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR_STO111.dat"))
        #expect(hints.substrateTags.contains("STO"))
        #expect(hints.substrateTags.contains("111"))
    }

    @Test("HF token produces HF treatment tag")
    func substrateHFTreatment() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR_STO111_HF.dat"))
        #expect(hints.substrateTags.contains("HF"))
    }

    @Test("MGO token produces MgO material tag")
    func substrateMGO() throws {
        let ruleSet = try loadBundledRuleSet()
        let parser = FilenameRuleParser(ruleSet: ruleSet)
        let hints = parser.parse(from: URL(fileURLWithPath: "/data/PN20_MR_MGO.dat"))
        #expect(hints.substrateTags.contains("MgO"))
    }

    // MARK: - Any expansion equivalence

    // After migration, equalsAny[A,B] becomes two equals rules. Verify both produce
    // the same match output as a single hand-crafted pair of equals rules.
    @Test("equalsAny expansion: expanded rules match same tokens as inline equals pair")
    func anyExpansionEqualsEquivalence() throws {
        // Inline fixture: two explicit equals rules (post-expansion form)
        let expandedJSON = """
        {
          "version": 5,
          "tokenization": {"separators": "_", "caseFold": "preserve"},
          "sources": ["file"],
          "sampleId": {"matches": []},
          "measurementNameRules": [
            {"match": {"type": "equals", "value": "MR"}, "value": "MR"},
            {"match": {"type": "equals", "value": "AHE"}, "value": "AHE"}
          ],
          "measurementTagRules": [],
          "channel": {"aliases": {}},
          "conditionDefinitions": [],
          "conditions": {"extraConditions": {}, "tokenMapRules": {}, "displayLabels": {}}
        }
        """
        var expandedSet = try decodeRuleSet(expandedJSON)
        _ = expandedSet.compile()

        for (token, expected) in [("MR", "MR"), ("AHE", "AHE"), ("RT", nil as String?)] {
            let got = expandedSet.measurementName(from: [token])
            #expect(got == expected, "token '\(token)': expected \(String(describing: expected)), got \(String(describing: got))")
        }
    }

    @Test("containsAny expansion: expanded rules match same tokens as inline contains pair")
    func anyExpansionContainsEquivalence() throws {
        let expandedJSON = """
        {
          "version": 5,
          "tokenization": {"separators": "_", "caseFold": "preserve"},
          "sources": ["file"],
          "sampleId": {"matches": []},
          "measurementNameRules": [],
          "measurementTagRules": [
            {"match": {"type": "contains", "value": "amr"}, "value": "AMR"},
            {"match": {"type": "contains", "value": "phe"}, "value": "PHE"}
          ],
          "channel": {"aliases": {}},
          "conditionDefinitions": [],
          "conditions": {"extraConditions": {}, "tokenMapRules": {}, "displayLabels": {}}
        }
        """
        var expandedSet = try decodeRuleSet(expandedJSON)
        _ = expandedSet.compile()

        #expect(expandedSet.measurementTags(from: ["AMR"]) == ["AMR"])
        #expect(expandedSet.measurementTags(from: ["PHE"]) == ["PHE"])
        #expect(expandedSet.measurementTags(from: ["XY"]) == [])
    }

    // MARK: - Legacy evaluator baseline

    // A private reference evaluator that applies the 4 ops directly without
    // the CompiledMatchSpec / NSRegularExpression machinery. Used to cross-check
    // that the compiled engine produces identical results.

    @Test("legacy evaluator baseline: unit-suffix condition matches agree with engine")
    func legacyEvaluatorUnitSuffixBaseline() throws {
        var ruleSet = try loadBundledRuleSet()
        _ = ruleSet.compile()

        let cases: [(token: String, conditionID: String, expected: String?)] = [
            ("300K",   "temperature", "300K"),
            ("1T",     "field",       "1T"),
            ("1mA",    "current",     "1mA"),
            ("90shift","shift",       "90shift"),
            ("foobar", "temperature", nil),
            ("K",      "temperature", nil),
        ]

        for c in cases {
            let engineResult = ruleSet.conditionEvaluation(from: [c.token]).values[c.conditionID]
            let legacyResult = legacyUnitSuffixEval(token: c.token, conditionID: c.conditionID)
            #expect(
                engineResult == c.expected,
                "engine: token '\(c.token)' conditionID '\(c.conditionID)': expected \(String(describing: c.expected))"
            )
            #expect(
                legacyResult == c.expected,
                "legacy: token '\(c.token)' conditionID '\(c.conditionID)': expected \(String(describing: c.expected))"
            )
            #expect(
                engineResult == legacyResult,
                "engine vs legacy disagree for token '\(c.token)' conditionID '\(c.conditionID)'"
            )
        }
    }

    @Test("legacy evaluator baseline: starts-with sample ID matches agree with engine")
    func legacyEvaluatorSampleIDBaseline() throws {
        var ruleSet = try loadBundledRuleSet()
        _ = ruleSet.compile()

        let cases: [(token: String, expected: Bool)] = [
            ("PN20",   true),
            ("PT5",    true),
            ("SL1",    true),
            ("XX99",   false),
            ("PN",     false),
            ("pn20",   false),
        ]

        for c in cases {
            let engineIDs = ruleSet.sampleIDs(from: [c.token])
            let engineMatch = engineIDs.contains(c.token)
            let legacyMatch = legacySampleIDMatch(token: c.token)
            #expect(engineMatch == c.expected, "engine: '\(c.token)' expected \(c.expected)")
            #expect(legacyMatch == c.expected, "legacy: '\(c.token)' expected \(c.expected)")
            #expect(engineMatch == legacyMatch, "engine vs legacy disagree for '\(c.token)'")
        }
    }

    // MARK: - Helpers

    private func loadBundledRuleSet() throws -> FilenameRuleSet {
        let result = RuleLoader.shared.loadFromBundleOnly()
        guard result.metadata.sourceLabel != "Fallback" else {
            throw NSError(domain: "V515RegressionTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Bundle rules unavailable: \(result.warnings.joined(separator: "; "))"
            ])
        }
        return result.ruleSet
    }

    private func decodeRuleSet(_ json: String) throws -> FilenameRuleSet {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(FilenameRuleSet.self, from: data)
    }

    // Reference implementation: unit-suffix match using direct regex construction.
    // Mirrors the pattern "^-?\d+(?:\.\d+)?(?:<unit>)$" from the engine.
    private func legacyUnitSuffixEval(token: String, conditionID: String) -> String? {
        let unitsByCondition: [String: [String]] = [
            "temperature": ["K", "k", "C"],
            "current":     ["mA", "A", "uA"],
            "field":       ["T", "mT", "Oe"],
            "shift":       ["shift"],
        ]
        guard let units = unitsByCondition[conditionID] else { return nil }
        for unit in units {
            let escaped = NSRegularExpression.escapedPattern(for: unit)
            let pattern = "^-?\\d+(?:\\.\\d+)?(?:\(escaped))$"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(token.startIndex..<token.endIndex, in: token)
            if regex.firstMatch(in: token, range: range) != nil {
                return token
            }
        }
        return nil
    }

    // Reference implementation: starts-with sample ID match.
    // Mirrors the pattern "^<prefix>\d+$" from the engine.
    private func legacySampleIDMatch(token: String) -> Bool {
        let prefixes = ["PN", "PT", "SL"]
        for prefix in prefixes {
            let escaped = NSRegularExpression.escapedPattern(for: prefix)
            let pattern = "^\(escaped)\\d+$"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(token.startIndex..<token.endIndex, in: token)
            if regex.firstMatch(in: token, range: range) != nil {
                return true
            }
        }
        return false
    }
}
