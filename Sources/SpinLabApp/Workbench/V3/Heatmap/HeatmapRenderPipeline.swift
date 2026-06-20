import Foundation

/// Heatmap render path orchestrator (Plot System-owned).
/// Parallel to WorkbenchRenderPipeline; does not call or extend it.
/// Applies display overrides then delegates to HeatmapRenderer.
enum HeatmapRenderPipeline {

    struct Input: Sendable {
        var payload: HeatmapPlotPayload
        var colorScaleMode: HeatmapColorScaleMode = .linear
        var options: HeatmapPlotLayout.Options = .init()
        /// Override chart title. Empty = use payload title.
        var titleOverride: String = ""
        /// Override X-axis label. Empty = use payload xLabel.
        var xLabelOverride: String = ""
        /// Override Y-axis label. Empty = use payload yLabel.
        var yLabelOverride: String = ""
        /// Override colorbar label. Empty = use payload zLabel.
        var zLabelOverride: String = ""
    }

    struct Output: Sendable {
        let imageData: Data
        let layout: HeatmapPlotLayout
    }

    static func render(_ input: Input) throws -> Output {
        var payload = input.payload

        if !input.titleOverride.isEmpty  { payload.title  = input.titleOverride  }
        if !input.xLabelOverride.isEmpty { payload.xLabel = input.xLabelOverride }
        if !input.yLabelOverride.isEmpty { payload.yLabel = input.yLabelOverride }
        if !input.zLabelOverride.isEmpty { payload.zLabel = input.zLabelOverride }

        let layout    = HeatmapPlotLayout.compute(payload: payload, options: input.options)
        let imageData = try HeatmapRenderer().renderPNG(
            payload:        payload,
            colorScaleMode: input.colorScaleMode,
            options:        input.options
        )

        return Output(imageData: imageData, layout: layout)
    }
}
