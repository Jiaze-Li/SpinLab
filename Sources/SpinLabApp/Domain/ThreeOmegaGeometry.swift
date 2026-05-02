import Foundation

struct ThreeOmegaGeometry: Codable, Hashable, Sendable {
    /// Channel length along current direction (μm)
    var lxx: Double = 0
    /// Channel length along Hall direction (μm)
    var lxy: Double = 0
    /// Film thickness (nm)
    var dNm: Double = 0

    var isComplete: Bool { lxx > 0 && lxy > 0 && dNm > 0 }
}
