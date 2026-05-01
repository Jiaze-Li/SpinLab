import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.9 ConditionStandardization Runtime Evaluator")
struct V519ConditionStandardizationRuntimeTests {

    private func makeRuleSet(conditionDefinitionsJSON: String) throws -> FilenameRuleSet {
        let json = """
        {
          "version": 7,
          "tokenization": {"separators": "_", "caseFold": "lower"},
          "sources": ["file"],
          "sampleId": {"matches": []},
          "measurementNameRules": [],
          "measurementTagRules": [],
          "channel": {"aliases": {}},
          "conditions": {"extraConditions": {}, "tokenMapRules": {}, "displayLabels": {}},
          "conditionDefinitions": \(conditionDefinitionsJSON)
        }
        """.data(using: .utf8)!
        var ruleSet = try JSONDecoder().decode(FilenameRuleSet.self, from: json)
        _ = ruleSet.compile()
        return ruleSet
    }

    @Test("standard unit selected but transform nil keeps original unit token")
    func standardUnitWithoutTransformKeepsOriginalUnitToken() throws {
        let ruleSet = try makeRuleSet(conditionDefinitionsJSON: """
        [{
          "id": "current",
          "standardization": {"standardUnit": "mA", "precision": null},
          "matches": [
            {"match": {"type": "unit-suffix", "value": "mA"}, "value": "$MATCH"},
            {"match": {"type": "unit-suffix", "value": "A"}, "value": "$MATCH"}
          ]
        }]
        """)
        // A row has no transform — output raw token (mixed units allowed)
        let result = ruleSet.conditionEvaluation(from: ["2.31A"]).values
        #expect(result["current"] == "2.31A", "no transform → raw token")
    }

    @Test("non-standard unit with transform outputs in standard unit (regex op)")
    func nonStandardUnitTransformOutputsStandardUnit() throws {
        let ruleSet = try makeRuleSet(conditionDefinitionsJSON: """
        [{
          "id": "current",
          "standardization": {"standardUnit": "mA", "precision": null},
          "matches": [
            {"match": {"type": "unit-suffix", "value": "mA"}, "value": "$MATCH"},
            {"match": {"type": "regex", "value": "A"}, "value": "$MATCH", "transform": "*1000"}
          ]
        }]
        """)
        let result = ruleSet.conditionEvaluation(from: ["2.31A"]).values
        #expect(result["current"] == "2310mA")
    }

    @Test("precision rounds after transform in standard unit (regex op)")
    func precisionRoundsAfterTransformInStandardUnit() throws {
        let ruleSet = try makeRuleSet(conditionDefinitionsJSON: """
        [{
          "id": "current",
          "standardization": {"standardUnit": "mA", "precision": "0.5"},
          "matches": [
            {"match": {"type": "unit-suffix", "value": "mA"}, "value": "$MATCH"},
            {"match": {"type": "regex", "value": "A"}, "value": "$MATCH", "transform": "*1000"}
          ]
        }]
        """)
        // 2.31 A * 1000 = 2310 mA, round to 0.5 → 2310 (already on grid)
        let result = ruleSet.conditionEvaluation(from: ["2.31A"]).values
        #expect(result["current"] == "2310mA")
    }

    @Test("unit-suffix transform is ignored (only regex triggers transform)")
    func unitSuffixTransformIsIgnored() throws {
        let ruleSet = try makeRuleSet(conditionDefinitionsJSON: """
        [{
          "id": "current",
          "standardization": {"standardUnit": "mA", "precision": null},
          "matches": [
            {"match": {"type": "unit-suffix", "value": "A"}, "value": "$MATCH", "transform": "*1000"}
          ]
        }]
        """)
        let result = ruleSet.conditionEvaluation(from: ["2.31A"]).values
        #expect(result["current"] == "2.31A", "unit-suffix ignores transform — raw token returned")
    }

    @Test("missing standard unit outputs raw matched token without normalization")
    func missingStandardUnitOutputsRawMatchedToken() throws {
        let ruleSet = try makeRuleSet(conditionDefinitionsJSON: """
        [{
          "id": "temperature",
          "standardization": {"standardUnit": null, "precision": null},
          "matches": [
            {"match": {"type": "unit-suffix", "value": "K"}, "value": "$MATCH"},
            {"match": {"type": "unit-suffix", "value": "k"}, "value": "$MATCH"}
          ]
        }]
        """)
        // standardUnit nil → raw token, no casing normalization
        let result = ruleSet.conditionEvaluation(from: ["80k"]).values
        #expect(result["temperature"] == "80k", "raw token preserved when no standardUnit")
    }

    @Test("transform ignored when standard unit is nil")
    func transformIgnoredWhenStandardUnitNil() throws {
        let ruleSet = try makeRuleSet(conditionDefinitionsJSON: """
        [{
          "id": "current",
          "standardization": {"standardUnit": null, "precision": null},
          "matches": [
            {"match": {"type": "unit-suffix", "value": "A"}, "value": "$MATCH", "transform": "*1000"}
          ]
        }]
        """)
        // standardUnit nil → transform ignored, output raw token
        let result = ruleSet.conditionEvaluation(from: ["2.31A"]).values
        #expect(result["current"] == "2.31A", "transform must be ignored when standardUnit is nil")
    }

    @Test("invalid transform keeps original token and emits warning (regex op)")
    func invalidTransformKeepsOriginalTokenAndEmitsWarning() throws {
        let ruleSet = try makeRuleSet(conditionDefinitionsJSON: """
        [{
          "id": "current",
          "standardization": {"standardUnit": "mA", "precision": null},
          "matches": [
            {"match": {"type": "regex", "value": "A"}, "value": "$MATCH", "transform": "**invalid"}
          ]
        }]
        """)
        let evaluation = ruleSet.conditionEvaluation(from: ["2.31A"])
        #expect(evaluation.values["current"] == "2.31A", "invalid transform → raw token")
        #expect(!evaluation.warnings.isEmpty, "invalid transform must produce a warning")
    }

    @Test("first match wins before transform")
    func firstMatchWinsBeforeTransform() throws {
        let ruleSet = try makeRuleSet(conditionDefinitionsJSON: """
        [{
          "id": "current",
          "standardization": {"standardUnit": "mA", "precision": null},
          "matches": [
            {"match": {"type": "unit-suffix", "value": "mA"}, "value": "$MATCH"},
            {"match": {"type": "unit-suffix", "value": "A"}, "value": "$MATCH", "transform": "*1000"}
          ]
        }]
        """)
        // "100mA" matches first rule (mA), no transform, output raw
        let result = ruleSet.conditionEvaluation(from: ["100mA"]).values
        #expect(result["current"] == "100mA")
    }

    @Test("equals/contains rules use mapped value, transform ignored")
    func equalsContainsIgnoreTransformAndUseMappedValue() throws {
        let ruleSet = try makeRuleSet(conditionDefinitionsJSON: """
        [{
          "id": "device",
          "standardization": {"standardUnit": null, "precision": null},
          "matches": [
            {"match": {"type": "equals", "value": "wafer"}, "value": "Wafer"},
            {"match": {"type": "contains", "value": "chip"}, "value": "Chip Device"}
          ]
        }]
        """)
        let result = ruleSet.conditionEvaluation(from: ["wafer"]).values
        #expect(result["device"] == "Wafer")
    }

    @Test("mixed units can coexist across condition values (per-sample difference)")
    func mixedUnitsCanCoexistAcrossConditionValues() throws {
        let ruleSet = try makeRuleSet(conditionDefinitionsJSON: """
        [{
          "id": "current",
          "standardization": {"standardUnit": "mA", "precision": null},
          "matches": [
            {"match": {"type": "unit-suffix", "value": "mA"}, "value": "$MATCH"},
            {"match": {"type": "unit-suffix", "value": "A"}, "value": "$MATCH"}
          ]
        }]
        """)
        // Sample1 has mA (no transform → raw), Sample2 has A (no transform → raw)
        let r1 = ruleSet.conditionEvaluation(from: ["100mA"]).values
        let r2 = ruleSet.conditionEvaluation(from: ["2A"]).values
        #expect(r1["current"] == "100mA")
        #expect(r2["current"] == "2A")
    }
}
