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
    var linearDetrend: Bool = false
    var showAuxiliaryLine180: Bool = false
    var seriesRenderMode: SeriesRenderMode = .line
    var globalPlotDefaults: [String: String] = [:]
    var chartStyleOverrides: [String: String] = [:]
    var axisRangeOverride: AxisRangeOverride? = nil

    private let defaultOptions = WorkbenchChartRenderer.Options()

    private enum RenderOutcome {
        case success(Data, WorkbenchPlotLayout, [String])
        case failure(String)
    }

    // MARK: - R(φ) tab

    /// Tab 1: Rxx vs φ with one series per temperature, optionally stacked.
    mutating func renderRxxVsPhi(
        sweeps: [XYRotationAngleSweep],
        device: String
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard !sweeps.isEmpty else { return (nil, nil, nil, []) }

        let yArrays: [[Double]] = sweeps.map { sweep in
            var y = sweep.resistanceXX
            // Detrend: subtract line connecting first→last to remove instrumental drift
            if linearDetrend, y.count >= 2 {
                let angles = sweep.angleDeg
                let yFirst = y.first!, yLast = y.last!
                let phiFirst = angles.first!, phiLast = angles.last!
                let phiSpan = phiLast - phiFirst
                if abs(phiSpan) > 1e-9 {
                    y = zip(angles, y).map { phi, val in
                        val - (yFirst + (yLast - yFirst) * (phi - phiFirst) / phiSpan)
                    }
                }
            }
            // Center: subtract per-curve mean to remove R₀(T) baseline
            if centerBaseline, !y.isEmpty {
                let mean = y.reduce(0, +) / Double(y.count)
                y = y.map { $0 - mean }
            }
            return y
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
                sourceRef: (sweep.measurementFilePath ?? "").isEmpty ? sweep.stem : (sweep.measurementFilePath ?? ""),
                sampleID: sweep.id,
                metadata: sweep.sampleMetadata ?? [:]
            )
        }

        let yLabel = "Rxx (Ω)"
        var payload = WorkbenchPlotPayload(
            workflowID: WorkflowKey.xyRotation.rawValue,
            workflowDisplayName: "XY Rotation",
            title: _defaultTitle("Rxx vs φ", device: device),
            axisMapping: WorkbenchAxisMapping(xField: "φ (deg)", yField: yLabel),
            series: series,
            styleParams: ["xTickStep": "60"],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )

        var w: [String] = []
        let (data, layout) = _consume(_render(
            payload: &payload,
            options: _stackedOptions(sweepCount: sweeps.count)
        ), into: &w)
        return (data, layout, payload, w)
    }

    /// Tab 2: Rxy vs φ with one series per temperature, optionally stacked.
    /// Only renders sweeps that have Rxy data.
    mutating func renderRxyVsPhi(
        sweeps: [XYRotationAngleSweep],
        device: String
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        let rxySweeps = sweeps.filter { $0.resistanceXY != nil }
        guard !rxySweeps.isEmpty else { return (nil, nil, nil, []) }

        let yArrays: [[Double]] = rxySweeps.map { sweep in
            var y = sweep.resistanceXY!
            // Detrend: subtract line connecting first→last to remove instrumental drift
            if linearDetrend, y.count >= 2 {
                let angles = sweep.angleDeg
                let yFirst = y.first!, yLast = y.last!
                let phiFirst = angles.first!, phiLast = angles.last!
                let phiSpan = phiLast - phiFirst
                if abs(phiSpan) > 1e-9 {
                    y = zip(angles, y).map { phi, val in
                        val - (yFirst + (yLast - yFirst) * (phi - phiFirst) / phiSpan)
                    }
                }
            }
            // Center: subtract per-curve mean to remove R_AHE(T) baseline
            if centerBaseline, !y.isEmpty {
                let mean = y.reduce(0, +) / Double(y.count)
                y = y.map { $0 - mean }
            }
            return y
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
                sourceRef: (sweep.measurementFilePath ?? "").isEmpty ? sweep.stem : (sweep.measurementFilePath ?? ""),
                sampleID: sweep.id,
                metadata: sweep.sampleMetadata ?? [:]
            )
        }

        let yLabel = "Rxy (Ω)"
        var payload = WorkbenchPlotPayload(
            workflowID: WorkflowKey.xyRotation.rawValue,
            workflowDisplayName: "XY Rotation",
            title: _defaultTitle("Rxy vs φ", device: device),
            axisMapping: WorkbenchAxisMapping(xField: "φ (deg)", yField: yLabel),
            series: series,
            styleParams: ["xTickStep": "60"],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )

        var w: [String] = []
        let (data, layout) = _consume(_render(
            payload: &payload,
            options: _stackedOptions(sweepCount: rxySweeps.count)
        ), into: &w)
        return (data, layout, payload, w)
    }

    // MARK: - Private

    private mutating func _render(
        payload: inout WorkbenchPlotPayload,
        options: WorkbenchChartRenderer.Options? = nil
    ) -> RenderOutcome {
        var patch: [String: String] = [:]
        if showGrid { patch["showGrid"] = "true" }
        if showAuxiliaryLine180 { patch["auxVerticalX"] = "180" }

        let input = WorkbenchRenderPipeline.Input(
            payload: payload,
            baseOptions: options ?? defaultOptions,
            legendPoint: legendPoint,
            globalPlotDefaults: globalPlotDefaults,
            seriesRenderMode: seriesRenderMode,
            chartStyleOverrides: chartStyleOverrides,
            seriesLabelOverrides: seriesLabelOverrides,
            titleOverride: titleOverride,
            xLabelOverride: xLabelOverride,
            yLabelOverride: yLabelOverride,
            styleParamsPatch: patch,
            axisRangeOverride: axisRangeOverride
        )
        do {
            let output = try WorkbenchRenderPipeline.render(input)
            payload = output.manifestPayload
            return .success(output.imageData, output.layout, output.warnings)
        } catch {
            let reason = "pipeline failure: \(error)"
            fputs("[SpinLab] XYRotationPlotRenderer: \(reason)\n", stderr)
            return .failure(reason)
        }
    }

    private func _consume(_ outcome: RenderOutcome, into warnings: inout [String]) -> (Data?, WorkbenchPlotLayout?) {
        switch outcome {
        case .success(let imageData, let layout, let w):
            warnings.append(contentsOf: w)
            return (imageData, layout)
        case .failure(let reason):
            warnings.append(reason)
            return (nil, nil)
        }
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
