import Foundation

// MARK: - ThreeOmegaPlotRenderer
//
// Converts ThreeOmegaIngestionResult / ThreeOmegaScalingResult into
// WorkbenchPlotPayload and renders them to PNG Data using WorkbenchChartRenderer.

struct ThreeOmegaPlotRenderer {

    private let renderer = WorkbenchChartRenderer()

    // MARK: - Render all 5 analysis tabs (excludes scaling — geometry required)

    func renderAllTabs(result: ThreeOmegaIngestionResult) -> ThreeOmegaRenderedPlots {
        var plots = ThreeOmegaRenderedPlots()
        plots.r1omega  = renderR1omega(sweeps: result.fieldSweeps, angleLabel: result.angleLabel)
        plots.r3omega  = renderR3omega(sweeps: result.fieldSweeps, angleLabel: result.angleLabel)
        plots.raheVsT  = renderRAHEvsT(sweeps: result.fieldSweeps, angleLabel: result.angleLabel)
        plots.hcVsT    = renderHcVsT(sweeps: result.fieldSweeps, angleLabel: result.angleLabel)
        plots.rtCurve  = result.rtResult.flatMap { renderRT(rt: $0) }
        return plots
    }

    // MARK: - Individual tab renderers

    /// Tab 1: R¹ω vs H, stacked by temperature
    func renderR1omega(sweeps: [ThreeOmegaFieldSweepResult], angleLabel: String) -> Data? {
        guard !sweeps.isEmpty else { return nil }
        let series = sweeps.map { sweep in
            WorkbenchPlotSeries(
                label: _tempLabel(sweep.temperatureK),
                x: sweep.hField,
                y: sweep.r1omega
            )
        }
        let payload = WorkbenchPlotPayload(
            workflowID: "3W",
            workflowDisplayName: "3ω AHE",
            title: "R¹ω vs H  \(angleLabel)",
            // Formula: R¹ω(H) = V¹ω_X(H) / I_rms, centered
            axisMapping: WorkbenchAxisMapping(xField: "H (Oe)", yField: "R¹ω (Ω)"),
            series: series
        )
        return try? renderer.renderPNG(payload: payload)
    }

    /// Tab 2: R³ω vs H, stacked by temperature
    func renderR3omega(sweeps: [ThreeOmegaFieldSweepResult], angleLabel: String) -> Data? {
        guard !sweeps.isEmpty else { return nil }
        let series = sweeps.map { sweep in
            WorkbenchPlotSeries(
                label: _tempLabel(sweep.temperatureK),
                x: sweep.hField,
                y: sweep.r3omega
            )
        }
        let payload = WorkbenchPlotPayload(
            workflowID: "3W",
            workflowDisplayName: "3ω AHE",
            title: "R³ω vs H  \(angleLabel)",
            // Formula: R³ω(H) = V³ω_X(H) / I_rms, centered
            axisMapping: WorkbenchAxisMapping(xField: "H (Oe)", yField: "R³ω (Ω)"),
            series: series
        )
        return try? renderer.renderPNG(payload: payload)
    }

    /// Tab 3: RAHE¹ω and RAHE³ω vs T
    func renderRAHEvsT(sweeps: [ThreeOmegaFieldSweepResult], angleLabel: String) -> Data? {
        let temps1 = sweeps.compactMap { $0.rahe1omega != nil ? $0.temperatureK : nil }
        let rahe1  = sweeps.compactMap { $0.rahe1omega }
        let temps3 = sweeps.compactMap { $0.rahe3omega != nil ? $0.temperatureK : nil }
        let rahe3  = sweeps.compactMap { $0.rahe3omega }

        guard !temps1.isEmpty || !temps3.isEmpty else { return nil }

        var series: [WorkbenchPlotSeries] = []
        if !temps1.isEmpty {
            series.append(WorkbenchPlotSeries(label: "R¹ω_AHE", x: temps1, y: rahe1))
        }
        if !temps3.isEmpty {
            series.append(WorkbenchPlotSeries(label: "R³ω_AHE", x: temps3, y: rahe3))
        }

        let payload = WorkbenchPlotPayload(
            workflowID: "3W",
            workflowDisplayName: "3ω AHE",
            title: "RAHE vs T  \(angleLabel)",
            // Formula: RAHE = (b⁺ - b⁻) / 2  where b± are high-field linear intercepts
            axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "RAHE (Ω)"),
            series: series
        )
        return try? renderer.renderPNG(payload: payload)
    }

    /// Tab 4: Hc¹ω and Hc³ω vs T
    func renderHcVsT(sweeps: [ThreeOmegaFieldSweepResult], angleLabel: String) -> Data? {
        let temps1 = sweeps.compactMap { $0.hc1omega != nil ? $0.temperatureK : nil }
        let hc1    = sweeps.compactMap { $0.hc1omega }
        let temps3 = sweeps.compactMap { $0.hc3omega != nil ? $0.temperatureK : nil }
        let hc3    = sweeps.compactMap { $0.hc3omega }

        guard !temps1.isEmpty || !temps3.isEmpty else { return nil }

        var series: [WorkbenchPlotSeries] = []
        if !temps1.isEmpty {
            series.append(WorkbenchPlotSeries(label: "Hc¹ω", x: temps1, y: hc1))
        }
        if !temps3.isEmpty {
            series.append(WorkbenchPlotSeries(label: "Hc³ω", x: temps3, y: hc3))
        }

        let payload = WorkbenchPlotPayload(
            workflowID: "3W",
            workflowDisplayName: "3ω AHE",
            title: "Hc vs T  \(angleLabel)",
            // Formula: Hc = (|Hc⁺| + |Hc⁻|) / 2  (midpoint crossing on each branch)
            axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "Hc (Oe)"),
            series: series
        )
        return try? renderer.renderPNG(payload: payload)
    }

    /// Tab 5: Rxx vs T (from RT file)
    func renderRT(rt: ThreeOmegaRTResult) -> Data? {
        guard !rt.temperatureK.isEmpty else { return nil }
        let series = [WorkbenchPlotSeries(label: "Rxx", x: rt.temperatureK, y: rt.rxx)]
        let payload = WorkbenchPlotPayload(
            workflowID: "3W",
            workflowDisplayName: "3ω AHE",
            title: "Rxx vs T  \(rt.angleLabel)",
            // Formula: Rxx(T) = Col[9] = V¹ω_X / I_rms (pre-calculated in RT file)
            axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "Rxx (Ω)"),
            series: series
        )
        return try? renderer.renderPNG(payload: payload)
    }

    /// Tab 6: Fig 5b — E^(3ω)_AHE / (E_xx³ × σ_xx) vs σ²_xx
    func renderScaling(result: ThreeOmegaScalingResult) -> Data? {
        guard !result.points.isEmpty else { return nil }

        let xs = result.points.map { $0.sigma2xx }
        let ys = result.points.map { $0.scalingY }
        var series: [WorkbenchPlotSeries] = [
            WorkbenchPlotSeries(label: "Data", x: xs, y: ys)
        ]

        // Overlay linear fit line if available
        if let alpha = result.alpha, let beta = result.beta, xs.count >= 2 {
            let xMin = xs.min()!, xMax = xs.max()!
            let fitX = [xMin, xMax]
            let fitY = fitX.map { alpha * $0 + beta }
            series.append(WorkbenchPlotSeries(
                label: String(format: "Fit: β=%.3e", beta),
                x: fitX,
                y: fitY
            ))
        }

        let r2Str = result.rSquared.map { String(format: " R²=%.3f", $0) } ?? ""
        let payload = WorkbenchPlotPayload(
            workflowID: "3W",
            workflowDisplayName: "3ω AHE",
            title: "Fig 5b: Berry Curvature Quadrupole Scaling\(r2Str)",
            // Formula: Y = E^(3ω)_AHE / (E_xx³ × σ_xx) = α·σ²_xx + β
            // β → Q_xxz Berry curvature quadrupole; E_xx³ = E_xx to the power 3
            axisMapping: WorkbenchAxisMapping(
                xField: "σ²_xx (S/m)²",
                yField: "E^(3ω)_AHE / (E³_xx · σ_xx)"
            ),
            series: series
        )
        return try? renderer.renderPNG(payload: payload)
    }

    // MARK: - Private helpers

    private func _tempLabel(_ t: Double) -> String {
        if t.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(t)) K"
        }
        return String(format: "%.1f K", t)
    }
}
