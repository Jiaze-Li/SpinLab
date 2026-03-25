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

    func hasStandaloneOriginToken(fileName: String, originalFilePath: String?) -> Bool {
        let separators = CharacterSet(charactersIn: "_- ()")
        var texts: [String] = [fileName]

        if let originalFilePath {
            let url = URL(fileURLWithPath: originalFilePath)
            texts.append(url.deletingPathExtension().lastPathComponent)
            texts.append(url.deletingLastPathComponent().lastPathComponent)
            texts.append(url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent)
        }

        for text in texts {
            let tokens = text.components(separatedBy: separators).filter { !$0.isEmpty }
            if tokens.contains(where: { token in
                let lower = token.lowercased()
                return lower == "o" || lower.contains("origin") || lower.contains("original")
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
            if normalized == "hf" {
                constraints.treatments.insert("hf")
                continue
            }
            if normalized.contains("bake") {
                constraints.treatments.insert("baked")
                continue
            }
            if allowsOriginToken && (normalized == "o" || normalized.contains("origin") || normalized.contains("original")) {
                constraints.treatments.insert("o")
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

        if normalized.contains("hf") {
            candidate.treatment = "hf"
        } else if normalized.contains("bake") {
            candidate.treatment = "baked"
        } else if normalized.contains("origin") || normalized.contains("original") || normalized == "o" {
            candidate.treatment = "o"
        }

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
        guard let match = normalized.range(of: #"\d{3}"#, options: .regularExpression) else {
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
            if token == "hf" || token == "baked" || token == "bake" || token == "origin" || token == "original" || token == "o" {
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

        return material.uppercased()
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
