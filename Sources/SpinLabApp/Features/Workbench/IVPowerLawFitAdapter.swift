import Foundation

// MARK: - IVPowerLawFitAdapter
//
// IV-owned glue between the generic PowerLawFit module and the Plot System's
// WorkbenchPlotSeriesOverlay contract. PowerLawFit stays unit- and workflow-agnostic
// (raw Doubles in, raw Doubles out); Plot System stays physics-free (draws whatever
// series/overlay it is given). All IV domain knowledge — channel selection, Peak/RMS
// + A→mA/V→mV conversion, transforming the measurement curve to match the selected
// fit order, and IV harmonic axis/legend labels — lives here.
//
// Fit modes (None/1ω/2ω/3ω) select the power of current the measurement is plotted
// and fit against: X = I^n (mA^n), Y = V (mV). Both the measurement curve and the fit
// overlay share that same transformed X so they draw in the same coordinate space.
// "Zero at I=0" fits y = a·X + b once, then subtracts that same fitted intercept b from
// both the measurement points and the fit line — it does not re-fit a constrained line.

enum IVPowerLawFitAdapter {

    /// One base series, transformed into the currently selected fit order's coordinate
    /// space, plus the (optional) fit line to project into an overlay.
    struct SeriesProjection {
        var currentTransformed: [Double]
        var voltageMV: [Double]
        var fitLineX: [Double]?
        var fitLineY: [Double]?
        var overlayLabel: String?
    }

    /// - Parameters:
    ///   - currentMA: current already Peak/RMS-scaled to mA (A→mA + basis conversion is
    ///     the caller's existing responsibility; this adapter only raises it to the
    ///     fit order's power).
    ///   - voltageV: raw selected-channel voltage in V, unshifted by any display stack offset.
    static func project(
        currentMA: [Double],
        voltageV: [Double],
        fitMode: PowerLawFitMode,
        zeroAtCurrentOrigin: Bool,
        component: IVSignalComponent
    ) -> SeriesProjection {
        let exponent = fitMode.exponent ?? 1
        let currentTransformed = currentMA.map { pow($0, exponent) }
        let voltageMV = voltageV.map { $0 * 1000.0 }

        guard fitMode != .none else {
            return SeriesProjection(
                currentTransformed: currentTransformed,
                voltageMV: voltageMV,
                fitLineX: nil,
                fitLineY: nil,
                overlayLabel: nil
            )
        }

        let points = zip(currentMA, voltageMV).map { PowerLawFitPoint(x: $0, y: $1) }
        let result = PowerLawFitUseCase().execute(
            input: PowerLawFitInput(points: points),
            // subtractIntercept stays false: the module always returns the real fitted
            // intercept in `result.intercept`. Zeroing is applied below, uniformly to
            // both the measurement points and the fit line.
            configuration: PowerLawFitConfiguration(mode: fitMode, subtractIntercept: false)
        )
        guard result.isSuccessful, let fitLine = result.fitLine else {
            return SeriesProjection(
                currentTransformed: currentTransformed,
                voltageMV: voltageMV,
                fitLineX: nil,
                fitLineY: nil,
                overlayLabel: nil
            )
        }

        let interceptShift = zeroAtCurrentOrigin ? (result.intercept ?? 0) : 0
        let adjustedVoltageMV = voltageMV.map { $0 - interceptShift }
        // fitLine.x is sampled in raw (untransformed) current — raise it the same way
        // the measurement's X was raised so both share one coordinate space.
        let fitLineXTransformed = fitLine.x.map { pow($0, exponent) }
        let fitLineYAdjusted = fitLine.y.map { $0 - interceptShift }

        return SeriesProjection(
            currentTransformed: currentTransformed,
            voltageMV: adjustedVoltageMV,
            fitLineX: fitLineXTransformed,
            fitLineY: fitLineYAdjusted,
            overlayLabel: fitLabel(component: component, mode: fitMode)
        )
    }

    /// Projects one series' fit line into a display-anchored overlay. Returns nil when
    /// the projection carries no fit line (fit mode `.none` or a failed fit).
    static func makeOverlay(
        identityKey: String,
        projection: SeriesProjection,
        displayOffset: Double
    ) -> WorkbenchPlotSeriesOverlay? {
        guard let x = projection.fitLineX, let y = projection.fitLineY, let label = projection.overlayLabel else {
            return nil
        }
        let overlaySeries = WorkbenchPlotSeries(
            label: label,
            x: x,
            y: y.map { $0 + displayOffset },
            renderMode: .line,
            renderModeLocked: true,
            lineWidth: 1.5
        )
        return WorkbenchPlotSeriesOverlay(
            overlayIdentityKey: "\(identityKey)#powerLawFit",
            parentSeriesIdentityKey: identityKey,
            series: overlaySeries
        )
    }

    /// Human-readable picker text for a fit mode — IV's own vocabulary, not PowerLawFit's.
    static func fitModeDisplayName(_ mode: PowerLawFitMode) -> String {
        switch mode {
        case .none: return "None"
        case .one: return "1ω"
        case .two: return "2ω"
        case .three: return "3ω"
        }
    }

    // MARK: - Axis labels (IV-owned; Plot System stays physics-free)

    /// X-axis label for the currently selected fit order. `.none` keeps the existing
    /// current-basis vocabulary text (X is still plain current in mA); 1ω/2ω/3ω switch
    /// to the transformed-current text since the axis itself now plots I^n.
    static func xAxisLabel(
        mode: PowerLawFitMode,
        basis: IVCurrentBasis,
        context: WorkbenchDisplayContext
    ) -> String {
        guard let exponent = mode.exponent else {
            return WorkbenchPlotDisplayVocabulary.label(
                for: .current,
                context: context,
                currentBasis: basis.workbenchCurrentBasis
            )
        }
        let order = Int(exponent)
        switch context {
        case .plotAxis:
            return order == 1 ? "math:I (mA)" : "math:I^{\(order)} (mA^{\(order)})"
        case .manifestPlainText, .uiText:
            return order == 1 ? "I (mA)" : "I^\(order) (mA^\(order))"
        }
    }

    /// Y-axis label. Voltage is always displayed in mV once this adapter owns the axis,
    /// regardless of fit mode. Fit modes tag the label with the selected channel
    /// component and harmonic order; `.none` stays untagged.
    static func yAxisLabel(
        mode: PowerLawFitMode,
        component: IVSignalComponent,
        context: WorkbenchDisplayContext
    ) -> String {
        guard let exponent = mode.exponent else {
            return "V (mV)"
        }
        let order = Int(exponent)
        let componentTag = component.rawValue.lowercased()
        switch context {
        case .plotAxis:
            return "math:V_{\(componentTag)}^{\(order)ω} (mV)"
        case .manifestPlainText, .uiText:
            return "V(\(order)ω) (mV)"
        }
    }

    // MARK: - Private

    private static func fitLabel(component: IVSignalComponent, mode: PowerLawFitMode) -> String {
        guard let exponent = mode.exponent else { return "" }
        let order = Int(exponent)
        let componentTag = component.rawValue.lowercased()
        return "math:V_{\(componentTag)}^{\(order)ω} fit"
    }
}
