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

/// Global surface-leveling method applied before Line Flatten. V1 offers Off / Plane / Robust Plane;
/// the enum shape lets later methods be added without changing the saved format.
enum AFMSurfaceLevel: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case off
    case plane
    /// Huber-weighted plane fit that down-weights tall features (particles) in the background.
    case robustPlane
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
    var surfaceLevel: AFMSurfaceLevel = .off
    var lineFlattenOrder: AFMLineFlattenOrder = .off
    var zeroReference: AFMZeroReference = .none

    init(
        activeChannelID: String,
        surfaceLevel: AFMSurfaceLevel = .off,
        lineFlattenOrder: AFMLineFlattenOrder = .off,
        zeroReference: AFMZeroReference = .none
    ) {
        self.activeChannelID = activeChannelID
        self.surfaceLevel = surfaceLevel
        self.lineFlattenOrder = lineFlattenOrder
        self.zeroReference = zeroReference
    }

    /// Old/missing fields (e.g. a pack saved before a later AFM processing option existed)
    /// decode to the V1 "off" defaults rather than failing to decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeChannelID = try c.decodeIfPresent(String.self, forKey: .activeChannelID) ?? ""
        if let level = try c.decodeIfPresent(AFMSurfaceLevel.self, forKey: .surfaceLevel) {
            surfaceLevel = level
        } else if try c.decodeIfPresent(Bool.self, forKey: .planeLevelEnabled) == true {
            // Legacy configs stored Plane Level as a boolean.
            surfaceLevel = .plane
        } else {
            surfaceLevel = .off
        }
        lineFlattenOrder = try c.decodeIfPresent(AFMLineFlattenOrder.self, forKey: .lineFlattenOrder) ?? .off
        zeroReference = try c.decodeIfPresent(AFMZeroReference.self, forKey: .zeroReference) ?? .none
    }

    private enum CodingKeys: String, CodingKey {
        case activeChannelID
        case surfaceLevel
        case planeLevelEnabled   // legacy key — decoded only, not encoded
        case lineFlattenOrder
        case zeroReference
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(activeChannelID, forKey: .activeChannelID)
        try c.encode(surfaceLevel, forKey: .surfaceLevel)
        try c.encode(lineFlattenOrder, forKey: .lineFlattenOrder)
        try c.encode(zeroReference, forKey: .zeroReference)
    }
}
