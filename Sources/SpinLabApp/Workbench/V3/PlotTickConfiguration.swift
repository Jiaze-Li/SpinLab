import Foundation

/// Shared X/Y axis tick count configuration used by all plot render paths.
///
/// Provides a single source of truth for default, valid range, and clamping
/// across both the Heatmap and Cartesian XY render paths.
/// Must not import or depend on RSM, Heatmap, or XY series data.
struct PlotTickConfiguration: Codable, Hashable, Sendable {
    var xTargetCount: Int
    var yTargetCount: Int

    static let defaultValue = PlotTickConfiguration(xTargetCount: 5, yTargetCount: 5)
    static let validRange = 2...20

    init(xTargetCount: Int = 5, yTargetCount: Int = 5) {
        self.xTargetCount = Self.clamp(xTargetCount)
        self.yTargetCount = Self.clamp(yTargetCount)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xTargetCount = Self.clamp(try c.decodeIfPresent(Int.self, forKey: .xTargetCount) ?? Self.defaultValue.xTargetCount)
        yTargetCount = Self.clamp(try c.decodeIfPresent(Int.self, forKey: .yTargetCount) ?? Self.defaultValue.yTargetCount)
    }

    private enum CodingKeys: String, CodingKey {
        case xTargetCount
        case yTargetCount
    }

    static func clamp(_ value: Int) -> Int {
        max(validRange.lowerBound, min(validRange.upperBound, value))
    }
}
