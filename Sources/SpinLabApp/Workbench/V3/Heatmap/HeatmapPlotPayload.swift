import Foundation

/// 2D grid data for a heatmap render path (Plot System contract).
/// Must not inherit or extend WorkbenchPlotPayload/WorkbenchPlotSeries.
struct HeatmapGrid: Codable, Hashable, Sendable {
    /// nX axis values (column labels).
    var xValues: [Double]
    /// nY axis values (row labels).
    var yValues: [Double]
    /// Row-major Z matrix: zMatrix[row][col] where row=0 ↔ yValues[0], col=0 ↔ xValues[0].
    var zMatrix: [[Double]]

    var nX: Int { xValues.count }
    var nY: Int { yValues.count }

    /// True iff matrix dimensions are consistent with axis label counts.
    var isValid: Bool {
        guard nX > 0, nY > 0 else { return false }
        return zMatrix.count == nY && zMatrix.allSatisfy { $0.count == nX }
    }
}

/// Plot System input contract for the heatmap render path.
/// Parallel to WorkbenchPlotPayload; carries 2D grid data instead of XY series.
struct HeatmapPlotPayload: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var workflowID: String
    var title: String
    var xLabel: String
    var yLabel: String
    /// Colorbar title (Z-axis label).
    var zLabel: String
    var grid: HeatmapGrid
    /// Colormap hint key (e.g. "viridis"); nil = viridis default.
    var colormapKey: String?
    /// Optional Z-range clamp lower bound. Nil = auto from data.
    var zRangeClampMin: Double?
    /// Optional Z-range clamp upper bound. Nil = auto from data.
    var zRangeClampMax: Double?

    init(
        schemaVersion: Int = 1,
        workflowID: String,
        title: String,
        xLabel: String,
        yLabel: String,
        zLabel: String,
        grid: HeatmapGrid,
        colormapKey: String? = nil,
        zRangeClamp: ClosedRange<Double>? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.workflowID = workflowID
        self.title = title
        self.xLabel = xLabel
        self.yLabel = yLabel
        self.zLabel = zLabel
        self.grid = grid
        self.colormapKey = colormapKey
        self.zRangeClampMin = zRangeClamp?.lowerBound
        self.zRangeClampMax = zRangeClamp?.upperBound
    }
}
