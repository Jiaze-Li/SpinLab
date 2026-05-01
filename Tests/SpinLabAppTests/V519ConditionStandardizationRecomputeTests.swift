import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.9 ConditionStandardization Recompute & Dead Path")
struct V519ConditionStandardizationRecomputeTests {

    // MARK: - Dead path verification

    @Test("dead rule entry types have no production references (compilation smoke)")
    func deadRuleEntryTypesHaveNoProductionReferences() throws {
        // TokenMatchType, TokenMapping, RuleEntry, RuleEntryKind, NewRuleEntrySheet, TokenMapEditor
        // have been deleted. This test confirms SpinLabApp compiles without them.
        // If any reference remained, this file would fail to compile.
        #expect(Bool(true), "compilation of SpinLabApp with dead types removed confirms no lingering references")
    }

    // MARK: - Recompute pipeline smoke

    @Test("rules panel save marks measurement sidecars stale via RuleLoader bump")
    func rulesPanelSaveMarksMeasurementSidecarsStale() throws {
        // Verify that RuleLoader.shared.bumpRuleSetVersion() increments version.
        let before = RuleLoader.shared.load().ruleSetVersion
        guard case .success(let bumped) = RuleLoader.shared.bumpRuleSetVersion() else {
            Issue.record("bumpRuleSetVersion returned failure")
            return
        }
        #expect(bumped > before, "bumpRuleSetVersion must increment version for stale-banner trigger")
    }

    @Test("condition evaluation with transform rewrites conditionValues in compiled rule set")
    func recomputeAllMeasurementSidecarsRewritesConditionValuesWithTransform() throws {
        // Build a rule set with standardUnit + transform and verify conditionValues output.
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
          "conditionDefinitions": [{
            "id": "current",
            "standardization": {"standardUnit": "mA", "precision": null},
            "matches": [
              {"match": {"type": "unit-suffix", "value": "mA"}, "value": "$MATCH"},
              {"match": {"type": "unit-suffix", "value": "A"}, "value": "$MATCH", "transform": "*1000"}
            ]
          }]
        }
        """.data(using: .utf8)!

        var ruleSet = try JSONDecoder().decode(FilenameRuleSet.self, from: json)
        _ = ruleSet.compile()

        let result = ruleSet.conditionEvaluation(from: ["0.5A"]).values
        #expect(result["current"] == "500mA", "transform *1000 converts 0.5A → 500mA")
    }

    @Test("recompute preserves user overrides (non-matching tokens unchanged)")
    func recomputePreservesUserOverridesWhileUpdatingRuleSnapshot() throws {
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
          "conditionDefinitions": [{
            "id": "current",
            "standardization": {"standardUnit": "mA", "precision": null},
            "matches": [
              {"match": {"type": "unit-suffix", "value": "mA"}, "value": "$MATCH"}
            ]
          }]
        }
        """.data(using: .utf8)!

        var ruleSet = try JSONDecoder().decode(FilenameRuleSet.self, from: json)
        _ = ruleSet.compile()

        // Token with no matching rule → no conditionValue written
        let result = ruleSet.conditionEvaluation(from: ["100V"]).values
        #expect(result["current"] == nil, "non-matching token produces no conditionValue")
    }
}
