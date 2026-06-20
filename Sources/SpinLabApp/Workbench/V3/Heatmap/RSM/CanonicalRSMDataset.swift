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

    private static let axisTolerance: Double = 1e-9

    /// Which RSMView is appropriate given which axes actually vary in the scan.
    /// If H is fixed → KL; if K is fixed → HL; if L is fixed → HK; else HL fallback.
    var recommendedView: RSMView {
        guard !points.isEmpty else { return .hl }
        let tol = Self.axisTolerance
        let h0 = points[0].h, k0 = points[0].k, l0 = points[0].l
        let hFixed = points.allSatisfy { abs($0.h - h0) <= tol }
        let kFixed = points.allSatisfy { abs($0.k - k0) <= tol }
        let lFixed = points.allSatisfy { abs($0.l - l0) <= tol }
        if hFixed { return .kl }
        if kFixed { return .hl }
        if lFixed { return .hk }
        return .hl
    }

    /// True if both axes that `view` needs to vary actually vary in the dataset.
    func isViewCompatible(_ view: RSMView) -> Bool {
        guard !points.isEmpty else { return true }
        let tol = Self.axisTolerance
        let h0 = points[0].h, k0 = points[0].k, l0 = points[0].l
        let hFixed = points.allSatisfy { abs($0.h - h0) <= tol }
        let kFixed = points.allSatisfy { abs($0.k - k0) <= tol }
        let lFixed = points.allSatisfy { abs($0.l - l0) <= tol }
        switch view {
        case .hl: return !hFixed && !lFixed
        case .kl: return !kFixed && !lFixed
        case .hk: return !hFixed && !kFixed
        }
    }
}
