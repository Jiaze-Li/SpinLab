import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    // MARK: - Manifest payload helpers

    /// Builds a manifest payload for the given tab with sourceRef properly filled.
    private func _projectFieldSweepSeries(
        sweeps: [ThreeOmegaFieldSweepResult],
        inputFiles: [String],
        yValues: KeyPath<ThreeOmegaFieldSweepResult, [Double]>
    ) -> [WorkbenchPlotSeries] {
        sweeps.enumerated().map { index, sweep in
            let sourceRef = sweep.sourceFilePath ?? (index < inputFiles.count ? inputFiles[index] : nil)
            return WorkbenchPlotSeries(
                label: _temperatureLabel(sweep.temperatureK),
                x: sweep.hField.map { $0 / 10000 },
                y: sweep[keyPath: yValues],
                sourceRef: sourceRef,
                sampleID: sweep.sampleID,
                metadata: sweep.sampleMetadata ?? [:]
            )
        }
    }

    private func _buildManifestPayload(
        tab: ThreeOmegaWorkbenchTab,
        device: String,
        deviceMode: String,
        devices: [String],
        inputFiles: [String],
        fieldSweeps: [ThreeOmegaFieldSweepResult],
        seriesOrder: [String]? = nil,
        rtFilePath: String?,
        titleTemplate: String,
        titleTokens: [String: String],
        v3Method: ThreeOmegaV3Method
    ) -> WorkbenchPlotPayload? {
        let methodTag = v3Method == .highField ? "HFE" : "WA"
        let isAngleSweep = deviceMode == "angleSweep"
        let deviceToken = isAngleSweep ? "" : device
        let devicesToken = devices.isEmpty ? "" : devices.joined(separator: ",")

        func resolveTitle(_ tabName: String) -> String {
            var tokens = titleTokens
            tokens["tab"] = tabName
            if isAngleSweep {
                tokens["device"] = ""
                tokens["deviceMode"] = "angleSweep"
            } else {
                tokens["device"] = device
            }
            var result = titleTemplate
            for (key, value) in tokens {
                result = result.replacingOccurrences(of: "#\(key)", with: value)
            }
            result = result.replacingOccurrences(of: "#\\S+", with: "", options: .regularExpression)
            return result.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }

        func makePayload(title: String, xField: String, yField: String, files: [String], extraParams: [String: String] = [:]) -> WorkbenchPlotPayload {
            var params: [String: String] = ["tabKey": tab.stableKey]
            if !deviceToken.isEmpty {
                params["device"] = deviceToken
            }
            if isAngleSweep {
                params["deviceMode"] = "angleSweep"
                if !devicesToken.isEmpty {
                    params["devices"] = devicesToken
                }
            }
            for (k, v) in extraParams { params[k] = v }
            return WorkbenchPlotPayload(
                workflowID: "3w",
                workflowDisplayName: "3w",
                title: title,
                axisMapping: WorkbenchAxisMapping(xField: xField, yField: yField),
                series: files.map { WorkbenchPlotSeries(label: URL(fileURLWithPath: $0).lastPathComponent, x: [], y: [], sourceRef: $0) },
                semanticParams: params
            )
        }

        switch tab {
        case .fieldSweep1omega:
            let orderedSweeps = Self.manifestOrderedFieldSweeps(fieldSweeps, seriesOrder: seriesOrder)
            var payload = WorkbenchPlotPayload(
                workflowID: "3w",
                workflowDisplayName: "3w",
                title: resolveTitle("R(1ω)"),
                axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R(1ω) (Ω)"),
                series: _projectFieldSweepSeries(sweeps: orderedSweeps, inputFiles: inputFiles, yValues: \.r1omega),
                semanticParams: isAngleSweep
                    ? ["tabKey": tab.stableKey, "deviceMode": "angleSweep", "devices": devicesToken]
                    : ["device": device, "tabKey": tab.stableKey],
                seriesReorderable: true
            )
            _ = WorkbenchRenderPipeline.applyLegendDimensionResolution(to: &payload)
            return payload
        case .fieldSweep3omega:
            let orderedSweeps = Self.manifestOrderedFieldSweeps(fieldSweeps, seriesOrder: seriesOrder)
            var payload = WorkbenchPlotPayload(
                workflowID: "3w",
                workflowDisplayName: "3w",
                title: resolveTitle("R(3ω)"),
                axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R(3ω) (Ω)"),
                series: _projectFieldSweepSeries(sweeps: orderedSweeps, inputFiles: inputFiles, yValues: \.r3omega),
                semanticParams: isAngleSweep
                    ? ["tabKey": tab.stableKey, "deviceMode": "angleSweep", "devices": devicesToken]
                    : ["device": device, "tabKey": tab.stableKey],
                seriesReorderable: true
            )
            _ = WorkbenchRenderPipeline.applyLegendDimensionResolution(to: &payload)
            return payload
        case .rahe1omegaVsT:
            let tag = rahe1omegaMethod == .highField ? "HFE" : "WA"
            return makePayload(
                title: resolveTitle("RAHE(1ω)") + " (\(tag))",
                xField: "T (K)", yField: "RAHE(1ω) (Ω)", files: inputFiles,
                extraParams: ["v3method": tag]
            )
        case .rahe3omegaVsT:
            let tag = rahe3omegaMethod == .highField ? "HFE" : "WA"
            return makePayload(
                title: resolveTitle("RAHE(3ω)") + " (\(tag))",
                xField: "T (K)", yField: "RAHE(3ω) (Ω)", files: inputFiles,
                extraParams: ["v3method": tag]
            )
        case .hcVsT:
            return makePayload(title: resolveTitle("Hc"), xField: "T (K)", yField: "Hc (Oe)", files: inputFiles)
        case .rtCurve:
            guard let rtPath = rtFilePath else { return nil }
            return makePayload(title: resolveTitle("RT"), xField: "T (K)", yField: "Rxx (Ω)", files: [rtPath])
        case .scaling:
            let rangeSig = fitRanges
                .sorted { ($0.tLo ?? 0) < ($1.tLo ?? 0) }
                .map { "\($0.tLo ?? 0)K-\($0.tHi ?? 9999)K" }
                .joined(separator: ",")
            return makePayload(
                title: resolveTitle("Scaling Law") + " (\(methodTag))",
                xField: "σ²_xx (S²/m²)", yField: "E(3ω)_AHE / (E³_xx · σ_xx)",
                files: inputFiles,
                extraParams: ["v3method": methodTag, "fitRanges": rangeSig]
            )
        }
    }

    /// Returns the field-sweep series in bottom-to-top render order for manifest caching.
    /// Matches the committed series order so that activeManifestPayload.series.map(sourceRef)
    /// equals the bottom-to-top order committed by the panel.
    nonisolated static func manifestOrderedFieldSweeps(
        _ fieldSweeps: [ThreeOmegaFieldSweepResult],
        seriesOrder: [String]?
    ) -> [ThreeOmegaFieldSweepResult] {
        _applySeriesOrder(seriesOrder, to: fieldSweeps)
    }


    /// Caches manifest payloads for all tabs after analysis completes.
    /// Snapshots sampleKeys, conditions, inputFiles from the current selection.
    /// Called once after runAnalysis completes; scaling re-runs call `_refreshManifestPayloads()` instead.
    ///
    /// Pack restore path calls the no-arg overload (reads cachedSearchResults after it has been
    /// written from the pack). Analysis path calls the parameterized overload with the run-scoped
    /// selectedHits captured at runAnalysis entry, so stale cachedSearchResults cannot corrupt
    /// cachedInputFiles for a snapshot-driven run.
    func _snapshotAndCacheManifestPayloads(from selectedHits: [WorkflowMeasurementSearchHit]) {
        // Snapshot from current selection — frozen for the lifetime of this analysis run
        cachedInputFiles = selectedHits.map { $0.measurementFilePath }
        cachedRTFilePath = selectedRTHit?.measurementFilePath
        var seen = Set<String>()
        cachedSampleKeys = selectedHits.compactMap { seen.insert($0.sampleKey).inserted ? $0.sampleKey : nil }
        var condMap: [String: [String: String]] = [:]
        for hit in selectedHits where condMap[hit.sampleKey] == nil {
            condMap[hit.sampleKey] = hit.conditions
        }
        cachedConditionsBySampleKey = condMap

        _refreshManifestPayloads()
    }

    /// Legacy/restore overload: derives selectedHits from cachedSearchResults.
    /// Used by restoreFromPack(), which writes cachedSearchResults before calling this.
    func _snapshotAndCacheManifestPayloads() {
        let ids = selectionReading?.selectedIDs(for: .threeOmega) ?? []
        let selectedHits = cachedSearchResults
            .filter { ids.contains($0.id) }
            .sorted(by: { $0.measurementFilePath < $1.measurementFilePath })
        _snapshotAndCacheManifestPayloads(from: selectedHits)
    }


    /// Rebuilds manifest payloads from cached (frozen) inputFiles/sampleKeys.
    /// Safe to call after scaling reruns — does NOT re-read UI selection.
    func _refreshManifestPayloads() {
        let device = ingestionResult?.device ?? ""
        let deviceMode = ingestionResult?.deviceMode ?? "single"
        let devices = ingestionResult?.devices ?? []
        let sharedFieldSweepSeriesOrder = fieldSweepSeriesOrder

        for tab in ThreeOmegaWorkbenchTab.allCases {
            let seriesOrder: [String]?
            switch tab {
            case .fieldSweep1omega, .fieldSweep3omega:
                seriesOrder = sharedFieldSweepSeriesOrder
            default:
                seriesOrder = tabs.state(for: tab).seriesOrder
            }
            let rawPayload = _buildManifestPayload(
                tab: tab,
                device: device,
                deviceMode: deviceMode,
                devices: devices,
                inputFiles: cachedInputFiles,
                fieldSweeps: ingestionResult?.fieldSweeps ?? [],
                seriesOrder: seriesOrder,
                rtFilePath: cachedRTFilePath,
                titleTemplate: titleTemplate,
                titleTokens: _titleTokens,
                v3Method: v3Method
            )
            if let rawPayload, rawPayload.seriesReorderable, rawPayload.series.contains(where: { ($0.sourceRef?.isEmpty ?? true) }) {
                let message = "Reorderable \(tab.stableKey) manifest payload missing sourceRef."
                assertionFailure(message)
                appendWarning(source: "Manifest", message: message)
            }
            // Apply per-tab text overrides (same patch contract as _rerenderActiveTab).
            let payload: WorkbenchPlotPayload? = {
                guard var p = rawPayload else { return nil }
                let s = tabs.state(for: tab)
                if !s.titleOverride.isEmpty { p.title = s.titleOverride }
                if !s.xLabelOverride.isEmpty { p.axisMapping.xField = s.xLabelOverride }
                if !s.yLabelOverride.isEmpty { p.axisMapping.yField = s.yLabelOverride }
                if !s.seriesLabelOverrides.isEmpty {
                    p.series = p.series.map { series in
                        guard let sid = series.sampleID,
                              let renamed = s.seriesLabelOverrides[sid] else { return series }
                        var copy = series
                        copy.label = renamed
                        return copy
                    }
                }
                return p
            }()
            var existing = tabs.tabOutputs[tab] ?? TabRenderOutput()
            existing.manifestPayload = payload
            tabs.tabOutputs[tab] = existing
        }
    }


    /// Rebuilds manifest payloads for RAHE overlay tabs with one sourceRef per file.
    func _rebuildOverlayManifestPayloads(
        groups: [(label: String, sweeps: [ThreeOmegaFieldSweepResult], sourceFiles: [String])]
    ) {
        // Collect all source files across all groups (individual entries, not ;-joined)
        let allFiles = groups.flatMap(\.sourceFiles)
        let device = ingestionResult?.device ?? ""
        let deviceMode = ingestionResult?.deviceMode ?? "single"
        let devices = ingestionResult?.devices ?? []

        for tab in [ThreeOmegaWorkbenchTab.rahe1omegaVsT, .rahe3omegaVsT] {
            let isR1 = tab == .rahe1omegaVsT
            let method = isR1 ? rahe1omegaMethod : rahe3omegaMethod
            let methodTag = method == .highField ? "HFE" : "WA"
            let hLabel = isR1 ? "1ω" : "3ω"

            let series = groups.flatMap { group in
                zip(group.sweeps, group.sourceFiles).map { sweep, sourceFile in
                    WorkbenchPlotSeries(
                        label: sweep.sampleID ?? URL(fileURLWithPath: sourceFile).lastPathComponent,
                        x: [],
                        y: [],
                        sourceRef: sourceFile,
                        sampleID: sweep.sampleID,
                        metadata: sweep.sampleMetadata ?? [:]
                    )
                }
            }
            let fallbackSeries = series.isEmpty ? allFiles.map {
                WorkbenchPlotSeries(label: URL(fileURLWithPath: $0).lastPathComponent, x: [], y: [], sourceRef: $0)
            }
            : series
            let params: [String: String] = deviceMode == "angleSweep"
                ? ["tabKey": tab.stableKey, "v3method": methodTag, "deviceMode": "angleSweep", "devices": devices.joined(separator: ",")]
                : ["device": device, "tabKey": tab.stableKey, "v3method": methodTag]
            let title = WorkbenchTitleResolver.resolve(
                template: titleTemplate,
                tokens: _titleTokens.merging(deviceMode == "angleSweep"
                    ? ["tab": "RAHE(\(hLabel))", "device": "", "deviceMode": "angleSweep"]
                    : ["tab": "RAHE(\(hLabel))", "device": device]) { _, new in new }
            ) + " (\(methodTag))"

            var existing = tabs.tabOutputs[tab] ?? TabRenderOutput()
            existing.manifestPayload = WorkbenchPlotPayload(
                workflowID: "3w",
                workflowDisplayName: "3w",
                title: title,
                axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "RAHE(\(hLabel)) (Ω)"),
                series: fallbackSeries,
                semanticParams: params
            )
            // Apply per-tab text overrides (same patch contract as _rerenderActiveTab).
            let tabState = tabs.state(for: tab)
            if !tabState.titleOverride.isEmpty {
                existing.manifestPayload?.title = tabState.titleOverride
            }
            if !tabState.xLabelOverride.isEmpty {
                existing.manifestPayload?.axisMapping.xField = tabState.xLabelOverride
            }
            if !tabState.yLabelOverride.isEmpty {
                existing.manifestPayload?.axisMapping.yField = tabState.yLabelOverride
            }
            if !tabState.seriesLabelOverrides.isEmpty, var p = existing.manifestPayload {
                p.series = p.series.map { series in
                    guard let sid = series.sampleID,
                          let renamed = tabState.seriesLabelOverrides[sid] else { return series }
                    var copy = series
                    copy.label = renamed
                    return copy
                }
                existing.manifestPayload = p
            }
            tabs.tabOutputs[tab] = existing
            }
        }
    }

    private func _temperatureLabel(_ temperatureK: Double) -> String {
        "\(Int(temperatureK.rounded())) K"
    }
