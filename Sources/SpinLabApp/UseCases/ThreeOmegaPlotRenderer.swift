import Foundation

// MARK: - ThreeOmegaPlotRenderer
//
// Converts ThreeOmegaIngestionResult / ThreeOmegaScalingResult into
// WorkbenchPlotPayload and renders them to PNG Data + WorkbenchPlotLayout
// using WorkbenchChartRenderer / WorkbenchPlotLayout.

struct ThreeOmegaPlotRenderer {

    var showGrid: Bool = true
    var legendAnchor: String = ""           // "" = top-right (default)
    var legendPoint: CGPoint? = nil         // normalized free-position; overrides anchor
    var stackOffsetMultiplier: Double = 1.2 // spacing between stacked curves; 0 = no stacking
    var minGapFraction: Double = 0.15      // minimum gap as fraction of max peak-to-peak; 0 = no floor
    var titleTemplate: String = "#tab #method #device #sample"
    var titleTokens: [String: String] = [:]  // sample, numericDisplay keys

    // Display-only overrides applied after payload construction (mirrors AHEWorkspaceStore pattern)
    var titleOverride: String = ""
    var xLabelOverride: String = ""
    var yLabelOverride: String = ""
    var seriesLabelOverrides: [Int: String] = [:]

    private let defaultOptions = WorkbenchChartRenderer.Options()

    // MARK: - Render all 5 analysis tabs (excludes scaling — geometry required)

    func renderAllTabs(
        result: ThreeOmegaIngestionResult,
        rahe1Method: ThreeOmegaV3Method = .highField,
        rahe3Method: ThreeOmegaV3Method = .highField
    ) -> ThreeOmegaRenderedPlots {
        var plots = ThreeOmegaRenderedPlots()
        (plots.r1omega,  plots.layoutR1omega)  = renderR1omega(sweeps: result.fieldSweeps, device: result.device)
        (plots.r3omega,  plots.layoutR3omega)  = renderR3omega(sweeps: result.fieldSweeps, device: result.device)
        (plots.rahe1omegaVsT, plots.layoutRAHE1omegaVsT) = renderRAHE1omegaVsT(sweeps: result.fieldSweeps, device: result.device, method: rahe1Method)
        (plots.rahe3omegaVsT, plots.layoutRAHE3omegaVsT) = renderRAHE3omegaVsT(sweeps: result.fieldSweeps, device: result.device, method: rahe3Method)
        (plots.hcVsT,    plots.layoutHcVsT)    = renderHcVsT(sweeps: result.fieldSweeps, device: result.device)
        if let rt = result.rtResult {
            (plots.rtCurve, plots.layoutRTCurve) = renderRT(rt: rt)
        }
        return plots
    }

    // MARK: - Individual tab renderers

    /// Tab 1: R(1ω) vs H, stacked by temperature
    func renderR1omega(sweeps: [ThreeOmegaFieldSweepResult], device: String) -> (Data?, WorkbenchPlotLayout?) {
        guard !sweeps.isEmpty else { return (nil, nil) }
        let offsets = ThreeOmegaStackOffsetUseCase().execute(
            yValues: sweeps.map { $0.r1omega },
            multiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction
        )
        // Reverse so legend order matches visual order: high temp at top of legend = top of plot
        let series = zip(sweeps, offsets).map { (sweep, offset) in
            WorkbenchPlotSeries(
                label: _tempLabel(sweep.temperatureK),
                x: sweep.hField.map { $0 / 10000 },
                y: sweep.r1omega.map { $0 + offset }
            )
        }.reversed() as [WorkbenchPlotSeries]
        let yLabel = stackOffsetMultiplier > 0 ? "R(1ω) (Ω, stacked)" : "R(1ω) (Ω)"
        var payload = WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: _defaultTitle("R(1ω)", device: device),
            // Formula: R(1ω)(H) = V¹ω_X(H) / I_rms, centered, then stacked by temperature
            axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: yLabel),
            series: series
        )
        return _render(payload: &payload, options: _stackedOptions(sweepCount: sweeps.count))
    }

    /// Tab 2: R(3ω) vs H, stacked by temperature
    func renderR3omega(sweeps: [ThreeOmegaFieldSweepResult], device: String) -> (Data?, WorkbenchPlotLayout?) {
        guard !sweeps.isEmpty else { return (nil, nil) }
        let offsets = ThreeOmegaStackOffsetUseCase().execute(
            yValues: sweeps.map { $0.r3omega },
            multiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction
        )
        // Reverse so legend order matches visual order: high temp at top of legend = top of plot
        let series = zip(sweeps, offsets).map { (sweep, offset) in
            WorkbenchPlotSeries(
                label: _tempLabel(sweep.temperatureK),
                x: sweep.hField.map { $0 / 10000 },
                y: sweep.r3omega.map { $0 + offset }
            )
        }.reversed() as [WorkbenchPlotSeries]
        let yLabel = stackOffsetMultiplier > 0 ? "R(3ω) (Ω, stacked)" : "R(3ω) (Ω)"
        var payload = WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: _defaultTitle("R(3ω)", device: device),
            // Formula: R(3ω)(H) = V³ω_X(H) / I_rms, centered, then stacked by temperature
            axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: yLabel),
            series: series
        )
        return _render(payload: &payload, options: _stackedOptions(sweepCount: sweeps.count))
    }

    /// Tab 3a: RAHE(1ω) vs T
    func renderRAHE1omegaVsT(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> (Data?, WorkbenchPlotLayout?) {
        let temps = sweeps.compactMap { $0.rahe(harmonic: 1, method: method) != nil ? $0.temperatureK : nil }
        let vals  = sweeps.compactMap { $0.rahe(harmonic: 1, method: method) }
        guard !temps.isEmpty else { return (nil, nil) }

        let methodTag = method == .highField ? "HFE" : "WA"
        var payload = WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: _defaultTitle("RAHE(1ω) (\(methodTag))", device: device),
            axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "RAHE(1ω) (Ω)"),
            series: [WorkbenchPlotSeries(label: "RAHE(1ω)", x: temps, y: vals)]
        )
        return _render(payload: &payload)
    }

    /// Tab 3b: RAHE(3ω) vs T
    func renderRAHE3omegaVsT(sweeps: [ThreeOmegaFieldSweepResult], device: String, method: ThreeOmegaV3Method) -> (Data?, WorkbenchPlotLayout?) {
        let temps = sweeps.compactMap { $0.rahe(harmonic: 3, method: method) != nil ? $0.temperatureK : nil }
        let vals  = sweeps.compactMap { $0.rahe(harmonic: 3, method: method) }
        guard !temps.isEmpty else { return (nil, nil) }

        let methodTag = method == .highField ? "HFE" : "WA"
        var payload = WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: _defaultTitle("RAHE(3ω) (\(methodTag))", device: device),
            axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "RAHE(3ω) (Ω)"),
            series: [WorkbenchPlotSeries(label: "RAHE(3ω)", x: temps, y: vals)]
        )
        return _render(payload: &payload)
    }

    /// Tab 4: Hc¹ω and Hc³ω vs T
    func renderHcVsT(sweeps: [ThreeOmegaFieldSweepResult], device: String) -> (Data?, WorkbenchPlotLayout?) {
        let temps1 = sweeps.compactMap { $0.hc1omega != nil ? $0.temperatureK : nil }
        let hc1    = sweeps.compactMap { $0.hc1omega }
        let temps3 = sweeps.compactMap { $0.hc3omega != nil ? $0.temperatureK : nil }
        let hc3    = sweeps.compactMap { $0.hc3omega }
        guard !temps1.isEmpty || !temps3.isEmpty else { return (nil, nil) }

        var series: [WorkbenchPlotSeries] = []
        if !temps1.isEmpty { series.append(WorkbenchPlotSeries(label: "Hc¹ω", x: temps1, y: hc1)) }
        if !temps3.isEmpty { series.append(WorkbenchPlotSeries(label: "Hc³ω", x: temps3, y: hc3)) }

        var payload = WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: _defaultTitle("Hc", device: device),
            // Formula: Hc = (|Hc⁺| + |Hc⁻|) / 2  (midpoint crossing on each branch)
            axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "Hc (Oe)"),
            series: series
        )
        return _render(payload: &payload)
    }

    /// Tab 5: Rxx vs T (from RT file)
    func renderRT(rt: ThreeOmegaRTResult) -> (Data?, WorkbenchPlotLayout?) {
        guard !rt.temperatureK.isEmpty else { return (nil, nil) }
        var payload = WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: _defaultTitle("RT", device: rt.device),
            // Formula: Rxx(T) = Col[9] = V¹ω_X / I_rms (pre-calculated in RT file)
            axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "Rxx (Ω)"),
            series: [WorkbenchPlotSeries(label: "Rxx", x: rt.temperatureK, y: rt.rxx)]
        )
        return _render(payload: &payload)
    }

    /// Tab 6: Fig 5b — E^(3ω)_AHE / (E_xx³ × σ_xx) vs σ²_xx
    /// Display units: X in 10⁷ S²/cm², Y in Ω·μm³·V⁻²
    /// Conversions: X_SI (S/m)² × 1e-11 → 10⁷ S²/cm²
    ///              Y_SI (Ω·m³/V²) × 1e20 → Ω·μm³·V⁻² × 10²
    func renderScaling(result: ThreeOmegaScalingResult, device: String = "", method: String = "") -> (Data?, WorkbenchPlotLayout?) {
        guard !result.points.isEmpty else { return (nil, nil) }

        let xs = result.points.map { $0.sigma2xx * 1e-11 }   // (S/m)² → 10⁷ S²/cm²
        let ys = result.points.map { $0.scalingY  * 1e20  }  // Ω·m³/V² → Ω·μm³·V⁻² × 10²
        let tempLabels = result.points.map { "\(Int($0.temperatureK.rounded())) K" }
        var series: [WorkbenchPlotSeries] = [
            WorkbenchPlotSeries(label: "Experiment Data", x: xs, y: ys,
                                isScatter: true, pointLabels: tempLabels)
        ]

        let isSingleFull = result.isSingleFullRange()
        for segment in result.segments {
            // Fit in display units: alpha_d = alpha_SI × 1e31, beta_d = beta_SI × 1e20
            let alphaD = segment.alpha * 1e31
            let betaD  = segment.beta  * 1e20

            // Compute fit line range using perpendicular projection of each data point
            // onto the line y = alphaD * x + betaD.
            // Foot x-coordinate: x_foot = (xi + alphaD * (yi - betaD)) / (1 + alphaD²)
            let denom = 1.0 + alphaD * alphaD
            let segPointIndices = result.points.enumerated().compactMap { i, pt in
                segment.participatingXValues.contains(pt.sigma2xx) ? i : nil
            }
            let footXs: [Double] = segPointIndices.map { i in
                let xi = result.points[i].sigma2xx * 1e-11
                let yi = result.points[i].scalingY * 1e20
                return (xi + alphaD * (yi - betaD)) / denom
            }
            let x0 = footXs.min() ?? (segment.participatingXValues.min() ?? 0) * 1e-11
            let x1 = footXs.max() ?? (segment.participatingXValues.max() ?? 0) * 1e-11
            let fitY = [x0, x1].map { alphaD * $0 + betaD }
            // Single full-range segment keeps the legacy label; partial/multi use temperature range
            let label = isSingleFull
                ? "Fitting Results"
                : "Fit \(Int(segment.tLo.rounded()))K–\(Int(segment.tHi.rounded()))K"
            series.append(WorkbenchPlotSeries(
                label: label,
                x: [x0, x1],
                y: fitY,
                lineWidth: 2.5
            ))
        }

        // Show R² in title only for single full-range fit
        let r2Str: String
        if isSingleFull, let seg = result.segments.first {
            r2Str = String(format: " R²=%.3f", seg.rSquared)
        } else {
            r2Str = ""
        }
        var payload = WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3w",
            title: _defaultTitle("Scaling Law", device: device, method: method) + r2Str,
            // Formula: Y = E^(3ω)_AHE / (E_xx³ × σ_xx) = α·σ²_xx + β
            // β → Q_xxz Berry curvature quadrupole; E_xx³ = E_xx to the power 3
            axisMapping: WorkbenchAxisMapping(
                xField: "σ²_x_x (10⁷ S²/cm²)",
                yField: "E^(^3^ω)_A_H_E / (E³_x_x · σ_x_x) × 10² (Ω·μm³·V⁻²)"
            ),
            series: series
        )
        return _render(payload: &payload)
    }

    // MARK: - Private

    /// Applies current style params (grid, legend), renders PNG and computes layout.
    /// Pass `options` to override the default size (e.g. for stacked waterfall plots).
    private func _render(
        payload: inout WorkbenchPlotPayload,
        options: WorkbenchChartRenderer.Options? = nil
    ) -> (Data?, WorkbenchPlotLayout?) {
        let baseOpts = options ?? defaultOptions
        if showGrid { payload.styleParams["showGrid"] = "true" }
        if !legendAnchor.isEmpty { payload.styleParams["legendAnchor"] = legendAnchor }
        if let pt = legendPoint {
            payload.styleParams["legendX"] = "\(pt.x)"
            payload.styleParams["legendY"] = "\(pt.y)"
        }
        // Apply display-only overrides (mirrors AHEWorkspaceStore pattern)
        if !titleOverride.isEmpty { payload.title = titleOverride }
        if !xLabelOverride.isEmpty { payload.axisMapping.xField = xLabelOverride }
        if !yLabelOverride.isEmpty { payload.axisMapping.yField = yLabelOverride }
        // Resolve options (dynamic padding + maxYTickLabelWidth) — shared by layout and renderer.
        let opts = WorkbenchChartRenderer().resolvedOptions(payload: payload, base: baseOpts)
        // Compute layout BEFORE series label overrides so legendRow.originalLabel
        // is the stable pre-override key used by plotSeriesLabelOverrides.
        let layout = WorkbenchPlotLayout.compute(options: opts, payload: payload, legendPoint: legendPoint)
        if !seriesLabelOverrides.isEmpty {
            payload.series = payload.series.enumerated().map { i, s in
                guard let custom = seriesLabelOverrides[i] else { return s }
                var copy = s; copy.label = custom; return copy
            }
        }
        let data = try? WorkbenchChartRenderer().renderPNG(payload: payload, options: opts)
        return (data, layout)
    }

    /// Computes chart height for stacked waterfall plots.
    /// Base 600px fits ~6 curves comfortably; each additional curve adds 40px.
    private func _stackedOptions(sweepCount: Int) -> WorkbenchChartRenderer.Options {
        var opts = defaultOptions
        opts.height = max(defaultOptions.height, defaultOptions.height + (sweepCount - 6) * 40)
        return opts
    }

    private func _defaultTitle(_ tabName: String, device: String, method: String = "") -> String {
        var tokens = titleTokens
        tokens["tab"] = tabName
        tokens["device"] = device
        if !method.isEmpty { tokens["method"] = method }
        return WorkbenchTitleResolver.resolve(template: titleTemplate, tokens: tokens)
    }

    private func _tempLabel(_ t: Double) -> String {
        "\(Int(t.rounded())) K"
    }
}
