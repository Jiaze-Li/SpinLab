import Foundation

struct FileRoutingSemanticRules {
    var treatmentNeedles: [String: String]
    var materialNeedles: [String: String]
    var orientationNeedles: Set<String>
    var orientationAliases: [String: String]

    static let `default` = FileRoutingSemanticRules(
        treatmentNeedles: [:],
        materialNeedles: [:],
        orientationNeedles: [],
        orientationAliases: [:]
    )

    static func load(ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared) -> FileRoutingSemanticRules {
        var rules = FileRoutingSemanticRules.default

        if let config = ruleProvider.substrateConfig() {
            for treatment in config.treatments {
                let canonical = normalizeToken(treatment.displayName)
                if !canonical.isEmpty { rules.treatmentNeedles[canonical] = treatment.displayName }
                for match in treatment.matches {
                    let normalized = normalizeToken(match.value)
                    guard !normalized.isEmpty else { continue }
                    rules.treatmentNeedles[normalized] = treatment.displayName
                }
            }
            for material in config.materials {
                let canonical = normalizeToken(material.displayName)
                if !canonical.isEmpty { rules.materialNeedles[canonical] = material.displayName }
                for match in material.matches {
                    let normalized = normalizeToken(match.value)
                    guard !normalized.isEmpty else { continue }
                    rules.materialNeedles[normalized] = material.displayName
                }
            }
            for orientation in config.orientations {
                let canonical = normalizeToken(orientation.displayName)
                guard !canonical.isEmpty else { continue }
                rules.orientationNeedles.insert(canonical)
                for match in orientation.matches {
                    let normalized = normalizeToken(match.value)
                    guard !normalized.isEmpty else { continue }
                    rules.orientationNeedles.insert(normalized)
                    if normalized != canonical {
                        rules.orientationAliases[normalized] = canonical
                    }
                }
            }
        }

        return rules
    }

    private static func normalizeToken(_ token: String) -> String {
        token.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
    }

}
