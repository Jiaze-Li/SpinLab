import Foundation

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
    case reciprocalH
    case reciprocalK
    case reciprocalL
    case diffractionIntensity
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
            // AHE's harmonic-agnostic combined R_AHE (post ordinary-Hall background
            // correction) — same quantity family as rahe1omega/rahe3omega, distinct case
            // because AHE has no harmonic to tag. See AHE_LABEL_KEY_AUDIT.md.
            switch context {
            case .plotAxis:
                return #"math:R_{AHE} (Ω)"#
            case .manifestPlainText, .uiText:
                return "RAHE (Ω)"
            }
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
            // Temperature Dependence right-axis special-case convention (approved
            // 2026-07-03, implemented v5.5.6) — see PLOT_DISPLAY_SPEC.md §4. This quantity is
            // only ever consumed by the Temperature Dependence tab, distinct from Scaling Law's
            // σxx² (scalingLawX) below.
            return #"math:σ_{xx} × 10^{3} (S cm^{-1})"#
        case .scalingLawX:
            return #"math:σ_{xx}^{2} × 10^{7} (S^{2} cm^{-2})"#
        case .scalingLawY:
            // Future target label for the 3ω scaling-law plot remains distinct from
            // the temperature-dependence ratio label below.
            return #"math:E_{AHE}^{3ω} / (E_{xx}^{3}·σ_{xx}) × 10^{2} (Ω·μm^{3}·V^{-2})"#
        case .temperatureDependenceERatio:
            // Temperature Dependence left-axis special-case convention (approved
            // 2026-07-03, implemented v5.5.6) — see PLOT_DISPLAY_SPEC.md §4. Distinct from the
            // visually similar Scaling Law y-quantity (scalingLawY) above.
            return #"math:E_{AHE}^{3ω} / E_{xx}^{3} × 10^{2} (μm^{2} V^{-2})"#
        case .current:
            switch currentBasis ?? .peak {
            case .peak:
                return "Current (mA, peak)"
            case .rms:
                return "Current (mA, RMS)"
            }
        case .voltage:
            return "V (V)"
        case .reciprocalH:
            return "H (r.l.u.)"
        case .reciprocalK:
            return "K (r.l.u.)"
        case .reciprocalL:
            return "L (r.l.u.)"
        case .diffractionIntensity:
            return "Intensity (counts)"
        }
    }

    /// Label for text actually drawn on a rendered chart axis. Fixed to `.plotAxis` so
    /// callers never choose the wrong context — math-markup quantities (e.g. `.rxx`) come
    /// back with the `"math:"` prefix the chart renderer needs to draw subscripts.
    static func plotLabel(
        for quantity: WorkbenchPhysicalQuantity,
        currentBasis: WorkbenchCurrentBasis? = nil
    ) -> String {
        label(for: quantity, context: .plotAxis, currentBasis: currentBasis)
    }

    /// Label for manifest/run-trace/log/UI text — anything that is not drawn on a chart.
    /// Fixed to `.manifestPlainText` so persisted and logged text never picks up `"math:"`
    /// markup meant only for the chart renderer.
    static func plainTextLabel(
        for quantity: WorkbenchPhysicalQuantity,
        currentBasis: WorkbenchCurrentBasis? = nil
    ) -> String {
        label(for: quantity, context: .manifestPlainText, currentBasis: currentBasis)
    }

    /// `plotLabel(for:)` variant for the magnetic-field-unit-aware quantities.
    static func plotLabel(for quantity: WorkbenchPhysicalQuantity, unit: MagneticFieldUnit) -> String {
        magneticFieldLabel(for: quantity, context: .plotAxis, unit: unit)
    }

    /// `plainTextLabel(for:)` variant for the magnetic-field-unit-aware quantities.
    static func plainTextLabel(for quantity: WorkbenchPhysicalQuantity, unit: MagneticFieldUnit) -> String {
        magneticFieldLabel(for: quantity, context: .manifestPlainText, unit: unit)
    }

    /// Magnetic-field-unit-aware label for `.externalMagneticField` / `.coerciveField`.
    /// Kept separate from `label(for:context:)` because that function's output for these two
    /// quantities is also consumed by `AHEAxisDetector.displayXField` to feed chart-identity
    /// hashing (`WorkbenchArtifactIdentity`) — AHE's migration to this policy is a separate,
    /// not-yet-scheduled phase (see AHE_LABEL_KEY_AUDIT.md).
    static func magneticFieldLabel(
        for quantity: WorkbenchPhysicalQuantity,
        context: WorkbenchDisplayContext,
        unit: MagneticFieldUnit
    ) -> String {
        let symbol: String
        switch quantity {
        case .externalMagneticField:
            symbol = "μ₀H"
        case .coerciveField:
            symbol = "μ₀Hc"
        default:
            return label(for: quantity, context: context)
        }
        let unitText: String
        switch unit {
        case .oersted: unitText = "Oe"
        case .tesla: unitText = "T"
        case .millitesla: unitText = "mT"
        }
        return "\(symbol) (\(unitText))"
    }

    /// Formats a single temperature value (Kelvin) as a compact per-series legend label,
    /// e.g. "300 K" or "77.5 K". Distinct from `label(for: .temperature, ...)`, which
    /// produces the axis-level quantity+unit string ("Temperature (K)"), not a value.
    static func temperatureValueLabel(_ kelvin: Double) -> String {
        kelvin.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(kelvin)) K"
            : String(format: "%.1f K", kelvin)
    }
}
