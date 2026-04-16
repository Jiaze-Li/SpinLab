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

            func appendSynthesizedDefinition(id: String, kind: FilenameRuleSet.ConditionDefinitionKind) {
                synthesized.append(
                    .init(
                        id: id,
                        label: ConditionFieldCatalog.defaultLabel(for: id),
                        kind: kind,
                        binding: canonicalBinding(for: id, kind: kind)
                    )
                )
            }

            for id in [ConditionFieldCatalog.temperatureID, ConditionFieldCatalog.currentID, ConditionFieldCatalog.fieldID] {
                appendSynthesizedDefinition(id: id, kind: .unitSuffix)
            }
            appendSynthesizedDefinition(id: ConditionFieldCatalog.deviceID, kind: .tokenMap)

            for key in ruleSet.conditions.extraConditions.keys.sorted()
                where !synthesized.contains(where: { $0.id.caseInsensitiveCompare(key) == .orderedSame && $0.kind == .unitSuffix }) {
                appendSynthesizedDefinition(id: key, kind: .unitSuffix)
            }
            for key in ruleSet.conditions.tokenMapRules.keys.sorted()
                where !synthesized.contains(where: { $0.id.caseInsensitiveCompare(key) == .orderedSame && $0.kind == .tokenMap }) {
                appendSynthesizedDefinition(id: key, kind: .tokenMap)
            }

            ruleSet.conditionDefinitions = synthesized
            warnings.append("\(sourceLabel) has no conditionDefinitions; synthesized canonical definitions for compatibility.")
            return warnings
        }

        var changed = false
        var normalized: [FilenameRuleSet.ConditionDefinition] = []

        for definition in ruleSet.conditionDefinitions {
            let id = definition.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                continue
            }
            var updated = definition
            let binding = definition.binding.trimmingCharacters(in: .whitespacesAndNewlines)

            switch definition.kind {
            case .unitSuffix:
                let canonical = canonicalBinding(for: id, kind: .unitSuffix)
                if binding != canonical {
                    updated.binding = canonical
                    changed = true
                }
            case .tokenMap:
                let canonical = canonicalBinding(for: id, kind: .tokenMap)
                if binding != canonical {
                    updated.binding = canonical
                    changed = true
                }
            }

            normalized.append(updated)
        }

        if changed {
            warnings.append("\(sourceLabel) conditionDefinitions bindings were normalized to canonical paths.")
        }
        ruleSet.conditionDefinitions = normalized
        return warnings
    }

    static func migrateUserRuleJSONToCanonical(_ originalJSON: [String: Any]) -> UserRuleMigrationResult {
        var json = originalJSON
        let hasInbox = json["inbox"] is [String: Any]
        var inbox = (json["inbox"] as? [String: Any]) ?? [:]
        var conditions = (hasInbox ? inbox["conditions"] : json["conditions"]) as? [String: Any] ?? [:]
        var changed = false

        var extraConditions = (conditions["extraConditions"] as? [String: String]) ?? [:]
        var tokenMapRules = (conditions["tokenMapRules"] as? [String: Any]) ?? [:]

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
            let canonicalBinding = kindRaw == "unit_suffix"
                ? canonicalBinding(for: id, kind: .unitSuffix)
                : canonicalBinding(for: id, kind: .tokenMap)

            if (raw["binding"] as? String) != canonicalBinding
                || (raw["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty == nil {
                changed = true
            }

            return [
                "id": id,
                "label": label,
                "kind": kindRaw,
                "binding": canonicalBinding
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
                "kind": kind.rawValue,
                "binding": kind == .unitSuffix
                    ? canonicalBinding(for: normalizedID, kind: .unitSuffix)
                    : canonicalBinding(for: normalizedID, kind: .tokenMap)
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

    private static func canonicalBinding(
        for id: String,
        kind: FilenameRuleSet.ConditionDefinitionKind
    ) -> String {
        switch kind {
        case .unitSuffix:
            return "conditions.extraConditions.\(id)"
        case .tokenMap:
            return "conditions.tokenMapRules.\(id)"
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
