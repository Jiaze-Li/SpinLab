import Foundation

// MARK: - XY Rotation Data Contracts

/// Source file format for XY Rotation measurements.
enum XYRotationFileKind: String, Codable, Hashable, Sendable {
    case lvm
    case dat
}

/// One angle-sweep at a given temperature.
struct XYRotationAngleSweep: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(stem)_\(String(format: "%.1f", temperatureK))K" }

    var temperatureK: Double
    var stem: String
    var sourceKind: XYRotationFileKind
    var angleDeg: [Double]
    var resistance: [Double]
    var resistanceXY: [Double]?
    var defaultPhiOffset: Double
}

/// Aggregated result from ingesting multiple XY Rotation files.
struct XYRotationIngestionResult: Codable, Hashable, Sendable {
    var sweeps: [XYRotationAngleSweep] = []
    var warnings: [String] = []
}

/// Tab identifiers for the XY Rotation workbench.
enum XYRotationWorkbenchTab: String, CaseIterable, Hashable, Identifiable {
    case rVsPhi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rVsPhi: return "R vs φ"
        }
    }
}
