import Foundation

enum ThreeOmegaWorkbenchTab: String, CaseIterable, Identifiable {
    case ahe                 = "AHE"
    case fieldSweep1omega    = "AHE (1ω)"
    case fieldSweep3omega    = "AHE (3ω)"
    case rahe1omegaVsT       = "RAHE (1ω)"
    case rahe3omegaVsT       = "RAHE (3ω)"
    case rahe1omegaVsDevice  = "RAHE(1ω) Dev"
    case rahe3omegaVsDevice  = "RAHE(3ω) Dev"
    case hcVsT               = "Hc"
    case rtCurve             = "RT"
    case scaling             = "Scaling Law"
    case temperatureDependence = "Temperature Dependence"

    var id: String { rawValue }

    /// Stable identity key for persistence. Hand-written, never derived via reflection.
    var stableKey: String {
        switch self {
        case .ahe:                return "ahe"
        case .fieldSweep1omega:   return "fieldSweep1omega"
        case .fieldSweep3omega:   return "fieldSweep3omega"
        case .rahe1omegaVsT:      return "rahe1omegaVsT"
        case .rahe3omegaVsT:      return "rahe3omegaVsT"
        case .rahe1omegaVsDevice: return "rahe1omegaVsDevice"
        case .rahe3omegaVsDevice: return "rahe3omegaVsDevice"
        case .hcVsT:              return "hcVsT"
        case .rtCurve:            return "rtCurve"
        case .scaling:            return "scaling"
        case .temperatureDependence: return "temperatureDependence"
        }
    }

    /// Index in `allCases` order, used for sort rank.
    static let stableKeyRank: [String: Int] = {
        Dictionary(uniqueKeysWithValues: allCases.enumerated().map { ($1.stableKey, $0) })
    }()
}
