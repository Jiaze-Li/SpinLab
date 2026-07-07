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
        var colorScaleMode: PlotScaleTransform = .linear
        var zDomainState: HeatmapZDomainState = .init()
        var options: HeatmapPlotLayout.Options = .init()
        /// Shared text styling defaults used by heatmap labels and tick marks.
        var chartStyle: WorkbenchChartStyle = .init()
        /// Override chart title. Empty = use payload title.
        var titleOverride: String = ""
        /// Override X-axis label. Empty = use payload xLabel.
        var xLabelOverride: String = ""
        /// Override Y-axis label. Empty = use payload yLabel.
        var yLabelOverride: String = ""
        /// Override colorbar label. Empty = use payload zLabel.
        var zLabelOverride: String = ""
        /// Whether the colorbar block (gradient, tick labels, Z title) should be rendered.
        var showColorbar: Bool = true
        /// Target X-axis tick count. Clamped to 2…20 in Options.
        var xTickCount: Int = 5
        /// Target Y-axis tick count. Clamped to 2…20 in Options.
        var yTickCount: Int = 5
        /// Display interpolation mode. Defaults to nearest for all workflows, including RSM —
        /// gaussianUpsample2x must be opted into explicitly (it broadens sharp features like
        /// Bragg peaks, though less aggressively than plain bilinear).
        /// Display-only: never applied to stored scientific data.
        var interpolationMode: HeatmapInterpolationMode = .nearest
    }

    struct Output: Sendable {
        let imageData: Data
        let layout: HeatmapPlotLayout
    }

    static func render(_ input: Input) throws -> Output {
        var payload = input.payload
        let rawZValues = payload.grid.zMatrix.flatMap { $0 }

        switch input.zDomainState.resolve(rawValues: rawZValues) {
        case .resolved(let lowerBound, let upperBound):
            payload.zRangeClampMin = lowerBound
            payload.zRangeClampMax = upperBound
        case .fallbackToAuto:
            payload.zRangeClampMin = nil
            payload.zRangeClampMax = nil
        }

        // Validate Z-range clamp before rendering.
        if let lo = payload.zRangeClampMin, let hi = payload.zRangeClampMax {
            guard lo < hi else {
                throw HeatmapRenderError.invalidZRangeClamp(min: lo, max: hi)
            }
        }

        if !input.titleOverride.isEmpty  { payload.title  = input.titleOverride  }
        if !input.xLabelOverride.isEmpty { payload.xLabel = input.xLabelOverride }
        if !input.yLabelOverride.isEmpty { payload.yLabel = input.yLabelOverride }
        if !input.zLabelOverride.isEmpty { payload.zLabel = input.zLabelOverride }

        // Display-only interpolation. Computed from the raw grid above; never mutates
        // stored scientific data. Nearest by default for all workflows — gaussianUpsample2x
        // is an explicit opt-in via input.interpolationMode.
        switch input.interpolationMode {
        case .nearest:
            break
        case .gaussianUpsample2x:
            let smoothed = HeatmapGridInterpolator.gaussianSmooth(payload.grid, sigma: 0.35)
            payload.grid = HeatmapGridInterpolator.bilinear(smoothed, scale: 2)
        }

        var options = input.options
        options.tickConfiguration = PlotTickConfiguration(xTargetCount: input.xTickCount, yTargetCount: input.yTickCount)

        let layout = HeatmapPlotLayout.compute(
            payload: payload,
            options: options,
            colorScaleMode: input.colorScaleMode,
            chartStyle: input.chartStyle,
            showColorbar: input.showColorbar
        )
        let imageData = try HeatmapRenderer().renderPNG(
            payload:        payload,
            colorScaleMode: input.colorScaleMode,
            options:        options,
            showColorbar:   input.showColorbar,
            chartStyle:     input.chartStyle
        )

        return Output(imageData: imageData, layout: layout)
    }
}
