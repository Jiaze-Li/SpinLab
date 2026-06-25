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
