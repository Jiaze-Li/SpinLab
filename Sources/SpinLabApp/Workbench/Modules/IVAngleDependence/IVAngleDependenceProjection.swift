import Foundation

// MARK: - IVAngleDependenceProjection
//
// IV-owned glue between the workflow-agnostic IVAngleDependence module and the
// Plot System's WorkbenchPlotSeries/axis-label contracts. Mirrors the role
// IVPowerLawFitAdapter plays for the V-vs-I^n view — this file owns angle-view
// units/labels/series mapping; it does not modify IVPowerLawFitAdapter.

enum IVAngleDependenceProjection {

    /// Angular plot is a single scatter series: one point per valid sweep, x = angle (deg).
    static func makeSeries(from result: IVAngleDependenceResult, label: String) -> WorkbenchPlotSeries {
        WorkbenchPlotSeries(
            label: label,
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
        guard let exponent = mode.exponent else { return "" }
        let order = Int(exponent)
        let componentTag = component.rawValue.lowercased()
        let numerator = order == 1 ? "V_{\(componentTag)}^{ω}" : "V_{\(componentTag)}^{\(order)ω}"
        let denominator = order == 1 ? "I_x^{ω}" : "(I_x^{ω})^{\(order)}"
        let unit = order == 1 ? "mV/mA" : "mV/(mA)^{\(order)}"
        switch context {
        case .plotAxis:
            return "math:\(numerator)/\(denominator) (\(unit))"
        case .manifestPlainText, .uiText:
            return "V(\(order)ω)/I^\(order) (\(unit))"
        }
    }

    static let titleSuffix = "a_n(Ψ)"
}
