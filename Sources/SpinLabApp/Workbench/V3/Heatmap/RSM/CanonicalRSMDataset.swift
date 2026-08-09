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

    // MARK: - View compatibility
    //
    // Derived interpretation, not raw-loading facts — the real logic lives in
    // RSMViewClassifier (Phase 3i RSM migration); these remain as compatibility wrappers so
    // existing call sites (`dataset.recommendedView`, `dataset.isViewCompatible(_:)`) are
    // unchanged.

    var recommendedView: RSMView {
        RSMViewClassifier.recommendedView(for: self)
    }

    func isViewCompatible(_ view: RSMView) -> Bool {
        RSMViewClassifier.isViewCompatible(view, for: self)
    }
}
