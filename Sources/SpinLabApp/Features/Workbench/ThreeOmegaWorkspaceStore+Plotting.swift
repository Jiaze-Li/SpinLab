import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    // MARK: - Series order management

    func updateSeriesOrder(_ order: [String]) {
        // Order keys use the shared Plot System resolver; legacy sampleID tokens are only tolerated during alignment.
        let normalized = order.map { Self.bareFieldSweepSourceRefToken($0, workflowID: workflowID) }
        let nextOrder = normalized.isEmpty ? nil : normalized

        guard fieldSweepSeriesOrder != nextOrder else { return }

        setFieldSweepSeriesOrder(nextOrder)
        _refreshManifestPayloads()
    }

    /// Strips the `workflowID:tabKey:seriesRole:sourceRef` composite prefix that
    /// `WorkbenchSeriesOrderKeyResolver` embeds in a field-sweep series' identityKey,
    /// leaving the bare sourceRef.
    ///
    /// `fieldSweepSeriesOrder` is shared verbatim between the 1ω and 3ω field-sweep
    /// tabs (`setFieldSweepSeriesOrder`), but each tab renders its series under a
    /// different tabKey (`r1omega-vs-h` vs `r3omega-vs-h`). A composite identityKey
    /// committed from one tab's reorder panel — e.g. `WorkbenchSeriesOrderPanel`'s
    /// `rows.map(\.identityKey)` — therefore never matches the other tab's own
    /// identityKeys, and the other tab silently falls back to its default order.
    /// The bare sourceRef has no tab prefix, so it matches via the resolver's
    /// `bySourceRef` fallback in both tabs. Tokens that are already bare (or that
    /// don't match this workflow's field-sweep tabKeys) pass through unchanged.
    nonisolated static func bareFieldSweepSourceRefToken(_ token: String, workflowID: String) -> String {
        let fieldSweepTabKeys: Set<Substring> = [
            Substring(WorkbenchPlotSeriesIdentityTabKey.threeOmegaR1omegaVsH),
            Substring(WorkbenchPlotSeriesIdentityTabKey.threeOmegaR3omegaVsH)
        ]
        let parts = token.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts[0] == Substring(workflowID),
              fieldSweepTabKeys.contains(parts[1])
        else {
            return token
        }
        return String(parts[3])
    }


    func resetSeriesOrder() {
        setFieldSweepSeriesOrder(nil)
        _rerenderActiveTab()
        _refreshManifestPayloads()
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
    }

    func updateSeriesVisibility(identityKey: String, isVisible: Bool) {
        tabs.updateSeriesVisibility(identityKey: identityKey, isVisible: isVisible)
    }

    func updateAxisBound(_ bound: AxisRangeBound, value: Double?) {
        guard tabs.updateAxisBound(bound, value: value) else { return }
        _rerenderActiveTab()
    }

    /// Atomically clears all four axis-range bounds for the active tab.
    func resetAxisRanges() {
        guard tabs.resetAxisRangeOverride() else { return }
        _rerenderActiveTab()
    }

    func updateTickCount(axis: PlotTickAxis, count: Int) {
        guard tabs.updateTickCount(axis: axis, count: count) else { return }
        _rerenderActiveTab()
    }


    func togglePointLabelVisibility(sampleID: String, pointIndex: Int) {
        tabs.togglePointLabelVisibility(sampleID: sampleID, pointIndex: pointIndex)
        rerenderForStyleChange()
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

            entries.append(PendingMetricEntry(sampleKey: sampleKey, metric: "alpha", value: seg.alpha * ThreeOmegaDisplayScale.scalingLawFitSlope.scaleFactor, canonicalUnit: "Ω·μm³·cm²·V⁻²·S⁻²", conditions: segConditions))
            entries.append(PendingMetricEntry(sampleKey: sampleKey, metric: "beta", value: seg.beta * ThreeOmegaDisplayScale.scalingLawY.scaleFactor, canonicalUnit: "Ω·μm³·V⁻²", conditions: segConditions))
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
        // Reuse the axis mapping actually rendered for the active tab, rather than
        // hardcoding a field-sweep-shaped mapping — Scaling/RAHE-vs-Device tabs don't
        // plot H in Oe. Falls back to the legacy field-sweep labels only when no
        // manifest payload is available yet (matches the AHE buildRunTrace pattern).
        let axisMapping = activeChartManifestPayload?.axisMapping
            ?? WorkbenchAxisMapping(xField: "H (Oe)", yField: "R (Ω)")
        return WorkbenchRunTraceProjection(
            runID: UUID().uuidString,
            workflowID: workflowID,
            inputFiles: cachedInputFiles,
            axisMapping: axisMapping,
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
