import Foundation

enum ThreeOmegaWorkbenchTab: String, CaseIterable, Identifiable {
    case rahe                = "RAHE"
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

    /// Tabs shown in the visible 3ω workspace picker.
    /// Legacy RAHE-vs-T tabs stay addressable for restore compatibility, but are hidden from UI.
    static var visibleTabs: [ThreeOmegaWorkbenchTab] {
        [
            .rahe,
            .fieldSweep1omega,
            .fieldSweep3omega,
            .rahe1omegaVsDevice,
            .rahe3omegaVsDevice,
            .hcVsT,
            .rtCurve,
            .scaling,
            .temperatureDependence
        ]
    }

    /// Stable identity key for persistence. Hand-written, never derived via reflection.
    var stableKey: String {
        switch self {
        case .rahe:               return "rahe"
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

    /// Resolves a persisted stable key to a current tab.
    ///
    /// `includeLegacyAliases` migrates hidden legacy RAHE-vs-T keys onto `.rahe`
    /// for active-tab restore. Tab-state restore can opt out to avoid merging old
    /// display overrides into the combined RAHE tab.
    static func tab(forStableKey key: String, includeLegacyAliases: Bool = false) -> ThreeOmegaWorkbenchTab? {
        if includeLegacyAliases {
            switch key {
            case "ahe", "rahe1omegaVsT", "rahe3omegaVsT":
                return .rahe
            default:
                break
            }
        }
        if let tab = allCases.first(where: { $0.stableKey == key }) {
            return tab
        }
        return nil
    }

    /// Index in `allCases` order, used for sort rank.
    static let stableKeyRank: [String: Int] = {
        Dictionary(uniqueKeysWithValues: allCases.enumerated().map { ($1.stableKey, $0) })
    }()
}
