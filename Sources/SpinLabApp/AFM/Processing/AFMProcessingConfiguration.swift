import Foundation

/// Line Flatten polynomial order applied independently to each fast-scan row.
enum AFMLineFlattenOrder: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
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
enum AFMZeroReference: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case none
    case mean
    case minimum
}

/// User-controlled AFM processing state. Defaults are all "off" — source metadata reporting a
/// prior instrument-side Planefit/Flatten must never auto-enable these (see
/// `AFMChannelProvenance` / `AFMDatasetContract.md`).
struct AFMProcessingConfiguration: Sendable, Equatable, Hashable, Codable {
    var activeChannelID: String
    var planeLevelEnabled: Bool = false
    var lineFlattenOrder: AFMLineFlattenOrder = .off
    var zeroReference: AFMZeroReference = .none

    init(
        activeChannelID: String,
        planeLevelEnabled: Bool = false,
        lineFlattenOrder: AFMLineFlattenOrder = .off,
        zeroReference: AFMZeroReference = .none
    ) {
        self.activeChannelID = activeChannelID
        self.planeLevelEnabled = planeLevelEnabled
        self.lineFlattenOrder = lineFlattenOrder
        self.zeroReference = zeroReference
    }

    /// Old/missing fields (e.g. a pack saved before a later AFM processing option existed)
    /// decode to the V1 "off" defaults rather than failing to decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeChannelID = try c.decodeIfPresent(String.self, forKey: .activeChannelID) ?? ""
        planeLevelEnabled = try c.decodeIfPresent(Bool.self, forKey: .planeLevelEnabled) ?? false
        lineFlattenOrder = try c.decodeIfPresent(AFMLineFlattenOrder.self, forKey: .lineFlattenOrder) ?? .off
        zeroReference = try c.decodeIfPresent(AFMZeroReference.self, forKey: .zeroReference) ?? .none
    }
}
