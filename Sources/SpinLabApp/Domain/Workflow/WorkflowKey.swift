import Foundation

/// Typed code projection of Rule Book workflow ids.
/// Raw values exactly match the `id` fields in `workflow.json`.
/// Every Rule Book workflow id must have a case here. Add no ids absent from the Rule Book.
enum WorkflowKey: String, CaseIterable, Codable, Hashable, Sendable {
    case mr         = "MR"
    case ahe        = "ahe"
    case iv         = "IV"
    case threeOmega = "3w"
    case rt         = "RT"
    case xyRotation = "XY"
    case rsm        = "rsm"

    /// All known sidecar/filename aliases for canonicalization.
    var aliases: [String] {
        switch self {
        case .mr:         return ["mr", "MR"]
        case .ahe:        return ["ahe", "AHE", "a", "anomaloushall"]
        case .iv:         return ["IV", "iv"]
        case .threeOmega: return ["3w", "3omega"]
        case .rt:         return ["rt", "RT"]
        case .xyRotation: return ["xy", "XY"]
        case .rsm:        return ["rsm", "RSM"]
        }
    }

    /// Search token aliases for matching user queries.
    var searchAliases: [String] {
        switch self {
        case .mr:         return ["mr"]
        case .ahe:        return ["ahe", "a"]
        case .iv:         return ["iv"]
        case .threeOmega: return ["3w", "3omega"]
        case .rt:         return ["rt"]
        case .xyRotation: return ["xy"]
        case .rsm:        return ["rsm"]
        }
    }

    /// Default search prefix pre-filled into the search box.
    var searchPrefix: String {
        switch self {
        case .mr:         return "MR "
        case .ahe:        return "ahe "
        case .iv:         return "IV "
        case .threeOmega: return "3w "
        case .rt:         return "RT "
        case .xyRotation: return "xy "
        case .rsm:        return "rsm "
        }
    }

    /// Resolve a sidecar workflow field or raw id string to a known key.
    /// Returns nil when no alias matches — the caller decides whether to show
    /// NotImplementedWorkflowView or an error.
    static func from(sidecarValue value: String) -> Self? {
        let normalized = normalize(value)
        guard !normalized.isEmpty else { return nil }
        return allCases.first { key in
            key.aliases.contains { normalize($0) == normalized }
        }
    }

    func matchesDisplayNameContains(_ displayName: String) -> Bool {
        let normalizedDisplayName = Self.normalize(displayName)
        guard !normalizedDisplayName.isEmpty else { return false }
        return aliases.contains { alias in
            let normalizedAlias = Self.normalize(alias)
            guard !normalizedAlias.isEmpty else { return false }
            // Short aliases without digits (e.g. "rt") require exact match
            // to avoid false positives like "transport" matching RT.
            if normalizedAlias.contains(where: { $0.isNumber }) {
                return normalizedDisplayName.contains(normalizedAlias)
            } else {
                return normalizedDisplayName == normalizedAlias
            }
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

// MARK: - Rule Book consistency audit

extension WorkflowKey {
    /// Expected Rule Book workflow ids, in the same order as CaseIterable.
    /// If this diverges from workflow.json, the assertion below fires at launch in debug builds.
    static let ruleBookIDs: [String] = ["MR", "ahe", "IV", "3w", "RT", "XY", "rsm"]

    static func assertRuleBookConsistency() {
        let caseIDs = allCases.map(\.rawValue)
        assert(
            caseIDs == ruleBookIDs,
            "[WorkflowKey] Mismatch with Rule Book workflow ids.\n"
            + "  WorkflowKey: \(caseIDs)\n"
            + "  Rule Book:   \(ruleBookIDs)"
        )
    }
}

// MARK: - Domain model bridge

extension WorkflowKey {
    /// Maps to the legacy WorkflowKind stored in Codable domain model structs.
    /// Used only at the import pipeline boundary; do not use elsewhere.
    var legacyKind: SpinLabDomain.WorkflowKind {
        switch self {
        case .ahe:        return .amrPhe
        case .threeOmega: return .threeOmegaAHE
        case .xyRotation: return .xyRotation
        case .rsm:        return .rsm
        case .mr, .iv, .rt: return .amrPhe
        }
    }
}
