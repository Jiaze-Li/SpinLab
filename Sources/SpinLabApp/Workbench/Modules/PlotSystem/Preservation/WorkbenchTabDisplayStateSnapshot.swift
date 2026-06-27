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
    /// Stable-key → hidden point label indices.
    let hiddenPointLabelsBySeries: [String: [Int]]
    let seriesOrder: [String]?
    let axisRangeOverride: AxisRangeOverride?
    let showPointTags: Bool

    /// Returns a copy with a different seriesOrder. Used inside tasks when series
    /// order is known only after ingestion (e.g. newly-aligned field-sweep order).
    func with(seriesOrder: [String]?) -> WorkbenchTabDisplayStateSnapshot {
        WorkbenchTabDisplayStateSnapshot(
            titleOverride: titleOverride,
            xLabelOverride: xLabelOverride,
            yLabelOverride: yLabelOverride,
            seriesLabelOverrides: seriesLabelOverrides,
            legendPoint: legendPoint,
            hiddenPointLabelsBySeries: hiddenPointLabelsBySeries,
            seriesOrder: seriesOrder,
            axisRangeOverride: axisRangeOverride,
            showPointTags: showPointTags
        )
    }
}
