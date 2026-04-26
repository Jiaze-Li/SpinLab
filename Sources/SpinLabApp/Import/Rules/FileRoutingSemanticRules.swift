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
        let ruleSet = ruleProvider.ruleSet()

        if let config = ruleProvider.substrateConfig() {
            for treatment in config.treatments {
                for keyword in treatment.keywords {
                    let normalized = normalizeToken(keyword)
                    guard !normalized.isEmpty else { continue }
                    rules.treatmentNeedles[normalized] = treatment.id
                }
            }
            for material in config.materials {
                for token in material.tokens {
                    let normalized = normalizeToken(token)
                    guard !normalized.isEmpty else { continue }
                    rules.materialNeedles[normalized] = material.id.uppercased()
                }
                for alias in material.aliases {
                    let normalized = normalizeToken(alias)
                    guard !normalized.isEmpty else { continue }
                    rules.materialNeedles[normalized] = material.id.uppercased()
                }
            }
            for row in config.orientations.rows {
                for token in row.tokens {
                    let normalized = normalizeToken(token)
                    guard !normalized.isEmpty else { continue }
                    rules.orientationNeedles.insert(normalized)
                }
                for alias in row.aliases {
                    let normalizedAlias = normalizeToken(alias)
                    let normalizedCanonical = normalizeToken(row.id)
                    guard !normalizedAlias.isEmpty, !normalizedCanonical.isEmpty else { continue }
                    rules.orientationNeedles.insert(normalizedAlias)
                    rules.orientationNeedles.insert(normalizedCanonical)
                    rules.orientationAliases[normalizedAlias] = normalizedCanonical
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

        for entry in ruleSet.substrateTagRules {
            let normalizedValue = normalizeToken(entry.value)
            guard !normalizedValue.isEmpty else {
                continue
            }
            let probes = probesForMatch(entry.match)
            if let treatment = SampleSemanticDescriptor.normalizedProcessingTokenForRules(entry.value) {
                for probe in probes where !probe.isEmpty {
                    rules.treatmentNeedles[probe] = treatment
                }
                continue
            }

            if let material = canonicalMaterial(from: normalizedValue, materialNeedles: rules.materialNeedles) {
                for probe in probes where !probe.isEmpty {
                    rules.materialNeedles[probe] = material
                }
            }

            if isOrientationToken(normalizedValue, orientationNeedles: rules.orientationNeedles) {
                rules.orientationNeedles.insert(normalizedValue)
                for probe in probes where !probe.isEmpty {
                    if isOrientationToken(probe, orientationNeedles: rules.orientationNeedles) {
                        rules.orientationNeedles.insert(probe)
                    }
                }
            }
        }

        return rules
    }

    private static func probesForMatch(_ match: FilenameRuleSet.MatchSpec) -> [String] {
        let rawValues = (match.values ?? []) + [match.value].compactMap { $0 }
        return rawValues.map(normalizeToken)
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

    private static func canonicalMaterial(from normalized: String, materialNeedles: [String: String]) -> String? {
        for (needle, canonical) in materialNeedles.sorted(by: { $0.key.count > $1.key.count }) {
            if normalized.contains(needle) {
                return canonical
            }
        }
        return nil
    }

    private static func isOrientationToken(_ normalized: String, orientationNeedles: Set<String>) -> Bool {
        orientationNeedles.contains(normalized)
    }
}
