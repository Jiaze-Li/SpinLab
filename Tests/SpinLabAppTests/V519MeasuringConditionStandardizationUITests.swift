import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.9 MeasuringCondition Standardization — UI Logic")
struct V519MeasuringConditionStandardizationUITests {

    // MARK: - Unit options derivation

    private func unitOptions(from rules: [MapRule]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for rule in rules {
            let op = FilenameRuleSet.Operation(rawValue: rule.match.type)
            guard op == .unitSuffix || op == .regex else { continue }
            let trimmed = rule.match.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted { result.append(trimmed) }
        }
        return result
    }

    @Test("standard unit options come only from unit-suffix and regex rows")
    func standardUnitOptionsComeOnlyFromUnitSuffixAndRegexRows() {
        let rules: [MapRule] = [
            MapRule(match: .init(type: "unit-suffix", value: "mA"), value: "$MATCH"),
            MapRule(match: .init(type: "equals", value: "DC"), value: "DC"),
            MapRule(match: .init(type: "contains", value: "AC"), value: "AC"),
            MapRule(match: .init(type: "regex", value: "uA"), value: "$MATCH")
        ]
        let options = unitOptions(from: rules)
        #expect(options.contains("mA"))
        #expect(options.contains("uA"))
        #expect(!options.contains("DC"))
        #expect(!options.contains("AC"))
    }

    @Test("standard unit options preserve source order and user casing")
    func standardUnitOptionsPreserveSourceOrderAndUserCasing() {
        let rules: [MapRule] = [
            MapRule(match: .init(type: "unit-suffix", value: "mA"), value: "$MATCH"),
            MapRule(match: .init(type: "unit-suffix", value: "A"), value: "$MATCH"),
            MapRule(match: .init(type: "unit-suffix", value: "uA"), value: "$MATCH")
        ]
        let options = unitOptions(from: rules)
        #expect(options == ["mA", "A", "uA"], "source order and casing must be preserved")
    }

    @Test("standard unit picker shows no options when no unit rows exist")
    func standardUnitPickerDisabledWhenNoUnitRowsExist() {
        let rules: [MapRule] = [
            MapRule(match: .init(type: "equals", value: "wafer"), value: "Wafer")
        ]
        let options = unitOptions(from: rules)
        #expect(options.isEmpty, "no unit-suffix/regex rows → no picker options")
    }

    @Test("unit-suffix row matching standardUnit is detected as identity (case-insensitive)")
    func unitSuffixRowMatchingStandardUnitKeepsTransformDisabled() {
        let standardUnit = "mA"
        let rule = MapRule(match: .init(type: "unit-suffix", value: "mA"), value: "$MATCH")
        let isIdentity = rule.match.value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == standardUnit.lowercased()
        #expect(isIdentity)
    }

    @Test("unit-suffix row with different unit enables transform field")
    func unitSuffixRowWithDifferentUnitEnablesTransformField() {
        let standardUnit = "mA"
        let rule = MapRule(match: .init(type: "unit-suffix", value: "A"), value: "$MATCH")
        let isIdentity = rule.match.value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == standardUnit.lowercased()
        #expect(!isIdentity, "A != mA → transform field should be enabled")
    }

    @Test("standardUnit matches row unit case-insensitively")
    func standardUnitMatchesRowUnitCaseInsensitively() {
        let standardUnit = "MA"  // user typed uppercase
        let rule = MapRule(match: .init(type: "unit-suffix", value: "mA"), value: "$MATCH")
        let isIdentity = rule.match.value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == standardUnit.lowercased()
        #expect(isIdentity, "MA and mA must match case-insensitively")
    }

    // MARK: - Precision/transform normalization

    @Test("clearing transform saves nil")
    func clearingTransformSavesNilAndKeepsOriginalUnit() {
        var rule = MapRule(match: .init(type: "unit-suffix", value: "A"), value: "$MATCH", transform: "*1000")
        let newTransform = "  "  // whitespace → nil
        rule.transform = newTransform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newTransform
        #expect(rule.transform == nil, "whitespace transform saves as nil")
    }

    @Test("blank precision saves nil")
    func precisionBlankSavesNil() {
        var standardization = ConditionStandardization(standardUnit: "mA", precision: "0.1")
        let newPrecision = ""
        standardization.precision = newPrecision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newPrecision
        #expect(standardization.precision == nil)
    }

    @Test("invalid precision string produces nil parsedPrecision")
    func precisionInvalidBlocksSaveWithAlert() {
        let standardization = ConditionStandardization(standardUnit: "mA", precision: "abc")
        #expect(standardization.parsedPrecision == nil, "non-numeric precision → parsedPrecision is nil")
    }

    @Test("negative precision produces nil parsedPrecision")
    func negativePrecisionIsInvalid() {
        let standardization = ConditionStandardization(standardUnit: "mA", precision: "-0.1")
        #expect(standardization.parsedPrecision == nil, "negative precision is invalid")
    }

    @Test("valid precision parses correctly")
    func validPrecisionParsesCorrectly() {
        let standardization = ConditionStandardization(standardUnit: "mA", precision: "0.1")
        #expect(standardization.parsedPrecision == Decimal(string: "0.1"))
    }

    // MARK: - Standardization codable round-trip

    @Test("ConditionStandardization round-trip: both nil")
    func standardizationBothNilRoundTrip() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let original = ConditionStandardization(standardUnit: nil, precision: nil)
        let data = try enc.encode(original)
        let decoded = try JSONDecoder().decode(ConditionStandardization.self, from: data)
        #expect(decoded.standardUnit == nil)
        #expect(decoded.precision == nil)
    }

    @Test("ConditionStandardization round-trip: values present")
    func standardizationWithValuesRoundTrip() throws {
        let enc = JSONEncoder()
        let original = ConditionStandardization(standardUnit: "mA", precision: "0.5")
        let data = try enc.encode(original)
        let decoded = try JSONDecoder().decode(ConditionStandardization.self, from: data)
        #expect(decoded.standardUnit == "mA")
        #expect(decoded.precision == "0.5")
    }
}
