import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    // MARK: - Series order management

    func updateSeriesOrder(_ order: [String]) {
        tabs.updateSeriesOrder(order)
        _rerenderActiveTab()
    }


    func resetSeriesOrder() {
        tabs.resetSeriesOrder()
        _rerenderActiveTab()
    }


    /// Applies a bottom-to-top seriesOrder to fieldSweeps, producing the render order.
    nonisolated static func _applySeriesOrder(
        _ order: [String]?,
        to sweeps: [ThreeOmegaFieldSweepResult]
    ) -> [ThreeOmegaFieldSweepResult] {
        guard let order, !order.isEmpty else { return sweeps }
        // Group by sampleID — duplicate IDs are possible when the same sample/temperature
        // is selected more than once; preserve all matches in encounter order.
        var bySampleID: [String: [ThreeOmegaFieldSweepResult]] = [:]
        for s in sweeps {
            guard let sid = s.sampleID else { continue }
            bySampleID[sid, default: []].append(s)
        }
        var result: [ThreeOmegaFieldSweepResult] = []
        var consumed = Set<String>()
        for id in order {
            if let bucket = bySampleID[id] {
                result.append(contentsOf: bucket)
                consumed.insert(id)
            }
        }
        for s in sweeps where s.sampleID.map({ !consumed.contains($0) }) ?? true {
            result.append(s)
        }
        return result
    }


    /// Builds a minimal WorkbenchPlotSeries array from sweeps (for toIndexedOverrides translation).
    nonisolated static func _sweepsToFakeSeries(_ sweeps: [ThreeOmegaFieldSweepResult]) -> [WorkbenchPlotSeries] {
        sweeps.map { WorkbenchPlotSeries(label: $0.sampleID ?? "", x: [], y: [], sampleID: $0.sampleID) }
    }


    /// Aligns old seriesOrder against current sweep IDs.
    /// Returns nil when alignment matches the default order (no user customization needed).
    nonisolated static func alignSeriesOrder(old: [String]?, defaultIDs: [String]) -> [String]? {
        guard let old, !old.isEmpty else { return nil }
        let currentSet = Set(defaultIDs)
        var seen: Set<String> = []
        var kept: [String] = []
        for id in old where currentSet.contains(id) && seen.insert(id).inserted {
            kept.append(id)
        }
        let keptSet = Set(kept)
        var result = kept
        for id in defaultIDs where !keptSet.contains(id) {
            result.append(id)
        }
        return result == defaultIDs ? nil : result
    }
}

@MainActor
extension ThreeOmegaWorkspaceStore: WorkbenchPlottingStore {

    func updateLegendPoint(_ point: CGPoint) {
        tabs.updateLegendPoint(point)
        tabs.legendAnchor = ""
        _rerenderActiveTab()
    }


    func updatePlotTitle(_ title: String) {
        tabs.updateTitleOverride(title)
        _rerenderActiveTab()
    }


    func updateXAxisLabel(_ label: String) {
        tabs.updateXLabelOverride(label)
        _rerenderActiveTab()
    }


    func updateYAxisLabel(_ label: String) {
        tabs.updateYLabelOverride(label)
        _rerenderActiveTab()
    }


    func updateSeriesLabel(sampleID: String, newLabel: String) {
        tabs.updateSeriesLabel(sampleID: sampleID, newLabel: newLabel)
        _rerenderActiveTab()
    }


    func togglePointLabelVisibility(sampleID: String, pointIndex: Int) {
        tabs.togglePointLabelVisibility(sampleID: sampleID, pointIndex: pointIndex)
        rerenderForStyleChange()
    }


    func renderPNGAtScale(_ scale: CGFloat) -> Data? {
        if scale == 2.0, let cached = activeImageData { return cached }
        guard let payload = activeChartManifestPayload else { return nil }
        let tab = tabs.activeTab
        let tabState = tabs.state(for: tab)
        var patch: [String: String] = [:]
        if tabs.showPlotGrid { patch["showGrid"] = "true" }
        if !tabs.legendAnchor.isEmpty { patch["legendAnchor"] = tabs.legendAnchor }
        var input = WorkbenchRenderPipeline.Input(payload: payload)
        input.pixelScaleOverride = scale
        input.legendPoint = tabState.legendPoint?.cgPoint
        input.seriesRenderMode = tabs.seriesRenderMode
        input.chartStyleOverrides = tabs.chartStyleOverrides
        input.seriesLabelOverrides = toIndexedOverrides(tabState.seriesLabelOverrides, series: payload.series)
        input.titleOverride = tabState.titleOverride
        input.xLabelOverride = tabState.xLabelOverride
        input.yLabelOverride = tabState.yLabelOverride
        input.hiddenPointLabelsBySeries = toIndexedOverrides(tabs.hiddenPointLabelsBySampleID(for: tab), series: payload.series).mapValues { Set($0) }
        input.styleParamsPatch = patch
        return try? WorkbenchRenderPipeline.render(input).imageData
    }
}

@MainActor
extension ThreeOmegaWorkspaceStore: ActiveChartProviding {
    func buildActiveChartMetrics() -> [PendingMetricEntry] {
        guard tabs.activeTab == .scaling,
              let scaling = scalingResult, !scaling.segments.isEmpty else {
            return []
        }
        guard let sampleKey = cachedSampleKeys.first else { return [] }
        let methodTag = v3Method == .highField ? "HFE" : "WA"
        let device = ingestionResult?.device ?? ""

        var entries: [PendingMetricEntry] = []
        for seg in scaling.segments {
            var segConditions: [String: String] = [
                "range": "\(Int(seg.tLo.rounded()))K–\(Int(seg.tHi.rounded()))K",
                "v3method": methodTag
            ]
            if !device.isEmpty { segConditions["device"] = device }

            entries.append(PendingMetricEntry(sampleKey: sampleKey, metric: "alpha", value: seg.alpha * 1e31, canonicalUnit: "Ω·μm³·cm²·V⁻²·S⁻²", conditions: segConditions))
            entries.append(PendingMetricEntry(sampleKey: sampleKey, metric: "beta", value: seg.beta * 1e20, canonicalUnit: "Ω·μm³·V⁻²", conditions: segConditions))
            entries.append(PendingMetricEntry(sampleKey: sampleKey, metric: "r_squared", value: seg.rSquared, canonicalUnit: "", conditions: segConditions))
        }
        return entries
    }
}

@MainActor
extension ThreeOmegaWorkspaceStore: WorkbenchWorkspaceProviding {
    func buildRunTrace() -> WorkbenchRunTraceProjection? {
        guard let result = ingestionResult else { return nil }
        let sweepCount = result.fieldSweeps.count
        return WorkbenchRunTraceProjection(
            runID: UUID().uuidString,
            workflowID: "3w",
            inputFiles: cachedInputFiles,
            axisMapping: WorkbenchAxisMapping(xField: "H (Oe)", yField: "R (Ω)"),
            semanticParams: [
                "device":       result.device.isEmpty ? "unknown" : result.device,
                "fieldSweeps":  "\(sweepCount)",
                "rtLoaded":     result.rtResult != nil ? "yes" : "no"
            ],
            outputImagePath: "",
            manifestPath: "",
            generatedAt: Date()
        )
    }
}
