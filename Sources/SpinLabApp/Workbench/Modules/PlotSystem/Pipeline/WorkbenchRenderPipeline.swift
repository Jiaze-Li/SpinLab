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

        /// Shared plot defaults across workflows.
        var globalPlotDefaults: [String: String] = [:]
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
        /// Stable series keys hidden from display. Rendering/filtering is wired in a later commit.
        var hiddenSeriesKeys: [String] = []
        /// Additional styleParams patches (showGrid, legendAnchor, auxVerticalX, etc.).
        var styleParamsPatch: [String: String] = [:]
        /// Pixel density override for export at a non-default scale (nil = use baseOptions.pixelScale).
        var pixelScaleOverride: CGFloat? = nil
        /// Expected bottom-to-top series order keys. Used for mismatch detection only —
        /// the pipeline never reorders; reordering must happen in the workflow renderer before this call.
        var seriesOrder: [String]? = nil
        /// Per-tab axis range override. nil bounds fall back to auto-fit from data extents.
        var axisRangeOverride: AxisRangeOverride? = nil
        /// When false, all per-series pointLabels are stripped before rendering and hit-target
        /// generation, except payloads that explicitly opt into default-visible point tags.
        /// This allows workflow-owned scientific annotations, such as 3ω scaling temperatures,
        /// to remain visible by default while still preserving the global point-tag toggle path.
        var showPointTags: Bool = true
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

        // 1. Preserve original data-column axis mapping and title for manifest
        let originalAxisMapping = payload.axisMapping
        let originalTitle = payload.title

        // 2. Apply shared plot defaults and styleParams patches.
        for (k, v) in input.globalPlotDefaults {
            payload.styleParams[k] = v
        }
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

        // 4a. Strip point tags when the feature toggle is off, except for payloads that
        // explicitly carry scientific point labels intended to be visible by default.
        // The 3ω Scaling Law tab uses pointLabels for per-point temperature annotation.
        let hasPayloadPointLabels = payload.series.contains { !$0.pointLabels.isEmpty }
        let keepDefaultPointTags = payload.workflowID == "3w"
            && payload.title.contains("Scaling Law")
            && hasPayloadPointLabels
        if !input.showPointTags && !keepDefaultPointTags {
            payload.series = payload.series.map { var s = $0; s.pointLabels = []; return s }
        }

        // 4c. Series order consistency check (v5.3.6):
        //     Reorderable payloads must carry unique series identities so order keys stay
        //     attached to stable series identity instead of render geometry.
        if payload.seriesReorderable {
            let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: payload.series)
            assert(Set(identities.map(\.identityKey)).count == identities.count,
                   "seriesReorderable payloads require unique series identity keys")
        }
        //     If the payload opts in to drag reordering and a seriesOrder was provided,
        //     verify the renderer already produced series in the expected order.
        //     The pipeline NEVER reorders — mismatch means the renderer has a bug.
        if payload.seriesReorderable, let expectedOrder = input.seriesOrder {
            if let warning = Self.detectSeriesOrderMismatch(payload.series, expected: expectedOrder) {
                pipelineWarnings.append(warning)
            }
        }

        // 4d. Reverse series for legend-visual consistency (v5.3.4):
        //     Stacked curves are built bottom-to-top (index 0 = lowest offset).
        //     Reversing makes index 0 = highest offset = legend top = visual top.
        if payload.reverseSeriesForLegend, payload.series.count > 1 {
            payload.series.reverse()
        }

        // 4e. Auto-resolve legend dimension from series metadata (v5.3.4):
        //     When legendDimension is not pre-set and series carry metadata,
        //     run LegendDimensionResolver to infer the distinguishing dimension
        //     and update series labels accordingly.
        pipelineWarnings.append(contentsOf: Self.applyLegendDimensionResolution(to: &payload))

        // 5. Merge chart style overrides into styleParams
        for (k, v) in input.chartStyleOverrides {
            payload.styleParams[k] = v
        }

        // 6. Parse unified chart style
        let chartStyle = WorkbenchChartStyle.from(styleParams: payload.styleParams)

        // 6a. Apply global lineWidth override to unlocked series (locked series keep their own width)
        if let lw = chartStyle.lineWidth {
            payload.series = payload.series.map {
                guard !$0.renderModeLocked else { return $0 }
                var s = $0; s.lineWidth = lw; return s
            }
        }

        // 7. Resolve renderer options (dynamic padding based on y-tick label widths)
        let renderer = WorkbenchChartRenderer()
        var effectiveBase = input.baseOptions
        if let scale = input.pixelScaleOverride { effectiveBase.pixelScale = scale }
        // Apply per-tab axis range override to renderer options
        if let override = input.axisRangeOverride {
            if let v = override.xMin { effectiveBase.fixedXMin = v }
            if let v = override.xMax { effectiveBase.fixedXMax = v }
            if let v = override.yMin { effectiveBase.fixedYMin = v }
            if let v = override.yMax { effectiveBase.fixedYMax = v }
        }
        let opts = renderer.resolvedOptions(payload: payload, base: effectiveBase, style: chartStyle)

        // 8. Compute layout BEFORE series label overrides (legendRow.originalLabel must be stable).
        //    Pass label overrides so measuredLabelWidth reflects the display (renamed) label,
        //    keeping drag-preview geometry correct for long-renamed series.
        let layout = WorkbenchPlotLayout.compute(
            options: opts, payload: payload, legendPoint: input.legendPoint, style: chartStyle,
            seriesLabelOverrides: input.seriesLabelOverrides
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
        let imageData = try renderer.renderPNG(payload: payload, options: optsWithHidden, style: chartStyle, layout: layout)

        // 11. Build manifest payload with original data-column axis mapping and title
        var manifestPayload = payload
        manifestPayload.title = originalTitle
        manifestPayload.axisMapping = originalAxisMapping

        // 12. Attach pipeline warnings to semanticParams for store extraction (v5.3.4).
        if !pipelineWarnings.isEmpty {
            manifestPayload.semanticParams["_pipelineWarnings"] = pipelineWarnings.joined(separator: ";;")
        }

        return Output(imageData: imageData, layout: layout, manifestPayload: manifestPayload, warnings: pipelineWarnings)
    }

    // MARK: - Private helpers

    /// Applies metadata-driven legend label resolution in the same way for both
    /// live rendering and manifest payload generation.
    @discardableResult
    static func applyLegendDimensionResolution(to payload: inout WorkbenchPlotPayload) -> [String] {
        guard payload.legendDimension == nil, payload.series.count > 1 else { return [] }
        let seriesMeta = payload.series.map(\.metadata)
        guard seriesMeta.contains(where: { !$0.isEmpty }) else { return [] }

        let resolver = LegendDimensionResolver(chain: LegendDimensionResolver.defaultChain)
        let result = resolver.resolve(seriesMetadata: seriesMeta)
        var warnings: [String] = []
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
            warnings.append("Legend: multiple dimensions vary at the same priority (\(names)). Select legend manually.")
        case .indeterminate:
            payload.legendDimension = "⚠ No distinguishing dimension"
            warnings.append("Legend: no distinguishing dimension found across selected samples.")
        }
        return warnings
    }

    /// Returns a warning string if `series` order keys (filtered to those in `expected`)
    /// does not match `expected` order (filtered to those in `series`). Returns nil when consistent.
    static func detectSeriesOrderMismatch(_ series: [WorkbenchPlotSeries], expected: [String]) -> String? {
        let actual = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: series).map { identity in
            (
                key: identity.identityKey,
                sampleID: identity.sampleID ?? "",
                sourceRef: identity.sourceRef ?? "",
                index: identity.originalIndex
            )
        }
        let actualKeys = actual.map(\.key)
        let resolvedExpected = resolveSeriesOrder(expected, actual: actual)
        let expectedFiltered = resolvedExpected.filter { id in actualKeys.contains(id) }
        let actualFiltered = actualKeys.filter { id in resolvedExpected.contains(id) }
        guard expectedFiltered != actualFiltered else { return nil }
        return "seriesOrder mismatch: renderer produced \(actualFiltered) but expected \(expectedFiltered). " +
               "Stack offsets are likely incorrect — fix the renderer to honor input.seriesOrder."
    }

    private static func resolveSeriesOrder(
        _ order: [String],
        actual: [(key: String, sampleID: String, sourceRef: String, index: Int)]
    ) -> [String] {
        let byKey = Dictionary(uniqueKeysWithValues: actual.map { ($0.key, $0.index) })
        let bySampleID = Dictionary(grouping: actual, by: { $0.sampleID })
        let bySourceRef = Dictionary(grouping: actual, by: { $0.sourceRef })
        var consumed = Set<Int>()
        var result: [String] = []

        func append(index: Int) {
            guard consumed.insert(index).inserted else { return }
            result.append(actual[index].key)
        }

        for token in order {
            if let index = byKey[token] {
                append(index: index)
                continue
            }
            if let matches = bySourceRef[token], !matches.isEmpty {
                for match in matches {
                    append(index: match.index)
                }
                continue
            }
            if let matches = bySampleID[token], !matches.isEmpty {
                for match in matches {
                    append(index: match.index)
                }
            }
        }

        for item in actual where !consumed.contains(item.index) {
            append(index: item.index)
        }
        return result
    }
}
