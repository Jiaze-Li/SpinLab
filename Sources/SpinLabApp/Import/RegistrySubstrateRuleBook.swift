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
    private let originTreatmentDisplayNames: Set<String>
    private let compiledTreatments: [FilenameRuleSet.CompiledSubstrateEntry]
    private let compiledMaterials: [FilenameRuleSet.CompiledSubstrateEntry]
    private let compiledOrientations: [FilenameRuleSet.CompiledSubstrateEntry]

    // Fallback fields for v1/v2 sharedSubstrate path
    private let legacyOriginStandaloneTokens: Set<String>
    private let legacyOriginContainsTokens: [String]
    private let legacyTreatmentKeywords: [String: [String]]
    private let legacyMaterialTokens: Set<String>
    private let legacyOrientationPattern: String

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
        tokenSeparators = CharacterSet(charactersIn: ruleProvider.ruleSet().tokenization.separators)
        let compiled = ruleProvider.ruleSet().compiled

        if !compiled.substrateTreatmentEntries.isEmpty || ruleProvider.substrateConfig() != nil {
            // v4 path: use compiled substrate entries
            compiledTreatments = compiled.substrateTreatmentEntries
            compiledMaterials = compiled.substrateMaterialEntries
            compiledOrientations = compiled.substrateOrientationEntries
            originTreatmentDisplayNames = compiled.originTreatmentDisplayNames

            legacyOriginStandaloneTokens = []
            legacyOriginContainsTokens = []
            legacyTreatmentKeywords = [:]
            legacyMaterialTokens = []
            legacyOrientationPattern = ""
        } else {
            // v1/v2 sharedSubstrate fallback
            compiledTreatments = []
            compiledMaterials = []
            compiledOrientations = []
            originTreatmentDisplayNames = []

            let substrate = ruleProvider.sharedSubstrateRules()
            legacyOriginStandaloneTokens = Set(substrate.originStandaloneTokens.map { $0.lowercased() })
            legacyOriginContainsTokens = substrate.originContainsTokens.map { $0.lowercased() }
            legacyTreatmentKeywords = substrate.treatmentKeywords.mapValues { $0.map { $0.lowercased() } }
            legacyMaterialTokens = Set(substrate.materialTokens.map { $0.lowercased() })
            legacyOrientationPattern = substrate.orientationPattern
        }
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
                if !compiledTreatments.isEmpty {
                    let normalized = FilenameRuleSet.normalizeForSubstrate(token)
                    return originTreatmentDisplayNames.contains(where: { displayName in
                        guard let entry = compiledTreatments.first(where: { $0.displayName == displayName }) else { return false }
                        return entry.equalsKeysNormalized.contains(normalized)
                            || entry.containsNeedlesNormalized.contains(where: { normalized.contains($0) })
                    })
                }
                let lower = token.lowercased()
                if legacyOriginStandaloneTokens.contains(lower) { return true }
                return legacyOriginContainsTokens.contains(where: { lower.contains($0) })
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
        let normalizedTags = substrateTags.compactMap(normalized(_:))
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
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func substrateConstraints(from substrateTags: [String], allowsOriginToken: Bool) -> SubstrateConstraints {
        var constraints = SubstrateConstraints()

        for tag in substrateTags {
            if let treatment = matchedTreatment(from: tag, allowsOriginToken: allowsOriginToken) {
                constraints.treatments.insert(treatment)
                continue
            }

            if let orientation = extractOrientation(from: tag) {
                constraints.orientations.insert(orientation)
            }

            if let material = conservativeMaterial(from: tag) {
                constraints.materials.insert(material)
            }
        }

        if constraints.treatments.contains(where: { !originTreatmentDisplayNames.contains($0) && !legacyOriginStandaloneTokens.contains($0.lowercased()) }) {
            for originName in originTreatmentDisplayNames {
                constraints.treatments.remove(originName)
            }
        }

        return constraints
    }

    private func parseSubstrateCandidate(_ substrate: String) -> SubstrateCandidate {
        var candidate = SubstrateCandidate(raw: substrate, treatment: nil, material: nil, orientation: nil)
        candidate.treatment = matchedTreatment(from: substrate, allowsOriginToken: true)
        candidate.orientation = extractOrientation(from: substrate)
        candidate.material = conservativeMaterial(from: substrate)
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

    private func matchedTreatment(from tag: String, allowsOriginToken: Bool) -> String? {
        if !compiledTreatments.isEmpty {
            let normalized = FilenameRuleSet.normalizeForSubstrate(tag)
            for entry in compiledTreatments {
                if !allowsOriginToken, originTreatmentDisplayNames.contains(entry.displayName) { continue }
                if entry.equalsKeysNormalized.contains(normalized)
                    || entry.containsNeedlesNormalized.contains(where: { normalized.contains($0) }) {
                    return entry.displayName
                }
            }
            return nil
        }

        // Legacy v1/v2 path
        let lower = tag.lowercased()
        for key in legacyTreatmentKeywords.keys.sorted() {
            if key == "o", !allowsOriginToken { continue }
            guard let keywords = legacyTreatmentKeywords[key] else { continue }
            if keywords.contains(where: { keyword in
                if keyword.count <= 1 { return lower == keyword }
                return lower == keyword || lower.contains(keyword)
            }) {
                return key
            }
        }
        return nil
    }

    private func extractOrientation(from tag: String) -> String? {
        if !compiledOrientations.isEmpty {
            let normalized = FilenameRuleSet.normalizeForSubstrate(tag)
            for entry in compiledOrientations {
                if entry.equalsKeysNormalized.contains(normalized)
                    || entry.containsNeedlesNormalized.contains(where: { normalized.contains($0) }) {
                    return entry.displayName
                }
            }
            return nil
        }

        // Legacy v1/v2 path: regex-based
        guard !legacyOrientationPattern.isEmpty,
              let match = tag.lowercased().range(of: legacyOrientationPattern, options: .regularExpression) else {
            return nil
        }
        return String(tag.lowercased()[match])
    }

    private func conservativeMaterial(from source: String) -> String? {
        if !compiledMaterials.isEmpty {
            let normalized = FilenameRuleSet.normalizeForSubstrate(source)
            // Try exact match first (displayName or equals probe)
            for entry in compiledMaterials {
                if entry.equalsKeysNormalized.contains(normalized) {
                    return entry.displayName
                }
            }
            // Try contains match
            for entry in compiledMaterials {
                if entry.containsNeedlesNormalized.contains(where: { normalized.contains($0) }) {
                    return entry.displayName
                }
            }
            // Try substring match against all equals keys (longest first for disambiguation)
            let allProbes = compiledMaterials.flatMap { entry in
                entry.equalsKeysNormalized.map { (key: $0, displayName: entry.displayName) }
            }.sorted { $0.key.count > $1.key.count }
            for probe in allProbes where normalized.contains(probe.key) {
                // Verify it's not a treatment token
                guard !isTreatmentToken(probe.key) else { continue }
                return probe.displayName
            }
            return nil
        }

        // Legacy v1/v2 path
        let cleaned = source.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let rawTokens = cleaned
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        let materialCandidates = rawTokens.compactMap { token -> String? in
            if isTreatmentToken(token) { return nil }
            if token.range(of: #"^\d+$"#, options: .regularExpression) != nil { return nil }
            if token.range(of: #"^[a-z]{2,}\d{3}$"#, options: .regularExpression) != nil {
                let letters = token.replacingOccurrences(of: #"\d+$"#, with: "", options: .regularExpression)
                return letters.count >= 2 ? letters : nil
            }
            if token.range(of: #"^[a-z]{2,}$"#, options: .regularExpression) != nil { return token }
            return nil
        }

        let unique = Array(Set(materialCandidates))
        guard unique.count == 1, let material = unique.first else { return nil }
        if !legacyMaterialTokens.isEmpty, !legacyMaterialTokens.contains(material.lowercased()) { return nil }
        return material.uppercased()
    }

    private func isTreatmentToken(_ token: String) -> Bool {
        if !compiledTreatments.isEmpty {
            let normalized = FilenameRuleSet.normalizeForSubstrate(token)
            return compiledTreatments.contains { entry in
                entry.equalsKeysNormalized.contains(normalized)
            }
        }
        let lower = token.lowercased()
        return legacyTreatmentKeywords.values.contains { keywords in keywords.contains(lower) }
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
