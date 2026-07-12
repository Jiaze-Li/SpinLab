import Foundation

// MARK: - IVPowerLawFitAdapter
//
// IV-owned glue between the generic PowerLawFit module and the Plot System's
// WorkbenchPlotSeriesOverlay contract. PowerLawFit stays unit- and workflow-agnostic
// (raw Doubles in, raw Doubles out); Plot System stays physics-free (draws whatever
// overlay series it is given). All IV domain knowledge — which channel/component feeds
// the fit, Peak/RMS + A→mA/V→mV conversion, and IV harmonic label text — lives here.

enum IVPowerLawFitAdapter {

    /// One base series' fit input, already channel-selected by the caller and expressed
    /// in the same physical units as the base plot (current already Peak/RMS-scaled to
    /// mA; voltage raw in V, unshifted by any display stack offset).
    struct SeriesInput {
        var identityKey: String
        var currentMA: [Double]
        var voltageV: [Double]
    }

    /// Builds one fit overlay per series input, anchored to its parent series identity.
    /// - Parameters:
    ///   - displayOffsetsByIdentityKey: additive y-shift already applied to the parent
    ///     series for display (stacking). Pass an empty dictionary to project unshifted
    ///     (manifest) overlays.
    static func makeOverlays(
        for inputs: [SeriesInput],
        fitMode: PowerLawFitMode,
        zeroAtCurrentOrigin: Bool,
        component: IVSignalComponent,
        displayOffsetsByIdentityKey: [String: Double] = [:]
    ) -> [WorkbenchPlotSeriesOverlay] {
        guard fitMode != .none else { return [] }
        let configuration = PowerLawFitConfiguration(
            mode: fitMode,
            subtractIntercept: zeroAtCurrentOrigin
        )
        let label = fitLabel(component: component, mode: fitMode)
        return inputs.compactMap { seriesInput in
            makeOverlay(
                seriesInput: seriesInput,
                configuration: configuration,
                displayOffset: displayOffsetsByIdentityKey[seriesInput.identityKey] ?? 0,
                label: label
            )
        }
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

    // MARK: - Private

    private static func makeOverlay(
        seriesInput: SeriesInput,
        configuration: PowerLawFitConfiguration,
        displayOffset: Double,
        label: String
    ) -> WorkbenchPlotSeriesOverlay? {
        guard seriesInput.currentMA.count == seriesInput.voltageV.count else { return nil }
        let voltageMV = seriesInput.voltageV.map { $0 * 1000.0 }
        let points = zip(seriesInput.currentMA, voltageMV).map { PowerLawFitPoint(x: $0, y: $1) }
        let result = PowerLawFitUseCase().execute(
            input: PowerLawFitInput(points: points),
            configuration: configuration
        )
        guard result.isSuccessful, let fitLine = result.fitLine else { return nil }

        let overlaySeries = WorkbenchPlotSeries(
            label: label,
            x: fitLine.x,
            y: fitLine.y.map { ($0 / 1000.0) + displayOffset },
            renderMode: .line,
            renderModeLocked: true,
            lineWidth: 1.5
        )
        return WorkbenchPlotSeriesOverlay(
            overlayIdentityKey: "\(seriesInput.identityKey)#powerLawFit",
            parentSeriesIdentityKey: seriesInput.identityKey,
            series: overlaySeries
        )
    }

    private static func fitLabel(component: IVSignalComponent, mode: PowerLawFitMode) -> String {
        guard let exponent = mode.exponent else { return "" }
        let order = Int(exponent)
        let componentTag = component.rawValue.lowercased()
        let currentExponentTag = order == 1 ? "" : "^\(order)"
        return "math:V_{\(componentTag)}^{\(order)ω} fit vs (I^{ω})\(currentExponentTag)"
    }
}
