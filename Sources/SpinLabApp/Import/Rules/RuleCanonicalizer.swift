import Foundation

struct RuleCanonicalizer {
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
}
