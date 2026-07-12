import Foundation

// MARK: - XYRotationPlotRenderer
//
// Builds WorkbenchPlotPayload and renders PNG for XY Rotation tabs.
// Currently: R(φ) vs angle, stacked by temperature.

struct XYRotationPlotRenderer {

    var workflowID: String = WorkflowKey.xyRotation.rawValue
    var stackOffsetMultiplier: Double = 0.0
    var minGapFraction: Double = 0.15
    var titleTemplate: String = "#tab #device #sample"
    var titleTokens: [String: String] = [:]
    var phiOffsetOverrides: [String: Double] = [:]
    var centerBaseline: Bool = false
    var linearDetrend: Bool = false

    private struct StackedRotationPayloads {
        let manifestPayload: WorkbenchPlotPayload
        let displayPayload: WorkbenchPlotPayload
        let warnings: [String]
    }

    // MARK: - R(φ) tab

    func makeRxxVsPhiPayload(
        sweeps: [XYRotationAngleSweep],
        device: String,
        seriesOrder: [String]? = nil
    ) -> WorkbenchPlotPayload? {
        makeRxxVsPhiPayloads(sweeps: sweeps, device: device, seriesOrder: seriesOrder, hiddenSeriesKeys: [])?.manifestPayload
    }

    // MARK: - Tab 2: Rxy vs φ payload accessors
    //
    // Only renders sweeps that have Rxy data.
    func makeRxyVsPhiPayload(
        sweeps: [XYRotationAngleSweep],
        device: String,
        seriesOrder: [String]? = nil
    ) -> WorkbenchPlotPayload? {
        makeRxyVsPhiPayloads(sweeps: sweeps, device: device, seriesOrder: seriesOrder, hiddenSeriesKeys: [])?.manifestPayload
    }

    // MARK: - Payload-only construction (shared XY render route)
    //
    // Used by XYRotationWorkspaceStore, which renders via
    // TabRenderManager.buildPipelineInput + WorkbenchRenderPipeline.render directly.

    func makeRxxVsPhiDisplayPayload(
        sweeps: [XYRotationAngleSweep],
        device: String,
        seriesOrder: [String]? = nil,
        hiddenSeriesKeys: [String] = []
    ) -> (payload: WorkbenchPlotPayload, warnings: [String])? {
        guard let payloads = makeRxxVsPhiPayloads(
            sweeps: sweeps,
            device: device,
            seriesOrder: seriesOrder,
            hiddenSeriesKeys: hiddenSeriesKeys
        ) else {
            return nil
        }
        return (payloads.displayPayload, payloads.warnings)
    }

    func makeRxyVsPhiDisplayPayload(
        sweeps: [XYRotationAngleSweep],
        device: String,
        seriesOrder: [String]? = nil,
        hiddenSeriesKeys: [String] = []
    ) -> (payload: WorkbenchPlotPayload, warnings: [String])? {
        let rxySweeps = sweeps.filter { $0.resistanceXY != nil }
        guard let payloads = makeRxyVsPhiPayloads(
            sweeps: rxySweeps,
            device: device,
            seriesOrder: seriesOrder,
            hiddenSeriesKeys: hiddenSeriesKeys
        ) else {
            return nil
        }
        return (payloads.displayPayload, payloads.warnings)
    }

    /// Dynamic chart height (scaled to sweep count) and the full-cycle angle axis span —
    /// exposed statically so callers can build a `WorkbenchRenderPipeline.Input` directly.
    static func stackedOptions(
        sweepCount: Int,
        base: WorkbenchChartRenderer.Options = WorkbenchChartRenderer.Options()
    ) -> WorkbenchChartRenderer.Options {
        var opts = base
        opts.height = max(base.height, base.height + (sweepCount - 6) * 40)
        opts.fixedXMin = 0
        opts.fixedXMax = 360
        return opts
    }

    // MARK: - Private

    private func makeRxxVsPhiPayloads(
        sweeps: [XYRotationAngleSweep],
        device: String,
        seriesOrder: [String]?,
        hiddenSeriesKeys: [String]
    ) -> StackedRotationPayloads? {
        makePlannedStackedRotationPayloads(
            sweeps: sweeps,
            device: device,
            seriesOrder: seriesOrder,
            yValueForSweep: { $0.resistanceXX },
            hiddenSeriesKeys: hiddenSeriesKeys,
            tabKey: WorkbenchPlotSeriesIdentityTabKey.xyRxxVsPhi,
            titlePrefix: "Rxx vs φ",
            yQuantity: .rxx
        )
    }

    private func makeRxyVsPhiPayloads(
        sweeps: [XYRotationAngleSweep],
        device: String,
        seriesOrder: [String]?,
        hiddenSeriesKeys: [String]
    ) -> StackedRotationPayloads? {
        makePlannedStackedRotationPayloads(
            sweeps: sweeps,
            device: device,
            seriesOrder: seriesOrder,
            yValueForSweep: { $0.resistanceXY ?? [] },
            hiddenSeriesKeys: hiddenSeriesKeys,
            tabKey: WorkbenchPlotSeriesIdentityTabKey.xyRxyVsPhi,
            titlePrefix: "Rxy vs φ",
            yQuantity: .rxy
        )
    }

    private func makePlannedStackedRotationPayloads(
        sweeps: [XYRotationAngleSweep],
        device: String,
        seriesOrder: [String]?,
        yValueForSweep: (XYRotationAngleSweep) -> [Double],
        hiddenSeriesKeys: [String],
        tabKey: String,
        titlePrefix: String,
        yQuantity: WorkbenchPhysicalQuantity
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


        let plan = SeriesVisualPlanner.plan(
            SeriesVisualPlanningInput(
                series: rawSeries,
                visualSeriesOrder: seriesOrder,
                hiddenSeriesKeys: hiddenSeriesKeys,
                stackingPolicy: .orderEnforcingVertical(
                    multiplier: stackOffsetMultiplier,
                    minGapFraction: minGapFraction
                )
            )
        )

        let title = _defaultTitle(titlePrefix, device: device)
        let manifestPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "XY Rotation",
            title: title,
            axisMapping: WorkbenchAxisMapping(
                xField: WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .angleOffset),
                yField: WorkbenchPlotDisplayVocabulary.plainTextLabel(for: yQuantity)
            ),
            series: plan.visualSeries,
            reverseSeriesForLegend: false,
            seriesReorderable: true
        )
        let displayPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "XY Rotation",
            title: title,
            axisMapping: WorkbenchAxisMapping(
                xField: WorkbenchPlotDisplayVocabulary.plotLabel(for: .angleOffset),
                yField: WorkbenchPlotDisplayVocabulary.plotLabel(for: yQuantity)
            ),
            series: plan.displaySeries,
            reverseSeriesForLegend: false,
            seriesReorderable: true
        )
        return StackedRotationPayloads(
            manifestPayload: manifestPayload,
            displayPayload: displayPayload,
            warnings: plan.warnings
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
