import Foundation

/// Decides, per Sample, whether an AHE run produced exactly one trustworthy curve whose Hc / R_AHE may be
/// offered for Sample Result assignment (Task 12, design §3). Pure: it never changes the extraction
/// algorithm; it only inspects the final background-corrected series and the selections that fed them.
struct BuildAHEResultCandidatesUseCase {

    /// - Parameters:
    ///   - selections: the selections of this run (their conditions/source are what the curves came from).
    ///   - correctedSeries: the final background-corrected series, as handed to the metric extractor.
    ///   - metrics: the extractor output for those series.
    func execute(
        selections: [AHEPlotSelectionItem],
        correctedSeries: [WorkbenchPlotSeries],
        metrics: [String: AHEExtractedMetric]
    ) -> [String: AHECandidateAvailability] {
        var verdicts: [String: AHECandidateAvailability] = [:]
        let sampleKeys = Set(correctedSeries.compactMap(\.sampleID))
        for key in sampleKeys {
            let curves = correctedSeries.filter { $0.sampleID == key }
            guard curves.count == 1, let curve = curves.first else {
                verdicts[key] = .unavailable(
                    reason: "This sample has \(curves.count) curves, so it is unclear which one to use. Select a single measurement and Analyze again."
                )
                continue
            }
            guard curve.x.count >= 2, curve.x.count == curve.y.count else {
                verdicts[key] = .unavailable(reason: "Too few data points for a trustworthy Hc / R_AHE.")
                continue
            }
            guard let metric = metrics[key], metric.hc.isFinite, metric.rAHE.isFinite else {
                verdicts[key] = .unavailable(reason: "No finite Hc / R_AHE result was obtained.")
                continue
            }
            guard let selection = uniqueSelection(for: curve, key: key, in: selections) else {
                verdicts[key] = .unavailable(reason: "The input behind this curve cannot be identified uniquely, so it cannot be assigned.")
                continue
            }
            let fileName = URL(fileURLWithPath: selection.sourceFilePath).lastPathComponent
            verdicts[key] = .available(AHECandidateBase(
                sourceSampleKey: key,
                sourceBatchID: selection.batchID,
                inputSummary: "\(fileName) · \(selection.channel.rawValue)",
                conditions: selection.conditions,
                hc: metric.hc,
                rAHE: metric.rAHE
            ))
        }
        return verdicts
    }

    /// The single selection that produced `curve`: same sample, same file, same channel-derived series
    /// identity and (when the curve carries one) the same originating hit. Zero or several matches → nil.
    private func uniqueSelection(
        for curve: WorkbenchPlotSeries,
        key: String,
        in selections: [AHEPlotSelectionItem]
    ) -> AHEPlotSelectionItem? {
        guard let sourceRef = curve.sourceRef else { return nil }
        let identity = curve.metadata[WorkbenchSeriesOrderKeyResolver.seriesIdentityMetadataKey]
        let hitID = curve.metadata[WorkbenchSeriesOrderKeyResolver.sourceHitIDMetadataKey]
        let matches = selections.filter { selection in
            guard selection.sampleKey == key, selection.sourceFilePath == sourceRef else { return false }
            if let identity, Self.seriesIdentityKey(for: selection) != identity { return false }
            if let hitID, selection.hitID != hitID { return false }
            return true
        }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Mirrors the key `IngestAHESelectionsUseCase` stamps on each series.
    static func seriesIdentityKey(for selection: AHEPlotSelectionItem) -> String {
        WorkbenchSeriesIdentityMetadata.seriesIdentityKey(
            workflowID: selection.workflowID,
            tabKey: WorkbenchPlotSeriesIdentityTabKey.ahe,
            seriesRole: "channel-\(selection.channel.bridgeIndex)",
            stableSemanticID: selection.sourceFilePath
        )
    }
}
