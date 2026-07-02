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
        /// generation, except payloads that explicitly opt into default-visible point tags via
        /// styleParams["defaultPointTagsVisible"]. This lets a workflow keep its own scientific
        /// point annotations visible by default while still preserving the global point-tag toggle.
        var showPointTags: Bool = true
    }

    struct Output: Sendable {
        /// Rendered chart image as PNG data.
        let imageData: Data
        /// Layout with hit rects, plotRect, and rendererSize for canvas interaction.
        let layout: WorkbenchPlotLayout
        /// Full manifest-safe payload for persistence and downstream analysis.
        /// This retains the original series set and only carries non-destructive warnings.
        let manifestPayload: WorkbenchPlotPayload
        /// Warnings generated during the render pipeline (e.g. legend dimension ambiguity).
        let warnings: [String]
    }

    /// Executes the full render pipeline. Throws on renderer failure.
    static func render(_ input: Input) throws -> Output {
        let manifestPayload = input.payload
        var renderPayload = input.payload
        var pipelineWarnings: [String] = []

        // 1. Preserve the original payload for manifest/persistence.
        //    Render-specific mutations are applied only to renderPayload.
        let originalDisplaySeries = displayIdentitySeries(for: renderPayload)

        // 2. Apply shared plot defaults and styleParams patches.
        for (k, v) in input.globalPlotDefaults {
            renderPayload.styleParams[k] = v
        }
        for (k, v) in input.styleParamsPatch {
            renderPayload.styleParams[k] = v
        }
        if let pt = input.legendPoint {
            renderPayload.styleParams["legendX"] = "\(pt.x)"
            renderPayload.styleParams["legendY"] = "\(pt.y)"
        }

        // 3. Apply display-only overrides (title, axis labels)
        if !input.titleOverride.isEmpty { renderPayload.title = input.titleOverride }
        if !input.xLabelOverride.isEmpty { renderPayload.axisMapping.xField = input.xLabelOverride }
        if !input.yLabelOverride.isEmpty { renderPayload.axisMapping.yField = input.yLabelOverride }

        // 4. Apply render mode to unlocked series (locked series keep their own mode)
        renderPayload.series = renderPayload.series.map {
            guard !$0.renderModeLocked else { return $0 }
            var s = $0; s.renderMode = input.seriesRenderMode; return s
        }

        // 4a. Strip point tags when the feature toggle is off, except for payloads that
        // opt in via styleParams["defaultPointTagsVisible"] == "true". This is a generic
        // opt-in for workflow-owned scientific point labels intended to be visible by
        // default; the pipeline does not know which workflow set the flag.
        let hasPayloadPointLabels = renderPayload.series.contains { !$0.pointLabels.isEmpty }
        let keepDefaultPointTags = hasPayloadPointLabels
            && renderPayload.styleParams["defaultPointTagsVisible"] == "true"
        if !input.showPointTags && !keepDefaultPointTags {
            renderPayload.series = renderPayload.series.map { var s = $0; s.pointLabels = []; return s }
        }

        // 4c. Series order consistency check (v5.3.6):
        //     Reorderable payloads must carry unique series identities so order keys stay
        //     attached to stable series identity instead of render geometry.
        if renderPayload.seriesReorderable {
            let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: renderPayload.series)
            assert(Set(identities.map(\.identityKey)).count == identities.count,
                   "seriesReorderable payloads require unique series identity keys")
        }
        //     If the payload opts in to drag reordering and a seriesOrder was provided,
        //     verify the renderer already produced series in the expected order.
        //     The pipeline NEVER reorders — mismatch means the renderer has a bug.
        if renderPayload.seriesReorderable, let expectedOrder = input.seriesOrder {
            if let warning = Self.detectSeriesOrderMismatch(renderPayload.series, expected: expectedOrder) {
                pipelineWarnings.append(warning)
            }
        }

        // 4d. Apply series visibility to the render payload only.
        //     The manifest payload remains complete for persistence and analysis.
        let visibility = applySeriesVisibility(to: renderPayload, hiddenSeriesKeys: input.hiddenSeriesKeys)
        renderPayload = visibility.payload
        if visibility.ignoredAllHidden {
            pipelineWarnings.append("series visibility ignored: all series were hidden")
        }

        // 4e. Reverse series for legend-visual consistency (v5.3.4):
        //     Stacked curves are built bottom-to-top (index 0 = lowest offset).
        //     Reversing makes index 0 = highest offset = legend top = visual top.
        if renderPayload.reverseSeriesForLegend, renderPayload.series.count > 1 {
            renderPayload.series.reverse()
        }

        // 4f. Auto-resolve legend dimension from series metadata (v5.3.4):
        //     When legendDimension is not pre-set and series carry metadata,
        //     run LegendDimensionResolver to infer the distinguishing dimension
        //     and update series labels accordingly.
        pipelineWarnings.append(contentsOf: Self.applyLegendDimensionResolution(to: &renderPayload))

        // 5. Merge chart style overrides into styleParams
        for (k, v) in input.chartStyleOverrides {
            renderPayload.styleParams[k] = v
        }

        // 6. Parse unified chart style
        let chartStyle = WorkbenchChartStyle.from(styleParams: renderPayload.styleParams)

        // 6a. Apply global lineWidth override to unlocked series (locked series keep their own width)
        if let lw = chartStyle.lineWidth {
            renderPayload.series = renderPayload.series.map {
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
        let opts = renderer.resolvedOptions(payload: renderPayload, base: effectiveBase, style: chartStyle)

        // Map index-keyed overrides onto the visible render payload after filtering.
        let visibleDisplaySeries = renderPayload.series
        let seriesLabelOverrides = remapIndexedOverrides(
            input.seriesLabelOverrides,
            from: originalDisplaySeries,
            to: visibleDisplaySeries
        )
        let hiddenPointLabelsBySeries = remapIndexedOverrides(
            input.hiddenPointLabelsBySeries,
            from: originalDisplaySeries,
            to: visibleDisplaySeries
        )

        // 8. Compute layout BEFORE series label overrides (legendRow.originalLabel must be stable).
        //    Pass label overrides so measuredLabelWidth reflects the display (renamed) label,
        //    keeping drag-preview geometry correct for long-renamed series.
        let layout = WorkbenchPlotLayout.compute(
            options: opts, payload: renderPayload, legendPoint: input.legendPoint, style: chartStyle,
            seriesLabelOverrides: seriesLabelOverrides
        )

        // 9. Apply series label overrides
        if !seriesLabelOverrides.isEmpty {
            renderPayload.series = renderPayload.series.enumerated().map { i, s in
                guard let custom = seriesLabelOverrides[i] else { return s }
                var copy = s; copy.label = custom; return copy
            }
        }

        // 10. Render PNG
        var optsWithHidden = opts
        optsWithHidden.hiddenPointLabelsBySeries = hiddenPointLabelsBySeries
        let imageData = try renderer.renderPNG(payload: renderPayload, options: optsWithHidden, style: chartStyle, layout: layout)

        // 11. Attach pipeline warnings to semanticParams for store extraction (v5.3.4).
        var outputManifestPayload = manifestPayload
        if !pipelineWarnings.isEmpty {
            outputManifestPayload.semanticParams["_pipelineWarnings"] = pipelineWarnings.joined(separator: ";;")
        }

        return Output(imageData: imageData, layout: layout, manifestPayload: outputManifestPayload, warnings: pipelineWarnings)
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

    private static func applySeriesVisibility(
        to payload: WorkbenchPlotPayload,
        hiddenSeriesKeys: [String]
    ) -> (payload: WorkbenchPlotPayload, didFilter: Bool, ignoredAllHidden: Bool) {
        guard !hiddenSeriesKeys.isEmpty, !payload.series.isEmpty else {
            return (payload, false, false)
        }
        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: payload.series)
        guard !identities.isEmpty else { return (payload, false, false) }
        let hidden = Set(hiddenSeriesKeys)
        let visibleSeries = payload.series.enumerated().compactMap { index, series in
            guard index < identities.count else { return series }
            return hidden.contains(identities[index].identityKey) ? nil : series
        }
        guard visibleSeries.count != payload.series.count else { return (payload, false, false) }
        if visibleSeries.isEmpty {
            return (payload, false, true)
        }
        var filtered = payload
        filtered.series = visibleSeries
        return (filtered, true, false)
    }

    private static func remapIndexedOverrides<V>(
        _ overrides: [Int: V],
        from sourceSeries: [WorkbenchPlotSeries],
        to targetSeries: [WorkbenchPlotSeries]
    ) -> [Int: V] {
        guard !overrides.isEmpty else { return [:] }
        let sourceIdentities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: sourceSeries)
        let targetIdentities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: targetSeries)
        guard !sourceIdentities.isEmpty, !targetIdentities.isEmpty else { return [:] }
        let targetIndexByIdentity = Dictionary(uniqueKeysWithValues: targetIdentities.enumerated().map { ($1.identityKey, $0) })
        var remapped: [Int: V] = [:]
        for (sourceIndex, value) in overrides {
            guard sourceIdentities.indices.contains(sourceIndex) else { continue }
            let identityKey = sourceIdentities[sourceIndex].identityKey
            guard let targetIndex = targetIndexByIdentity[identityKey] else { continue }
            remapped[targetIndex] = value
        }
        return remapped
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
