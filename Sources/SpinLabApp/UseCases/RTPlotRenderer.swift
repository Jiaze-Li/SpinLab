import Foundation

// MARK: - RTPlotRenderer
//
// Converts [RTAnalysisResult] into a WorkbenchPlotPayload (one series per result)
// and renders it to PNG Data + WorkbenchPlotLayout using WorkbenchRenderPipeline.
//
// Caller is responsible for applying TabRenderState overrides via
// TabRenderManager.buildPipelineInput() before calling WorkbenchRenderPipeline.render().

struct RTPlotRenderer {

    var workflowID: String = WorkflowKey.rt.rawValue
    var titleTemplate: String = "#tab #device #sample"
    var titleTokens: [String: String] = [:]

    struct RTPayloads {
        let manifestPayload: WorkbenchPlotPayload
        let displayPayload: WorkbenchPlotPayload
    }

    // MARK: - Payload construction

    /// Builds the manifest-facing WorkbenchPlotPayload (plain-text axis labels) from
    /// non-empty RT results. Returns nil when all results are empty (nothing to plot).
    func makePayload(results: [RTAnalysisResult]) -> WorkbenchPlotPayload? {
        makePayloads(results: results)?.manifestPayload
    }

    /// Builds both the manifest payload (plain-text axis labels, for persistence/run-trace)
    /// and the display payload (math-markup axis labels, for the rendered chart) from
    /// non-empty RT results. Returns nil when all results are empty (nothing to plot).
    func makePayloads(results: [RTAnalysisResult]) -> RTPayloads? {
        let nonEmpty = results.filter { !$0.temperatureK.isEmpty && !$0.rxx.isEmpty }
        guard !nonEmpty.isEmpty else { return nil }

        let device = nonEmpty.first?.device ?? ""
        let title = _resolveTitle(device: device)

        let series: [WorkbenchPlotSeries] = nonEmpty.map { result in
            let stableSemanticID = WorkbenchSeriesIdentityMetadata.stableSemanticID(
                sourceRef: result.sourceFilePath,
                sampleID: result.sampleID ?? result.sampleKey,
                fallback: result.channelID
            ) ?? result.sourceFilePath
            return WorkbenchPlotSeries(
                label: _seriesLabel(result),
                x: result.temperatureK,
                y: result.rxx,
                sourceRef: result.sourceFilePath,
                sampleID: result.sampleID ?? result.sampleKey,
                metadata: WorkbenchSeriesIdentityMetadata.metadata(
                    base: result.sampleMetadata ?? [:],
                    seriesIdentityKey: WorkbenchSeriesIdentityMetadata.seriesIdentityKey(
                        workflowID: workflowID,
                        tabKey: WorkbenchPlotSeriesIdentityTabKey.threeOmegaRT,
                        seriesRole: "series",
                        stableSemanticID: stableSemanticID
                    )
                )
            )
        }

        var semanticParams: [String: String] = ["tabKey": RTWorkbenchTab.rtCurve.stableKey]
        if !device.isEmpty { semanticParams["device"] = device }

        let manifestPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "RT",
            title: title,
            axisMapping: WorkbenchAxisMapping(
                xField: WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .temperature),
                yField: WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .rxx)
            ),
            series: series,
            semanticParams: semanticParams
        )
        let displayPayload = WorkbenchPlotPayload(
            workflowID: workflowID,
            workflowDisplayName: "RT",
            title: title,
            axisMapping: WorkbenchAxisMapping(
                xField: WorkbenchPlotDisplayVocabulary.plotLabel(for: .temperature),
                yField: WorkbenchPlotDisplayVocabulary.plotLabel(for: .rxx)
            ),
            series: series,
            semanticParams: semanticParams
        )
        return RTPayloads(manifestPayload: manifestPayload, displayPayload: displayPayload)
    }

    // MARK: - Private helpers

    private func _seriesLabel(_ result: RTAnalysisResult) -> String {
        let base = result.sampleID ?? result.sampleKey
        if let ch = result.channelID, !ch.isEmpty {
            return "\(base) (\(ch))"
        }
        return base
    }

    private func _resolveTitle(device: String) -> String {
        var tokens = titleTokens
        tokens["tab"] = "RT"
        if !device.isEmpty { tokens["device"] = device }
        return WorkbenchTitleResolver.resolve(template: titleTemplate, tokens: tokens)
    }
}
