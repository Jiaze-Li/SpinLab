import Foundation

extension RulesBootstrapper {

    static func migrateMeasuringConditionIfNeeded(json: [String: Any], warnings: inout [String]) throws -> [String: Any] {
        let isV1 = (json["conditions"] as? [String: Any]) != nil
        guard isV1 else { return json }

        let conditions = (json["conditions"] as? [String: Any]) ?? [:]
        let extraConditions = (conditions["extraConditions"] as? [String: String]) ?? [:]
        let tokenMapRules = (conditions["tokenMapRules"] as? [String: [[String: Any]]]) ?? [:]
        let definitions = (json["conditionDefinitions"] as? [[String: Any]]) ?? []

        var migratedDefinitions: [[String: Any]] = []
        for definition in definitions {
            guard let id = definition["id"] as? String,
                  let kind = definition["kind"] as? String else {
                warnings.append("measuring_condition: conditionDefinitions entry missing id/kind, skipped")
                continue
            }

            var migrated: [String: Any] = [
                "id": id,
                "kind": kind
            ]
            if let label = definition["label"] as? String {
                migrated["label"] = label
            }

            let binding = definition["binding"] as? String
            switch kind {
            case "unit_suffix":
                let bindingKey = bindingKeyFrom(binding, prefix: "conditions.extraConditions.")
                if let binding,
                   binding.hasPrefix("conditions.tokenMapRules.") {
                    warnings.append("measuring_condition: kind/binding mismatch for \(id), kind unit_suffix takes precedence")
                }
                let key = bindingKey ?? id
                if let pattern = extraConditions[key] {
                    migrated["unitPattern"] = pattern
                } else {
                    warnings.append("measuring_condition: missing unitPattern for \(id)")
                }
            case "token_map":
                let bindingKey = bindingKeyFrom(binding, prefix: "conditions.tokenMapRules.")
                if let binding,
                   binding.hasPrefix("conditions.extraConditions.") {
                    warnings.append("measuring_condition: kind/binding mismatch for \(id), kind token_map takes precedence")
                }
                let key = bindingKey ?? id
                if let rules = tokenMapRules[key] {
                    migrated["tokenMap"] = rules
                } else {
                    warnings.append("measuring_condition: missing tokenMap for \(id)")
                    migrated["tokenMap"] = []
                }
            default:
                warnings.append("measuring_condition: unsupported kind \(kind) for \(id), skipped")
                continue
            }

            migratedDefinitions.append(migrated)
        }

        return [
            "version": 2,
            "conditionDefinitions": migratedDefinitions
        ]
    }

    static func migrateMeasuringConditionV2ToV3IfNeeded(json: [String: Any], warnings: inout [String]) throws -> [String: Any] {
        let version = (json["version"] as? Int) ?? 0
        guard version < 3 else { return json }

        let definitions = (json["conditionDefinitions"] as? [[String: Any]]) ?? []
        var migratedDefinitions: [[String: Any]] = []
        for var def in definitions {
            if let label = def["label"] as? String {
                def["displayName"] = label
                def.removeValue(forKey: "label")
            }
            if let tokenMap = def["tokenMap"] as? [[String: Any]] {
                let cleaned: [[String: Any]] = tokenMap.map { rule in
                    guard var match = rule["match"] as? [String: Any] else { return rule }
                    match.removeValue(forKey: "scope")
                    var cleaned = rule
                    cleaned["match"] = match
                    return cleaned
                }
                def["tokenMap"] = cleaned
            }
            migratedDefinitions.append(def)
        }
        return ["version": 3, "conditionDefinitions": migratedDefinitions]
    }

    static func migrateMeasuringConditionV3ToV4IfNeeded(json: [String: Any], warnings: inout [String]) throws -> [String: Any] {
        let version = (json["version"] as? Int) ?? 0
        guard version < 4 else { return json }

        let definitions = (json["conditionDefinitions"] as? [[String: Any]]) ?? []
        var migratedDefinitions: [[String: Any]] = []
        for def in definitions {
            guard let id = def["id"] as? String,
                  let kind = def["kind"] as? String else {
                warnings.append("measuring_condition: conditionDefinitions entry missing id/kind, skipped")
                continue
            }
            var migrated: [String: Any] = ["id": id, "kind": kind]
            if let displayName = def["displayName"] as? String {
                migrated["displayName"] = displayName
            }
            switch kind {
            case "unit_suffix":
                let rawPattern = (def["unitPattern"] as? String) ?? ""
                if let units = parseUnitPatternAlternation(rawPattern) {
                    let matches: [[String: String]] = units.map { ["type": "unit-suffix", "value": $0] }
                    migrated["matches"] = matches
                } else {
                    warnings.append("measuring_condition: conditionDefinitions[\(id)].unitPattern could not be converted to unit-suffix rows and was discarded: '\(rawPattern)'")
                    migrated["matches"] = [[String: String]]()
                }
            case "token_map":
                let legacyRules = (def["tokenMap"] as? [[String: Any]]) ?? []
                var expandedRules: [[String: Any]] = []
                for (ruleIdx, rule) in legacyRules.enumerated() {
                    guard let matchSpec = rule["match"] as? [String: Any] else { continue }
                    let outputValue = (rule["value"] as? String) ?? ""
                    let label = "measuring_condition: conditionDefinitions[\(id)].tokenMap[\(ruleIdx)]"
                    let expanded = expandLegacyMatchSpec(matchSpec, label: label, warnings: &warnings)
                    for newSpec in expanded {
                        expandedRules.append(["match": newSpec, "value": outputValue])
                    }
                }
                migrated["matches"] = expandedRules
            default:
                throw NSError(domain: "RulesBootstrapper", code: 10,
                    userInfo: [NSLocalizedDescriptionKey: "measuring_condition: unsupported kind '\(kind)' for id '\(id)'"])
            }
            migratedDefinitions.append(migrated)
        }
        return ["version": 4, "conditionDefinitions": migratedDefinitions]
    }

    static func migrateMeasuringConditionV5ToV6IfNeeded(json: [String: Any], warnings: inout [String]) throws -> [String: Any] {
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
                // flat MatchSpec [{type, value}] → MapRule [{match: {type, value}, value: "$MATCH"}]
                let mapRules: [[String: Any]] = rawMatches.compactMap { spec in
                    guard let t = spec["type"] as? String, let v = spec["value"] as? String else { return nil }
                    return ["match": ["type": t, "value": v] as [String: Any], "value": "$MATCH"]
                }
                migrated["matches"] = mapRules
            default:
                // token_map (or unknown kind treated as token_map): already MapRule format.
                // Fix any unit-suffix rows whose output is not "$MATCH".
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

    static func migrateMeasuringConditionV6ToV7IfNeeded(json: [String: Any], warnings: inout [String]) throws -> [String: Any] {
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

    // MARK: - Private helpers (only used within this extension file)

    private static func bindingKeyFrom(_ binding: String?, prefix: String) -> String? {
        guard let binding else { return nil }
        guard binding.hasPrefix(prefix) else { return nil }
        return String(binding.dropFirst(prefix.count))
    }

    private static func parseUnitPatternAlternation(_ pattern: String) -> [String]? {
        let prefix = "^-?\\d+(?:\\.\\d+)?(?:"
        let suffix = ")$"
        guard pattern.hasPrefix(prefix), pattern.hasSuffix(suffix) else { return nil }
        let inner = String(pattern.dropFirst(prefix.count).dropLast(suffix.count))
        let candidates = inner.components(separatedBy: "|")
        let metaChars: Set<Character> = ["\\", "(", ")", "[", "]", "{", "}", "*", "+", "?", ".", "^", "$", "|"]
        for candidate in candidates {
            if candidate.isEmpty { return nil }
            if candidate.contains(where: { metaChars.contains($0) }) { return nil }
        }
        var seen = Set<String>()
        var result: [String] = []
        for candidate in candidates {
            if seen.insert(candidate).inserted {
                result.append(candidate)
            }
        }
        return result
    }
}
