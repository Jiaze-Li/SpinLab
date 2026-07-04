enum WorkbenchDisplayContext: Hashable, Sendable {
    case plotAxis
    case manifestPlainText
    case uiText
}

enum WorkbenchPhysicalQuantity: Hashable, Sendable, CaseIterable {
    case externalMagneticField
    case coerciveField
    case temperature
    case deviceAngle
    case angleOffset
    case resistance1omega
    case resistance3omega
    case rahe1omega
    case rahe3omega
    case raheCombined
    case rxx
    case rxy
    case hallResistance
    case sigmaXX
    case scalingLawX
    case scalingLawY
    case temperatureDependenceERatio
    case current
    case voltage
}

enum WorkbenchCurrentBasis: Hashable, Sendable {
    case peak
    case rms
}

enum WorkbenchPlotDisplayVocabulary {
    static func label(
        for quantity: WorkbenchPhysicalQuantity,
        context: WorkbenchDisplayContext,
        currentBasis: WorkbenchCurrentBasis? = nil
    ) -> String {
        switch quantity {
        case .externalMagneticField:
            // Future target label: "μ₀H (T/mT)"
            return "H (T)"
        case .coerciveField:
            // Future target label: "μ₀Hc (T/mT)"
            switch context {
            case .plotAxis:
                return #"math:H_{c} (Oe)"#
            case .manifestPlainText, .uiText:
                return "Hc (Oe)"
            }
        case .temperature:
            return "Temperature (K)"
        case .deviceAngle:
            return "Ψ (deg)"
        case .angleOffset:
            // Future target label: "Angle offset (deg)"
            return "φ (deg)"
        case .resistance1omega:
            switch context {
            case .plotAxis:
                return #"math:R^{1ω} (Ω)"#
            case .manifestPlainText, .uiText:
                return "R(1ω) (Ω)"
            }
        case .resistance3omega:
            switch context {
            case .plotAxis:
                return #"math:R^{3ω} (Ω)"#
            case .manifestPlainText, .uiText:
                return "R(3ω) (Ω)"
            }
        case .rahe1omega:
            switch context {
            case .plotAxis:
                return #"math:R_{AHE}^{1ω} (Ω)"#
            case .manifestPlainText, .uiText:
                return "RAHE(1ω) (Ω)"
            }
        case .rahe3omega:
            switch context {
            case .plotAxis:
                return #"math:R_{AHE}^{3ω} (Ω)"#
            case .manifestPlainText, .uiText:
                return "RAHE(3ω) (Ω)"
            }
        case .raheCombined:
            return #"math:R_{AHE} (Ω)"#
        case .rxx:
            switch context {
            case .plotAxis:
                return #"math:R_{xx} (Ω)"#
            case .manifestPlainText, .uiText:
                return "Rxx (Ω)"
            }
        case .rxy:
            return "Rxy (Ω)"
        case .hallResistance:
            return "R_H (Ω)"
        case .sigmaXX:
            return #"math:σ_{xx} (S/m)"#
        case .scalingLawX:
            return #"math:σ_{xx}^{2} × 10^{7} (S^{2} cm^{-2})"#
        case .scalingLawY:
            // Future target label for the 3ω scaling-law plot remains distinct from
            // the temperature-dependence ratio label below.
            return #"math:E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})"#
        case .temperatureDependenceERatio:
            // Future target label: 3ω temperature dependence specific label.
            return #"math:E_{AHE}^{3ω} / E_{xx}^{3}"#
        case .current:
            switch currentBasis ?? .peak {
            case .peak:
                return "Current (mA, peak)"
            case .rms:
                return "Current (mA, RMS)"
            }
        case .voltage:
            return "V (V)"
        }
    }
}
