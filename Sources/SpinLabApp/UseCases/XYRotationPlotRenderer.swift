import Foundation

// MARK: - XYRotationPlotRenderer
//
// Builds WorkbenchPlotPayload and renders PNG for XY Rotation tabs.
// Currently: R(φ) vs angle, stacked by temperature.

struct XYRotationPlotRenderer {

    var showGrid: Bool = true
    var legendPoint: CGPoint? = nil
    var stackOffsetMultiplier: Double = 0.0
    var minGapFraction: Double = 0.15
    var titleTemplate: String = "#tab #device #sample"
    var titleTokens: [String: String] = [:]
    var titleOverride: String = ""
    var xLabelOverride: String = ""
    var yLabelOverride: String = ""
    var seriesLabelOverrides: [Int: String] = [:]
    var phiOffsetOverrides: [String: Double] = [:]
    var centerBaseline: Bool = false

    private let defaultOptions = WorkbenchChartRenderer.Options()

    // MARK: - R(φ) tab

    /// Tab 1: Rxx vs φ with one series per temperature, optionally stacked.
    mutating func renderRxxVsPhi(
        sweeps: [XYRotationAngleSweep],
        device: String
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?) {
        guard !sweeps.isEmpty else { return (nil, nil, nil) }

        // Center: subtract per-curve mean to remove R₀(T) baseline
        let yArrays: [[Double]] = sweeps.map { sweep in
            let raw = sweep.resistanceXX
            if centerBaseline, !raw.isEmpty {
                let mean = raw.reduce(0, +) / Double(raw.count)
                return raw.map { $0 - mean }
            }
            return raw
        }

        let offsets = ThreeOmegaStackOffsetUseCase().execute(
            yValues: yArrays,
            multiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction
        )

        let series: [WorkbenchPlotSeries] = zip(zip(sweeps, yArrays), offsets).map { pair, yOffset in
            let (sweep, yData) = pair
            let phiOffset = phiOffsetOverrides[sweep.id] ?? sweep.defaultPhiOffset
            let paired = _rebaseAndSort(angles: sweep.angleDeg, y: yData, offset: phiOffset, yShift: yOffset)
            return WorkbenchPlotSeries(
                label: _tempLabel(sweep.temperatureK),
                x: paired.x,
                y: paired.y,
                sourceRef: sweep.measurementFilePath.isEmpty ? sweep.stem : sweep.measurementFilePath
            )
        }.reversed()

        var yLabel = centerBaseline ? "Rxx − R₀ (Ω" : "Rxx (Ω"
        yLabel += stackOffsetMultiplier > 0 ? ", stacked)" : ")"
        var payload = WorkbenchPlotPayload(
            workflowID: "xy",
            workflowDisplayName: "XY Rotation",
            title: _defaultTitle("Rxx vs φ", device: device),
            axisMapping: WorkbenchAxisMapping(xField: "φ (deg)", yField: yLabel),
            series: series
        )

        let (data, layout) = _render(
            payload: &payload,
            options: _stackedOptions(sweepCount: sweeps.count)
        )
        return (data, layout, payload)
    }

    /// Tab 2: Rxy vs φ with one series per temperature, optionally stacked.
    /// Only renders sweeps that have Rxy data.
    mutating func renderRxyVsPhi(
        sweeps: [XYRotationAngleSweep],
        device: String
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?) {
        let rxySweeps = sweeps.filter { $0.resistanceXY != nil }
        guard !rxySweeps.isEmpty else { return (nil, nil, nil) }

        // Center: subtract per-curve mean to remove R_AHE(T) baseline
        let yArrays: [[Double]] = rxySweeps.map { sweep in
            let raw = sweep.resistanceXY!
            if centerBaseline, !raw.isEmpty {
                let mean = raw.reduce(0, +) / Double(raw.count)
                return raw.map { $0 - mean }
            }
            return raw
        }

        let offsets = ThreeOmegaStackOffsetUseCase().execute(
            yValues: yArrays,
            multiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction
        )

        let series: [WorkbenchPlotSeries] = zip(zip(rxySweeps, yArrays), offsets).map { pair, yOffset in
            let (sweep, yData) = pair
            let phiOffset = phiOffsetOverrides[sweep.id] ?? sweep.defaultPhiOffset
            let paired = _rebaseAndSort(angles: sweep.angleDeg, y: yData, offset: phiOffset, yShift: yOffset)
            return WorkbenchPlotSeries(
                label: _tempLabel(sweep.temperatureK),
                x: paired.x,
                y: paired.y,
                sourceRef: sweep.measurementFilePath.isEmpty ? sweep.stem : sweep.measurementFilePath
            )
        }.reversed()

        var yLabel = centerBaseline ? "Rxy − R_AHE (Ω" : "Rxy (Ω"
        yLabel += stackOffsetMultiplier > 0 ? ", stacked)" : ")"
        var payload = WorkbenchPlotPayload(
            workflowID: "xy",
            workflowDisplayName: "XY Rotation",
            title: _defaultTitle("Rxy vs φ", device: device),
            axisMapping: WorkbenchAxisMapping(xField: "φ (deg)", yField: yLabel),
            series: series
        )

        let (data, layout) = _render(
            payload: &payload,
            options: _stackedOptions(sweepCount: rxySweeps.count)
        )
        return (data, layout, payload)
    }

    // MARK: - Private

    private mutating func _render(
        payload: inout WorkbenchPlotPayload,
        options: WorkbenchChartRenderer.Options? = nil
    ) -> (Data?, WorkbenchPlotLayout?) {
        let baseOpts = options ?? defaultOptions
        if showGrid { payload.styleParams["showGrid"] = "true" }
        if let pt = legendPoint {
            payload.styleParams["legendX"] = "\(pt.x)"
            payload.styleParams["legendY"] = "\(pt.y)"
        }
        if !titleOverride.isEmpty { payload.title = titleOverride }
        if !xLabelOverride.isEmpty { payload.axisMapping.xField = xLabelOverride }
        if !yLabelOverride.isEmpty { payload.axisMapping.yField = yLabelOverride }

        let opts = WorkbenchChartRenderer().resolvedOptions(payload: payload, base: baseOpts)
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

    private func _stackedOptions(sweepCount: Int) -> WorkbenchChartRenderer.Options {
        var opts = defaultOptions
        opts.height = max(defaultOptions.height, defaultOptions.height + (sweepCount - 6) * 40)
        opts.fixedXMin = 0
        opts.fixedXMax = 360
        return opts
    }

    private func _defaultTitle(_ tabName: String, device: String) -> String {
        var tokens = titleTokens
        tokens["tab"] = tabName
        tokens["device"] = device
        return WorkbenchTitleResolver.resolve(template: titleTemplate, tokens: tokens)
    }

    private func _tempLabel(_ t: Double) -> String {
        t.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(t)) K"
            : String(format: "%.1f K", t)
    }

    /// Rebases angles by subtracting offset, wraps to [0, 360), applies yShift,
    /// sorts by new angle, then adds periodic ghost points at both ends for splice smoothing.
    private func _rebaseAndSort(angles: [Double], y: [Double], offset: Double, yShift: Double) -> (x: [Double], y: [Double]) {
        guard angles.count == y.count, !angles.isEmpty else { return ([], []) }
        var pairs = zip(angles, y).map { ang, yVal -> (x: Double, y: Double) in
            var newAngle = (ang - offset).truncatingRemainder(dividingBy: 360)
            if newAngle < 0 { newAngle += 360 }
            return (x: newAngle, y: yVal + yShift)
        }
        pairs.sort { $0.x < $1.x }

        // Periodic extension: mirror boundary points so the line is smooth at the splice.
        // Only when data covers near-full cycle (>300° span).
        let xSpan = (pairs.last?.x ?? 0) - (pairs.first?.x ?? 0)
        if xSpan > 300 {
            let k = min(3, pairs.count / 2)
            let headMirror = pairs.suffix(k).map { (x: $0.x - 360, y: $0.y) }
            let tailMirror = pairs.prefix(k).map { (x: $0.x + 360, y: $0.y) }
            pairs = headMirror + pairs + tailMirror
        }

        return (x: pairs.map(\.x), y: pairs.map(\.y))
    }
}
