import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    // MARK: - Manifest payload helpers

    /// Builds a manifest payload for the given tab with sourceRef properly filled.
    private func _projectFieldSweepSeries(
        sweeps: [ThreeOmegaFieldSweepResult],
        inputFiles: [String],
        yValues: KeyPath<ThreeOmegaFieldSweepResult, [Double]>,
        tabKey: String
    ) -> [WorkbenchPlotSeries] {
        sweeps.enumerated().map { index, sweep in
            let sourceRef = sweep.sourceFilePath ?? (index < inputFiles.count ? inputFiles[index] : nil)
            let stableSemanticID = WorkbenchSeriesIdentityMetadata.stableSemanticID(
                sourceRef: sourceRef,
                sampleID: sweep.sampleID,
                fallback: sourceRef
            ) ?? ""
            return WorkbenchPlotSeries(
                label: _temperatureLabel(sweep.temperatureK),
                x: sweep.hField.map { $0 / 10000 },
                y: sweep[keyPath: yValues],
                sourceRef: sourceRef,
                sampleID: sweep.sampleID,
                metadata: WorkbenchSeriesIdentityMetadata.metadata(
                    base: sweep.sampleMetadata ?? [:],
                    seriesIdentityKey: WorkbenchSeriesIdentityMetadata.seriesIdentityKey(
                        workflowID: workflowID,
                        tabKey: tabKey,
                        seriesRole: "sweep",
                        stableSemanticID: stableSemanticID
                    )
                )
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

        func makePayload(title: String, xField: String, yField: String, files: [String], tabKey: String, extraParams: [String: String] = [:]) -> WorkbenchPlotPayload {
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
                workflowID: workflowID,
                workflowDisplayName: "3w",
                title: title,
                axisMapping: WorkbenchAxisMapping(xField: xField, yField: yField),
                series: files.map { sourceRef in
                    WorkbenchPlotSeries(
                        label: URL(fileURLWithPath: sourceRef).lastPathComponent,
                        x: [],
                        y: [],
                        sourceRef: sourceRef,
                        metadata: WorkbenchSeriesIdentityMetadata.metadata(
                            seriesIdentityKey: WorkbenchSeriesIdentityMetadata.seriesIdentityKey(
                                workflowID: workflowID,
                                tabKey: tabKey,
                                seriesRole: "series",
                                stableSemanticID: sourceRef
                            )
                        )
                    )
                },
                semanticParams: params
            )
        }

        switch tab {
        case .rahe:
            var renderer = ThreeOmegaPlotRenderer()
            renderer.titleTemplate = titleTemplate
            renderer.titleTokens = titleTokens
            renderer.stackOffsetMultiplier = stackOffsetMultiplier
            renderer.minGapFraction = minGapFraction
            return renderer.makeRAHEPayload(
                sweeps: fieldSweeps,
                device: device,
                seriesOrder: seriesOrder,
                rahe1Method: rahe1omegaMethod,
                rahe3Method: rahe3omegaMethod
            )
        case .rahe1omegaVsT, .rahe3omegaVsT:
            return nil
        case .fieldSweep1omega:
            let orderedSweeps = Self.manifestOrderedFieldSweeps(fieldSweeps, seriesOrder: seriesOrder)
            var payload = WorkbenchPlotPayload(
                workflowID: workflowID,
                workflowDisplayName: "3w",
                title: resolveTitle("R(1ω)"),
                axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R(1ω) (Ω)"),
                series: _projectFieldSweepSeries(sweeps: orderedSweeps, inputFiles: inputFiles, yValues: \.r1omega, tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaR1omegaVsH),
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
                workflowID: workflowID,
                workflowDisplayName: "3w",
                title: resolveTitle("R(3ω)"),
                axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R(3ω) (Ω)"),
                series: _projectFieldSweepSeries(sweeps: orderedSweeps, inputFiles: inputFiles, yValues: \.r3omega, tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaR3omegaVsH),
                semanticParams: isAngleSweep
                    ? ["tabKey": tab.stableKey, "deviceMode": "angleSweep", "devices": devicesToken]
                    : ["device": device, "tabKey": tab.stableKey],
                seriesReorderable: true
            )
            _ = WorkbenchRenderPipeline.applyLegendDimensionResolution(to: &payload)
            return payload
        case .rahe1omegaVsDevice:
            let tag = rahe1omegaVsDeviceMethod == .highField ? "HFE" : "WA"
            return makePayload(
                title: resolveTitle("RAHE(1ω)") + " (\(tag))",
                xField: "Device angle (deg)", yField: "RAHE(1ω) (Ω)", files: inputFiles,
                tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaRAHE1omegaVsDevice,
                extraParams: ["v3method": tag]
            )
        case .rahe3omegaVsDevice:
            let tag = rahe3omegaVsDeviceMethod == .highField ? "HFE" : "WA"
            return makePayload(
                title: resolveTitle("RAHE(3ω)") + " (\(tag))",
                xField: "Device angle (deg)", yField: "RAHE(3ω) (Ω)", files: inputFiles,
                tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaRAHE3omegaVsDevice,
                extraParams: ["v3method": tag]
            )
        case .hcVsT:
            return makePayload(title: resolveTitle("Hc"), xField: "T (K)", yField: "Hc (Oe)", files: inputFiles, tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaHcVsT)
        case .rtCurve:
            guard let rtPath = rtFilePath else { return nil }
            return makePayload(title: resolveTitle("RT"), xField: "T (K)", yField: "Rxx (Ω)", files: [rtPath], tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaRT)
        case .scaling:
            let rangeSig = fitRanges
                .sorted { ($0.tLo ?? 0) < ($1.tLo ?? 0) }
                .map { "\($0.tLo ?? 0)K-\($0.tHi ?? 9999)K" }
                .joined(separator: ",")
            return makePayload(
                title: resolveTitle("Scaling Law") + " (\(methodTag))",
                xField: ThreeOmegaPlotRenderer.scalingXAxisLabel,
                yField: ThreeOmegaPlotRenderer.scalingYAxisLabel,
                files: inputFiles,
                tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaScaling,
                extraParams: ["v3method": methodTag, "fitRanges": rangeSig]
            )
        case .temperatureDependence:
            return nil
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
        let ids = selectionReading?.selectedIDs(for: workflowID) ?? []
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

        for tab in ThreeOmegaWorkbenchTab.visibleTabs {
            if tab == .temperatureDependence {
                continue
            }
            let seriesOrder: [String]?
            switch tab {
            case .fieldSweep1omega, .fieldSweep3omega:
                seriesOrder = Self.rendererSeriesOrder(fromVisualOrder: sharedFieldSweepSeriesOrder)
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
            if let rawPayload, rawPayload.seriesReorderable {
                let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: rawPayload.series)
                if Set(identities.map(\.identityKey)).count != identities.count {
                    let message = "Reorderable \(tab.stableKey) manifest payload has duplicate series identity keys."
                    assertionFailure(message)
                    appendWarning(source: "Manifest", message: message)
                }
            }
            var existing = tabs.tabOutputs[tab] ?? TabRenderOutput()
            existing.manifestPayload = rawPayload
            tabs.setOutput(existing, for: tab)
        }
    }


    private func _temperatureLabel(_ temperatureK: Double) -> String {
        "\(Int(temperatureK.rounded())) K"
    }
}
