import CoreGraphics
import Foundation

/// Unified render pipeline for all Workbench workflows.
///
/// Encapsulates the common sequence: display overrides → style merge → resolve options →
/// compute layout → apply series label overrides → render PNG.
///
/// Each workflow only needs to build a `WorkbenchPlotPayload` from its domain data,
/// then call `WorkbenchRenderPipeline.render(_:)` to get a PNG + layout.
enum WorkbenchRenderPipeline {

    struct Input: Sendable {
        /// Payload constructed by the workflow (raw data + initial styleParams).
        var payload: WorkbenchPlotPayload
        /// Base renderer options (canvas size, fixed axis range, etc.).
        var baseOptions: WorkbenchChartRenderer.Options = .init()
        /// Normalized legend position (nil = use anchor mode).
        var legendPoint: CGPoint?

        // ── Shell-level overrides (same for all workflows) ──────────

        /// Global series render mode override.
        var seriesRenderMode: SeriesRenderMode = .line
        /// Chart style key-value overrides (font sizes, tick density, etc.).
        var chartStyleOverrides: [String: String] = [:]
        /// Per-series display label overrides keyed by series index.
        var seriesLabelOverrides: [Int: String] = [:]

        // ── Display-only overrides ──────────────────────────────────

        /// Override chart title text. Empty = use payload title.
        var titleOverride: String = ""
        /// Override x-axis display label. Empty = use payload axisMapping.xField.
        var xLabelOverride: String = ""
        /// Override y-axis display label. Empty = use payload axisMapping.yField.
        var yLabelOverride: String = ""
        /// Additional styleParams patches (showGrid, legendAnchor, auxVerticalX, etc.).
        var styleParamsPatch: [String: String] = [:]
    }

    struct Output: Sendable {
        /// Rendered chart image as PNG data.
        let imageData: Data
        /// Layout with hit rects, plotRect, and rendererSize for canvas interaction.
        let layout: WorkbenchPlotLayout
        /// Final payload after all overrides — axisMapping restored to original data columns
        /// (display overrides do not leak into manifest/persistence).
        let manifestPayload: WorkbenchPlotPayload
    }

    /// Executes the full render pipeline. Throws on renderer failure.
    static func render(_ input: Input) throws -> Output {
        var payload = input.payload

        // 1. Preserve original data-column axis mapping for manifest
        let originalAxisMapping = payload.axisMapping

        // 2. Apply styleParams patches (grid, legendAnchor, auxVerticalX, legend position)
        for (k, v) in input.styleParamsPatch {
            payload.styleParams[k] = v
        }
        if let pt = input.legendPoint {
            payload.styleParams["legendX"] = "\(pt.x)"
            payload.styleParams["legendY"] = "\(pt.y)"
        }

        // 3. Apply display-only overrides (title, axis labels)
        if !input.titleOverride.isEmpty { payload.title = input.titleOverride }
        if !input.xLabelOverride.isEmpty { payload.axisMapping.xField = input.xLabelOverride }
        if !input.yLabelOverride.isEmpty { payload.axisMapping.yField = input.yLabelOverride }

        // 4. Apply render mode to all series
        payload.series = payload.series.map {
            var s = $0; s.renderMode = input.seriesRenderMode; return s
        }

        // 5. Merge chart style overrides into styleParams
        for (k, v) in input.chartStyleOverrides {
            payload.styleParams[k] = v
        }

        // 6. Parse unified chart style
        let chartStyle = WorkbenchChartStyle.from(styleParams: payload.styleParams)

        // 7. Resolve renderer options (dynamic padding based on y-tick label widths)
        let renderer = WorkbenchChartRenderer()
        let opts = renderer.resolvedOptions(payload: payload, base: input.baseOptions, style: chartStyle)

        // 8. Compute layout BEFORE series label overrides (legendRow.originalLabel must be stable)
        let layout = WorkbenchPlotLayout.compute(
            options: opts, payload: payload, legendPoint: input.legendPoint, style: chartStyle
        )

        // 9. Apply series label overrides
        if !input.seriesLabelOverrides.isEmpty {
            payload.series = payload.series.enumerated().map { i, s in
                guard let custom = input.seriesLabelOverrides[i] else { return s }
                var copy = s; copy.label = custom; return copy
            }
        }

        // 10. Render PNG
        let imageData = try renderer.renderPNG(payload: payload, options: opts, style: chartStyle)

        // 11. Build manifest payload with original data-column axis mapping
        var manifestPayload = payload
        manifestPayload.axisMapping = originalAxisMapping

        return Output(imageData: imageData, layout: layout, manifestPayload: manifestPayload)
    }
}
