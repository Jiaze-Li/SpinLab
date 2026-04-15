import Foundation

// MARK: - XY Rotation Data Contracts

/// Source file format for XY Rotation measurements.
enum XYRotationFileKind: String, Codable, Hashable, Sendable {
    case lvm
    case dat
}

/// One angle-sweep at a given temperature.
struct XYRotationAngleSweep: Codable, Hashable, Sendable, Identifiable {
    var id: String {
        let pathHash = measurementFilePath.isEmpty ? stem : String(measurementFilePath.hashValue)
        return "\(pathHash)_\(String(format: "%.1f", temperatureK))K"
    }

    var temperatureK: Double
    var stem: String
    var sourceKind: XYRotationFileKind
    var angleDeg: [Double]
    var resistanceXX: [Double]
    var resistanceXY: [Double]?
    var defaultPhiOffset: Double
    var measurementFilePath: String = ""

    /// Sample metadata carried from search hit for legend resolution (v5.3.4).
    var sampleMetadata: [String: String] = [:]
}

/// Aggregated result from ingesting multiple XY Rotation files.
struct XYRotationIngestionResult: Codable, Hashable, Sendable {
    var sweeps: [XYRotationAngleSweep] = []
    var device: String = ""
    var warnings: [String] = []
}

/// Tab identifiers for the XY Rotation workbench.
enum XYRotationWorkbenchTab: String, CaseIterable, Hashable, Identifiable {
    case rxxVsPhi
    case rxyVsPhi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rxxVsPhi: return "Rxx vs φ"
        case .rxyVsPhi: return "Rxy vs φ"
        }
    }
}
