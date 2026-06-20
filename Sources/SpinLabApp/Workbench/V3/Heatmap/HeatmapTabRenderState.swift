import Foundation

/// Per-tab heatmap display override state (Plot System-owned, Plot Preservation).
/// Parallel structure to TabRenderState — must not extend or inherit from it.
/// XY-specific fields (seriesOrder, legendPoint, seriesLabelOverrides, hiddenPointLabels)
/// have no meaning for heatmap tabs and are absent.
struct HeatmapTabRenderState: Codable, Hashable, Sendable {
    var titleOverride: String = ""
    var xLabelOverride: String = ""
    var yLabelOverride: String = ""
    /// Colorbar label override (Z-axis title).
    var zLabelOverride: String = ""

    init(
        titleOverride: String = "",
        xLabelOverride: String = "",
        yLabelOverride: String = "",
        zLabelOverride: String = ""
    ) {
        self.titleOverride  = titleOverride
        self.xLabelOverride = xLabelOverride
        self.yLabelOverride = yLabelOverride
        self.zLabelOverride = zLabelOverride
    }
}
