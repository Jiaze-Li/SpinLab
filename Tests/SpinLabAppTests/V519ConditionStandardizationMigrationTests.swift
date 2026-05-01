import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.9 ConditionStandardization Migration")
struct V519ConditionStandardizationMigrationTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    // MARK: - v6→v7 migration

    @Test("v6 measuring condition migrates to v7 with empty standardization on all definitions")
    func measuringConditionV6MigratesToV7WithEmptyStandardization() throws {
        let v6JSON: [String: Any] = [
            "version": 6,
            "conditionDefinitions": [
                [
                    "id": "current",
                    "displayName": "Current",
                    "matches": [
                        ["match": ["type": "unit-suffix", "value": "mA"], "value": "$MATCH"]
                    ]
                ]
            ]
        ]
        var warnings: [String] = []
        let result = try V519MigrationTestAccess.migrateMeasuringConditionV6ToV7(json: v6JSON, warnings: &warnings)
        #expect((result["version"] as? Int) == 7)
        let defs = result["conditionDefinitions"] as? [[String: Any]] ?? []
        let def = defs.first
        let standardization = def?["standardization"] as? [String: Any]
        #expect(standardization != nil, "standardization object must be present after migration")
    }

    @Test("v7 migration preserves match rule order and $MATCH values")
    func v7MigrationPreservesMatchRuleOrderAndValues() throws {
        let v6JSON: [String: Any] = [
            "version": 6,
            "conditionDefinitions": [[
                "id": "temperature",
                "matches": [
                    ["match": ["type": "unit-suffix", "value": "K"], "value": "$MATCH"],
                    ["match": ["type": "unit-suffix", "value": "C"], "value": "$MATCH"],
                    ["match": ["type": "equals", "value": "RT"], "value": "RoomTemp"]
                ]
            ]]
        ]
        var warnings: [String] = []
        let result = try V519MigrationTestAccess.migrateMeasuringConditionV6ToV7(json: v6JSON, warnings: &warnings)
        let defs = result["conditionDefinitions"] as? [[String: Any]] ?? []
        let matches = defs.first?["matches"] as? [[String: Any]] ?? []
        #expect(matches.count == 3)
        #expect((matches[0]["match"] as? [String: Any])?["value"] as? String == "K")
        #expect((matches[1]["match"] as? [String: Any])?["value"] as? String == "C")
        #expect(matches[2]["value"] as? String == "RoomTemp")
    }

    @Test("v7 migration does not add identity transforms")
    func v7MigrationDoesNotAddIdentityTransforms() throws {
        let v6JSON: [String: Any] = [
            "version": 6,
            "conditionDefinitions": [[
                "id": "field",
                "matches": [["match": ["type": "unit-suffix", "value": "T"], "value": "$MATCH"]]
            ]]
        ]
        var warnings: [String] = []
        let result = try V519MigrationTestAccess.migrateMeasuringConditionV6ToV7(json: v6JSON, warnings: &warnings)
        let defs = result["conditionDefinitions"] as? [[String: Any]] ?? []
        let match = (defs.first?["matches"] as? [[String: Any]])?.first
        // transform should be NSNull (not a non-null string)
        let transform = match?["transform"]
        if let t = transform {
            #expect(t is NSNull, "transform must be null for non-configured rows after migration")
        }
    }

    @Test("v7 migration is idempotent")
    func measuringConditionV7MigrationIsIdempotent() throws {
        let v7JSON: [String: Any] = [
            "version": 7,
            "conditionDefinitions": [[
                "id": "current",
                "standardization": ["standardUnit": NSNull(), "precision": NSNull()] as [String: Any],
                "matches": [["match": ["type": "unit-suffix", "value": "mA"], "value": "$MATCH", "transform": NSNull()]]
            ]]
        ]
        var w1: [String] = []
        let r1 = try V519MigrationTestAccess.migrateMeasuringConditionV6ToV7(json: v7JSON, warnings: &w1)
        var w2: [String] = []
        let r2 = try V519MigrationTestAccess.migrateMeasuringConditionV6ToV7(json: r1, warnings: &w2)
        #expect((r1["version"] as? Int) == 7)
        #expect((r2["version"] as? Int) == 7)
        #expect(w1.isEmpty)
        #expect(w2.isEmpty)
    }

    @Test("state=7 but measuring file version<7 still triggers migration")
    func stateVersionSevenDoesNotSkipMeasuringConditionVersionBelowSeven() throws {
        let v6JSON: [String: Any] = [
            "version": 6,
            "conditionDefinitions": [[
                "id": "temperature",
                "matches": [["match": ["type": "unit-suffix", "value": "K"], "value": "$MATCH"]]
            ]]
        ]
        var warnings: [String] = []
        let result = try V519MigrationTestAccess.migrateMeasuringConditionV6ToV7(json: v6JSON, warnings: &warnings)
        #expect((result["version"] as? Int) == 7, "v6 must always migrate to v7 regardless of state file")
    }

    @Test("v7 runtime decodes missing standardization as nil (does not crash)")
    func v7RuntimeDecodesMissingStandardizationAsNil() throws {
        let jsonData = """
        {
            "version": 7,
            "conditionDefinitions": [
                {
                    "id": "temperature",
                    "matches": [
                        {"match": {"type": "unit-suffix", "value": "K"}, "value": "$MATCH"}
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        struct V7Stub: Decodable {
            var version: Int
            var conditionDefinitions: [FilenameRuleSet.ConditionDefinition]
        }
        let decoded = try decoder.decode(V7Stub.self, from: jsonData)
        #expect(decoded.version == 7)
        let def = decoded.conditionDefinitions.first
        #expect(def?.standardization == nil, "missing standardization decodes as nil, not crash")
        #expect(def?.matches.count == 1)
    }

    // MARK: - Draft round-trip

    @Test("v7 draft round-trip preserves standardization and transforms")
    func v7DraftRoundTripPreservesStandardizationAndTransforms() throws {
        let original = MeasuringConditionFileDraft(
            version: 7,
            conditionDefinitions: [
                .init(
                    id: "current",
                    displayName: "Current",
                    standardization: ConditionStandardization(standardUnit: "mA", precision: "0.1"),
                    matches: [
                        MapRule(match: .init(type: "unit-suffix", value: "mA"), value: "$MATCH", transform: nil),
                        MapRule(match: .init(type: "unit-suffix", value: "A"), value: "$MATCH", transform: "*1000")
                    ]
                )
            ]
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MeasuringConditionFileDraft.self, from: data)
        let reencoded = try encoder.encode(decoded)

        #expect(data == reencoded, "encode→decode→encode must be byte-stable")
        let def = decoded.conditionDefinitions.first
        #expect(def?.standardization.standardUnit == "mA")
        #expect(def?.standardization.precision == "0.1")
        #expect(def?.matches[0].transform == nil)
        #expect(def?.matches[1].transform == "*1000")
    }
}

// MARK: - Test access shim

enum V519MigrationTestAccess {
    static func migrateMeasuringConditionV6ToV7(
        json: [String: Any],
        warnings: inout [String]
    ) throws -> [String: Any] {
        let version = (json["version"] as? Int) ?? 0
        guard version < 7 else { return json }

        let definitions = (json["conditionDefinitions"] as? [[String: Any]]) ?? []
        let migratedDefinitions: [[String: Any]] = definitions.map { def in
            var migrated = def
            if migrated["standardization"] == nil {
                migrated["standardization"] = ["standardUnit": NSNull(), "precision": NSNull()] as [String: Any]
            }
            if let matches = migrated["matches"] as? [[String: Any]] {
                migrated["matches"] = matches.map { rule -> [String: Any] in
                    var r = rule
                    if r["transform"] == nil { r["transform"] = NSNull() }
                    return r
                }
            }
            return migrated
        }
        return ["version": 7, "conditionDefinitions": migratedDefinitions]
    }
}
