import Foundation

/// Errors thrown by the heatmap render pipeline during input validation.
enum HeatmapRenderError: Error, LocalizedError, Sendable {
    /// zRangeClampMin must be strictly less than zRangeClampMax.
    case invalidZRangeClamp(min: Double, max: Double)

    var errorDescription: String? {
        switch self {
        case .invalidZRangeClamp(let lo, let hi):
            return "Invalid Z-range clamp: min (\(lo)) must be strictly less than max (\(hi))."
        }
    }
}

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

        // Validate Z-range clamp before rendering. Partial clamps (only one bound set)
        // are silently ignored — the layout falls back to the data min/max in that case.
        if let lo = payload.zRangeClampMin, let hi = payload.zRangeClampMax {
            guard lo < hi else {
                throw HeatmapRenderError.invalidZRangeClamp(min: lo, max: hi)
            }
        }

        if !input.titleOverride.isEmpty  { payload.title  = input.titleOverride  }
        if !input.xLabelOverride.isEmpty { payload.xLabel = input.xLabelOverride }
        if !input.yLabelOverride.isEmpty { payload.yLabel = input.yLabelOverride }
        if !input.zLabelOverride.isEmpty { payload.zLabel = input.zLabelOverride }

        let layout    = HeatmapPlotLayout.compute(payload: payload, options: input.options, colorScaleMode: input.colorScaleMode)
        let imageData = try HeatmapRenderer().renderPNG(
            payload:        payload,
            colorScaleMode: input.colorScaleMode,
            options:        input.options
        )

        return Output(imageData: imageData, layout: layout)
    }
}
