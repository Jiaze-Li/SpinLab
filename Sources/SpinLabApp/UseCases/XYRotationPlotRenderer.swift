import Foundation

// MARK: - XYRotationPlotRenderer
//
// Builds WorkbenchPlotPayload and renders PNG for XY Rotation tabs.
// Currently: R(φ) vs angle, stacked by temperature.

struct XYRotationPlotRenderer {

    var workflowID: String = WorkflowKey.xyRotation.rawValue
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

    private struct StackedRotationPayloads {
        let manifestPayload: WorkbenchPlotPayload
        let displayPayload: WorkbenchPlotPayload
        let warnings: [String]
    }

    // MARK: - R(φ) tab

    func makeRxxVsPhiPayload(
        sweeps: [XYRotationAngleSweep],
        device: String
    ) -> WorkbenchPlotPayload? {
        makeRxxVsPhiPayloads(sweeps: sweeps, device: device, hiddenSeriesKeys: [])?.manifestPayload
    }

    /// Tab 1: Rxx vs φ with one series per temperature, optionally stacked.
    mutating func renderRxxVsPhi(
        sweeps: [XYRotationAngleSweep],
        device: String,
        hiddenSeriesKeys: [String] = []
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        guard let payloads = makeRxxVsPhiPayloads(sweeps: sweeps, device: device, hiddenSeriesKeys: hiddenSeriesKeys) else {
            return (nil, nil, nil, [])
        }
        var renderPayload = payloads.displayPayload
        var w: [String] = []
        let (data, layout) = _consume(_render(
            payload: &renderPayload,
            options: _stackedOptions(sweepCount: sweeps.count)
        ), into: &w)
        w.append(contentsOf: payloads.warnings)
        return (data, layout, data != nil ? payloads.displayPayload : nil, w)
    }

    /// Tab 2: Rxy vs φ with one series per temperature, optionally stacked.
    /// Only renders sweeps that have Rxy data.
    func makeRxyVsPhiPayload(
        sweeps: [XYRotationAngleSweep],
        device: String
    ) -> WorkbenchPlotPayload? {
        makeRxyVsPhiPayloads(sweeps: sweeps, device: device, hiddenSeriesKeys: [])?.manifestPayload
    }

    mutating func renderRxyVsPhi(
        sweeps: [XYRotationAngleSweep],
        device: String,
        hiddenSeriesKeys: [String] = []
    ) -> (Data?, WorkbenchPlotLayout?, WorkbenchPlotPayload?, [String]) {
        let rxySweeps = sweeps.filter { $0.resistanceXY != nil }
        guard let payloads = makeRxyVsPhiPayloads(sweeps: rxySweeps, device: device, hiddenSeriesKeys: hiddenSeriesKeys) else {
            return (nil, nil, nil, [])
        }
        var renderPayload = payloads.displayPayload
        var w: [String] = []
        let (data, layout) = _consume(_render(
            payload: &renderPayload,
            options: _stackedOptions(sweepCount: rxySweeps.count)
        ), into: &w)
        w.append(contentsOf: payloads.warnings)
        return (data, layout, data != nil ? payloads.displayPayload : nil, w)
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

    private func makeRxxVsPhiPayloads(
        sweeps: [XYRotationAngleSweep],
        device: String,
        hiddenSeriesKeys: [String]
    ) -> StackedRotationPayloads? {
        makeStackedRotationPayloads(
            sweeps: sweeps,
            device: device,
            yValueForSweep: { $0.resistanceXX },
            hiddenSeriesKeys: hiddenSeriesKeys,
            tabKey: WorkbenchPlotSeriesIdentityTabKey.xyRxxVsPhi,
            titlePrefix: "Rxx vs φ",
            yLabel: WorkbenchPlotDisplayVocabulary.label(for: .rxx, context: .manifestPlainText)
        )
    }

    private func makeRxyVsPhiPayloads(
        sweeps: [XYRotationAngleSweep],
        device: String,
        hiddenSeriesKeys: [String]
    ) -> StackedRotationPayloads? {
        makeStackedRotationPayloads(
            sweeps: sweeps,
            device: device,
            yValueForSweep: { $0.resistanceXY ?? [] },
            hiddenSeriesKeys: hiddenSeriesKeys,
            tabKey: WorkbenchPlotSeriesIdentityTabKey.xyRxyVsPhi,
            titlePrefix: "Rxy vs φ",
            yLabel: WorkbenchPlotDisplayVocabulary.label(for: .rxy, context: .manifestPlainText)
        )
    }

    private func makeStackedRotationPayloads(
        sweeps: [XYRotationAngleSweep],
        device: String,
        yValueForSweep: (XYRotationAngleSweep) -> [Double],
        hiddenSeriesKeys: [String],
        tabKey: String,
        titlePrefix: String,
        yLabel: String
    ) -> StackedRotationPayloads? {
        guard !sweeps.isEmpty else { return nil }

        let preparedSweeps: [(sweep: XYRotationAngleSweep, y: [Double])] = sweeps.map { sweep in
            var y = yValueForSweep(sweep)
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
            if centerBaseline, !y.isEmpty {
                let mean = y.reduce(0, +) / Double(y.count)
                y = y.map { $0 - mean }
            }
            return (sweep: sweep, y: y)
        }

        let rawSeries = preparedSweeps.map { prepared in
            let sweep = prepared.sweep
            let phiOffset = phiOffsetOverrides[sweep.id] ?? sweep.defaultPhiOffset
            let paired = _rebaseAndSort(angles: sweep.angleDeg, y: prepared.y, offset: phiOffset, yShift: 0)
            let stableSemanticID = WorkbenchSeriesIdentityMetadata.stableSemanticID(
                sourceRef: sweep.measurementFilePath,
                sampleID: nil,
                fallback: sweep.stem
            ) ?? sweep.stem
            return WorkbenchPlotSeries(
                label: _tempLabel(sweep.temperatureK),
                x: paired.x,
                y: paired.y,
                sourceRef: (sweep.measurementFilePath ?? "").isEmpty ? sweep.stem : (sweep.measurementFilePath ?? ""),
                sampleID: sweep.id,
                metadata: _seriesMetadata(
                    base: sweep.sampleMetadata ?? [:],
                    tabKey: tabKey,
                    seriesRole: "sweep",
                    stableSemanticID: stableSemanticID
                )
            )
        }

        let visibility = filterHiddenStackSeries(rawSeries, hiddenSeriesKeys: hiddenSeriesKeys)
        let visibleSeries = visibility.series
        let stackInputSeries = visibility.ignoredAllHidden ? rawSeries : visibleSeries
        let offsets = ThreeOmegaStackOffsetUseCase().execute(
            yValues: stackInputSeries.map(\.y),
            multiplier: stackOffsetMultiplier,
            minGapFraction: minGapFraction
        )

        let displaySeries = zip(stackInputSeries, offsets).map { pair in
            let (series, offset) = pair
            guard offset != 0 else { return series }
            var shifted = series
            shifted.y = series.y.map { $0 + offset }
            return shifted
        }
        let warning = visibility.ignoredAllHidden ? ["series visibility ignored: all series were hidden"] : []

        let title = _defaultTitle(titlePrefix, device: device)
        let manifestPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "XY Rotation",
            title: title,
            axisMapping: WorkbenchAxisMapping(
                xField: WorkbenchPlotDisplayVocabulary.label(for: .angleOffset, context: .manifestPlainText),
                yField: yLabel
            ),
            series: rawSeries,
            styleParams: ["xTickStep": "60"],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )
        let displayPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "XY Rotation",
            title: title,
            axisMapping: WorkbenchAxisMapping(
                xField: WorkbenchPlotDisplayVocabulary.label(for: .angleOffset, context: .manifestPlainText),
                yField: yLabel
            ),
            series: displaySeries,
            styleParams: ["xTickStep": "60"],
            reverseSeriesForLegend: true,
            seriesReorderable: true
        )
        return StackedRotationPayloads(
            manifestPayload: manifestPayload,
            displayPayload: displayPayload,
            warnings: warning
        )
    }

    private func _defaultTitle(_ tabName: String, device: String) -> String {
        var tokens = titleTokens
        tokens["tab"] = tabName
        tokens["device"] = device
        return WorkbenchTitleResolver.resolve(template: titleTemplate, tokens: tokens)
    }

    private func _seriesMetadata(
        base: [String: String] = [:],
        tabKey: String,
        seriesRole: String,
        stableSemanticID: String
    ) -> [String: String] {
        WorkbenchSeriesIdentityMetadata.metadata(
            base: base,
            seriesIdentityKey: WorkbenchSeriesIdentityMetadata.seriesIdentityKey(
                workflowID: workflowID,
                tabKey: tabKey,
                seriesRole: seriesRole,
                stableSemanticID: stableSemanticID
            )
        )
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
