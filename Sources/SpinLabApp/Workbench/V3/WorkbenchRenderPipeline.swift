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
        /// Per-series hidden point-label indices for render-time label suppression.
        var hiddenPointLabelsBySeries: [Int: Set<Int>] = [:]
        /// Additional styleParams patches (showGrid, legendAnchor, auxVerticalX, etc.).
        var styleParamsPatch: [String: String] = [:]
        /// Pixel density override for export at a non-default scale (nil = use baseOptions.pixelScale).
        var pixelScaleOverride: CGFloat? = nil
        /// Expected bottom-to-top series order by sampleID (v5.3.6). Used for mismatch detection only —
        /// the pipeline never reorders; reordering must happen in the workflow renderer before this call.
        var seriesOrder: [String]? = nil
    }

    struct Output: Sendable {
        /// Rendered chart image as PNG data.
        let imageData: Data
        /// Layout with hit rects, plotRect, and rendererSize for canvas interaction.
        let layout: WorkbenchPlotLayout
        /// Final payload after all overrides — axisMapping restored to original data columns
        /// (display overrides do not leak into manifest/persistence).
        let manifestPayload: WorkbenchPlotPayload
        /// Warnings generated during the render pipeline (e.g. legend dimension ambiguity).
        let warnings: [String]
    }

    /// Executes the full render pipeline. Throws on renderer failure.
    static func render(_ input: Input) throws -> Output {
        var payload = input.payload
        var pipelineWarnings: [String] = []

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

        // 4. Apply render mode to unlocked series (locked series keep their own mode)
        payload.series = payload.series.map {
            guard !$0.renderModeLocked else { return $0 }
            var s = $0; s.renderMode = input.seriesRenderMode; return s
        }

        // 4a. Series order consistency check (v5.3.6):
        //     If the payload opts in to drag reordering and a seriesOrder was provided,
        //     verify the renderer already produced series in the expected order.
        //     The pipeline NEVER reorders — mismatch means the renderer has a bug.
        if payload.seriesReorderable, let expectedOrder = input.seriesOrder {
            if let warning = Self.detectSeriesOrderMismatch(payload.series, expected: expectedOrder) {
                pipelineWarnings.append(warning)
            }
        }

        // 4b. Reverse series for legend-visual consistency (v5.3.4):
        //     Stacked curves are built bottom-to-top (index 0 = lowest offset).
        //     Reversing makes index 0 = highest offset = legend top = visual top.
        if payload.reverseSeriesForLegend, payload.series.count > 1 {
            payload.series.reverse()
        }

        // 4c. Auto-resolve legend dimension from series metadata (v5.3.4):
        //     When legendDimension is not pre-set and series carry metadata,
        //     run LegendDimensionResolver to infer the distinguishing dimension
        //     and update series labels accordingly.
        if payload.legendDimension == nil, payload.series.count > 1 {
            let seriesMeta = payload.series.map(\.metadata)
            let hasMetadata = seriesMeta.contains { !$0.isEmpty }
            if hasMetadata {
                let resolver = LegendDimensionResolver(chain: LegendDimensionResolver.defaultChain)
                let result = resolver.resolve(seriesMetadata: seriesMeta)
                switch result {
                case .resolved(let dim, let values):
                    payload.legendDimension = dim.displayName
                    for i in payload.series.indices {
                        if !values[i].isEmpty {
                            payload.series[i].label = values[i]
                        }
                    }
                case .ambiguous(let dims):
                    let names = dims.map(\.displayName).joined(separator: " / ")
                    payload.legendDimension = "⚠ " + names
                    pipelineWarnings.append("Legend: multiple dimensions vary at the same priority (\(names)). Select legend manually.")
                case .indeterminate:
                    payload.legendDimension = "⚠ No distinguishing dimension"
                    pipelineWarnings.append("Legend: no distinguishing dimension found across selected samples.")
                }
            }
        }

        // 5. Merge chart style overrides into styleParams
        for (k, v) in input.chartStyleOverrides {
            payload.styleParams[k] = v
        }

        // 6. Parse unified chart style
        let chartStyle = WorkbenchChartStyle.from(styleParams: payload.styleParams)

        // 7. Resolve renderer options (dynamic padding based on y-tick label widths)
        let renderer = WorkbenchChartRenderer()
        var effectiveBase = input.baseOptions
        if let scale = input.pixelScaleOverride { effectiveBase.pixelScale = scale }
        let opts = renderer.resolvedOptions(payload: payload, base: effectiveBase, style: chartStyle)

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
        var optsWithHidden = opts
        optsWithHidden.hiddenPointLabelsBySeries = input.hiddenPointLabelsBySeries
        let imageData = try renderer.renderPNG(payload: payload, options: optsWithHidden, style: chartStyle)

        // 11. Build manifest payload with original data-column axis mapping
        var manifestPayload = payload
        manifestPayload.axisMapping = originalAxisMapping

        // 12. Attach pipeline warnings to semanticParams for store extraction (v5.3.4).
        if !pipelineWarnings.isEmpty {
            manifestPayload.semanticParams["_pipelineWarnings"] = pipelineWarnings.joined(separator: ";;")
        }

        return Output(imageData: imageData, layout: layout, manifestPayload: manifestPayload, warnings: pipelineWarnings)
    }

    // MARK: - Private helpers

    /// Returns a warning string if `series` sampleID order (filtered to those in `expected`)
    /// does not match `expected` order (filtered to those in `series`). Returns nil when consistent.
    static func detectSeriesOrderMismatch(_ series: [WorkbenchPlotSeries], expected: [String]) -> String? {
        let actual = series.compactMap(\.sampleID)
        let expectedFiltered = expected.filter { id in actual.contains(id) }
        let actualFiltered = actual.filter { id in expected.contains(id) }
        guard expectedFiltered != actualFiltered else { return nil }
        return "seriesOrder mismatch: renderer produced \(actualFiltered) but expected \(expectedFiltered). " +
               "Stack offsets are likely incorrect — fix the renderer to honor input.seriesOrder."
    }
}
