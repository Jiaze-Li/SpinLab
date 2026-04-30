import Foundation

struct RuleCanonicalizer {
    struct UserRuleMigrationResult {
        var json: [String: Any]
        var changed: Bool
    }

    static func normalizeConditionDefinitionBindings(
        ruleSet: inout FilenameRuleSet,
        sourceLabel: String
    ) -> [String] {
        var warnings: [String] = []

        if ruleSet.conditionDefinitions.isEmpty {
            var synthesized: [FilenameRuleSet.ConditionDefinition] = []
            var seenIDs: Set<String> = []

            func appendIfNew(id: String) {
                let key = id.lowercased()
                guard seenIDs.insert(key).inserted else { return }
                synthesized.append(.init(
                    id: id,
                    displayName: ConditionFieldCatalog.defaultLabel(for: id),
                    matches: []
                ))
            }

            for id in [ConditionFieldCatalog.temperatureID, ConditionFieldCatalog.currentID,
                       ConditionFieldCatalog.fieldID, ConditionFieldCatalog.deviceID] {
                appendIfNew(id: id)
            }
            for key in ruleSet.conditions.extraConditions.keys.sorted() { appendIfNew(id: key) }
            for key in ruleSet.conditions.tokenMapRules.keys.sorted() { appendIfNew(id: key) }

            ruleSet.conditionDefinitions = synthesized
            warnings.append("\(sourceLabel) has no conditionDefinitions; synthesized canonical definitions for compatibility.")
            return warnings
        }
        return warnings
    }

    static func migrateUserRuleJSONToCanonical(_ originalJSON: [String: Any]) -> UserRuleMigrationResult {
        var json = originalJSON
        let hasInbox = json["inbox"] is [String: Any]
        var inbox = (json["inbox"] as? [String: Any]) ?? [:]
        var conditions = (hasInbox ? inbox["conditions"] : json["conditions"]) as? [String: Any] ?? [:]
        var changed = false

        let extraConditions = (conditions["extraConditions"] as? [String: String]) ?? [:]
        let tokenMapRules = (conditions["tokenMapRules"] as? [String: Any]) ?? [:]

        let conditionDefinitions = (hasInbox ? inbox["conditionDefinitions"] : json["conditionDefinitions"]) as? [[String: Any]] ?? []
        if conditionDefinitions.isEmpty {
            changed = true
        }

        func canonicalizedDefinition(_ raw: [String: Any]) -> [String: Any]? {
            guard let rawID = raw["id"] as? String else { return nil }
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }

            guard let kindRaw = raw["kind"] as? String,
                  kindRaw == "unit_suffix" || kindRaw == "token_map" else {
                return nil
            }

            let label = ((raw["label"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty) ?? ConditionFieldCatalog.defaultLabel(for: id)
            if (raw["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty == nil {
                changed = true
            }

            return [
                "id": id,
                "label": label,
                "kind": kindRaw
            ]
        }

        var canonicalDefinitions = conditionDefinitions.compactMap { canonicalizedDefinition($0) }
        var seenDefinitionKeys: Set<String> = Set(
            canonicalDefinitions.compactMap { definition in
                guard let id = definition["id"] as? String,
                      let kind = definition["kind"] as? String else {
                    return nil
                }
                return "\(id.lowercased()):\(kind)"
            }
        )

        func appendDefinitionIfMissing(id: String, kind: RuleEntryKind) {
            let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedID.isEmpty else { return }
            let key = "\(normalizedID.lowercased()):\(kind.rawValue)"
            guard seenDefinitionKeys.insert(key).inserted else { return }
            canonicalDefinitions.append([
                "id": normalizedID,
                "label": ConditionFieldCatalog.defaultLabel(for: normalizedID),
                "kind": kind.rawValue
            ])
            changed = true
        }

        appendDefinitionIfMissing(id: ConditionFieldCatalog.temperatureID, kind: .unitSuffix)
        appendDefinitionIfMissing(id: ConditionFieldCatalog.currentID, kind: .unitSuffix)
        appendDefinitionIfMissing(id: ConditionFieldCatalog.fieldID, kind: .unitSuffix)
        appendDefinitionIfMissing(id: ConditionFieldCatalog.deviceID, kind: .tokenMap)
        for key in extraConditions.keys.sorted() {
            appendDefinitionIfMissing(id: key, kind: .unitSuffix)
        }
        for key in tokenMapRules.keys.sorted() {
            appendDefinitionIfMissing(id: key, kind: .tokenMap)
        }

        conditions["extraConditions"] = extraConditions
        conditions["tokenMapRules"] = tokenMapRules

        if hasInbox {
            inbox["conditions"] = conditions
            inbox["conditionDefinitions"] = canonicalDefinitions
            json["inbox"] = inbox
        } else {
            json["conditions"] = conditions
            json["conditionDefinitions"] = canonicalDefinitions
        }

        return UserRuleMigrationResult(json: json, changed: changed)
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
