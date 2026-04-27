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
        } else {
            let substrate = ruleProvider.sharedSubstrateRules()
            for canonical in substrate.treatmentKeywords.keys.sorted() {
                guard let keywords = substrate.treatmentKeywords[canonical] else { continue }
                for keyword in keywords {
                    let normalized = normalizeToken(keyword)
                    guard !normalized.isEmpty else { continue }
                    rules.treatmentNeedles[normalized] = canonical
                }
            }
            for material in substrate.materialTokens {
                let normalized = normalizeToken(material)
                guard !normalized.isEmpty else { continue }
                rules.materialNeedles[normalized] = material.uppercased()
            }
            for (alias, canonical) in (substrate.materialAliases ?? [:]) {
                let normalized = normalizeToken(alias)
                guard !normalized.isEmpty else { continue }
                rules.materialNeedles[normalized] = canonical.uppercased()
            }
            for token in (substrate.orientationTokens ?? []) {
                let normalized = normalizeToken(token)
                guard !normalized.isEmpty else { continue }
                rules.orientationNeedles.insert(normalized)
            }
            for (alias, canonical) in (substrate.orientationAliases ?? [:]) {
                let normalizedAlias = normalizeToken(alias)
                let normalizedCanonical = normalizeToken(canonical)
                guard !normalizedAlias.isEmpty, !normalizedCanonical.isEmpty else { continue }
                rules.orientationNeedles.insert(normalizedAlias)
                rules.orientationNeedles.insert(normalizedCanonical)
                rules.orientationAliases[normalizedAlias] = normalizedCanonical
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
