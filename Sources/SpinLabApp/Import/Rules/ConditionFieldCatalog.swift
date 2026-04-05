import Foundation

struct ConditionFieldCatalog {
    static let temperatureID = "temperature"
    static let currentID = "current"
    static let fieldID = "field"
    static let deviceID = "device"

    static let builtInConditionIDs: Set<String> = [
        temperatureID,
        currentID,
        fieldID
    ]

    static let builtInConditionLabels: [String: String] = [
        temperatureID: "Temperature",
        currentID: "Current",
        fieldID: "Field",
        deviceID: "Device"
    ]

    static func defaultLabel(for ruleID: String) -> String {
        if let builtIn = builtInConditionLabels[ruleID] {
            return builtIn
        }
        let cleaned = ruleID
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return ruleID }
        return cleaned
            .split(separator: " ")
            .map { token in
                let lowercased = token.lowercased()
                guard let first = lowercased.first else { return "" }
                return String(first).uppercased() + lowercased.dropFirst()
            }
            .joined(separator: " ")
    }

    static func labelMap(from ruleSet: FilenameRuleSet) -> [String: String] {
        var labels = builtInConditionLabels
        for (key, value) in ruleSet.conditions.displayLabels {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { continue }
            labels[normalizedKey] = normalizedValue
        }
        return labels
    }

    static func conditionValues(from hints: SpinLabDomain.ParsedFilenameHints) -> [String: String] {
        hints.conditionValues
    }
}
