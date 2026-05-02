import Foundation

struct MeasuringConditionRuleProjection {

    struct NormalizationOutcome {
        let normalizedRules: [MapRule]
        let standardUnit: String?
        let didInvalidateStandardUnit: Bool
    }

    static func normalize(rules: [MapRule], standardUnit: String?) -> NormalizationOutcome {
        let normalized = rules.map { normalizeRule($0, standardUnit: standardUnit) }

        if let su = standardUnit {
            let available = normalized
                .filter {
                    let op = FilenameRuleSet.Operation(rawValue: $0.match.type)
                    return op == .unitSuffix || op == .regex
                }
                .map { $0.match.value.trimmingCharacters(in: .whitespacesAndNewlines) }

            if !available.contains(where: { $0.lowercased() == su.lowercased() }) {
                let reNormalized = rules.map { normalizeRule($0, standardUnit: nil) }
                return NormalizationOutcome(
                    normalizedRules: reNormalized,
                    standardUnit: nil,
                    didInvalidateStandardUnit: true
                )
            }
        }

        return NormalizationOutcome(
            normalizedRules: normalized,
            standardUnit: standardUnit,
            didInvalidateStandardUnit: false
        )
    }

    static func standardUnitOptions(from rules: [MapRule]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for rule in rules {
            let op = FilenameRuleSet.Operation(rawValue: rule.match.type)
            guard op == .unitSuffix || op == .regex else { continue }
            let trimmed = rule.match.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    private static func normalizeRule(_ rule: MapRule, standardUnit: String?) -> MapRule {
        let op = FilenameRuleSet.Operation(rawValue: rule.match.type)
        guard op == .unitSuffix || op == .regex else {
            var r = rule
            r.transform = nil
            return r
        }
        var normalized = rule
        normalized.value = "$MATCH"
        if let su = standardUnit,
           rule.match.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == su.lowercased() {
            normalized.transform = "*1"
        } else if rule.transform == "*1" {
            normalized.transform = nil
        }
        return normalized
    }
}
