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
        case .hl, .hk: return WorkbenchPlotDisplayVocabulary.label(for: .reciprocalH, context: .plotAxis)
        case .kl:       return WorkbenchPlotDisplayVocabulary.label(for: .reciprocalK, context: .plotAxis)
        }
    }

    var yLabel: String {
        switch self {
        case .hl, .kl: return WorkbenchPlotDisplayVocabulary.label(for: .reciprocalL, context: .plotAxis)
        case .hk:      return WorkbenchPlotDisplayVocabulary.label(for: .reciprocalK, context: .plotAxis)
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
