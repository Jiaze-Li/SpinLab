import Foundation

/// RSM workflow interpretation of which `RSMView` a dataset supports, per the Phase 3i RSM
/// migration audit: which axes are fixed vs. varying is derived interpretation of raw H/K/L
/// values, not a raw-loading fact, so it does not belong on `CanonicalRSMDataset` itself.
/// `CanonicalRSMDataset.recommendedView`/`isViewCompatible(_:)` remain as thin compatibility
/// wrappers delegating here — this is the single implementation.
enum RSMViewClassifier {

    private static let axisTolerance: Double = 1e-9

    /// Which RSMView is appropriate given which axes actually vary in the scan.
    /// If H is fixed → KL; if K is fixed → HL; if L is fixed → HK; else HL fallback.
    static func recommendedView(for dataset: CanonicalRSMDataset) -> RSMView {
        guard !dataset.points.isEmpty else { return .hl }
        let (hFixed, kFixed, lFixed) = fixedAxes(of: dataset)
        if hFixed { return .kl }
        if kFixed { return .hl }
        if lFixed { return .hk }
        return .hl
    }

    /// True if both axes that `view` needs to vary actually vary in the dataset.
    static func isViewCompatible(_ view: RSMView, for dataset: CanonicalRSMDataset) -> Bool {
        guard !dataset.points.isEmpty else { return true }
        let (hFixed, kFixed, lFixed) = fixedAxes(of: dataset)
        switch view {
        case .hl: return !hFixed && !lFixed
        case .kl: return !kFixed && !lFixed
        case .hk: return !hFixed && !kFixed
        }
    }

    private static func fixedAxes(of dataset: CanonicalRSMDataset) -> (h: Bool, k: Bool, l: Bool) {
        let points = dataset.points
        let tol = axisTolerance
        let h0 = points[0].h, k0 = points[0].k, l0 = points[0].l
        let hFixed = points.allSatisfy { abs($0.h - h0) <= tol }
        let kFixed = points.allSatisfy { abs($0.k - k0) <= tol }
        let lFixed = points.allSatisfy { abs($0.l - l0) <= tol }
        return (hFixed, kFixed, lFixed)
    }
}
