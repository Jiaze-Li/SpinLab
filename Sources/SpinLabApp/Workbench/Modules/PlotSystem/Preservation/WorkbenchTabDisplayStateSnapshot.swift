import CoreGraphics
import Foundation

/// Workflow-agnostic per-tab display override state for detached rendering.
///
/// Captured on MainActor before entering a detached task so that title/axis/series
/// label overrides, legend position, axis range, and point tag state are applied
/// consistently to rendered PNGs on every render path — including re-analysis.
struct WorkbenchTabDisplayStateSnapshot: Sendable {
    let titleOverride: String
    let xLabelOverride: String
    let yLabelOverride: String
    /// Stable-key → display label. Keys are sampleID, sourceRef, or identityKey.
    let seriesLabelOverrides: [String: String]
    let legendPoint: CGPoint?
    /// Stable-key → hidden series display state.
    let hiddenSeriesKeys: [String]
    /// Stable-key → hidden point label indices.
    let hiddenPointLabelsBySeries: [String: [Int]]
    let seriesOrder: [String]?
    let axisRangeOverride: AxisRangeOverride?
    /// Per-tab Cartesian XY tick-count override. nil = use WorkbenchChartStyle defaults.
    let tickOverride: PlotTickOverride?
    let showPointTags: Bool
    let showTitle: Bool

    init(
        titleOverride: String,
        xLabelOverride: String,
        yLabelOverride: String,
        seriesLabelOverrides: [String: String],
        legendPoint: CGPoint?,
        hiddenSeriesKeys: [String] = [],
        hiddenPointLabelsBySeries: [String: [Int]],
        seriesOrder: [String]?,
        axisRangeOverride: AxisRangeOverride?,
        tickOverride: PlotTickOverride? = nil,
        showPointTags: Bool,
        showTitle: Bool = true
    ) {
        self.titleOverride = titleOverride
        self.xLabelOverride = xLabelOverride
        self.yLabelOverride = yLabelOverride
        self.seriesLabelOverrides = seriesLabelOverrides
        self.legendPoint = legendPoint
        self.hiddenSeriesKeys = hiddenSeriesKeys
        self.hiddenPointLabelsBySeries = hiddenPointLabelsBySeries
        self.seriesOrder = seriesOrder
        self.axisRangeOverride = axisRangeOverride
        self.tickOverride = tickOverride
        self.showPointTags = showPointTags
        self.showTitle = showTitle
    }

    /// Canonical mapping from the persisted per-tab state to this sendable snapshot.
    /// The single source of truth for this field list — call sites that need a
    /// snapshot from a `TabRenderState` (live or already source/policy-resolved)
    /// must go through this initializer rather than re-listing the fields.
    init(_ state: TabRenderState) {
        self.init(
            titleOverride: state.titleOverride,
            xLabelOverride: state.xLabelOverride,
            yLabelOverride: state.yLabelOverride,
            seriesLabelOverrides: state.seriesLabelOverrides,
            legendPoint: state.legendPoint?.cgPoint,
            hiddenSeriesKeys: state.hiddenSeriesKeys,
            hiddenPointLabelsBySeries: state.hiddenPointLabelIndicesBySeries,
            seriesOrder: state.seriesOrder,
            axisRangeOverride: state.axisRangeOverride,
            tickOverride: state.tickOverride,
            showPointTags: state.showPointTags,
            showTitle: state.showTitle
        )
    }

    /// Returns a copy with a different seriesOrder. Used inside tasks when series
    /// order is known only after ingestion (e.g. newly-aligned field-sweep order).
    func with(seriesOrder: [String]?) -> WorkbenchTabDisplayStateSnapshot {
        WorkbenchTabDisplayStateSnapshot(
            titleOverride: titleOverride,
            xLabelOverride: xLabelOverride,
            yLabelOverride: yLabelOverride,
            seriesLabelOverrides: seriesLabelOverrides,
            legendPoint: legendPoint,
            hiddenSeriesKeys: hiddenSeriesKeys,
            hiddenPointLabelsBySeries: hiddenPointLabelsBySeries,
            seriesOrder: seriesOrder,
            axisRangeOverride: axisRangeOverride,
            tickOverride: tickOverride,
            showPointTags: showPointTags,
            showTitle: showTitle
        )
    }

    /// Returns a copy with a different hidden-series set.
    func with(hiddenSeriesKeys: [String]) -> WorkbenchTabDisplayStateSnapshot {
        WorkbenchTabDisplayStateSnapshot(
            titleOverride: titleOverride,
            xLabelOverride: xLabelOverride,
            yLabelOverride: yLabelOverride,
            seriesLabelOverrides: seriesLabelOverrides,
            legendPoint: legendPoint,
            hiddenSeriesKeys: hiddenSeriesKeys,
            hiddenPointLabelsBySeries: hiddenPointLabelsBySeries,
            seriesOrder: seriesOrder,
            axisRangeOverride: axisRangeOverride,
            tickOverride: tickOverride,
            showPointTags: showPointTags,
            showTitle: showTitle
        )
    }
}
