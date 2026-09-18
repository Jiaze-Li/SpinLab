import Foundation

/// Line Flatten polynomial order applied independently to each fast-scan row.
enum AFMLineFlattenOrder: String, Sendable, Equatable, Codable, CaseIterable {
    case off
    case order0
    case order1
    case order2

    /// Polynomial degree to fit, or nil when `.off` (no row operation).
    var polynomialDegree: Int? {
        switch self {
        case .off: return nil
        case .order0: return 0
        case .order1: return 1
        case .order2: return 2
        }
    }
}

/// Post-leveling/flattening zero-reference policy.
enum AFMZeroReference: String, Sendable, Equatable, Codable, CaseIterable {
    case none
    case mean
    case minimum
}

/// User-controlled AFM processing state. Defaults are all "off" — source metadata reporting a
/// prior instrument-side Planefit/Flatten must never auto-enable these (see
/// `AFMChannelProvenance` / `AFMDatasetContract.md`).
struct AFMProcessingConfiguration: Sendable, Equatable, Codable {
    var activeChannelID: String
    var planeLevelEnabled: Bool = false
    var lineFlattenOrder: AFMLineFlattenOrder = .off
    var zeroReference: AFMZeroReference = .none
}
