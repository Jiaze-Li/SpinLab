import Foundation
import Testing
@testable import SpinLabApp

/// Regression tests for condition kind switching (unit_suffix ↔ token_map).
///
/// The binding logic in MeasuringConditionSection filters tokenMap by op when in
/// token_map mode, so that unit-suffix ops don't hit a Picker with no matching tag
/// (which causes SwiftUI auto-snap data corruption). These tests guard that contract.
@Suite("V5.1.5 Condition Kind Switch")
struct V515ConditionKindSwitchTests {

    // MARK: - Helpers mirroring MeasuringConditionSection binding logic

    /// Mirrors unitSuffixSpecsBinding getter: reads all rules from tokenMap as MatchSpecs.
    private func readUnitSuffixSpecs(from def: MeasuringConditionFileDraft.ConditionDefinition) -> [FilenameRuleSet.MatchSpec] {
        guard let tokenMap = def.tokenMap else { return [] }
        return tokenMap.compactMap { rule -> FilenameRuleSet.MatchSpec? in
            guard let op = FilenameRuleSet.Operation(rawValue: rule.match.type) else { return nil }
            return FilenameRuleSet.MatchSpec(type: op, value: rule.match.value)
        }
    }

    /// Mirrors tokenMapRulesBinding getter: excludes unit-suffix op rules.
    private func readTokenMapRules(from def: MeasuringConditionFileDraft.ConditionDefinition) -> [MapRule] {
        (def.tokenMap ?? []).filter { $0.match.type != "unit-suffix" }
    }

    /// Mirrors tokenMapRulesBinding setter: merges new token_map rules with preserved unit-suffix rules.
    private func applyTokenMapRules(_ newRules: [MapRule], to def: inout MeasuringConditionFileDraft.ConditionDefinition) {
        let preserved = (def.tokenMap ?? []).filter { $0.match.type == "unit-suffix" }
        def.tokenMap = preserved + newRules
    }

    /// Mirrors unitSuffixSpecsBinding setter: writes specs as MapRules with value "$MATCH".
    private func applyUnitSuffixSpecs(_ specs: [FilenameRuleSet.MatchSpec], to def: inout MeasuringConditionFileDraft.ConditionDefinition) {
        def.tokenMap = specs.map { MapRule(match: .init(type: $0.type.rawValue, value: $0.value), value: "$MATCH") }
        def.unitPattern = nil
    }

    // MARK: - Tests

    @Test("unit_suffix rules survive round-trip through token_map kind")
    func unitSuffixRulesSurviveKindRoundTrip() {
        var def = MeasuringConditionFileDraft.ConditionDefinition(
            id: "temperature", displayName: nil, kind: "unit_suffix", unitPattern: nil, tokenMap: []
        )

        // Add unit-suffix rules in unit_suffix mode
        applyUnitSuffixSpecs([
            .init(type: .unitSuffix, value: "K"),
            .init(type: .unitSuffix, value: "mK")
        ], to: &def)

        // Switch to token_map: unit-suffix rules must NOT appear in token_map view
        def.kind = "token_map"
        let tokenMapView = readTokenMapRules(from: def)
        #expect(tokenMapView.isEmpty, "unit-suffix rules must be hidden in token_map mode")

        // While in token_map mode: add a token_map rule
        let newMapRule = MapRule(match: .init(type: "equals", value: "foo"), value: "bar")
        applyTokenMapRules([newMapRule], to: &def)

        // Switch back to unit_suffix
        def.kind = "unit_suffix"
        let unitSuffixView = readUnitSuffixSpecs(from: def)
        let unitSuffixOps = unitSuffixView.filter { $0.type == .unitSuffix }
        #expect(unitSuffixOps.count == 2, "original unit-suffix rules must be preserved after round-trip")
        #expect(unitSuffixOps.map(\.value).sorted() == ["K", "mK"])
    }

    @Test("token_map rules are preserved when switching back to unit_suffix")
    func tokenMapRulesPreservedOnSwitchBack() {
        var def = MeasuringConditionFileDraft.ConditionDefinition(
            id: "device", displayName: nil, kind: "token_map", unitPattern: nil, tokenMap: []
        )

        // Add rules in token_map mode
        applyTokenMapRules([
            MapRule(match: .init(type: "equals", value: "dev1"), value: "Device 1"),
            MapRule(match: .init(type: "contains", value: "dev"), value: "Generic")
        ], to: &def)

        // Switch to unit_suffix and back
        def.kind = "unit_suffix"
        def.kind = "token_map"

        let view = readTokenMapRules(from: def)
        #expect(view.count == 2)
    }

    @Test("unit-suffix op rules are invisible in token_map view but intact in storage")
    func unitSuffixOpsInvisibleInTokenMapView() {
        var def = MeasuringConditionFileDraft.ConditionDefinition(
            id: "field", displayName: nil, kind: "unit_suffix", unitPattern: nil, tokenMap: []
        )

        // Write unit-suffix rules
        applyUnitSuffixSpecs([.init(type: .unitSuffix, value: "T")], to: &def)
        #expect(def.tokenMap?.count == 1)

        // Switch to token_map: view must be empty
        def.kind = "token_map"
        #expect(readTokenMapRules(from: def).isEmpty)

        // Raw storage still has the rule
        #expect(def.tokenMap?.count == 1)
        #expect(def.tokenMap?.first?.match.type == "unit-suffix")
    }

    @Test("equals and contains rules in unit_suffix mode survive token_map round-trip")
    func equalsContainsRulesSurviveRoundTrip() {
        var def = MeasuringConditionFileDraft.ConditionDefinition(
            id: "current", displayName: nil, kind: "unit_suffix", unitPattern: nil, tokenMap: []
        )

        // unit_suffix mode allows equals and contains too
        applyUnitSuffixSpecs([
            .init(type: .equals, value: "DC"),
            .init(type: .contains, value: "AC")
        ], to: &def)

        // Switch to token_map: equals/contains rules ARE visible (they're compatible)
        def.kind = "token_map"
        let tokenMapView = readTokenMapRules(from: def)
        #expect(tokenMapView.count == 2, "equals/contains rules should appear in token_map view")

        // Switch back
        def.kind = "unit_suffix"
        let specs = readUnitSuffixSpecs(from: def)
        #expect(specs.count == 2)
        #expect(specs.map(\.value).sorted() == ["AC", "DC"])
    }

    @Test("token_map encode/decode round-trip preserves output value")
    func tokenMapEncodeDecodePreservesOutputValue() throws {
        var def = MeasuringConditionFileDraft.ConditionDefinition(
            id: "device", displayName: nil, kind: "token_map", unitPattern: nil, tokenMap: [
                MapRule(match: .init(type: "equals", value: "dev1"), value: "Device 1"),
                MapRule(match: .init(type: "contains", value: "chip"), value: "Chip")
            ]
        )
        _ = def  // suppress unused warning

        // Encode to JSON
        let encoded = try JSONEncoder().encode(
            MeasuringConditionFileDraft(version: 1, conditionDefinitions: [def])
        )

        // Decode back
        let decoded = try JSONDecoder().decode(MeasuringConditionFileDraft.self, from: encoded)
        let roundTripped = decoded.conditionDefinitions.first
        #expect(roundTripped?.kind == "token_map")
        #expect(roundTripped?.tokenMap?.count == 2)
        #expect(roundTripped?.tokenMap?.first?.value == "Device 1", "output value must survive encode/decode")
        #expect(roundTripped?.tokenMap?.last?.value == "Chip")
        #expect(roundTripped?.tokenMap?.first?.match.type == "equals")
    }

    @Test("unit_suffix encode/decode round-trip preserves specs")
    func unitSuffixEncodeDecodePreservesSpecs() throws {
        let def = MeasuringConditionFileDraft.ConditionDefinition(
            id: "temperature", displayName: nil, kind: "unit_suffix", unitPattern: nil, tokenMap: [
                MapRule(match: .init(type: "unit-suffix", value: "K"), value: "$MATCH"),
                MapRule(match: .init(type: "equals", value: "RT"), value: "$MATCH")
            ]
        )

        let encoded = try JSONEncoder().encode(
            MeasuringConditionFileDraft(version: 1, conditionDefinitions: [def])
        )
        let decoded = try JSONDecoder().decode(MeasuringConditionFileDraft.self, from: encoded)
        let roundTripped = decoded.conditionDefinitions.first
        #expect(roundTripped?.kind == "unit_suffix")
        #expect(roundTripped?.tokenMap?.count == 2)
        #expect(roundTripped?.tokenMap?.map(\.match.type).sorted() == ["equals", "unit-suffix"])
    }
}
