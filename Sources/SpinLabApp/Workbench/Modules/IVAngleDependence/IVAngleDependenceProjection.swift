import Foundation

// MARK: - IVAngleDependenceProjection
//
// IV-owned glue between the workflow-agnostic IVAngleDependence module and the
// Plot System's WorkbenchPlotSeries/axis-label contracts. Mirrors the role
// IVPowerLawFitAdapter plays for the V-vs-I^n view — this file owns angle-view
// units/labels/series mapping; it does not modify IVPowerLawFitAdapter.
//
// Legend labels reuse the Plot System's existing "math:" prefix convention
// (see MathMarkupRenderer) — the canvas legend already renders any
// WorkbenchPlotSeries.label starting with "math:" through the same markup
// parser used for axis labels, so no Plot System change is needed here.

enum IVAngleDependenceProjection {

    /// Angular plot is a single scatter series: one point per valid sweep, x = angle (deg).
    static func makeSeries(from result: IVAngleDependenceResult, legendLabel: String) -> WorkbenchPlotSeries {
        WorkbenchPlotSeries(
            label: legendLabel,
            x: result.points.map(\.angleDeg),
            y: result.points.map(\.slope),
            renderMode: .scatter,
            renderModeLocked: true,
            pointLabels: result.points.map(\.label)
        )
    }

    /// X axis is the shared device-angle vocabulary entry — do not fork a local copy.
    static func xAxisLabel(context: WorkbenchDisplayContext) -> String {
        WorkbenchPlotDisplayVocabulary.label(for: .deviceAngle, context: context)
    }

    /// a_n = V^{nω}/(I^ω)^n. Y axis unit: mV/mA, mV/(mA)^2, mV/(mA)^3 for n = 1, 2, 3.
    static func yAxisLabel(
        mode: PowerLawFitMode,
        component: IVSignalComponent,
        context: WorkbenchDisplayContext
    ) -> String {
        guard let fraction = _fraction(mode: mode, component: component) else { return "" }
        let unit = fraction.order == 1 ? "mV/mA" : "mV/(mA)^{\(fraction.order)}"
        switch context {
        case .plotAxis:
            return "math:\(fraction.numerator)/\(fraction.denominator) (\(unit))"
        case .manifestPlainText, .uiText:
            return "V(\(fraction.order)ω)/I^\(fraction.order) (\(unit))"
        }
    }

    /// Series legend label for the a_n(Ψ) point series. Reuses the same
    /// numerator/denominator construction as `yAxisLabel` (no unit), through the
    /// existing "math:" legend path — falls back to the generic "a_n(Ψ)" name when
    /// no fit order is available (Angular Plot is normally gated on Fit != .none).
    static func legendLabel(
        mode: PowerLawFitMode,
        component: IVSignalComponent,
        context: WorkbenchDisplayContext
    ) -> String {
        guard let fraction = _fraction(mode: mode, component: component) else {
            switch context {
            case .plotAxis: return "math:a_{n}(Ψ)"
            case .manifestPlainText, .uiText: return "a_n(Ψ)"
            }
        }
        switch context {
        case .plotAxis:
            return "math:\(fraction.numerator)/\(fraction.denominator)"
        case .manifestPlainText, .uiText:
            return "V(\(fraction.order)ω)/I^\(fraction.order)"
        }
    }

    /// Plain-text tab-title suffix (not legend/axis text — titles are never math-rendered).
    static let titleSuffix = "a_n(Ψ)"

    // MARK: - Private

    private struct Fraction {
        var numerator: String
        var denominator: String
        var order: Int
    }

    /// Shared numerator/denominator construction — the single source of truth for both
    /// `yAxisLabel` and `legendLabel` so the two never drift apart.
    private static func _fraction(mode: PowerLawFitMode, component: IVSignalComponent) -> Fraction? {
        guard let exponent = mode.exponent else { return nil }
        let order = Int(exponent)
        let componentTag = component.rawValue.lowercased()
        let numerator = order == 1 ? "V_{\(componentTag)}^{ω}" : "V_{\(componentTag)}^{\(order)ω}"
        let denominator = order == 1 ? "I_x^{ω}" : "(I_x^{ω})^{\(order)}"
        return Fraction(numerator: numerator, denominator: denominator, order: order)
    }
}
