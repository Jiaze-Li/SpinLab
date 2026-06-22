import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    // MARK: - Series order management

    func updateSeriesOrder(_ order: [String]) {
        // Order keys use the shared Plot System resolver; legacy sampleID tokens are only tolerated during alignment.
        setFieldSweepSeriesOrder(order.isEmpty ? nil : order)
        _rerenderActiveTab()
        _refreshManifestPayloads()
    }


    func resetSeriesOrder() {
        setFieldSweepSeriesOrder(nil)
        _rerenderActiveTab()
        _refreshManifestPayloads()
    }


    /// Applies a bottom-to-top per-series order to fieldSweeps, producing the render order.
    nonisolated static func _applySeriesOrder(
        _ order: [String]?,
        to sweeps: [ThreeOmegaFieldSweepResult]
    ) -> [ThreeOmegaFieldSweepResult] {
        guard let order, !order.isEmpty else { return sweeps }
        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: sweeps.enumerated().map { _, sweep in
            WorkbenchPlotSeries(
                label: "",
                x: [],
                y: [],
                sourceRef: sweep.sourceFilePath,
                sampleID: sweep.sampleID
            )
        })
        let keyedSweeps = zip(identities, sweeps).map { identity, sweep in
            (identity: identity, sweep: sweep)
        }
        let byKey = Dictionary(uniqueKeysWithValues: keyedSweeps.map { ($0.identity.identityKey, $0.sweep) })
        let bySampleID = Dictionary(grouping: keyedSweeps, by: { $0.identity.sampleID ?? "" })
        let bySourceRef = Dictionary(grouping: keyedSweeps, by: { $0.identity.sourceRef ?? "" })
        var result: [ThreeOmegaFieldSweepResult] = []
        var consumedKeys = Set<String>()

        func append(_ keyedSweep: (identity: WorkbenchSeriesIdentity, sweep: ThreeOmegaFieldSweepResult)) {
            guard consumedKeys.insert(keyedSweep.identity.identityKey).inserted else { return }
            result.append(keyedSweep.sweep)
        }

        for token in order {
            if let sweep = byKey[token] {
                append((identity: WorkbenchSeriesIdentity(
                    identityKey: token,
                    sampleID: nil,
                    sourceRef: nil,
                    metadataSignature: nil,
                    originalIndex: 0
                ), sweep: sweep))
                continue
            }
            if let matches = bySourceRef[token], !matches.isEmpty {
                for keyedSweep in matches {
                    append(keyedSweep)
                }
                continue
            }
            if let matches = bySampleID[token], !matches.isEmpty {
                for keyedSweep in matches {
                    append(keyedSweep)
                }
            }
        }
        for keyedSweep in keyedSweeps where !consumedKeys.contains(keyedSweep.identity.identityKey) {
            append(keyedSweep)
        }
        return result
    }


    /// Builds a minimal WorkbenchPlotSeries array from sweeps (for toIndexedOverrides translation).
    nonisolated static func _sweepsToFakeSeries(_ sweeps: [ThreeOmegaFieldSweepResult]) -> [WorkbenchPlotSeries] {
        sweeps.enumerated().map { _, sweep in
            WorkbenchPlotSeries(
                label: sweep.sampleID ?? "",
                x: [],
                y: [],
                sourceRef: sweep.sourceFilePath,
                sampleID: sweep.sampleID
            )
        }
    }


    /// Aligns old seriesOrder against current sweep keys.
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


    /// Aligns old seriesOrder against the current sweep identities.
    /// sourceRef keys are preferred; legacy sampleID tokens expand to the matching curves.
    nonisolated static func alignSeriesOrder(old: [String]?, fieldSweeps: [ThreeOmegaFieldSweepResult]) -> [String]? {
        guard let old, !old.isEmpty else { return nil }
        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: fieldSweeps.enumerated().map { _, sweep in
            WorkbenchPlotSeries(
                label: "",
                x: [],
                y: [],
                sourceRef: sweep.sourceFilePath,
                sampleID: sweep.sampleID
            )
        })
        let defaultKeys = identities.map(\.identityKey)
        guard !defaultKeys.isEmpty else { return nil }

        let keyedSweeps = zip(identities, fieldSweeps).map { identity, sweep in
            (
                key: identity.identityKey,
                sampleID: identity.sampleID ?? "",
                sourceRef: identity.sourceRef ?? "",
                index: identity.originalIndex
            )
        }
        let byKey = Dictionary(uniqueKeysWithValues: keyedSweeps.map { ($0.key, $0.index) })
        let bySampleID = Dictionary(grouping: keyedSweeps, by: { $0.sampleID })
        let bySourceRef = Dictionary(grouping: keyedSweeps, by: { $0.sourceRef })

        var consumed = Set<Int>()
        var result: [String] = []

        func append(index: Int) {
            guard consumed.insert(index).inserted else { return }
            result.append(defaultKeys[index])
        }

        for token in old {
            if let index = byKey[token] {
                append(index: index)
                continue
            }
            if let matches = bySourceRef[token], !matches.isEmpty {
                for match in matches.sorted(by: { $0.index < $1.index }) {
                    append(index: match.index)
                }
                continue
            }
            if let matches = bySampleID[token], !matches.isEmpty {
                for match in matches.sorted(by: { $0.index < $1.index }) {
                    append(index: match.index)
                }
            }
        }

        for index in fieldSweeps.indices where !consumed.contains(index) {
            append(index: index)
        }
        return result == defaultKeys ? nil : result
    }
}

@MainActor
extension ThreeOmegaWorkspaceStore: WorkbenchCartesianXYPlottingStore {

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


    func updateSeriesLabel(identityKey: String, newLabel: String) {
        tabs.updateSeriesLabel(identityKey: identityKey, newLabel: newLabel)
        _rerenderActiveTab()
    }


    func togglePointLabelVisibility(sampleID: String, pointIndex: Int) {
        tabs.togglePointLabelVisibility(sampleID: sampleID, pointIndex: pointIndex)
        rerenderForStyleChange()
    }


    func renderPNGAtScale(_ scale: CGFloat) -> Data? {
        copyCurrentPlotPNG(scale: scale)
    }

    func copyCurrentPlotPNG(scale: CGFloat) -> Data? {
        // Export scale is NOT macOS Retina backing scale.
        // 1x/2x/3x are user-facing export pixel-density multipliers applied to the logical render size.
        // displayPayload is the export/render source — it carries offset/stacked y-values shown on screen.
        // manifestPayload is persistence/schema only and must never be used as export source.
        // activeImageData is fallback only: when displayPayload is nil, input construction fails,
        // or the render pipeline returns empty data. Guarantees no blank output.
        guard let input = copyCurrentPlotPNGInput(scale: scale) else {
            return tabs.activeImageData
        }
        guard let rendered = try? WorkbenchRenderPipeline.render(input).imageData,
              !rendered.isEmpty
        else {
            return tabs.activeImageData
        }
        return rendered
    }

    private func copyCurrentPlotPNGInput(scale: CGFloat) -> WorkbenchRenderPipeline.Input? {
        let tab = tabs.activeTab
        guard let payload = copyCurrentPlotPayload(for: tab) else { return nil }
        let tabState = tabs.state(for: tab)
        var patch: [String: String] = [:]
        if tabs.showPlotGrid { patch["showGrid"] = "true" }
        if !tabs.legendAnchor.isEmpty { patch["legendAnchor"] = tabs.legendAnchor }

        var baseOptions = WorkbenchChartRenderer.Options()
        if let activeLayout {
            baseOptions.width = Int(activeLayout.rendererSize.width.rounded())
            baseOptions.height = Int(activeLayout.rendererSize.height.rounded())
        }

        var input = WorkbenchRenderPipeline.Input(payload: payload, baseOptions: baseOptions, globalPlotDefaults: globalPlotDefaults)
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
        return input
    }

    private func copyCurrentPlotPayload(for tab: ThreeOmegaWorkbenchTab) -> WorkbenchPlotPayload? {
        if tab == .scaling {
            guard let scalingResult else { return nil }
            let method = v3Method == .highField ? "(HFE)" : "(WA)"
            return ThreeOmegaPlotRenderer().makeScalingPayload(
                result: scalingResult,
                device: ingestionResult?.device ?? "",
                method: method
            )
        }
        // displayPayload holds the offset/stacked y-values actually shown on screen.
        // manifestPayload is a persistence/schema artifact with raw data — must NOT be used as export source.
        if let display = tabs.output(for: tab).displayPayload { return display }
        // Reject empty-series stubs (RAHE schema records with x:[] y:[]): rendering them produces
        // a blank chart. Returning nil here lets the caller fall back to activeImageData instead.
        guard let manifest = activeChartManifestPayload,
              manifest.series.contains(where: { !$0.x.isEmpty || !$0.y.isEmpty })
        else { return nil }
        return manifest
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
        let deviceMode = ingestionResult?.deviceMode ?? "single"
        let devices = ingestionResult?.devices ?? []

        var entries: [PendingMetricEntry] = []
        for seg in scaling.segments {
            var segConditions: [String: String] = [
                "range": "\(Int(seg.tLo.rounded()))K–\(Int(seg.tHi.rounded()))K",
                "v3method": methodTag
            ]
            if deviceMode == "angleSweep" {
                segConditions["deviceMode"] = "angleSweep"
                if !devices.isEmpty {
                    segConditions["devices"] = devices.joined(separator: ",")
                }
            } else if !device.isEmpty {
                segConditions["device"] = device
            }

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
        let device = result.deviceMode == "angleSweep" ? "angle_sweep" : (result.device.isEmpty ? "unknown" : result.device)
        return WorkbenchRunTraceProjection(
            runID: UUID().uuidString,
            workflowID: "3w",
            inputFiles: cachedInputFiles,
            axisMapping: WorkbenchAxisMapping(xField: "H (Oe)", yField: "R (Ω)"),
            semanticParams: [
                "device":       device,
                "deviceMode":   result.deviceMode,
                "devices":      result.devices.joined(separator: ","),
                "fieldSweeps":  "\(sweepCount)",
                "rtLoaded":     result.rtResult != nil ? "yes" : "no"
            ],
            outputImagePath: "",
            manifestPath: "",
            generatedAt: Date()
        )
    }
}
