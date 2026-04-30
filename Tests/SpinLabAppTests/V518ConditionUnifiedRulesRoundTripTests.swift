import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.8 Condition Unified Rules — Round-trip")
struct V518ConditionUnifiedRulesRoundTripTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    @Test("v6 conditionDefinition encode→decode→encode: rule order and values stable")
    func v6ConditionDefinitionRoundTripPreservesUnifiedRuleOrder() throws {
        let original = MeasuringConditionFileDraft(
            version: 6,
            conditionDefinitions: [
                .init(id: "temperature", displayName: "Temperature", matches: [
                    MapRule(match: .init(type: "unit-suffix", value: "K"), value: "$MATCH"),
                    MapRule(match: .init(type: "unit-suffix", value: "C"), value: "$MATCH"),
                    MapRule(match: .init(type: "equals", value: "RT"), value: "RoomTemp")
                ])
            ]
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MeasuringConditionFileDraft.self, from: data)
        let reencoded = try encoder.encode(decoded)

        #expect(data == reencoded, "encode→decode→encode must be byte-stable")
        let def = decoded.conditionDefinitions.first
        #expect(def?.matches.count == 3)
        #expect(def?.matches[0].match.value == "K")
        #expect(def?.matches[1].match.value == "C")
        #expect(def?.matches[2].match.value == "RT")
    }

    @Test("v6 unit-suffix rule round-trip preserves $MATCH sentinel")
    func v6UnitSuffixRuleRoundTripPreservesMatchSentinel() throws {
        let draft = MeasuringConditionFileDraft(
            version: 6,
            conditionDefinitions: [
                .init(id: "field", displayName: nil, matches: [
                    MapRule(match: .init(type: "unit-suffix", value: "T"), value: "$MATCH")
                ])
            ]
        )
        let data = try encoder.encode(draft)
        let decoded = try decoder.decode(MeasuringConditionFileDraft.self, from: data)
        let rule = decoded.conditionDefinitions.first?.matches.first
        #expect(rule?.value == "$MATCH", "unit-suffix $MATCH must survive encode/decode")
        #expect(rule?.match.type == "unit-suffix")
    }

    @Test("v6 equals/contains rules preserve editable output")
    func v6EqualsContainsRulesPreserveEditableOutput() throws {
        let draft = MeasuringConditionFileDraft(
            version: 6,
            conditionDefinitions: [
                .init(id: "device", displayName: "Device", matches: [
                    MapRule(match: .init(type: "equals", value: "wafer"), value: "Wafer"),
                    MapRule(match: .init(type: "contains", value: "chip"), value: "Chip Device")
                ])
            ]
        )
        let data = try encoder.encode(draft)
        let decoded = try decoder.decode(MeasuringConditionFileDraft.self, from: data)
        let rules = decoded.conditionDefinitions.first?.matches ?? []
        #expect(rules[0].value == "Wafer")
        #expect(rules[1].value == "Chip Device")
    }

    @Test("v6 draft encode does not produce kind, unitPattern, or tokenMap fields")
    func v6DraftDoesNotEncodeKindUnitPatternOrTokenMap() throws {
        let draft = MeasuringConditionFileDraft(
            version: 6,
            conditionDefinitions: [
                .init(id: "temperature", displayName: "Temperature", matches: [
                    MapRule(match: .init(type: "unit-suffix", value: "K"), value: "$MATCH")
                ])
            ]
        )
        let data = try encoder.encode(draft)
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        #expect(!jsonString.contains("\"kind\""), "v6 must not encode kind")
        #expect(!jsonString.contains("\"unitPattern\""), "v6 must not encode unitPattern")
        #expect(!jsonString.contains("\"tokenMap\""), "v6 must not encode tokenMap")
    }

    @Test("runtime ConditionDefinition decodes v6 shape successfully")
    func runtimeConditionDefinitionDecodesOnlyUnifiedMatches() throws {
        let v6JSON = """
        {
            "version": 6,
            "conditionDefinitions": [
                {
                    "id": "temperature",
                    "displayName": "Temperature",
                    "matches": [
                        {"match": {"type": "unit-suffix", "value": "K"}, "value": "$MATCH"},
                        {"match": {"type": "equals", "value": "RT"}, "value": "RoomTemp"}
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        struct V6Stub: Decodable {
            var version: Int
            var conditionDefinitions: [FilenameRuleSet.ConditionDefinition]
        }
        let decoded = try decoder.decode(V6Stub.self, from: v6JSON)
        #expect(decoded.version == 6)
        let def = decoded.conditionDefinitions.first
        #expect(def?.matches.count == 2)
        #expect(def?.matches[0].match.type == .unitSuffix)
        #expect(def?.matches[0].value == "$MATCH")
        #expect(def?.matches[1].match.type == .equals)
        #expect(def?.matches[1].value == "RoomTemp")
    }
}
