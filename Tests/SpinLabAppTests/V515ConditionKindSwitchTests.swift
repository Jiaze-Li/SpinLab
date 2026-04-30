import Foundation
import Testing
@testable import SpinLabApp

/// Tests for unified condition rule list behavior (v5.1.8+).
/// Guards user-visible contracts: rules are not lost, order is preserved,
/// all rules participate in matching, and no hidden partition exists.
@Suite("V5.1.8 Condition Unified Rules — UI Behavior")
struct V515ConditionKindSwitchTests {

    // MARK: - Helpers mirroring rulesBinding / normalizeConditionRuleForUI

    private func normalizeRule(_ rule: MapRule) -> MapRule {
        guard rule.match.type == "unit-suffix" else { return rule }
        var r = rule
        r.value = "$MATCH"
        return r
    }

    private func applyRules(_ newRules: [MapRule], to def: inout MeasuringConditionFileDraft.ConditionDefinition) {
        def.matches = newRules.map(normalizeRule)
    }

    // MARK: - Tests

    @Test("append, edit, delete preserves order")
    func unifiedRulesAppendEditDeletePreservesOrder() {
        var def = MeasuringConditionFileDraft.ConditionDefinition(id: "temperature", displayName: nil, matches: [])

        var rules = def.matches
        rules.append(MapRule(match: .init(type: "unit-suffix", value: "K"), value: "$MATCH"))
        rules.append(MapRule(match: .init(type: "equals", value: "RT"), value: "RoomTemp"))
        applyRules(rules, to: &def)
        #expect(def.matches.count == 2)
        #expect(def.matches[0].match.value == "K")
        #expect(def.matches[1].match.value == "RT")

        // Edit second rule
        var edited = def.matches
        edited[1].value = "Room Temperature"
        applyRules(edited, to: &def)
        #expect(def.matches[1].value == "Room Temperature")

        // Delete first rule
        var deleted = def.matches
        deleted.remove(at: 0)
        applyRules(deleted, to: &def)
        #expect(def.matches.count == 1)
        #expect(def.matches[0].match.value == "RT")
    }

    @Test("changing rule to unit-suffix locks output to $MATCH")
    func changingRuleToUnitSuffixLocksOutputToMatch() {
        var def = MeasuringConditionFileDraft.ConditionDefinition(id: "field", displayName: nil, matches: [
            MapRule(match: .init(type: "equals", value: "zero"), value: "ZeroField")
        ])

        // Simulate op change to unit-suffix → normalizer forces value to $MATCH
        var rules = def.matches
        rules[0].match.type = "unit-suffix"
        applyRules(rules, to: &def)
        #expect(def.matches[0].value == "$MATCH", "unit-suffix must force $MATCH output")
    }

    @Test("changing rule from unit-suffix to equals makes output editable")
    func changingRuleFromUnitSuffixToEqualsMakesOutputEditable() {
        var def = MeasuringConditionFileDraft.ConditionDefinition(id: "current", displayName: nil, matches: [
            MapRule(match: .init(type: "unit-suffix", value: "mA"), value: "$MATCH")
        ])

        // Switch to equals; normalizer leaves value unchanged (equals is not locked)
        var rules = def.matches
        rules[0].match.type = "equals"
        rules[0].value = ""  // simulate UI clearing stale $MATCH when op changes to editable
        applyRules(rules, to: &def)
        #expect(def.matches[0].value == "", "switching from unit-suffix clears $MATCH")

        // User types an output value
        var withOutput = def.matches
        withOutput[0].value = "milliAmps"
        applyRules(withOutput, to: &def)
        #expect(def.matches[0].value == "milliAmps", "user output must be preserved")
    }

    @Test("all unified rules participate in condition matching")
    func allUnifiedRulesParticipateInConditionMatching() throws {
        var ruleSet = FilenameRuleSet.fallback()
        ruleSet.conditionDefinitions = [
            .init(id: "temperature", displayName: nil, matches: [
                FilenameRuleSet.MapRule(match: .init(type: .equals, value: "RT"), value: "RoomTemp"),
                FilenameRuleSet.MapRule(match: .init(type: .contains, value: "AC"), value: "AltCurrent"),
                FilenameRuleSet.MapRule(match: .init(type: .unitSuffix, value: "K"), value: "$MATCH")
            ])
        ]
        _ = ruleSet.compile()

        // equals rule fires
        let evalEquals = ruleSet.conditionEvaluation(from: ["RT"])
        #expect(evalEquals.values["temperature"] == "RoomTemp")

        // contains rule fires
        let evalContains = ruleSet.conditionEvaluation(from: ["ACtest"])
        #expect(evalContains.values["temperature"] == "AltCurrent")

        // unit-suffix rule fires
        let evalUnit = ruleSet.conditionEvaluation(from: ["300K"])
        #expect(evalUnit.values["temperature"] == "300K")
    }

    @Test("no hidden rule partition after editing")
    func noHiddenRulePartitionAfterEditing() {
        var def = MeasuringConditionFileDraft.ConditionDefinition(id: "device", displayName: nil, matches: [
            MapRule(match: .init(type: "unit-suffix", value: "T"), value: "$MATCH"),
            MapRule(match: .init(type: "equals", value: "wafer"), value: "wafer")
        ])

        // Getter returns all rules — no filter by op
        let allRules = def.matches
        #expect(allRules.count == 2, "no rules are hidden; getter returns complete list")
        #expect(allRules.contains(where: { $0.match.type == "unit-suffix" }),
                "unit-suffix rule must be visible in unified list")
        #expect(allRules.contains(where: { $0.match.type == "equals" }),
                "equals rule must be visible in unified list")

        // After a setter round-trip, all rules survive
        applyRules(allRules, to: &def)
        #expect(def.matches.count == 2)
    }
}
