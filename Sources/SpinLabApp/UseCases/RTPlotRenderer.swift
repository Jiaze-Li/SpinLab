import Foundation

// MARK: - RTPlotRenderer
//
// Converts [RTAnalysisResult] into a WorkbenchPlotPayload (one series per result)
// and renders it to PNG Data + WorkbenchPlotLayout using WorkbenchRenderPipeline.
//
// Caller is responsible for applying TabRenderState overrides via
// TabRenderManager.buildPipelineInput() before calling WorkbenchRenderPipeline.render().

struct RTPlotRenderer {

    var titleTemplate: String = "#tab #device #sample"
    var titleTokens: [String: String] = [:]

    // MARK: - Payload construction

    /// Builds a WorkbenchPlotPayload from non-empty RT results.
    /// Returns nil when all results are empty (nothing to plot).
    func makePayload(results: [RTAnalysisResult]) -> WorkbenchPlotPayload? {
        let nonEmpty = results.filter { !$0.temperatureK.isEmpty && !$0.rxx.isEmpty }
        guard !nonEmpty.isEmpty else { return nil }

        let device = nonEmpty.first?.device ?? ""
        let title = _resolveTitle(device: device)

        let series: [WorkbenchPlotSeries] = nonEmpty.map { result in
            WorkbenchPlotSeries(
                label: _seriesLabel(result),
                x: result.temperatureK,
                y: result.rxx,
                sourceRef: result.sourceFilePath,
                sampleID: result.sampleID ?? result.sampleKey,
                metadata: result.sampleMetadata ?? [:]
            )
        }

        var semanticParams: [String: String] = ["tabKey": RTWorkbenchTab.rtCurve.stableKey]
        if !device.isEmpty { semanticParams["device"] = device }

        return WorkbenchPlotPayload(
            workflowID: WorkflowKey.rt.rawValue,
            workflowDisplayName: "RT",
            title: title,
            axisMapping: WorkbenchAxisMapping(xField: "T (K)", yField: "Rxx (Ω)"),
            series: series,
            semanticParams: semanticParams
        )
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
