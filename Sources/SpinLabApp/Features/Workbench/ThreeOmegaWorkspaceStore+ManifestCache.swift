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
            let sourceRef = index < inputFiles.count ? inputFiles[index] : nil
            return WorkbenchPlotSeries(
                label: sweep.sampleID ?? sourceRef.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "",
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
        inputFiles: [String],
        fieldSweeps: [ThreeOmegaFieldSweepResult],
        rtFilePath: String?,
        titleTemplate: String,
        titleTokens: [String: String],
        v3Method: ThreeOmegaV3Method
    ) -> WorkbenchPlotPayload? {
        let methodTag = v3Method == .highField ? "HFE" : "WA"

        func resolveTitle(_ tabName: String) -> String {
            var tokens = titleTokens
            tokens["tab"] = tabName
            tokens["device"] = device
            var result = titleTemplate
            for (key, value) in tokens {
                result = result.replacingOccurrences(of: "#\(key)", with: value)
            }
            result = result.replacingOccurrences(of: "#\\S+", with: "", options: .regularExpression)
            return result.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }

        func makePayload(title: String, xField: String, yField: String, files: [String], extraParams: [String: String] = [:]) -> WorkbenchPlotPayload {
            var params: [String: String] = ["device": device, "tabKey": tab.stableKey]
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
            return WorkbenchPlotPayload(
                workflowID: "3w",
                workflowDisplayName: "3w",
                title: resolveTitle("R(1ω)"),
                axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R(1ω) (Ω)"),
                series: _projectFieldSweepSeries(sweeps: fieldSweeps, inputFiles: inputFiles, yValues: \.r1omega),
                semanticParams: ["device": device, "tabKey": tab.stableKey]
            )
        case .fieldSweep3omega:
            return WorkbenchPlotPayload(
                workflowID: "3w",
                workflowDisplayName: "3w",
                title: resolveTitle("R(3ω)"),
                axisMapping: WorkbenchAxisMapping(xField: "H (T)", yField: "R(3ω) (Ω)"),
                series: _projectFieldSweepSeries(sweeps: fieldSweeps, inputFiles: inputFiles, yValues: \.r3omega),
                semanticParams: ["device": device, "tabKey": tab.stableKey]
            )
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


    /// Caches manifest payloads for all tabs after analysis completes.
    /// Snapshots sampleKeys, conditions, inputFiles from the current selection.
    /// Called once after runAnalysis completes; scaling re-runs call `_refreshManifestPayloads()` instead.
    func _snapshotAndCacheManifestPayloads() {
        let selectedHits = cachedSearchResults.filter { selectedSearchResultIDs.contains($0.id) }
            .sorted(by: { $0.measurementFilePath < $1.measurementFilePath })

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


    /// Rebuilds manifest payloads from cached (frozen) inputFiles/sampleKeys.
    /// Safe to call after scaling reruns — does NOT re-read UI selection.
    func _refreshManifestPayloads() {
        let device = ingestionResult?.device ?? ""

        for tab in ThreeOmegaWorkbenchTab.allCases {
            let payload = _buildManifestPayload(
                tab: tab,
                device: device,
                inputFiles: cachedInputFiles,
                fieldSweeps: ingestionResult?.fieldSweeps ?? [],
                rtFilePath: cachedRTFilePath,
                titleTemplate: titleTemplate,
                titleTokens: _titleTokens,
                v3Method: v3Method
            )
            if let payload, payload.seriesReorderable, payload.series.contains(where: { $0.sampleID == nil }) {
                let message = "Reorderable \(tab.stableKey) manifest payload missing sampleID."
                assertionFailure(message)
                appendWarning(source: "Manifest", message: message)
            }
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

        for tab in [ThreeOmegaWorkbenchTab.rahe1omegaVsT, .rahe3omegaVsT] {
            let isR1 = tab == .rahe1omegaVsT
            let method = isR1 ? rahe1omegaMethod : rahe3omegaMethod
            let methodTag = method == .highField ? "HFE" : "WA"
            let hLabel = isR1 ? "1ω" : "3ω"

            let series = allFiles.map {
                WorkbenchPlotSeries(label: URL(fileURLWithPath: $0).lastPathComponent, x: [], y: [], sourceRef: $0)
            }
            let params: [String: String] = ["device": device, "tabKey": tab.stableKey, "v3method": methodTag]
            let title = WorkbenchTitleResolver.resolve(
                template: titleTemplate,
                tokens: _titleTokens.merging(["tab": "RAHE(\(hLabel))", "device": device]) { _, new in new }
            ) + " (\(methodTag))"

            var existing = tabs.tabOutputs[tab] ?? TabRenderOutput()
            existing.manifestPayload = WorkbenchPlotPayload(
                workflowID: "3w",
                workflowDisplayName: "3w",
                title: title,
                axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "RAHE(\(hLabel)) (Ω)"),
                series: series,
                semanticParams: params
            )
            tabs.tabOutputs[tab] = existing
        }
    }
}
