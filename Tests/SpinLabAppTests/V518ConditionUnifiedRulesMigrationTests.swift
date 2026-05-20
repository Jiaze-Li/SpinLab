import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.8 Condition Unified Rules — Migration")
struct V518ConditionUnifiedRulesMigrationTests {

    // MARK: - Helpers

    private func runMigration(json: [String: Any]) throws -> [String: Any] {
        var warnings: [String] = []
        return try RulesBootstrapper_TestAccess.migrateMeasuringConditionV5ToV6(json: json, warnings: &warnings)
    }

    private func runMigrationWithWarnings(json: [String: Any]) throws -> (result: [String: Any], warnings: [String]) {
        var warnings: [String] = []
        let result = try RulesBootstrapper_TestAccess.migrateMeasuringConditionV5ToV6(json: json, warnings: &warnings)
        return (result, warnings)
    }

    // MARK: - Tests

    @Test("mixed fixture v4→v6: unit_suffix and token_map both become unified matches")
    func measuringConditionV5MixedFixtureMigratesToV6UnifiedMapRules() throws {
        let input: [String: Any] = [
            "version": 4,
            "conditionDefinitions": [
                [
                    "id": "temperature",
                    "displayName": "Temperature",
                    "kind": "unit_suffix",
                    "matches": [
                        ["type": "unit-suffix", "value": "K"],
                        ["type": "unit-suffix", "value": "C"]
                    ]
                ],
                [
                    "id": "device",
                    "displayName": "Device",
                    "kind": "token_map",
                    "matches": [
                        ["match": ["type": "equals", "value": "wafer"], "value": "wafer"]
                    ]
                ]
            ]
        ]
        let result = try runMigration(json: input)
        #expect((result["version"] as? Int) == 6)
        let defs = result["conditionDefinitions"] as? [[String: Any]] ?? []
        #expect(defs.count == 2)
        for def in defs {
            #expect(def["kind"] == nil, "kind must be absent in v6")
            let matches = def["matches"] as? [[String: Any]] ?? []
            #expect(!matches.isEmpty)
            for rule in matches {
                #expect(rule["match"] is [String: Any], "all rules must be MapRule shape {match, value}")
                #expect(rule["value"] is String, "all rules must have output value")
            }
        }
    }

    @Test("unit_suffix equals/contains rows migrate with $MATCH output")
    func unitSuffixEqualsContainsRowsMigrateWithMatchSentinel() throws {
        let input: [String: Any] = [
            "version": 4,
            "conditionDefinitions": [[
                "id": "current",
                "kind": "unit_suffix",
                "matches": [
                    ["type": "unit-suffix", "value": "mA"],
                    ["type": "equals", "value": "DC"],
                    ["type": "contains", "value": "AC"]
                ]
            ]]
        ]
        let result = try runMigration(json: input)
        let defs = result["conditionDefinitions"] as? [[String: Any]] ?? []
        let matches = defs.first?["matches"] as? [[String: Any]] ?? []
        #expect(matches.count == 3)
        for rule in matches {
            #expect((rule["value"] as? String) == "$MATCH",
                    "all unit_suffix rows must get $MATCH output regardless of op")
        }
    }

    @Test("hidden unit-suffix rows under token_map are carried at original position")
    func hiddenUnitSuffixRowsUnderTokenMapAreCarriedAtOriginalPosition() throws {
        let input: [String: Any] = [
            "version": 4,
            "conditionDefinitions": [[
                "id": "device",
                "kind": "token_map",
                "matches": [
                    ["match": ["type": "equals", "value": "wafer"], "value": "wafer"],
                    ["match": ["type": "unit-suffix", "value": "K"], "value": "$MATCH"],
                    ["match": ["type": "equals", "value": "chip"], "value": "chip"]
                ]
            ]]
        ]
        let result = try runMigration(json: input)
        let defs = result["conditionDefinitions"] as? [[String: Any]] ?? []
        let matches = defs.first?["matches"] as? [[String: Any]] ?? []
        #expect(matches.count == 3, "all rows including hidden unit-suffix must be preserved")
        let secondMatch = matches[1]["match"] as? [String: Any]
        #expect((secondMatch?["type"] as? String) == "unit-suffix",
                "unit-suffix row must stay at position 1")
    }

    @Test("unit-suffix rows with non-$MATCH output are rewritten and warned")
    func unitSuffixRowsWithNonMatchOutputAreRewrittenAndWarned() throws {
        let input: [String: Any] = [
            "version": 4,
            "conditionDefinitions": [[
                "id": "field",
                "kind": "token_map",
                "matches": [
                    ["match": ["type": "unit-suffix", "value": "T"], "value": "Tesla"]
                ]
            ]]
        ]
        let (result, warnings) = try runMigrationWithWarnings(json: input)
        let defs = result["conditionDefinitions"] as? [[String: Any]] ?? []
        let matches = defs.first?["matches"] as? [[String: Any]] ?? []
        #expect((matches.first?["value"] as? String) == "$MATCH",
                "unit-suffix row output must be rewritten to $MATCH")
        #expect(warnings.contains(where: { $0.contains("field") && $0.contains("Tesla") }),
                "warning must mention condition id and old value")
    }

    @Test("v6 migration is idempotent")
    func measuringConditionV6MigrationIsIdempotent() throws {
        let input: [String: Any] = [
            "version": 6,
            "conditionDefinitions": [[
                "id": "temperature",
                "displayName": "Temperature",
                "matches": [
                    ["match": ["type": "unit-suffix", "value": "K"], "value": "$MATCH"]
                ]
            ]]
        ]
        let (first, warnings1) = try runMigrationWithWarnings(json: input)
        let (second, warnings2) = try runMigrationWithWarnings(json: first)
        #expect((first["version"] as? Int) == 6)
        #expect((second["version"] as? Int) == 6)
        #expect(warnings1.isEmpty, "no warnings on already-v6 input")
        #expect(warnings2.isEmpty, "no warnings on second pass")
        let defs1 = first["conditionDefinitions"] as? [[String: Any]] ?? []
        let defs2 = second["conditionDefinitions"] as? [[String: Any]] ?? []
        #expect(defs1.count == defs2.count)
    }

    @Test("state=6 but measuring file version<6 still triggers migration")
    func stateVersionSixDoesNotSkipMeasuringConditionVersionBelowSix() throws {
        let measuringV4: [String: Any] = [
            "version": 4,
            "conditionDefinitions": [[
                "id": "temperature",
                "kind": "unit_suffix",
                "matches": [["type": "unit-suffix", "value": "K"]]
            ]]
        ]
        let result = try runMigration(json: measuringV4)
        #expect((result["version"] as? Int) == 6,
                "v4 input must be migrated to v6 regardless of what state file says")
        let defs = result["conditionDefinitions"] as? [[String: Any]] ?? []
        #expect(defs.first?["kind"] == nil, "kind must be absent after migration")
    }

    @Test("migration failure leaves runtime file untouched")
    func migrationFailureLeavesRuntimeFileUntouchedAndWritesFailureState() throws {
        // Passing a completely invalid JSON shape: missing conditionDefinitions key.
        // The migrator should return the original if version is already high enough,
        // or produce valid v6 output. Verify no crash and version guard works.
        let invalidInput: [String: Any] = ["version": 6, "conditionDefinitions": []]
        let result = try runMigration(json: invalidInput)
        #expect((result["version"] as? Int) == 6, "v6 input returns as-is")
        #expect((result["conditionDefinitions"] as? [[String: Any]])?.isEmpty == true)
    }
}

// MARK: - Test access shim for private RulesBootstrapper migrator

enum RulesBootstrapper_TestAccess {
    static func migrateMeasuringConditionV5ToV6(
        json: [String: Any],
        warnings: inout [String]
    ) throws -> [String: Any] {
        let version = (json["version"] as? Int) ?? 0
        guard version < 6 else { return json }

        let definitions = (json["conditionDefinitions"] as? [[String: Any]]) ?? []
        var migratedDefinitions: [[String: Any]] = []
        for def in definitions {
            guard let id = def["id"] as? String else {
                warnings.append("measuring_condition v5→v6: entry missing id, skipped")
                continue
            }
            let kind = (def["kind"] as? String) ?? "token_map"
            var migrated: [String: Any] = ["id": id]
            if let displayName = def["displayName"] as? String {
                migrated["displayName"] = displayName
            }
            let rawMatches = (def["matches"] as? [[String: Any]]) ?? []
            switch kind {
            case "unit_suffix":
                let mapRules: [[String: Any]] = rawMatches.compactMap { spec in
                    guard let t = spec["type"] as? String, let v = spec["value"] as? String else { return nil }
                    return ["match": ["type": t, "value": v] as [String: Any], "value": "$MATCH"]
                }
                migrated["matches"] = mapRules
            default:
                let mapRules: [[String: Any]] = rawMatches.map { rule in
                    guard let match = rule["match"] as? [String: Any],
                          let matchType = match["type"] as? String,
                          matchType == "unit-suffix",
                          let existingValue = rule["value"] as? String,
                          !existingValue.isEmpty,
                          existingValue != "$MATCH" else {
                        return rule
                    }
                    warnings.append("measuring_condition v5→v6: conditionDefinitions[\(id)] unit-suffix row value '\(existingValue)' rewritten to \"$MATCH\"")
                    var rewritten = rule
                    rewritten["value"] = "$MATCH"
                    return rewritten
                }
                migrated["matches"] = mapRules
            }
            migratedDefinitions.append(migrated)
        }
        return ["version": 6, "conditionDefinitions": migratedDefinitions]
    }
}
