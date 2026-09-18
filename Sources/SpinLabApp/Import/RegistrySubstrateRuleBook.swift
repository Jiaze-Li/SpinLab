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

/// Rule-derived lookup behavior for registry substrate resolution.
///
/// Does not permanently snapshot compiled rule data at init: `compiled` is a derived cache
/// keyed by the active RuleLoader fingerprint (`SpinLabRuleProviding.loadResult()`), rebuilt
/// whenever that fingerprint changes (a Rules save or Rules Book switch). This makes the type
/// safe to construct once and keep long-lived — it never goes stale after RuleLoader is
/// (re)configured, regardless of when in app startup it happened to be created.
struct RegistrySubstrateRuleBook: RegistrySubstrateRuleProviding {
    private let ruleProvider: any SpinLabRuleProviding
    private let cache: CompiledCache

    private struct Compiled {
        let tokenSeparators: CharacterSet
        let originTreatmentDisplayNames: Set<String>
        let compiledTreatments: [FilenameRuleSet.CompiledSubstrateEntry]
        let compiledMaterials: [FilenameRuleSet.CompiledSubstrateEntry]
        let compiledOrientations: [FilenameRuleSet.CompiledSubstrateEntry]

        init(ruleSet: FilenameRuleSet) {
            tokenSeparators = CharacterSet(charactersIn: ruleSet.tokenization.separators)
            let compiled = ruleSet.compiled
            compiledTreatments = compiled.substrateTreatmentEntries
            compiledMaterials = compiled.substrateMaterialEntries
            compiledOrientations = compiled.substrateOrientationEntries
            originTreatmentDisplayNames = compiled.originTreatmentDisplayNames
        }
    }

    /// Thread-safe fingerprint-keyed cache box. A class (not a struct field) because the
    /// protocol's lookup methods are non-mutating; the cache itself owns its mutable state.
    private final class CompiledCache: @unchecked Sendable {
        private let lock = NSLock()
        private var fingerprint: String?
        private var value: Compiled?

        func current(for ruleProvider: any SpinLabRuleProviding) -> Compiled {
            let loadResult = ruleProvider.loadResult()
            lock.lock()
            defer { lock.unlock() }
            if let value, fingerprint == loadResult.ruleSetFingerprint {
                return value
            }
            let rebuilt = Compiled(ruleSet: loadResult.ruleSet)
            fingerprint = loadResult.ruleSetFingerprint
            value = rebuilt
            return rebuilt
        }
    }

    /// Fetch once per public entry point and thread through as a parameter — not read via
    /// several independent computed-property accesses — so one `hasStandaloneOriginToken`/
    /// `resolvedSubstrate` call always sees a single consistent rule-set version, even if a
    /// concurrent Rules save changes the active fingerprint mid-resolution.
    private var compiled: Compiled { cache.current(for: ruleProvider) }

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
        self.ruleProvider = ruleProvider
        self.cache = CompiledCache()
    }

    /// Delegates to the primary initializer, so this also goes through `CompiledCache` — but
    /// wrapped in an `InlineRuleProvider`, whose `loadResult()` always returns the same frozen
    /// `ruleLoadResult` (it doesn't re-consult RuleLoader). The cache therefore never sees a
    /// fingerprint change and effectively stays pinned to that one snapshot. That's intentional
    /// here: this initializer exists for callers that explicitly want a frozen rule snapshot
    /// (e.g. a specific historical `RuleLoader.LoadResult`), not the live-updating default.
    init(ruleLoadResult: RuleLoader.LoadResult) {
        self.init(ruleProvider: InlineRuleProvider(loadResult: ruleLoadResult))
    }

    func hasStandaloneOriginToken(fileName: String, originalFilePath: String?) -> Bool {
        let compiled = self.compiled
        var texts: [String] = [fileName]

        if let originalFilePath {
            let url = URL(fileURLWithPath: originalFilePath)
            texts.append(url.deletingPathExtension().lastPathComponent)
            texts.append(url.deletingLastPathComponent().lastPathComponent)
            texts.append(url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent)
        }

        for text in texts {
            let tokens = text.components(separatedBy: compiled.tokenSeparators).filter { !$0.isEmpty }
            if tokens.contains(where: { token in
                let normalized = FilenameRuleSet.normalizeForSubstrate(token)
                return compiled.originTreatmentDisplayNames.contains(where: { displayName in
                    guard let entry = compiled.compiledTreatments.first(where: { $0.displayName == displayName }) else { return false }
                    return entry.matches(normalizedToken: normalized)
                })
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
        let compiled = self.compiled
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

        let constraints = substrateConstraints(from: normalizedTags, allowsOriginToken: allowsOriginToken, compiled: compiled)
        let candidates = variants.map { parseSubstrateCandidate($0, compiled: compiled) }
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

    private func substrateConstraints(from substrateTags: [String], allowsOriginToken: Bool, compiled: Compiled) -> SubstrateConstraints {
        var constraints = SubstrateConstraints()

        for tag in substrateTags {
            if let treatment = matchedTreatment(from: tag, allowsOriginToken: allowsOriginToken, compiled: compiled) {
                constraints.treatments.insert(treatment)
                continue
            }

            if let orientation = extractOrientation(from: tag, compiled: compiled) {
                constraints.orientations.insert(orientation)
            }

            if let material = conservativeMaterial(from: tag, compiled: compiled) {
                constraints.materials.insert(material)
            }
        }

        if constraints.treatments.contains(where: { !compiled.originTreatmentDisplayNames.contains($0) }) {
            for originName in compiled.originTreatmentDisplayNames {
                constraints.treatments.remove(originName)
            }
        }

        return constraints
    }

    private func parseSubstrateCandidate(_ substrate: String, compiled: Compiled) -> SubstrateCandidate {
        var candidate = SubstrateCandidate(raw: substrate, treatment: nil, material: nil, orientation: nil)
        candidate.treatment = matchedTreatment(from: substrate, allowsOriginToken: true, compiled: compiled)
        candidate.orientation = extractOrientation(from: substrate, compiled: compiled)
        candidate.material = conservativeMaterial(from: substrate, compiled: compiled)
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

    private func matchedTreatment(from tag: String, allowsOriginToken: Bool, compiled: Compiled) -> String? {
        let normalized = FilenameRuleSet.normalizeForSubstrate(tag)
        for entry in compiled.compiledTreatments {
            if !allowsOriginToken, compiled.originTreatmentDisplayNames.contains(entry.displayName) { continue }
            if entry.matches(normalizedToken: normalized) {
                return entry.displayName
            }
        }
        return nil
    }

    private func extractOrientation(from tag: String, compiled: Compiled) -> String? {
        let normalized = FilenameRuleSet.normalizeForSubstrate(tag)
        for entry in compiled.compiledOrientations {
            if entry.matches(normalizedToken: normalized) {
                return entry.displayName
            }
        }
        return nil
    }

    private func conservativeMaterial(from source: String, compiled: Compiled) -> String? {
        let normalized = FilenameRuleSet.normalizeForSubstrate(source)
        for entry in compiled.compiledMaterials {
            if entry.equalsKeysNormalized.contains(normalized) {
                return entry.displayName
            }
        }
        for entry in compiled.compiledMaterials {
            if entry.containsNeedlesNormalized.contains(where: { normalized.contains($0) }) {
                return entry.displayName
            }
        }
        let allProbes = compiled.compiledMaterials.flatMap { entry in
            entry.equalsKeysNormalized.map { (key: $0, displayName: entry.displayName) }
        }.sorted { $0.key.count > $1.key.count }
        for probe in allProbes where normalized.contains(probe.key) {
            guard !isTreatmentToken(probe.key, compiled: compiled) else { continue }
            return probe.displayName
        }
        return nil
    }

    private func isTreatmentToken(_ token: String, compiled: Compiled) -> Bool {
        let normalized = FilenameRuleSet.normalizeForSubstrate(token)
        return compiled.compiledTreatments.contains { entry in
            entry.equalsKeysNormalized.contains(normalized)
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
