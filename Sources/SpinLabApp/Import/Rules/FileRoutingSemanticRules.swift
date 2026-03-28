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
        let substrate = ruleProvider.sharedSubstrateRules()

        for canonical in substrate.treatmentKeywords.keys.sorted() {
            guard let keywords = substrate.treatmentKeywords[canonical] else {
                continue
            }
            for keyword in keywords {
                let normalizedKeyword = normalizeToken(keyword)
                guard !normalizedKeyword.isEmpty else {
                    continue
                }
                rules.treatmentNeedles[normalizedKeyword] = canonical
            }
        }

        for material in substrate.materialTokens {
            let normalizedMaterial = normalizeToken(material)
            guard !normalizedMaterial.isEmpty else {
                continue
            }
            rules.materialNeedles[normalizedMaterial] = material.uppercased()
        }

        for (alias, canonical) in (substrate.materialAliases ?? [:]) {
            let normalizedAlias = normalizeToken(alias)
            guard !normalizedAlias.isEmpty else {
                continue
            }
            rules.materialNeedles[normalizedAlias] = canonical.uppercased()
        }

        for token in (substrate.orientationTokens ?? []) {
            let normalizedToken = normalizeToken(token)
            guard !normalizedToken.isEmpty else {
                continue
            }
            rules.orientationNeedles.insert(normalizedToken)
        }

        for (alias, canonical) in (substrate.orientationAliases ?? [:]) {
            let normalizedAlias = normalizeToken(alias)
            let normalizedCanonical = normalizeToken(canonical)
            guard !normalizedAlias.isEmpty, !normalizedCanonical.isEmpty else {
                continue
            }
            rules.orientationNeedles.insert(normalizedAlias)
            rules.orientationNeedles.insert(normalizedCanonical)
            rules.orientationAliases[normalizedAlias] = normalizedCanonical
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
