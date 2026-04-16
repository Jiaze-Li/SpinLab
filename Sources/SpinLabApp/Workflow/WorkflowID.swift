import Foundation

enum WorkflowID: String, CaseIterable, Hashable, Sendable {
    case ahe
    case rt
    case threeOmega = "3w"

    /// All known aliases for canonicalization.
    var aliases: [String] {
        switch self {
        case .ahe:
            return ["ahe", "a", "anomaloushall"]
        case .rt:
            return ["rt"]
        case .threeOmega:
            return ["3w", "3omega"]
        }
    }

    /// Search token aliases, preserving current SearchWorkflowMeasurementsUseCase behavior.
    var searchAliases: [String] {
        switch self {
        case .ahe:
            return ["ahe", "a"]
        case .rt:
            return ["rt"]
        case .threeOmega:
            return ["3w", "3omega"]
        }
    }

    static func from(alias: String) -> Self? {
        let normalizedAlias = normalize(alias)
        guard !normalizedAlias.isEmpty else { return nil }

        return allCases.first { workflowID in
            workflowID.aliases.contains { normalize($0) == normalizedAlias }
        }
    }

    func matchesDisplayNameContains(_ displayName: String) -> Bool {
        let normalizedDisplayName = Self.normalize(displayName)
        guard !normalizedDisplayName.isEmpty else { return false }
        let normalizedRawValue = Self.normalize(rawValue)

        let containsAliases: [String] = aliases.compactMap { alias -> String? in
            let normalizedAlias = Self.normalize(alias)
            guard !normalizedAlias.isEmpty else { return nil }
            guard normalizedAlias == normalizedRawValue || normalizedAlias.contains(where: { $0.isNumber }) else {
                return nil
            }
            return normalizedAlias
        }

        return containsAliases.contains { normalizedAlias in
            normalizedDisplayName.contains(normalizedAlias)
        }
    }

    private static func normalize(_ value: String) -> String {
        let normalizedOmega = value
            .replacingOccurrences(of: "ω", with: "w")
            .replacingOccurrences(of: "Ω", with: "w")
            .lowercased()

        let parts = normalizedOmega
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return parts.joined(separator: "")
    }
}
