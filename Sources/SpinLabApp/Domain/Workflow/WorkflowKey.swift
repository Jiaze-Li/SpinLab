import Foundation

/// Typed application-capability identifier for workflows with concrete Workbench/dispatch support.
/// Raw values match the corresponding `id` fields in `workflow.json`, but this enum is not the
/// canonical list of Rule Book workflow membership — `workflow.json` is. A Rule Book workflow
/// with no case here is a valid, unimplemented workflow and must be handled safely, not crash.
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
