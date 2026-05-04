import Foundation

extension RulesBootstrapper {

    // expandLegacyMatchSpec is internal: called by both +MeasuringConditionMigration and +WorkflowMigration.
    static func expandLegacyMatchSpec(_ spec: [String: Any], label: String, warnings: inout [String]) -> [[String: String]] {
        guard let typeStr = spec["type"] as? String else { return [] }

        let rawValues: [String]
        if let mv = spec["matchValues"] as? [String] {
            rawValues = mv
        } else if let vs = spec["values"] as? [String] {
            rawValues = vs
        } else if let v = spec["value"] as? String {
            rawValues = [v]
        } else {
            rawValues = []
        }

        let values = rawValues
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if values.isEmpty {
            warnings.append("\(label): rule with empty matchValues dropped")
            return []
        }

        switch typeStr {
        case "equals":
            if values.count > 1 {
                warnings.append("\(label): type=equals with multiple matchValues treated as equalsAny")
            }
            return values.map { ["type": "equals", "value": $0] }
        case "contains":
            if values.count > 1 {
                warnings.append("\(label): type=contains with multiple matchValues treated as containsAny")
            }
            return values.map { ["type": "contains", "value": $0] }
        case "equalsAny":
            return values.map { ["type": "equals", "value": $0] }
        case "containsAny":
            return values.map { ["type": "contains", "value": $0] }
        case "equalsOrContainsAny":
            return values.map { ["type": "equals", "value": $0] }
                 + values.map { ["type": "contains", "value": $0] }
        case "regex":
            let pattern = values.first ?? ""
            warnings.append("\(label): regex rule was removed during s12 migration: '\(pattern)'")
            return []
        default:
            warnings.append("\(label): unknown rule type '\(typeStr)' dropped")
            return []
        }
    }
}
