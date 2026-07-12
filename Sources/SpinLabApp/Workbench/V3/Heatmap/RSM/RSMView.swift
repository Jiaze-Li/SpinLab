/// Which two reciprocal-space axes are mapped to the heatmap x/y plane.
/// The third axis is the "fixed" (out-of-plane) axis for a given scan.
enum RSMView: String, CaseIterable, Sendable {
    /// x = H, y = L  (K fixed)
    case hl
    /// x = K, y = L  (H fixed)
    case kl
    /// x = H, y = K  (L fixed)
    case hk

    var xLabel: String {
        switch self {
        case .hl, .hk: return WorkbenchPlotDisplayVocabulary.plotLabel(for: .reciprocalH)
        case .kl:       return WorkbenchPlotDisplayVocabulary.plotLabel(for: .reciprocalK)
        }
    }

    var yLabel: String {
        switch self {
        case .hl, .kl: return WorkbenchPlotDisplayVocabulary.plotLabel(for: .reciprocalL)
        case .hk:      return WorkbenchPlotDisplayVocabulary.plotLabel(for: .reciprocalK)
        }
    }

    func xValue(of point: CanonicalRSMPoint) -> Double {
        switch self {
        case .hl, .hk: return point.h
        case .kl:      return point.k
        }
    }

    func yValue(of point: CanonicalRSMPoint) -> Double {
        switch self {
        case .hl, .kl: return point.l
        case .hk:      return point.k
        }
    }
}
