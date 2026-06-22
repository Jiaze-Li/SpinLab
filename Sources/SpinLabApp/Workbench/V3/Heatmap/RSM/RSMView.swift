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
        case .hl, .hk: return "H (r.l.u.)"
        case .kl:       return "K (r.l.u.)"
        }
    }

    var yLabel: String {
        switch self {
        case .hl, .kl: return "L (r.l.u.)"
        case .hk:      return "K (r.l.u.)"
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
