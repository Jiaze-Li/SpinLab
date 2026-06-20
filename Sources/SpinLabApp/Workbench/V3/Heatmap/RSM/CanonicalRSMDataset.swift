import Foundation

/// One point in reciprocal space from an RSM scan.
struct CanonicalRSMPoint: Sendable, Equatable {
    let h: Double
    let k: Double
    let l: Double
    /// Diffraction intensity (Detector counts, Intensity, etc.).
    let detector: Double
}

/// Parsed RSM dataset: a flat list of reciprocal-space points with associated intensity.
/// No grid structure is assumed here; HeatmapPlotPayload grid is built by RSMHeatmapPayloadBuilder.
struct CanonicalRSMDataset: Sendable {
    let points: [CanonicalRSMPoint]
    let title: String
    let sourceRef: String
    /// Column name used for the intensity value (e.g. "Detector", "Intensity").
    let detectorColumnName: String
}
