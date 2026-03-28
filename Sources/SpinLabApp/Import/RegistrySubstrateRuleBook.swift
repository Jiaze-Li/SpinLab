import Foundation

struct RegistrySubstrateResolution {
    var resolvedSubstrate: String?
    var warning: String?
}

protocol RegistrySubstrateRuleProviding {
    func hasStandaloneOriginToken(fileName: String, originalFilePath: String?) -> Bool
    func resolvedSubstrate(
        sampleID: String,
        substrateValue: String?,
        substrateTags: [String],
        allowsOriginToken: Bool
    ) -> RegistrySubstrateResolution
}

struct RegistrySubstrateRuleBook: RegistrySubstrateRuleProviding {
    private let tokenSeparators: CharacterSet
    private let originStandaloneTokens: Set<String>
    private let originContainsTokens: [String]
    private let treatmentKeywords: [String: [String]]
    private let materialTokens: Set<String>
    private let orientationPattern: String

    private struct SubstrateConstraints {
        var treatments: Set<String> = []
        var materials: Set<String> = []
        var orientations: Set<String> = []
    }

    private struct SubstrateCandidate {
        var raw: String
        var treatment: String?
        var material: String?
        var orientation: String?
    }

    init(ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared) {
        let substrate = ruleProvider.sharedSubstrateRules()
        tokenSeparators = CharacterSet(charactersIn: substrate.tokenSeparators)
        originStandaloneTokens = Set(substrate.originStandaloneTokens.map { $0.lowercased() })
        originContainsTokens = substrate.originContainsTokens.map { $0.lowercased() }
        treatmentKeywords = substrate.treatmentKeywords.mapValues { $0.map { token in token.lowercased() } }
        materialTokens = Set(substrate.materialTokens.map { $0.lowercased() })
        orientationPattern = substrate.orientationPattern
    }

    init(ruleLoadResult: RuleLoader.LoadResult) {
        self.init(ruleProvider: InlineRuleProvider(loadResult: ruleLoadResult))
    }

    func hasStandaloneOriginToken(fileName: String, originalFilePath: String?) -> Bool {
        var texts: [String] = [fileName]

        if let originalFilePath {
            let url = URL(fileURLWithPath: originalFilePath)
            texts.append(url.deletingPathExtension().lastPathComponent)
            texts.append(url.deletingLastPathComponent().lastPathComponent)
            texts.append(url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent)
        }

        for text in texts {
            let tokens = text.components(separatedBy: tokenSeparators).filter { !$0.isEmpty }
            if tokens.contains(where: { token in
                let lower = token.lowercased()
                if originStandaloneTokens.contains(lower) {
                    return true
                }
                return originContainsTokens.contains(where: { lower.contains($0) })
            }) {
                return true
            }
        }

        return false
    }

    func resolvedSubstrate(
        sampleID: String,
        substrateValue: String?,
        substrateTags: [String],
        allowsOriginToken: Bool
    ) -> RegistrySubstrateResolution {
        let normalizedTags = substrateTags.compactMap { normalized($0) }
        guard let substrateValue else {
            return RegistrySubstrateResolution(
                resolvedSubstrate: nil,
                warning: "Registry substrate is missing for \(sampleID)."
            )
        }

        let variants = substrateValue
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !variants.isEmpty else {
            return RegistrySubstrateResolution(
                resolvedSubstrate: nil,
                warning: "Registry substrate is empty for \(sampleID)."
            )
        }

        if normalizedTags.isEmpty {
            if variants.count == 1 {
                return RegistrySubstrateResolution(resolvedSubstrate: variants[0], warning: nil)
            }
            return RegistrySubstrateResolution(resolvedSubstrate: nil, warning: nil)
        }

        let constraints = substrateConstraints(from: normalizedTags, allowsOriginToken: allowsOriginToken)
        let candidates = variants.map(parseSubstrateCandidate)
        let matches = candidates.filter { candidate in
            substrateCandidate(candidate, satisfies: constraints)
        }

        if matches.count == 1 {
            return RegistrySubstrateResolution(resolvedSubstrate: matches[0].raw, warning: nil)
        }

        let info = substrateConstraintDescription(constraints)
        if matches.isEmpty {
            return RegistrySubstrateResolution(
                resolvedSubstrate: nil,
                warning: "No substrate candidate matches parsed tags for \(sampleID) (\(info))."
            )
        }

        return RegistrySubstrateResolution(
            resolvedSubstrate: nil,
            warning: "Multiple substrate candidates match parsed tags for \(sampleID) (\(info))."
        )
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizeSubstrateTag(_ value: String) -> String {
        let normalized = value.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
        if normalized == "o" {
            return "origin"
        }
        return normalized
    }

    private func substrateConstraints(from substrateTags: [String], allowsOriginToken: Bool) -> SubstrateConstraints {
        var constraints = SubstrateConstraints()

        for tag in substrateTags {
            let normalized = normalizeSubstrateTag(tag)
            if let treatment = matchedTreatment(from: normalized, allowsOriginToken: allowsOriginToken) {
                constraints.treatments.insert(treatment)
                continue
            }

            if let orientation = extractOrientation(from: normalized) {
                constraints.orientations.insert(orientation)
            }

            if let material = conservativeMaterial(from: normalized) {
                constraints.materials.insert(material.lowercased())
            }
        }

        if constraints.treatments.contains("hf") || constraints.treatments.contains("baked") {
            constraints.treatments.remove("o")
        }

        return constraints
    }

    private func parseSubstrateCandidate(_ substrate: String) -> SubstrateCandidate {
        let normalized = normalizeSubstrateTag(substrate)
        var candidate = SubstrateCandidate(raw: substrate, treatment: nil, material: nil, orientation: nil)

        candidate.treatment = matchedTreatment(from: normalized, allowsOriginToken: true)

        candidate.orientation = extractOrientation(from: normalized)
        candidate.material = conservativeMaterial(from: substrate)?.lowercased()
        return candidate
    }

    private func substrateCandidate(_ candidate: SubstrateCandidate, satisfies constraints: SubstrateConstraints) -> Bool {
        if !constraints.treatments.isEmpty {
            guard let treatment = candidate.treatment, constraints.treatments.contains(treatment) else {
                return false
            }
        }

        if !constraints.materials.isEmpty {
            guard let material = candidate.material, constraints.materials.contains(material) else {
                return false
            }
        }

        if !constraints.orientations.isEmpty {
            guard let orientation = candidate.orientation, constraints.orientations.contains(orientation) else {
                return false
            }
        }

        return true
    }

    private func extractOrientation(from normalized: String) -> String? {
        guard let match = normalized.range(of: orientationPattern, options: .regularExpression) else {
            return nil
        }
        return String(normalized[match])
    }

    private func conservativeMaterial(from source: String) -> String? {
        let cleaned = source.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let rawTokens = cleaned
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        let materialCandidates = rawTokens.compactMap { token -> String? in
            if isTreatmentToken(token) {
                return nil
            }
            if token.range(of: #"^\d+$"#, options: .regularExpression) != nil {
                return nil
            }
            if token.range(of: #"^[a-z]{2,}\d{3}$"#, options: .regularExpression) != nil {
                let letters = token.replacingOccurrences(of: #"\d+$"#, with: "", options: .regularExpression)
                return letters.count >= 2 ? letters : nil
            }
            if token.range(of: #"^[a-z]{2,}$"#, options: .regularExpression) != nil {
                return token
            }
            return nil
        }

        let unique = Array(Set(materialCandidates))
        guard unique.count == 1, let material = unique.first else {
            return nil
        }

        if !materialTokens.isEmpty, !materialTokens.contains(material.lowercased()) {
            return nil
        }

        return material.uppercased()
    }

    private func matchedTreatment(from normalizedToken: String, allowsOriginToken: Bool) -> String? {
        for key in treatmentKeywords.keys.sorted() {
            if key == "o", !allowsOriginToken {
                continue
            }
            guard let keywords = treatmentKeywords[key] else {
                continue
            }
            if keywords.contains(where: { keyword in
                if keyword.count <= 1 {
                    return normalizedToken == keyword
                }
                return normalizedToken == keyword || normalizedToken.contains(keyword)
            }) {
                return key
            }
        }
        return nil
    }

    private func isTreatmentToken(_ token: String) -> Bool {
        let lower = token.lowercased()
        return treatmentKeywords.values.contains { keywords in
            keywords.contains(lower)
        }
    }

    private func substrateConstraintDescription(_ constraints: SubstrateConstraints) -> String {
        var parts: [String] = []
        if !constraints.treatments.isEmpty {
            parts.append("treatment=\(constraints.treatments.sorted().joined(separator: "/"))")
        }
        if !constraints.materials.isEmpty {
            parts.append("material=\(constraints.materials.sorted().joined(separator: "/"))")
        }
        if !constraints.orientations.isEmpty {
            parts.append("orientation=\(constraints.orientations.sorted().joined(separator: "/"))")
        }
        return parts.isEmpty ? "no substrate constraints" : parts.joined(separator: ", ")
    }

}
