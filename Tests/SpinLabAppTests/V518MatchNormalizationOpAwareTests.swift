import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.8 $MATCH normalization is op-aware (PR #61 Codex review)")
struct V518MatchNormalizationOpAwareTests {

    private func makeRuleSet(conditionDefinitions: String) throws -> FilenameRuleSet {
        let json = """
        {
          "version": 5,
          "tokenization": {"separators": "_", "caseFold": "lower"},
          "sources": ["file"],
          "sampleId": {"matches": []},
          "measurementNameRules": [],
          "measurementTagRules": [],
          "channel": {"aliases": {}},
          "conditions": {"extraConditions": {}, "tokenMapRules": {}, "displayLabels": {}},
          "conditionDefinitions": \(conditionDefinitions)
        }
        """.data(using: .utf8)!

        var ruleSet = try JSONDecoder().decode(FilenameRuleSet.self, from: json)
        _ = ruleSet.compile()
        return ruleSet
    }

    @Test("regex op with $MATCH preserves leading zeros in captured numeric+unit token")
    func regexPreservesLeadingZero() throws {
        // SpinLab regex op semantics: user pattern is the unit suffix part;
        // engine wraps it as `^-?\d+(?:\.\d+)?\s*(?:<pattern>)$`.
        // Token "001Oe" matches; without op-aware fix, $MATCH returns "1Oe" (leading zero stripped).
        let ruleSet = try makeRuleSet(conditionDefinitions: """
        [
          {
            "id": "regex_capture",
            "displayName": "Regex Capture",
            "matches": [
              {"match": {"type": "regex", "value": "Oe"}, "value": "$MATCH"}
            ]
          }
        ]
        """)
        let result = ruleSet.conditionEvaluation(from: ["001Oe"]).values
        #expect(result["regex_capture"] == "001Oe",
                "regex+\\$MATCH must return captured token verbatim; got \(String(describing: result["regex_capture"]))")
    }

    @Test("unit-suffix op with $MATCH returns raw token when no standardUnit set")
    func unitSuffixReturnsRawTokenWithoutStandardUnit() throws {
        // 5.1.9: normalizeUnitSuffixToken removed. Without standardUnit, raw token is preserved.
        let ruleSet = try makeRuleSet(conditionDefinitions: """
        [
          {
            "id": "unit_capture",
            "displayName": "Unit Capture",
            "matches": [
              {"match": {"type": "unit-suffix", "value": "A"}, "value": "$MATCH"}
            ]
          }
        ]
        """)
        let result = ruleSet.conditionEvaluation(from: ["001A"]).values
        #expect(result["unit_capture"] == "001A",
                "unit-suffix+$MATCH without standardUnit returns raw matched token; got \(String(describing: result["unit_capture"]))")
    }

    @Test("equals op with $MATCH returns matched token verbatim, no normalization")
    func equalsDoesNotNormalize() throws {
        let ruleSet = try makeRuleSet(conditionDefinitions: """
        [
          {
            "id": "equals_capture",
            "displayName": "Equals Capture",
            "matches": [
              {"match": {"type": "equals", "value": "001A"}, "value": "$MATCH"}
            ]
          }
        ]
        """)
        let result = ruleSet.conditionEvaluation(from: ["001A"]).values
        #expect(result["equals_capture"] == "001A")
    }

    @Test("contains op with $MATCH returns matched token verbatim, no normalization")
    func containsDoesNotNormalize() throws {
        // Token "100.0K" contains substring "0K"; without op-aware fix, normalizer
        // would reduce "100.0K" → "100K" (trim trailing-zero noise).
        let ruleSet = try makeRuleSet(conditionDefinitions: """
        [
          {
            "id": "contains_capture",
            "displayName": "Contains Capture",
            "matches": [
              {"match": {"type": "contains", "value": "0K"}, "value": "$MATCH"}
            ]
          }
        ]
        """)
        let result = ruleSet.conditionEvaluation(from: ["100.0K"]).values
        #expect(result["contains_capture"] == "100.0K",
                "contains+\\$MATCH must not trim noise; got \(String(describing: result["contains_capture"]))")
    }
}
