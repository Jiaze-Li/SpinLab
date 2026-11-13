import Foundation

/// Option lists and description composition for the structured substrate inputs of the
/// new-sample form (treatment, material, orientation). Lists come from the active Rules Book
/// and keep the rule's own spelling, so `MgO` and `MGO` stay distinct entries.
struct NativeSampleSubstrateChoices: Equatable {
    var treatments: [String]
    var materials: [String]
    var orientations: [String]
    /// Treatment used when the user picks none: the Rules Book's "original / untreated" entry.
    var defaultTreatment: String

    init(treatments: [String], materials: [String], orientations: [String], defaultTreatment: String) {
        self.treatments = treatments
        self.materials = materials
        self.orientations = orientations
        self.defaultTreatment = defaultTreatment
    }

    init(compiled: FilenameRuleSet.CompiledRules) {
        let treatments = Self.uniqueNames(compiled.substrateTreatmentEntries)
        self.init(
            treatments: treatments,
            materials: Self.uniqueNames(compiled.substrateMaterialEntries),
            orientations: Self.uniqueNames(compiled.substrateOrientationEntries),
            defaultTreatment: treatments.first(where: { compiled.originTreatmentDisplayNames.contains($0) })
                ?? treatments.first(where: { $0.caseInsensitiveCompare("o") == .orderedSame })
                ?? "o"
        )
    }

    static func current(provider: any SpinLabRuleProviding = SpinLabRuleProvider.shared) -> NativeSampleSubstrateChoices {
        NativeSampleSubstrateChoices(compiled: provider.ruleSet().compiled)
    }

    /// "<Treatment> <Material>(<Orientation>)" (treatment first, as in Registry data); nil until both material and orientation are given.
    /// An empty treatment falls back to the default (original / untreated).
    func composeDescription(material: String, orientation: String, treatment: String) -> String? {
        let material = material.trimmingCharacters(in: .whitespacesAndNewlines)
        let orientation = orientation.trimmingCharacters(in: .whitespacesAndNewlines)
        let treatment = treatment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !material.isEmpty, !orientation.isEmpty else { return nil }
        let resolvedTreatment = treatment.isEmpty ? defaultTreatment : treatment
        return "\(resolvedTreatment) \(material)(\(orientation))"
    }

    /// Exact-case de-duplication in rule order.
    private static func uniqueNames(_ entries: [FilenameRuleSet.CompiledSubstrateEntry]) -> [String] {
        var seen = Set<String>()
        return entries.map(\.displayName).filter { seen.insert($0).inserted }
    }
}
