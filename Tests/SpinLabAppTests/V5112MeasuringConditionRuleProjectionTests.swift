import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.12 MeasuringConditionRuleProjection")
struct V5112MeasuringConditionRuleProjectionTests {

    // MARK: - Helpers

    private func makeRule(type: FilenameRuleSet.Operation, matchValue: String, outputValue: String = "", transform: String? = nil) -> MapRule {
        MapRule(
            match: MapRule.MatchSpec(type: type.rawValue, value: matchValue),
            value: outputValue,
            transform: transform
        )
    }

    // MARK: - standardUnitOptions

    @Test("standardUnitOptions returns unitSuffix and regex match values deduplicated and trimmed")
    func standardUnitOptionsFiltersAndDeduplicates() {
        let rules: [MapRule] = [
            makeRule(type: .unitSuffix, matchValue: "K"),
            makeRule(type: .unitSuffix, matchValue: " T "),
            makeRule(type: .regex, matchValue: "mT"),
            makeRule(type: .equals, matchValue: "RT"),       // excluded
            makeRule(type: .unitSuffix, matchValue: "K"),    // duplicate
            makeRule(type: .unitSuffix, matchValue: ""),     // empty, excluded
        ]

        let options = MeasuringConditionRuleProjection.standardUnitOptions(from: rules)

        #expect(options == ["K", "T", "mT"])
    }

    @Test("standardUnitOptions returns empty for rules with no unitSuffix or regex ops")
    func standardUnitOptionsEmptyWhenNoUnitOps() {
        let rules: [MapRule] = [
            makeRule(type: .equals, matchValue: "RT"),
            makeRule(type: .contains, matchValue: "sample"),
        ]
        #expect(MeasuringConditionRuleProjection.standardUnitOptions(from: rules).isEmpty)
    }

    // MARK: - normalize: no standardUnit

    @Test("normalize without standardUnit sets $MATCH on unit rows and clears transform")
    func normalizeNoStandardUnit_setsMatchAndClearsTransform() {
        let rules: [MapRule] = [
            makeRule(type: .unitSuffix, matchValue: "K", outputValue: "old", transform: "*1"),
            makeRule(type: .equals, matchValue: "RT", outputValue: "some"),
        ]

        let outcome = MeasuringConditionRuleProjection.normalize(rules: rules, standardUnit: nil)

        #expect(!outcome.didInvalidateStandardUnit)
        #expect(outcome.standardUnit == nil)

        let unitRow = outcome.normalizedRules[0]
        #expect(unitRow.value == "$MATCH")
        #expect(unitRow.transform == nil)  // *1 removed because no standardUnit

        let equalsRow = outcome.normalizedRules[1]
        #expect(equalsRow.value == "some")
        #expect(equalsRow.transform == nil)
    }

    // MARK: - normalize: with standardUnit, still valid

    @Test("normalize with valid standardUnit keeps it and marks identity row with *1")
    func normalizeWithValidStandardUnit_keepsAndMarksIdentity() {
        let rules: [MapRule] = [
            makeRule(type: .unitSuffix, matchValue: "K", outputValue: "any"),   // identity row
            makeRule(type: .unitSuffix, matchValue: "T", outputValue: "any"),   // non-identity
            makeRule(type: .equals, matchValue: "RT", outputValue: "RT_val"),
        ]

        let outcome = MeasuringConditionRuleProjection.normalize(rules: rules, standardUnit: "K")

        #expect(!outcome.didInvalidateStandardUnit)
        #expect(outcome.standardUnit == "K")

        let identityRow = outcome.normalizedRules[0]
        #expect(identityRow.value == "$MATCH")
        #expect(identityRow.transform == "*1")

        let nonIdentityRow = outcome.normalizedRules[1]
        #expect(nonIdentityRow.value == "$MATCH")
        #expect(nonIdentityRow.transform == nil)

        let equalsRow = outcome.normalizedRules[2]
        #expect(equalsRow.transform == nil)
    }

    // MARK: - normalize: standardUnit invalidated

    @Test("normalize sets didInvalidateStandardUnit when standardUnit no longer exists in rules")
    func normalizeInvalidatesStandardUnit_whenUnitRemovedFromRules() {
        // Rules no longer contain "K" as a unitSuffix/regex match value
        let rules: [MapRule] = [
            makeRule(type: .unitSuffix, matchValue: "T"),
            makeRule(type: .equals, matchValue: "RT"),
        ]

        let outcome = MeasuringConditionRuleProjection.normalize(rules: rules, standardUnit: "K")

        #expect(outcome.didInvalidateStandardUnit)
        #expect(outcome.standardUnit == nil)
        // Re-normalized rules should have $MATCH with no *1 (standardUnit is nil)
        let unitRow = outcome.normalizedRules[0]
        #expect(unitRow.value == "$MATCH")
        #expect(unitRow.transform == nil)
    }

    @Test("normalize is case-insensitive when checking standardUnit validity")
    func normalizeStandardUnitCaseInsensitive() {
        let rules: [MapRule] = [
            makeRule(type: .unitSuffix, matchValue: "k"),  // lowercase
        ]

        let outcome = MeasuringConditionRuleProjection.normalize(rules: rules, standardUnit: "K")  // uppercase

        #expect(!outcome.didInvalidateStandardUnit)
        #expect(outcome.standardUnit == "K")
    }
}
